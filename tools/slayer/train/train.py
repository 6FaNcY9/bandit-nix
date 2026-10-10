"""QLoRA fine-tune of Andy-4.2 (Qwen3.5-9B, Qwen3_5ForConditionalGeneration) on our logged decisions.

Usage (through run-guarded.ps1, or directly with the venv python):
  python train.py --run andy-lora-1 --data A:\\bandit-ai\\train\\data\\sft.jsonl
  python train.py --run smoke --data ... --max-steps 3        # quick check that everything loads and steps

Approach (text only):
 * The checkpoint is loaded as Qwen3_5ForConditionalGeneration, the architecture it was saved from,
   so every weight name matches without remapping. The vision tower stays bf16 and untouched; the
   LoRA is applied by regex to the language model only. (AutoModelForCausalLM would map qwen3_5 to
   Qwen3_5ForCausalLM and rely on key renaming + ignoring visual/mtp weights: not verified, not needed.)
 * Base 4-bit nf4 with bf16 compute; lm_head and the vision tower are not quantized.
 * LoRA r=16 alpha=32 dropout 0.05 on q/k/v/o, gate/up/down and the linear-attention projections
   (in_proj_qkv, in_proj_z, out_proj) of the 32 layers (24 of them are linear attention).
 * Prompt = the repo chat template with add_generation_prompt and enable_thinking=False (exactly what
   the watcher's llama-server sees); target = reply + <|im_end|>. Loss only on the target.
   The vocabulary is 248k, so lm_head is applied to the target positions only (full-sequence fp32
   logits at 4096 tokens would be 4 GB).
 * Batch size 1 sequence, gradient accumulation --accum, gradient checkpointing.
 * Data rows are {messages, source, split} from the lab export (rows without split: every 10th row is
   held out). train -> training, val -> eval loss, test is never touched (kept for the replay).
 * Checkpoint every --save-every optimizer steps (keeps the last two) in A:\\bandit-ai\\train\\runs\\<run>;
   a rerun with the same --run resumes from the newest one (the data file is frozen into the run dir).
 * Ends with runs\\<run>\\adapter and runs\\<run>\\summary.json.
"""
import argparse, json, math, os, random, re, shutil, sys, time
from pathlib import Path

import torch

ROOT = Path(r'A:\bandit-ai\train')
LORA_TARGETS = r'.*language_model.*\.(q_proj|k_proj|v_proj|o_proj|gate_proj|up_proj|down_proj|in_proj_qkv|in_proj_z|out_proj)'


def parse():
    p = argparse.ArgumentParser()
    p.add_argument('--run', required=True)
    p.add_argument('--data', type=Path, help='sft.jsonl (required for a new run)')
    p.add_argument('--model', type=Path, default=ROOT / 'andy-4.2')
    p.add_argument('--epochs', type=float, default=3)
    p.add_argument('--lr', type=float, default=1e-4)
    p.add_argument('--accum', type=int, default=16)
    p.add_argument('--max-seq', type=int, default=4096)
    p.add_argument('--save-every', type=int, default=10)
    p.add_argument('--max-steps', type=int, default=0, help='stop after this many optimizer steps (smoke test)')
    p.add_argument('--seed', type=int, default=1234)
    return p.parse_args()


def log(run_dir, **kw):
    kw['t'] = time.strftime('%Y-%m-%dT%H:%M:%S')
    line = json.dumps(kw)
    print(line, flush=True)
    with open(run_dir / 'log.jsonl', 'a') as f:
        f.write(line + '\n')


def load_rows(path):
    rows = []
    for line in path.read_text(encoding='utf8').splitlines():
        if not line.strip():
            continue
        r = json.loads(line)
        m = r.get('messages')
        if m and m[-1]['role'] == 'assistant' and m[-1]['content'].strip():
            rows.append(r)
    return rows


def tokenize(tok, rows, cap):
    out, dropped = [], 0
    for r in rows:
        m = r['messages']
        prompt = tok.apply_chat_template(m[:-1], add_generation_prompt=True, enable_thinking=False, tokenize=False)
        p = tok(prompt, add_special_tokens=False)['input_ids']
        t = tok(m[-1]['content'].strip() + '<|im_end|>', add_special_tokens=False)['input_ids']
        if len(p) + len(t) > cap:
            dropped += 1
            continue
        out.append((p, t))
    return out, dropped


def split_rows(rows):
    if any('split' in r for r in rows):
        train = [r for r in rows if r.get('split', 'train') == 'train']
        val = [r for r in rows if r.get('split') == 'val']
    else:
        val = rows[9::10]
        train = [r for i, r in enumerate(rows) if i % 10 != 9]
    if not val and len(train) >= 10:  # tiny export without a val episode group
        val, train = train[9::10], [r for i, r in enumerate(train) if i % 10 != 9]
    return train, val


def sample_loss(inner, ids, n_prompt):
    """Mean cross-entropy over the target tokens of one sequence."""
    x = torch.tensor([ids], device='cuda')
    with torch.autocast('cuda', dtype=torch.bfloat16):
        h = inner.model(input_ids=x).last_hidden_state[0]
        logits = inner.lm_head(h[n_prompt - 1:len(ids) - 1])
    target = x[0, n_prompt:]
    return torch.nn.functional.cross_entropy(logits.float(), target), target.numel()


@torch.no_grad()
def evaluate(model, inner, data):
    model.eval()
    total = count = 0
    for p, t in data:
        loss, n = sample_loss(inner, p + t, len(p))
        total += loss.item() * n
        count += n
    model.train()
    return total / max(count, 1)


def newest_ckpt(run_dir):
    c = sorted(run_dir.glob('ckpt-*'), key=lambda d: int(d.name.split('-')[1]))
    return c[-1] if c else None


def main():
    a = parse()
    if not re.fullmatch(r'[A-Za-z0-9_][A-Za-z0-9_.-]*', a.run):
        sys.exit('--run must be letters, digits, _ . -')
    run_dir = ROOT / 'runs' / a.run
    run_dir.mkdir(parents=True, exist_ok=True)
    frozen = run_dir / 'train-data.jsonl'
    if not frozen.exists():
        if not a.data:
            sys.exit('New run: pass --data')
        shutil.copyfile(a.data, frozen)
    rows = load_rows(frozen)
    if not rows:
        sys.exit('No usable rows in the dataset; nothing to train on')

    from transformers import AutoTokenizer, BitsAndBytesConfig, Qwen3_5ForConditionalGeneration
    from peft import LoraConfig, get_peft_model, set_peft_model_state_dict
    from safetensors.torch import load_file

    random.seed(a.seed); torch.manual_seed(a.seed)
    tok = AutoTokenizer.from_pretrained(a.model)
    train_rows, val_rows = split_rows(rows)
    cap = min(a.max_seq, 4096)
    train, dropped = tokenize(tok, train_rows, cap)
    val, dropped_val = tokenize(tok, val_rows, cap)
    if not train:
        sys.exit('No training rows within the length cap')
    longest = max(len(p) + len(t) for p, t in train + val)
    n = len(train)
    total_micro = int(math.ceil(a.epochs * n))
    total_steps = int(math.ceil(total_micro / a.accum))
    if a.max_steps:
        total_steps = min(total_steps, a.max_steps)
    log(run_dir, event='data', rows=len(rows), train=n, val=len(val), dropped_too_long=dropped + dropped_val, longest_tokens=longest, steps=total_steps)

    bnb = BitsAndBytesConfig(load_in_4bit=True, bnb_4bit_quant_type='nf4', bnb_4bit_compute_dtype=torch.bfloat16,
                             bnb_4bit_use_double_quant=True, llm_int8_skip_modules=['visual', 'lm_head', 'in_proj_a', 'in_proj_b'])
    base = Qwen3_5ForConditionalGeneration.from_pretrained(a.model, quantization_config=bnb, dtype=torch.bfloat16, device_map={'': 0})
    base.config.use_cache = False
    base.gradient_checkpointing_enable(gradient_checkpointing_kwargs={'use_reentrant': False})
    model = get_peft_model(base, LoraConfig(r=16, lora_alpha=32, lora_dropout=0.05, target_modules=LORA_TARGETS, bias='none'))
    inner = model.base_model.model
    model.train()
    trainable = [p for p in model.parameters() if p.requires_grad]
    opt = torch.optim.AdamW(trainable, lr=a.lr, weight_decay=0.0, betas=(0.9, 0.999))
    warm = max(1, int(0.05 * total_steps))
    lam = lambda s: (s + 1) / warm if s < warm else 0.1 + 0.9 * 0.5 * (1 + math.cos(math.pi * (s - warm) / max(1, total_steps - warm)))
    sched = torch.optim.lr_scheduler.LambdaLR(opt, lam)
    log(run_dir, event='model', trainable_params=sum(p.numel() for p in trainable), vram_gb=round(torch.cuda.memory_allocated() / 2**30, 2))

    step, history, recent = 0, [], []
    ck = newest_ckpt(run_dir)
    if ck:
        set_peft_model_state_dict(model, load_file(ck / 'adapter_model.safetensors'))
        st = torch.load(ck / 'state.pt', weights_only=False)
        opt.load_state_dict(st['opt']); sched.load_state_dict(st['sched']); step = st['step']; history = st['history']
        log(run_dir, event='resume', checkpoint=ck.name, step=step)

    def order(epoch):
        idx = list(range(n)); random.Random(a.seed + epoch).shuffle(idx); return idx

    def save():
        d = run_dir / f'ckpt-{step}'
        tmp = run_dir / f'.tmp-{step}'
        shutil.rmtree(tmp, ignore_errors=True)
        model.save_pretrained(tmp)
        torch.save({'opt': opt.state_dict(), 'sched': sched.state_dict(), 'step': step, 'history': history}, tmp / 'state.pt')
        shutil.rmtree(d, ignore_errors=True)
        tmp.rename(d)
        for old in sorted(run_dir.glob('ckpt-*'), key=lambda x: int(x.name.split('-')[1]))[:-2]:
            shutil.rmtree(old, ignore_errors=True)

    started = time.time()
    while step < total_steps:
        step_loss = 0.0
        for k in range(a.accum):
            micro = step * a.accum + k
            if micro >= total_micro:
                break
            p, t = train[order(micro // n)[micro % n]]
            loss, _ = sample_loss(inner, p + t, len(p))
            (loss / a.accum).backward()
            step_loss += loss.item() / a.accum
        torch.nn.utils.clip_grad_norm_(trainable, 1.0)
        opt.step(); sched.step(); opt.zero_grad(set_to_none=True)
        step += 1
        recent = (recent + [step_loss])[-10:]
        log(run_dir, event='step', step=step, of=total_steps, loss=round(step_loss, 4), lr=sched.get_last_lr()[0], vram_peak_gb=round(torch.cuda.max_memory_allocated() / 2**30, 2), elapsed_s=int(time.time() - started))
        if step % a.save_every == 0 or step == total_steps:
            if val:
                history.append({'step': step, 'eval_loss': round(evaluate(model, inner, val), 4)})
                log(run_dir, event='eval', **history[-1])
            save()

    model.save_pretrained(run_dir / 'adapter')
    summary = {'run': a.run, 'rows': len(rows), 'train': n, 'val': len(val), 'dropped_too_long': dropped + dropped_val, 'epochs': a.epochs,
               'steps': step, 'accum': a.accum, 'lr': a.lr, 'final_train_loss_avg10': round(sum(recent) / max(len(recent), 1), 4),
               'eval_history': history, 'best_eval': min(history, key=lambda h: h['eval_loss']) if history else None,
               'peak_vram_gb': round(torch.cuda.max_memory_allocated() / 2**30, 2), 'seconds_this_session': int(time.time() - started),
               'torch': torch.__version__}
    (run_dir / 'summary.json').write_text(json.dumps(summary, indent=2))
    log(run_dir, event='done', **{k: summary[k] for k in ('steps', 'final_train_loss_avg10', 'best_eval')})


if __name__ == '__main__':
    main()
