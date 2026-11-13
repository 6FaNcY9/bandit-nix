# bnet job control: start/stop the local Ollama for the lab, keep a silent PC silent, show a notice.
# $Cfg is the agent's shared hashtable: Silence, SilencePowerPct, SilenceCpuPct, StatusDir, Job, SilenceOk.
# StatusDir is written by SYSTEM only (users read it): a user-writable folder here would let a user
# redirect SYSTEM's writes/deletes with a mount point.

# Thin wrappers around the outside world so tests can replace them.
function Invoke-BnetNvidia([string[]]$Arguments) { $o = & nvidia-smi @Arguments 2>&1; @{ Code = $LASTEXITCODE; Out = "$o" } }
function Invoke-BnetOllama([string[]]$Arguments) {
    $env:OLLAMA_HOST = '127.0.0.1:11435'   # the lab's own instance, see install.ps1
    $o = & ollama @Arguments 2>&1; @{ Code = $LASTEXITCODE; Out = ($o -join "`n") }
}
# Ollama on Windows is a tray app, not a service: install.ps1 registers `ollama serve` as task bnet-<name>.
function Start-BnetService([string]$Name) { Start-ScheduledTask -TaskName "bnet-$Name" }
function Stop-BnetService([string]$Name) {
    Stop-ScheduledTask -TaskName "bnet-$Name" -ErrorAction SilentlyContinue
    # Only the lab instance runs as SYSTEM; a user's own Ollama app (and its runners) runs as that user.
    Get-CimInstance Win32_Process -Filter "Name LIKE 'ollama%'" |
        Where-Object { (Invoke-CimMethod -InputObject $_ -MethodName GetOwner).User -eq 'SYSTEM' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}

function Test-BnetOllamaReady {
    try { $null = Invoke-RestMethod 'http://127.0.0.1:11435/api/version' -TimeoutSec 2; $true } catch { $false }
}
# Maximum processor state while a silent PC works, so the CPU cooler stays quiet too (100 = Windows default).
function Set-BnetCpuCap([int]$Pct) {
    powercfg /setacvalueindex scheme_current sub_processor PROCTHROTTLEMAX $Pct | Out-Null
    powercfg /setactive scheme_current | Out-Null
}

function Get-BnetDefaultPowerLimit {
    $r = Invoke-BnetNvidia @('--query-gpu=power.default_limit', '--format=csv,noheader,nounits')
    if ($r.Code -ne 0) { return $null }
    [int][math]::Round([double]($r.Out.Trim() -split "`n")[0])
}

function Set-BnetPowerLimit([int]$Watts) { (Invoke-BnetNvidia @('-pl', "$Watts")).Code -eq 0 }

function Start-BnetJob {
    param([Parameter(Mandatory, Position = 0)][string]$Kind, [Parameter(Mandatory, Position = 1)][hashtable]$Cfg,
          [int]$ReadyTimeoutSec = 20)
    if ($Kind -ne 'ollama') { return $false }   # phase 1 only routes Ollama
    if ($Cfg.Silence) {
        # The limit must hold before any load starts; if it cannot be set, this PC takes no work.
        $def = Get-BnetDefaultPowerLimit
        $ok = $def -and (Set-BnetPowerLimit ([int][math]::Floor($def * $Cfg.SilencePowerPct / 100)))
        $Cfg.SilenceOk = [bool]$ok
        if (-not $ok) { return $false }
        Set-BnetCpuCap $Cfg.SilenceCpuPct
    }
    $Cfg.Job = $Kind
    @{ job = $Kind; since = (Get-Date).ToString('o') } | ConvertTo-Json -Compress |
        Set-Content (Join-Path $Cfg.StatusDir 'job.json')
    Start-BnetService 'ollama'
    # The task returns before `ollama serve` listens; only report success once it answers.
    $until = (Get-Date).AddSeconds($ReadyTimeoutSec)
    do {
        if (Test-BnetOllamaReady) { return $true }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $until)
    Stop-BnetJob $Cfg
    $false
}

function Stop-BnetJob {
    param([Parameter(Mandatory, Position = 0)][hashtable]$Cfg)
    $ps = Invoke-BnetOllama @('ps')
    foreach ($line in @($ps.Out -split "`n" | Select-Object -Skip 1)) {
        $model = ($line.Trim() -split '\s+')[0]
        if ($model) { Invoke-BnetOllama @('stop', $model) | Out-Null }
    }
    Stop-BnetService 'ollama'
    if ($Cfg.Silence) {
        $def = Get-BnetDefaultPowerLimit; if ($def) { Set-BnetPowerLimit $def | Out-Null }
        Set-BnetCpuCap 100
    }
    Remove-Item (Join-Path $Cfg.StatusDir 'job.json') -ErrorAction SilentlyContinue
    $Cfg.Job = $null
}

function Update-BnetJob {
    # Called on every 5-s tick: the job must not outlive the permission to run.
    param([Parameter(Mandatory, Position = 0)]$Result, [Parameter(Mandatory, Position = 1)][hashtable]$Cfg)
    if ($Cfg.Job -and -not $Result.JobAllowed) { Stop-BnetJob $Cfg }
}

function Get-BnetJobAllowed {
    param([Parameter(Mandatory, Position = 0)]$Result, [Parameter(Mandatory, Position = 1)][hashtable]$Cfg)
    # A silent PC never works next to its user: the power cap would also slow the user's own game.
    if ($Cfg.Silence -and ($Result.State -ne 'idle' -or -not $Cfg.SilenceOk)) { return $false }
    [bool]$Result.JobAllowed
}

function Get-BnetUserLoad {
    # While our own job runs, its own CPU and GPU share are not the user's (else the job would read its own
    # load as "heavy" and stop itself); everything else, e.g. a windowed game, still counts.
    param([double]$CpuTotal, [double]$CpuOllama, [double]$Gpu, [double]$GpuOllama = 0, [bool]$JobRunning)
    if (-not $JobRunning) { return @{ CpuPct = $CpuTotal; GpuPct = $Gpu } }
    @{ CpuPct = [math]::Max(0, $CpuTotal - $CpuOllama); GpuPct = [math]::Max(0, $Gpu - $GpuOllama) }
}

function Get-BnetModels {
    # Model names in the lab store, read from Ollama's manifest tree so it works while Ollama is stopped:
    # manifests/<registry>/library/<name>/<tag> -> name:tag, manifests/<registry>/<ns>/<name>/<tag> -> ns/name:tag.
    param([Parameter(Mandatory, Position = 0)][string]$ModelsDir)
    $root = Join-Path $ModelsDir 'manifests'
    if (-not (Test-Path $root)) { return @() }
    $names = foreach ($f in Get-ChildItem $root -Recurse -File) {
        $p = [IO.Path]::GetRelativePath($root, $f.FullName) -split '[\\/]'
        if ($p.Count -lt 4) { continue }
        $repo = if ($p[1] -eq 'library') { $p[2..($p.Count - 2)] -join '/' } else { $p[1..($p.Count - 2)] -join '/' }
        "${repo}:$($p[-1])"
    }
    @($names | Sort-Object -Unique)
}

Export-ModuleMember -Function Start-BnetJob, Stop-BnetJob, Update-BnetJob, Get-BnetJobAllowed, Get-BnetUserLoad, Get-BnetModels
