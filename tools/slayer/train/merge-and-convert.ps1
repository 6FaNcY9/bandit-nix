<#
Turn a finished training run into a model the watcher can serve.
Usage:  .\merge-and-convert.ps1 -Run andy-lora-1 [-Adapter <dir>]   (default adapter: runs\<Run>\adapter)
Steps (each skipped when its output exists, so a rerun resumes):
  1. merge.py: adapter + bf16 base -> A:\bandit-ai\train\merged\<Run> (CPU, ~20 GB RAM, ~18 GB disk)
  2. llama.cpp b11541 convert_hf_to_gguf.py --outtype bf16 --no-mtp -> A:\bandit-ai\train\gguf\<Run>-bf16.gguf
  3. C:\bandit-ai\llama\llama-quantize.exe ... Q4_K_M -> A:\bandit-ai\models\andy-lora-<Run>.gguf
     (Q4_K_M is the quant of andy.gguf: the installer downloads andy-4.2.q4_k_m.gguf)
     The bf16 GGUF is deleted after a successful quantize; merged\<Run> is kept.
  4. symlink in C:\bandit-ai\models (when that folder does not already show the A: file)
  5. prints the candidate.json content. It does NOT write C:\bandit-ai\candidate.json.
Run it only while training is not running (it competes for RAM); Idle CPU priority.
#>
param(
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9_][A-Za-z0-9_.-]*$')][string]$Run,
    [string]$Adapter
)
$ErrorActionPreference = 'Stop'
(Get-Process -Id $PID).PriorityClass = 'Idle'
. "$PSScriptRoot\common.ps1"
if (-not $Adapter) { $Adapter = "$Root\runs\$Run\adapter" }
if (-not (Test-Path "$Adapter\adapter_model.safetensors")) { throw "No adapter at $Adapter" }
$merged = "$Root\merged\$Run"
$bf16 = "$Root\gguf\$Run-bf16.gguf"
$name = "andy-lora-$Run.gguf"
$final = "A:\bandit-ai\models\$name"
$quantize = 'C:\bandit-ai\llama\llama-quantize.exe'
New-Item -ItemType Directory -Force "$Root\gguf", 'A:\bandit-ai\models' | Out-Null

if (-not (Test-Path "$merged\config.json")) {
    & $Py "$PSScriptRoot\merge.py" $Adapter $merged
    if ($LASTEXITCODE) { Remove-Item $merged -Recurse -Force -ErrorAction SilentlyContinue; throw 'merge failed' }
}
if (-not (Test-Path $final)) {
    if (-not (Test-Path $bf16)) {
        $env:PYTHONPATH = "$Root\llama-src\gguf-py"
        & $Py "$Root\llama-src\convert_hf_to_gguf.py" $merged --outtype bf16 --no-mtp --outfile "$bf16.part"
        if ($LASTEXITCODE) { Remove-Item "$bf16.part" -Force -ErrorAction SilentlyContinue; throw 'GGUF conversion failed' }
        Move-Item "$bf16.part" $bf16
    }
    if (-not (Test-Path $quantize)) { throw "llama-quantize.exe is not at $quantize; the bf16 GGUF is kept at $bf16. Quantize it to Q4_K_M with any llama.cpp b11541 llama-quantize and save it as $final, then rerun." }
    & $quantize $bf16 "$final.part" Q4_K_M
    if ($LASTEXITCODE) { Remove-Item "$final.part" -Force -ErrorAction SilentlyContinue; throw 'quantize failed' }
    Move-Item "$final.part" $final
    Remove-Item $bf16 -Force
}
$link = "C:\bandit-ai\models\$name"
if (-not (Test-Path $link)) { New-Item -ItemType SymbolicLink -Path $link -Target $final | Out-Null }
$hash = (Get-FileHash $link -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Host "Model: $final ($([math]::Round((Get-Item $final).Length / 1GB, 2)) GB)"
Write-Host 'candidate.json (write it yourself when you want the watcher to serve this model):'
@{ file = $name; sha256 = $hash; alias = "andy-lora-$Run" } | ConvertTo-Json
