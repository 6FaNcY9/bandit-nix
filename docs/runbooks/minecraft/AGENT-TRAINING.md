# Improving the lab's Andy agent with local data

Design only, 2026-10-10. Base: fetched `origin/main`
`9854488089f3f5bf62de8142f6cd71d31db756de`. No implementation, model download,
training, activation, bot commands or push is authorized by this document.
Commands below are future operator procedures; configuration blocks are sketches.

## Decision and evidence

**Keep Ollama in production for now; test llama.cpp before training.** Prefer
llama.cpp's server if the paired replay and canary below pass. Fixing a serving
template is cheaper than teaching a model around a serving bug. Retain Ollama
0.34.2 and the original Andy model as the rollback path. Do not change the
executor's safety rules to improve a model's score.

The [Andy model card](https://huggingface.co/Mindcraft-CE/Andy-4.2) recommends
LM Studio and reports Ollama template/looping problems. That supports testing a
different backend, **not proof that Ollama causes this lab's failures**. Its
training report is 2,748 examples, one epoch, lr 2e-5 cosine, 4-bit QLoRA with
8-bit QAT, five hours on a 3090. Our proposal is ordinary QLoRA, without QAT;
do not describe it as reproducing their method. Their evaluation used 8-bit
weights, whereas our deployment uses Q4_K_M.

Local evidence to preserve in the replay set:

| Evidence | Behavior to improve |
| --- | --- |
| `c2cc96e` | Copies the removed “Sure, I'll stop” prompt example instead of progressing |
| `4042760` | Repeats failed collection; forgets deposits and smelting fuel |
| `b7de84c` | Lead mines underground, cannot reach chest, cycles through failing blueprints |
| `599473f` | Numeric variations of the same error bypass repeat detection |
| [AGENT-HANDOFF.md](AGENT-HANDOFF.md) | Idle wake/refusal loops, worker failure/replacement, Stop and movement acceptance boundaries |

Treat pathfinder/executor bugs in that handoff as software issues, not training
targets. Preserve regression scenarios for them, but do not label every path
failure a bad model choice. The scope of a later implementation would be
`tools/mcagents/agent.js` and its tests (backend transport/logging), the owning
`mcagents`/`ollama` modules and a new inference module, plus dataset/replay tools.
This change adds only this runbook.

## 1. Inference experiment and possible deployment

### Immutable candidate

Use the **same existing GGUF bytes** for A/B, not another quantization:

```text
URL=https://huggingface.co/Mindcraft-CE/Andy-4.2-GGUF/resolve/d3efcb8137c88cd3c23466ddabf985ea59b52fdf/andy-4.2.q4_k_m.gguf
SHA256=3cfccaa17be8d2ded998fab8bd4b7032f91f2a916ac2aa03a412908342228eb1
```

Candidate image, resolved from the public GHCR `server-cuda` manifest on
2026-10-10 (linux/amd64 child digest; registry identity verified, **not run**):

```text
ghcr.io/ggml-org/llama.cpp@sha256:e3f1cdbb7bd8c4d64df34e97336f2b56f67735fb988e074280805b587179f874
```

Resolved via the GHCR pull-token endpoint and registry V2
`/v2/ggml-org/llama.cpp/manifests/server-cuda`, selecting its linux/amd64
manifest; the image config identifies b11515, source revision
`3d65c90d04d337e88f2b1f7f0061f40a5324e662` and `/app/llama-server` entrypoint.
The multi-platform index was
`sha256:ccfd96bb2aba4ef77e3df656d713ce85bf3c6a886d7974243127c5ad66ca6d2a`.
Record `llama-server --version`, image labels/source revision and `--help` before
using it. Verify Qwen3.5 GGUF loading and flags against that binary; linked
upstream docs track current main and can differ. A failed smoke test means
choose and record another digest, not silently follow a moving tag.
See [official server documentation](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md)
and [image versions](https://github.com/ggml-org/llama.cpp/pkgs/container/llama.cpp).

### Enable and replay the optional module

`hosts/bandit-lab/services/llamacpp/default.nix` is imported alongside Ollama.
`bandit-lab.llamacpp.enable` defaults to **false**; the owner enables it after
review. These are future, authorized lab operations, not build checks.
Ollama remains the production backend and its configuration is unchanged.

Ollama deletes `/var/lib/ollama-import/andy.gguf` after copying it into its blob
store. Restage the exact pinned bytes before enabling llama.cpp, outside the
Nix closure. If `andy.gguf` already exists, verify its checksum and reuse it;
do not replace a file while llama.cpp is running. With llama.cpp stopped:

```bash
set -euo pipefail
sudo install -d -m 0700 /var/lib/ollama-import
sudo curl -fL --retry 3 -o /var/lib/ollama-import/andy.gguf.part \
  https://huggingface.co/Mindcraft-CE/Andy-4.2-GGUF/resolve/d3efcb8137c88cd3c23466ddabf985ea59b52fdf/andy-4.2.q4_k_m.gguf
echo '3cfccaa17be8d2ded998fab8bd4b7032f91f2a916ac2aa03a412908342228eb1  /var/lib/ollama-import/andy.gguf.part' | sudo sha256sum -c
sudo mv /var/lib/ollama-import/andy.gguf.part /var/lib/ollama-import/andy.gguf
```

Run staging with shell error checking (`set -euo pipefail`); never rename after
a failed download/hash check. The container mounts this root-owned directory
read-only at `/import`. There is no automatic downloader. A fresh Ollama import
can remove this file, so finish that import before staging. Optional vision:
place a separately verified compatible projector in the same directory and set
`bandit-lab.llamacpp.mmproj = "/import/mmproj.gguf";`; it defaults to `null`.

Add `bandit-lab.llamacpp.enable = true;` to the host configuration and build it
before the owner's normal deployment procedure. The container uses CDI,
8192 context, one slot, the embedded GGUF Jinja template, thinking off and the
same sampling as `tools/mcagents/agent.js`.
Only `127.0.0.1:8081` is published; no firewall port is added. Other containers
may still reach its bridge interface; restrict bridge access for durable use.
See [official server flags and endpoints](https://github.com/ggml-org/llama.cpp/blob/3d65c90d04d337e88f2b1f7f0061f40a5324e662/tools/server/README.md).

Both models may not fit on one GPU. Run the frozen replay sequentially on the
lab (repository checkout and Node required); the harness sends no bot actions.
Finish the Ollama run first, then stop its consumer so it cannot reload the
model. If enabling starts llama.cpp too early, stop it before the Ollama run:

```bash
sudo systemctl stop docker-llamacpp
node tools/mcagents/replay.js run replay.jsonl --endpoint http://127.0.0.1:11434 --api ollama --model andy-4.2 --seed 11 > ollama-11.jsonl
sudo systemctl stop mcagents docker-ollama
sudo systemctl start docker-llamacpp
curl --fail http://127.0.0.1:8081/health
curl --fail http://127.0.0.1:8081/v1/models
node tools/mcagents/replay.js run replay.jsonl --endpoint http://127.0.0.1:8081 --api openai --model andy-4.2-baseline --seed 11 > llamacpp-11.jsonl
node tools/mcagents/replay.js compare ollama-11.jsonl llamacpp-11.jsonl > comparison-11.json
```

Wait for `/health` to return HTTP 200 (503 means loading) and confirm
`andy-4.2-baseline` in `/v1/models` before replay. Use the same frozen prompts
and seeds for both backends; repeat for seeds 22 and 33 as below. Inspect
per-row errors and the human goal-consistency rubric before judging a winner.
Do not point production `agent.js` at this URL: its transport is Ollama-only.

Rollback: stop `docker-llamacpp`, start `docker-ollama`, confirm Ollama's
`/api/tags` contains `andy-4.2`, then restart `mcagents`. Set
`bandit-lab.llamacpp.enable = false;` and deploy through the normal owner
procedure to keep it off across boots. Preserve model files and replay results.

`--jinja` uses `tokenizer.chat_template` embedded in the GGUF; do not pass a
generic `--chat-template` override. Inspect metadata and tokenizer template,
EOS/BOS and rendered fixtures (first system turn, subsequent `SYSTEM:` user
turns, consecutive users, nested `!assign`, thinking off). Fail closed if the
template is absent or differs from the pinned Andy tokenizer. Inspect template
capabilities and confirm `enable_thinking=false` actually suppresses thinking.
[Qwen3.5 serving guidance](https://unsloth.ai/docs/models/qwen3.5#how-to-enable-or-disable-reasoning-and-thinking)
documents that flag, but Andy's own template is the authority here.

Migration needs an explicit backend transport in `agent.js`: `/api/chat` is
Ollama-specific. llama.cpp uses `/v1/chat/completions`, replies at
`choices[0].message.content`, and may put thinking in `reasoning_content`.
Preserve the logged `messages`, `thinking`, `reply`, timing, errors, rate cap,
and current removal of think tags before parsing commands. Add model/backend,
artifact hash, sampling and prompt revision to future log provenance. Retain
the current first-system-plus-`SYSTEM:`-user conversion; avoid double templating.
Changing `OLLAMA_URL` alone will not work. Order the agent after the chosen
server's health/model-readiness gate, update service dependencies and check
the current mcagents IP allowlist permits its Docker bridge. Keep fallback
configuration available rather than removing `ollama-andy`.

### Paired replay protocol

Archive and sanitize data as below. Freeze **200 held-out prompts** spanning
normal assignments, idle workers, failure recovery, deposits/fuel, Stop,
death/respawn, blocked ascent, and varied-number same-error loops. Include
historical failure prompts as a separate diagnostic stratum; do not attribute
an old prompt's bugs to the current prompt. Freeze a current-prompt variant of
each relevant scenario and report results for both strata separately.

For each prompt, send the same `messages` array to both servers, thinking off,
8,192 context, temp 0.6, top_k 20, top_p 0.95, min_p 0, repeat_penalty 1.0,
maximum 512 generated tokens. Use seeds 11, 22, 33 and alternate backend order;
run backends sequentially to avoid GPU contention. Seed equivalence does not
promise identical RNG streams. Tokenize first; no silent context truncation.
Report long prompts separately. Inference caps are experimental settings,
not claims about today's uncapped Ollama generation.

Each `replay.jsonl` line has `id`, `episode_id`, `messages`, `goal`, prior
canonical commands/outcomes, relevant bot/worker state, and human-written
`expected` constraints (e.g. allowed workers, prohibited self-gather, acceptable
recovery actions). Sidecar `manifest.json` pins dataset hash, source revision,
model/GGUF/image hashes, sampling, seeds and templates. Never call `/api/job`
from the replay harness: validate through pure parser/translation fixtures.

Request-file examples for one frozen row (`replay.js` automates the paired
runs above; these show the equivalent payloads):

```bash
jq -s '.[0].messages' replay.jsonl > messages.json
jq -n --slurpfile m messages.json '{model:"andy-4.2",messages:$m[0],stream:false,think:false,options:{num_ctx:8192,num_predict:512,seed:11,temperature:0.6,top_k:20,top_p:0.95,min_p:0,repeat_penalty:1.0}}' > ollama-request.json
curl --fail-with-body -sS --max-time 180 http://127.0.0.1:11434/api/chat \
  -H 'Content-Type: application/json' --data-binary @ollama-request.json > ollama-response.json
jq -n --slurpfile m messages.json '{model:"andy-4.2-baseline",messages:$m[0],stream:false,max_tokens:512,seed:11,temperature:0.6,top_k:20,top_p:0.95,min_p:0,repeat_penalty:1.0,chat_template_kwargs:{enable_thinking:false}}' > llama-request.json
curl --fail-with-body -sS --max-time 180 http://127.0.0.1:8081/v1/chat/completions \
  -H 'Content-Type: application/json' --data-binary @llama-request.json > llama-response.json
```

Store scored output lines as:

```json
{"id":"p001","seed":11,"backend":"llama","model_sha256":"...","reply":"!inventory","ms":620,"valid":true,"repeated":false,"goal_consistent":true,"reason":"checks fuel before assigning smelt","reviewer":"owner"}
```

| Metric | Definition |
| --- | --- |
| Valid command rate | Calls producing a parseable supported command with valid arguments and state/precondition checks, divided by all calls; unknown, unsafe, refused, malformed, empty, timeout and truncation failures score zero |
| Repeated-command rate | Action-eligible calls repeating the same canonical failed action without a material state change, or swapping blueprint/coordinates while the same prerequisite failure persists, divided by action-eligible calls; report raw count/denominator |
| Goal-consistent rate | All calls judged by blinded human review to advance the stated goal or sensibly inspect/recover/wait, divided by all calls; syntax or job completion alone is insufficient |

Strip thinking and use `parseCommand`, `translate`, `assignJob` and fixtures
from the pinned executor revision. Check full argument semantics rather than
trusting its permissive regex. A sensible no-command wait may be goal-consistent
but is not a valid command; report such waits separately. Queries are excluded
from the repeated-action denominator. Freeze the canonicalization rubric:
command/arguments, worker, goal and failure category; ignore irrelevant numbers
in error text, not meaningful command destinations. Compare against prior
commands in the frozen history, not outputs from unrelated replay rows.
Replay does not prove alternate actions succeed in the world.

Proposed gates (policy choices): valid >=95%, goal-consistent >=90%, harmful
repeats <=5%; no regression >2 percentage points in valid/goal-consistent rates
or in repeat rate versus Ollama. Require an improvement supported by a paired
bootstrap over **episodes**, e.g. >=5 points in goal consistency or fewer repeats
with a 95% interval excluding zero. Report per-scenario counts, uncertainty,
latency p50/p95, token limits and VRAM. If sample size cannot distinguish a win,
collect more episodes and keep Ollama. Do not add a grammar for only one backend;
it would hide the template comparison.

## 2. Dataset from decisions and outcomes

### Capture before data disappears

`logCall()` rotates at 50,000,000 bytes to `decisions.jsonl.1`, overwriting the
previous rotation. The dashboard's `EventLog` is an **in-memory 200-event ring**,
not a historical outcome database; IDs reset on process restart. Start bounded
archival before collecting a dataset. Do not assume old outcomes can be recovered.
Use a private operator directory (`umask 077`), outside Git and backups shared
with others. Example read-only acquisition from an already authorized lab shell:

```bash
umask 077
mkdir -p raw
sudo cat /var/lib/mcagents/decisions.jsonl.1 > raw/decisions-rotation.jsonl
sudo cat /var/lib/mcagents/decisions.jsonl > raw/decisions-current.jsonl
curl --fail-with-body -sS --config /run/credentials/agent-export/curl.conf \
  'http://127.0.0.1:8095/api/events?since=0' > raw/events-snapshot.json
sha256sum raw/* > raw/SHA256SUMS
```

The curl config is a **future provisioned, mode-0600 credential file**, not an
existing path; it supplies the agent bearer header without putting a token on
the command line. Never dump it. If `.1` does not exist, record its absence.
Copy near rotation can overlap or lose records: dedup overlaps, reject only a
trailing partial JSON line with an explicit count, and flag continuity gaps.
For sustained capture, archive both decision files on each rotation and poll
`/api/events?since=<lastId>` frequently enough to stay inside 200 entries; store
each returned event as JSONL with a collector `server_session` and capture time.
Detect ID reset and ring overflow; unmatched periods are unknown, not success.
Do not change active logging or poll the host as part of this design task.

Raw event format today is `{id,t,bot,kind,text}` (`t` epoch milliseconds,
`text` truncated to 200 characters). Archive wrapper example:

```json
{"server_session":"lab-20261010-a","captured_at":"2026-10-10T12:00:00Z","event":{"id":81,"t":1791633600000,"bot":"bot2","kind":"done","text":"finished: mine coal_ore 32 (60 s)"}}
```

### Join and label

1. Order calls by agent/time within a known process session. A decision's `t`
   is **after inference**; approximate start as `t-ms`. Extract assistant replies
   with the current command parser, including inner `!assign` commands. Multiple
   query rounds are separate calls, not separate executed jobs.
2. Diff later message histories against earlier ones so the same outcome in
   several prompts counts once. Direct results are `SYSTEM: Code output: ...`;
   assigned workers report `SYSTEM: Worker botN: finished/failed/...`, **not
   necessarily Code output**. Match the action and affected bot to the first
   compatible terminal event after dispatch. A query/local operation has an
   immediate response, not a job terminal event.
3. Check archived event `bot`, `kind`, time, command/job label and subsequent
   state. There is no stable decision ID/job ID in these logs and the worker
   assigner is process-local and can be replaced. Overlapping/replaced jobs,
   missing history, stale results, deaths near another job or ambiguous time
   matches get `unknown` and manual review. Never assign “the next Code output”
   to a decision just because it is next chronologically. Long-running shifts
   need deposit/stock-progress evidence and an observation window, not an
   invented `finished` event. Future logging should add correlation IDs.
4. Label `good` only when a supported, safe, goal-consistent decision has
   compatible success/progress evidence and a human agrees. `failed`, `gave up`
   or death is a candidate `bad`, not automatic blame: distinguish environmental
   failure from repeating a known bad plan. `stopped` is good only when Stop
   was appropriate. “finished” is insufficient for an irrelevant job or a lead
   gathering personally. Retain evidence and reviewer rationale.
5. Drop refused, malformed, looping and unknown turns from **SFT targets**.
   Keep sanitized negatives in the audit/replay set. For a useful failure
   scenario, a human may author a safe replacement reply, labeled `corrected`
   with its source and rationale; do not copy the bad reply as supervision.
   Do not fabricate hidden thinking; omit `thinking` from targets and preserve
   thinking-off template behavior. Bad historical assistant turns should be
   removed/rebuilt into a reviewed recovery context rather than repeatedly
   teaching the old loop through the prompt.

Intermediate `labels.jsonl` (private provenance; not sent to trainer):

```json
{"id":"d001","episode_id":"crew-session-a-goal-7","source":{"file_sha256":"...","line":73,"agent":"bot1","t":"2026-10-10T12:00:00Z"},"command":"!assign(\"bot2\", \"!startShift(\\\"coal_ore\\\")\")","outcome":{"server_session":"lab-a","event_ids":[81,86],"status":"progress","evidence":"worker deposited coal"},"label":"good","goal_consistent":true,"reviewer":"owner","reason":"supplies fuel; lead stays at base","dedup_key":"sha256:..."}
```

Training/eval format is one conversational prompt-completion object per line:

```json
{"prompt":[{"role":"system","content":"Reviewed command docs, lead goal and sanitized state."},{"role":"user","content":"SYSTEM: Worker bot2: failed: smelt iron - no coal"}],"completion":[{"role":"assistant","content":"!assign(\"bot3\", \"!startShift(\\\"coal_ore\\\")\")"}]}
```

This shortened row illustrates the schema, not a full usable prompt. Export
actual reviewed messages with the original role conversion and current docs.
Strip provenance columns from trainer rows; store them in the matching ID
sidecar. Use completion-only loss so historical assistants and system/user
content are not training targets. Preserve the tokenizer's own template and
verify its token-level completion mask before a full run.
[TRL documents this dataset format and loss behavior](https://huggingface.co/docs/trl/sft_trainer).

### Privacy, dedup and split

- Allow bot-to-bot messages only, using the explicit bot allowlist. Drop human
  chat turns **and every copy embedded in history/system state/replies/thinking**;
  do not retain humans' text by replacing just their names. Replace non-bot
  player identities in entity lists with stable anonymous labels or remove
  irrelevant entities. Human goals can be rewritten as approved task text.
- Scan every retained field for bearer/password/key material, addresses, private
  URLs and paths. No tokens, credential files, raw environment dumps, player
  chat, or raw logs in Git/Hugging Face/Cachix. Manual review follows automated
  filtering. Pin access/retention: owner-readable local data, remove raw archives
  after review (proposed 30 days); retain sanitized sets and hashes. No cloud
  training or telemetry upload of samples. Keep bot/world identifiers only
  where needed for the task; vary coordinates in reviewed examples to prevent
  memorizing one base.
- Dedup raw overlap by `(agent,t,messages,reply)` hash, then canonical sanitized
  prompt/completion hash. Cluster near-duplicates by goal, command, normalized
  state and failure cause. Keep representative variety; numeric error changes
  alone must not multiply the same lesson. Human synthetic variants share their
  source episode/cluster.
- Initial target: **1,000–2,000 reviewed unique examples**, roughly half normal
  leadership and half recovery/known failure cases; collect more if diversity
  is insufficient. Start with 100 to test the pipeline. Do not pad to Andy's
  2,748 count with repeated logs. Queries, appropriate waits and successful
  delegation must remain represented; corrected examples are clearly counted.
- Split **80/10/10 train/validation/test** by complete goal episode/session and
  near-duplicate cluster, never random lines. Hold newer sessions for test;
  quarantine all episodes/clusters containing frozen replay prompts before
  training. Reserve the 200-prompt regression suite separately if needed.
  Dedup before assigning splits, check cross-split normalized hashes and manually
  inspect nearest matches. Validation selects the checkpoint; the test/replay
  set is not used to tune prompts, hyperparameters or rewrite labels repeatedly.

## 3. One-off QLoRA on the lab

Use Unsloth + Transformers v5 + PEFT/bitsandbytes + TRL for **text-only continued
SFT of Andy's BF16/safetensors checkpoint**, not the Q4 GGUF and not plain
Qwen3.5. [Upstream Qwen3.5 fine-tuning guidance](https://unsloth.ai/docs/models/qwen3.5/fine-tune)
supports this family and specifies Transformers v5; its 9B BF16 LoRA estimate
is 22 GB, so that route does not fit this 16 GB card. **The following 4-bit
memory/timing figures are guesses, not measured lab results.**

Pin Andy's HF commit, tokenizer/config, framework dependency lock, CUDA/PyTorch
versions and the training image digest in `train-manifest.json` before a run.
Resolve and record pins after a compatibility smoke test rather than inventing
version numbers here. Download a revision with the Hugging Face CLI:

```bash
hf download Mindcraft-CE/Andy-4.2 --revision "$ANDY_HF_REV" --local-dir /work/base-andy
```

`ANDY_HF_REV` must be a recorded full HF commit, not `main`. Preserve the Andy
[license and notices](https://huggingface.co/Mindcraft-CE/Andy-4.2/tree/main/LICENSE)
in derived artifacts; review the actual license before distribution.

Proposed `train-config.json` contract for a future small training entry point
(the entry point and lockfile **do not exist yet**):

```json
{
  "base_model": "/work/base-andy",
  "load_in_4bit": true,
  "quant_type": "nf4",
  "double_quant": true,
  "compute_dtype": "bfloat16",
  "train_vision": false,
  "lora_rank": 8,
  "lora_alpha": 16,
  "lora_dropout": 0,
  "target_modules": ["q_proj","k_proj","v_proj","o_proj","gate_proj","up_proj","down_proj"],
  "gradient_checkpointing": "unsloth",
  "max_length": 2048,
  "per_device_train_batch_size": 1,
  "gradient_accumulation_steps": 8,
  "num_train_epochs": 1,
  "learning_rate": 0.00002,
  "lr_scheduler_type": "cosine",
  "warmup_ratio": 0.05,
  "optim": "adamw_8bit",
  "bf16": true,
  "packing": false,
  "completion_only_loss": true,
  "seed": 3407
}
```

Map these fields explicitly to the pinned loader/PEFT and `SFTConfig` APIs;
this JSON is not a CLI accepted by Unsloth itself. Freeze vision/projector,
embeddings and lm_head. Verify actual module names and trainable parameters;
the projection list deliberately starts with attention/MLP modules supported
by the converter, not every linear layer in the hybrid/vision architecture.
Rank 8 limits memory and overfitting; no rank sweep or DPO/RL for the first run.

2048 tokens is a starting memory budget, **not** the deployed 8192 context.
Tokenize with Andy's template; prune oldest irrelevant turns while retaining
docs, goal/state and the causal failure, otherwise skip overlength examples.
Never blindly right-truncate away the completion. Record the retained-length
distribution and evaluate at production context. Only try 4096 after measured
headroom. One epoch initially; a second only if validation behavior improves
without regressions. Save adapter + tokenizer and resume checkpoints outside
Git; never silently restart an interrupted run from zero.

### GPU scheduling and expected duration

Run a one-off digest-pinned CUDA training container with CDI, read-only
`/work/base-andy` and sanitized data mounts, writable `/work/output` and cache,
no Docker socket, no dashboard credentials, no published ports and no network
after dependencies/weights are staged. Future invocation shape:

```bash
docker run --rm --network=none --device=nvidia.com/gpu=all \
  --security-opt=no-new-privileges \
  -v /var/lib/agent-training/base-andy:/work/base-andy:ro \
  -v /var/lib/agent-training/data:/work/data:ro \
  -v /var/lib/agent-training/output:/work/output \
  "$TRAIN_IMAGE_DIGEST" python /opt/train.py --config /work/data/train-config.json
```

`TRAIN_IMAGE_DIGEST` and `/opt/train.py` are future artifacts, not runnable
deliverables of this design. The job is manual/oneshot, not an enabled training
timer. Check physical host, NVIDIA driver/CDI, disk/RAM and free VRAM first:

```bash
hostname
nvidia-smi --query-gpu=name,memory.total,memory.used,power.limit --format=csv
free -h
df -h /var/lib/agent-training
```

Guess: standalone 9B NF4 rank-8, batch-1, 2048 training needs roughly 10–14 GB;
original inference can take another 6–9 GB with context. **Do not promise both
fit simultaneously.** NVIDIA process sharing is not a memory quota or isolation.
Run a 20-optimizer-step smoke test, log peak allocated/reserved VRAM and system
RAM, loss/masks, step time, temperatures and power. Require >=1 GB GPU headroom.
If it OOMs, shorten to 1024 and rank 4, reviewing the dropped-context rate;
if still unsuitable, use another GPU rather than dropping safety context.

Bots keep running because workers execute scripted jobs independently of the
lead model. To keep a responsive lead too, temporarily route it to a **CPU-only
original-model server**, tested beforehand at the existing rate limit. Unload
Ollama's GPU model (future authorized operation: `docker exec ollama ollama stop
andy-4.2`) and stop any GPU candidate server before training; prevent the lead
from reloading it. CPU latency is uncertain and may be unacceptable. If CPU
inference misses the agreed latency budget, pause only lead decisions and leave
running scripted jobs intact, or train elsewhere. This requires explicit
operational agreement; do not restart `docker-mcbots`/Minecraft to train.
Restore GPU inference after the job. Simultaneous GPU training/inference is an
optional measured experiment, never the assumed default.

Guess: 1,000–2,000 examples at average 1024–2048 tokens, one epoch, takes **2–8
hours** on the power-limited 4090 Laptop, plus staging/export/replay; allow an
overnight window. The upstream five-hour 3090 run is an anchor, not a benchmark
for this GPU/recipe. Extrapolate from warmed-up measured optimizer-step time:
`ceil(train_examples / 8) * seconds_per_optimizer_step`, adding validation and
checkpoint time. Budget roughly 40–60 GB free host RAM and 60–100 GB disk for
base, merge and conversion; verify actual host capacity before scheduling.

### Export for llama.cpp

Save PEFT `adapter_model.safetensors`, `adapter_config.json`, tokenizer/template,
training manifest and dataset hashes. First try a GGUF adapter on the **exact
original Andy base**; never attach it to plain Qwen3.5. Use a checked-out, pinned
llama.cpp revision matching the serving build and its converter dependencies:

```bash
python llama.cpp/convert_lora_to_gguf.py /work/output/adapter \
  --base /work/base-andy --outfile /work/output/andy-lab-v1-lora.gguf --outtype f16
sha256sum /work/output/andy-lab-v1-lora.gguf
# Add to the server command, keeping the original model/template:
# --lora /models/andy-lab-v1-lora.gguf
```

[Official adapter converter](https://github.com/ggml-org/llama.cpp/blob/master/convert_lora_to_gguf.py)
is the CLI authority. Hybrid Qwen3.5 adapter conversion/loading with the chosen
targets must pass a smoke test; **compatibility is not established here**.
Compare adapter replies against HF inference before quantized replay. If the
converter rejects tensors or serving diverges, use the merged route, not a
partially exported adapter:

```text
model.save_pretrained_merged("/work/output/merged", tokenizer, save_method="merged_16bit")
```

That is an API operation in the future trainer/export job, documented by
[Unsloth export guidance](https://unsloth.ai/docs/basics/inference-and-deployment/saving-to-gguf).
Merge with sufficient **CPU RAM**, not a full BF16 model on the 16 GB GPU;
test the pinned exporter or use a CPU PEFT merge from the original checkpoint.
Then:

```bash
python llama.cpp/convert_hf_to_gguf.py /work/output/merged \
  --outfile /work/output/andy-lab-v1.f16.gguf --outtype f16
llama.cpp/build/bin/llama-quantize /work/output/andy-lab-v1.f16.gguf \
  /work/output/andy-lab-v1.q4_k_m.gguf Q4_K_M
sha256sum /work/output/andy-lab-v1.q4_k_m.gguf
```

Verify exported architecture, template and special tokens against base; run
the same replay on the Q4 artifact actually deployed. A merged full model is
the simpler durable artifact if adapter support is fragile. Publish nothing
automatically. Keep original GGUF/Ollama blobs, checksums and manifests.

## 4. Evaluation, canary and rollback

Compare three stages separately: current Ollama/original Andy, winning
llama.cpp/original Andy, and that **same** llama.cpp build with lab-tuned Andy.
This separates backend gains from training gains. Lock replay and sampling;
use the metrics/gates above, plus per-case checks for safe Stop, delegation,
fuel/deposits, error recovery and appropriate waits. No new unsupported code
generation (`!newAction`). Track executor refusals too: a guard catching an
unsafe output still counts as a model failure. Approval to deploy requires
all required executor tests and configuration/build checks in the later patch;
this document has no executable changes to validate.

Canary only after offline acceptance and owner-authorized live operations:

1. Run **one lead agent** on the new artifact. Use bot1 in a scheduled canary
   window, with its normal workers and bounded existing goals; disable the old
   controller for bot1 first. Never run two controllers or duplicate assignments
   against the same bot/crew. An extra bot is not world isolation: use a staging
   world/separate crew if parallel production/canary comparison is required.
2. Keep workers, executor rules and rate caps unchanged. Observe at least 100
   decisions and one complete goal episode across 24–48 hours (proposed, not a
   measured requirement), including failure/recovery and a Stop check. Capture
   job progress, deposits, deaths, refusals, latency, repeats and goal consistency
   with manual review. Compare a matched baseline period, not different goals.
3. Abort on any unsafe goal deviation, uncontrollable repetition (three repeated
   failed actions), broken Stop, model OOM/unavailability, or two consecutive
   180-second inference timeouts. Also roll back for metric-gate failure after
   the minimum sample. Do not weaken executor guards or handwave small samples.
4. Restore the previous backend/model configuration and restart **only mcagents**
   after checking outstanding jobs. A model switch does not undo jobs already
   submitted: the new lead must reconcile current state and existing worker
   assignments; `assigner` bookkeeping is lost on restart. If a job is unsafe,
   have the authorized operator Stop that specific job, then reconcile it.
   Do not silently stop all workers or restart Minecraft as a rollback step.

Fallback artifacts/configuration: original `andy-4.2` in Ollama at
`http://127.0.0.1:11434`, its pinned image
`ollama/ollama@sha256:da6e0dc5651df159e45686fd663c4dbe1624a52c44d7280eeac1551d8f865532`,
the original GGUF checksum above, and the pre-canary mcagents configuration.
For a llama.cpp adapter rollback, start without `--lora`; for merged artifacts,
point back to the immutable original file. Keep disk fallback warm/available,
but do not require both GPU models resident. Confirm model health, one
controller, workers still online and goal progress after rollback. Record the
exact activated source/model/backend IDs separately from build/replay results.

## Acceptance of this design

This runbook proposes formats, commands, gates and deployment shape. Upstream
pages were checked; repository logging, templates, event retention and service
wiring were inspected. No live logs, replay metrics, GPU memory benchmark,
training duration, model export or container runtime compatibility was tested.
Capture/sanitization and paired replay are implemented in `tools/mcagents/replay.js`;
training is justified only after serving is stable and reviewed data exists.
