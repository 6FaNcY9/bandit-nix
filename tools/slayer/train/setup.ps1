<#
Idempotent toolchain setup for the Andy-4.2 LoRA run. Run on albert in a normal (non-elevated)
PowerShell or over ssh. Everything lands under A:\bandit-ai\train; no PATH, registry or
system-wide change, no admin needed.

What it does (each step is skipped when already done):
  1. uv 0.13.0 (pinned zip, SHA256 checked) -> train\tools\uv
  2. Python 3.12 (uv's managed build) + venv -> train\py, train\venv
  3. torch 2.14.1+cu130 from the official PyTorch index (Blackwell/sm_120 needs CUDA 12.8+; cu130
     matches the CUDA 13 runtime the llama.cpp build uses). Wheel is fetched with curl.exe
     --limit-rate 15M, SHA256 checked, then installed from the file.
  4. Pinned transformers (needs qwen3_5), peft, bitsandbytes (Windows wheel with cuda130 DLL),
     accelerate, safetensors, sentencepiece, tokenizers (+ numpy/tqdm/pyyaml/requests/protobuf for
     the GGUF converter).
  5. llama.cpp source b11541 (the tag of C:\bandit-ai\llama, see install.ps1): convert_hf_to_gguf.py,
     its conversion\ package and gguf-py -> train\llama-src (used through PYTHONPATH, not pip).
  6. Self-test: CUDA visible, sm_120, bitsandbytes and the qwen3_5 classes import.
Runs at Idle CPU priority. uv's own downloads (Python build, small PyPI wheels, 39 MB bitsandbytes)
cannot be rate limited; the big files (torch, llama source, uv) go through curl.exe.
#>
$ErrorActionPreference = 'Stop'
(Get-Process -Id $PID).PriorityClass = 'Idle'
. "$PSScriptRoot\common.ps1"

$uvUrl = 'https://github.com/astral-sh/uv/releases/download/0.13.0/uv-x86_64-pc-windows-msvc.zip'
$uvSha = '088962f9e7b7bd9ea740c04c650b2a21c8928c345bd99ac24350dc924dba656c'
$torchFile = 'torch-2.14.1+cu130-cp312-cp312-win_amd64.whl'
$torchUrl = 'https://download.pytorch.org/whl/cu130/torch-2.14.1%2Bcu130-cp312-cp312-win_amd64.whl'
$torchSha = '0a09031e93632d14ef49553acd6211ece3ae9cdc0969a369b8c24e3cc4d15be9'
$llamaTag = 'b11541'
$llamaSrcUrl = "https://github.com/ggml-org/llama.cpp/archive/refs/tags/$llamaTag.zip"
$llamaSrcSha = '0c05472cb49c7f2c76aaddb59e2bd35431d6dc8736a54f57cda3f192a9b6870f'
$packages = @('transformers==5.19.0', 'peft==0.21.2', 'bitsandbytes==0.50.2', 'accelerate==1.15.0',
    'safetensors==0.8.0', 'sentencepiece==0.2.2', 'tokenizers==0.23.3',
    'numpy>=2.2.6,<3', 'tqdm', 'pyyaml', 'requests', 'protobuf>=4.21.0,<5')

# The llama.cpp release on the PC must be the one the converter source matches.
if ((Test-Path 'C:\bandit-ai\install.ps1') -and -not (Select-String -Path 'C:\bandit-ai\install.ps1' -Pattern "/$llamaTag/" -Quiet)) {
    throw "C:\bandit-ai\install.ps1 does not use llama.cpp $llamaTag; update the pins in this script first."
}
foreach ($d in $Root, $Dl, $Tmp, "$Root\tools") { New-Item -ItemType Directory -Force $d | Out-Null }

if (-not (Test-Path $Uv)) {
    Get-Verified $uvUrl "$Dl\uv.zip" $uvSha
    Expand-Archive "$Dl\uv.zip" "$Root\tools\uv" -Force
    if (-not (Test-Path $Uv)) { throw 'uv.exe missing from the archive' }
}
if (-not (Test-Path $Py)) {
    & $Uv venv $Venv --python 3.12 --managed-python
    if ($LASTEXITCODE) { throw 'uv venv failed' }
}
$installed = $null
try { $installed = & $Py -c "import importlib.metadata as m; print(m.version('torch'))" } catch { }
if ($installed -ne '2.14.1+cu130') {
    Get-Verified $torchUrl "$Dl\$torchFile" $torchSha
    & $Uv pip install --python $Py "$Dl\$torchFile"
    if ($LASTEXITCODE) { throw 'torch install failed' }
}
& $Uv pip install --python $Py @packages
if ($LASTEXITCODE) { throw 'package install failed' }

if (-not (Test-Path "$Root\llama-src\convert_hf_to_gguf.py")) {
    Get-Verified $llamaSrcUrl "$Dl\llama-src.zip" $llamaSrcSha
    $stage = "$Root\llama-src.stage"
    if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
    Expand-Archive "$Dl\llama-src.zip" $stage -Force
    Move-Item (Get-ChildItem $stage -Directory | Select-Object -First 1).FullName "$Root\llama-src"
    Remove-Item $stage -Recurse -Force
}

& $Py -c "import torch, bitsandbytes, transformers; from transformers import Qwen3_5ForConditionalGeneration; assert torch.cuda.is_available(), 'CUDA not available'; print('torch', torch.__version__, torch.cuda.get_device_name(0), torch.cuda.get_device_capability(0), 'transformers', transformers.__version__, 'bitsandbytes', bitsandbytes.__version__)"
if ($LASTEXITCODE) { throw 'self-test failed' }
Write-Host 'Setup complete.'
