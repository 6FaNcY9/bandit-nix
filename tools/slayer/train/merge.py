"""Merge a LoRA adapter into the bf16 Andy-4.2 base on the CPU (about 20 GB of RAM, 5-15 min) and
write a plain HF checkpoint (same Qwen3_5ForConditionalGeneration layout as the base, so
convert_hf_to_gguf.py handles it like the original). The mtp.* head is not loaded by transformers and
therefore not written; the converter runs with --no-mtp.
Usage: python merge.py ADAPTER_DIR OUT_DIR   (called by merge-and-convert.ps1)
"""
import shutil, sys
from pathlib import Path

import torch
from peft import PeftModel
from transformers import Qwen3_5ForConditionalGeneration

BASE = Path(r'A:\bandit-ai\train\andy-4.2')
adapter, out = Path(sys.argv[1]), Path(sys.argv[2])
model = Qwen3_5ForConditionalGeneration.from_pretrained(BASE, dtype=torch.bfloat16, device_map='cpu', low_cpu_mem_usage=True)
model = PeftModel.from_pretrained(model, adapter).merge_and_unload()
out.mkdir(parents=True, exist_ok=True)
model.save_pretrained(out, safe_serialization=True, max_shard_size='5GB')
for name in ('tokenizer.json', 'tokenizer_config.json', 'chat_template.jinja', 'generation_config.json', 'processor_config.json'):
    shutil.copyfile(BASE / name, out / name)
print('merged ->', out)
