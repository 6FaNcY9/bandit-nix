<#
Download Mindcraft-CE/Andy-4.2 (the bf16 safetensors, tokenizer and chat template; ~19.3 GB) to
A:\bandit-ai\train\andy-4.2 at a pinned revision. Resumable (rerun after any interruption),
rate limited to 15 MB/s, Idle priority. Every file is checked against the Hugging Face API: LFS files by
SHA256 (the lfs oid), small files by size and git blob SHA1. Needs only curl.exe (no setup.ps1 first).
#>
$ErrorActionPreference = 'Stop'
(Get-Process -Id $PID).PriorityClass = 'Idle'
. "$PSScriptRoot\common.ps1"
$repo = 'Mindcraft-CE/Andy-4.2'
$revision = '2992e6f835c27b84760f38d38683765e8815a2da'
$dir = "$Root\andy-4.2"
New-Item -ItemType Directory -Force $dir | Out-Null
$files = Invoke-RestMethod "https://huggingface.co/api/models/$repo/tree/$revision"
foreach ($f in $files) {
    if ($f.type -ne 'file' -or $f.path -in '.gitattributes') { continue }
    if ($f.path -notmatch '^[A-Za-z0-9._-]+$') { throw "Unexpected file name $($f.path)" }
    $target = "$dir\$($f.path)"
    if (-not (Test-Path $target)) {
        & curl.exe -L --fail --limit-rate 15M -C - -o "$target.part" "https://huggingface.co/$repo/resolve/$revision/$($f.path)"
        if ($LASTEXITCODE) { throw "curl failed ($LASTEXITCODE) for $($f.path); rerun to resume" }
        Move-Item "$target.part" $target
    }
    $item = Get-Item $target
    if ($item.Length -ne $f.size) { Remove-Item $target -Force; throw "Size mismatch for $($f.path); deleted, rerun" }
    if ($f.lfs) {
        $ok = (Get-FileHash $target -Algorithm SHA256).Hash.ToLowerInvariant() -eq $f.lfs.oid
    } else {
        # git blob id: sha1("blob <size>\0" + content)
        $sha1 = [Security.Cryptography.SHA1]::Create()
        $bytes = [IO.File]::ReadAllBytes($target)
        $head = [Text.Encoding]::ASCII.GetBytes("blob $($bytes.Length)`0")
        $ok = ([BitConverter]::ToString($sha1.ComputeHash([byte[]]($head + $bytes))) -replace '-', '').ToLowerInvariant() -eq $f.oid
    }
    if (-not $ok) { Remove-Item $target -Force; throw "Checksum mismatch for $($f.path); deleted, rerun" }
    Write-Host "ok $($f.path) ($([math]::Round($f.size / 1MB)) MB)"
}
Set-Content "$dir\REVISION.txt" $revision
Write-Host "Andy-4.2 @ $revision is complete in $dir"
