# Dot-sourced by the other scripts in this folder: shared paths and the verified-download helper.
$Root = 'A:\bandit-ai\train'
$Dl = "$Root\downloads"
$Tmp = "$Root\tmp"
$Uv = "$Root\tools\uv\uv.exe"
$Venv = "$Root\venv"
$Py = "$Venv\Scripts\python.exe"
# Keep every cache and temp file off the nearly full C: drive.
$env:UV_CACHE_DIR = "$Root\uv-cache"
$env:UV_PYTHON_INSTALL_DIR = "$Root\py"
$env:HF_HOME = "$Root\hf-cache"
$env:TEMP = $Tmp; $env:TMP = $Tmp
$env:PYTHONUTF8 = '1'
$env:PYTHONUNBUFFERED = '1'

# Resumable, rate-limited download with a SHA256 check; a wrong file is deleted so a retry starts clean.
function Get-Verified([string]$Url, [string]$Path, [string]$Sha256) {
    New-Item -ItemType Directory -Force (Split-Path $Path) | Out-Null
    if (-not (Test-Path $Path)) {
        & curl.exe -L --fail --limit-rate 15M -C - -o "$Path.part" $Url
        if ($LASTEXITCODE) { throw "curl failed ($LASTEXITCODE) for $Url; rerun to resume" }
        Move-Item "$Path.part" $Path
    }
    if ((Get-FileHash $Path -Algorithm SHA256).Hash.ToLowerInvariant() -ne $Sha256.ToLowerInvariant()) {
        Remove-Item -LiteralPath $Path -Force
        throw "Checksum mismatch for $Path; deleted, rerun to download again"
    }
}
