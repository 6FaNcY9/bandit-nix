# bnet job control: start/stop the local Ollama for the lab, keep a silent PC silent, show a notice.
# $Cfg is the agent's shared hashtable: Silence, SilencePowerPct, SessionDir, Job, SilenceOk.

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

function Get-BnetDefaultPowerLimit {
    $r = Invoke-BnetNvidia @('--query-gpu=power.default_limit', '--format=csv,noheader,nounits')
    if ($r.Code -ne 0) { return $null }
    [int][math]::Round([double]($r.Out.Trim() -split "`n")[0])
}

function Set-BnetPowerLimit([int]$Watts) { (Invoke-BnetNvidia @('-pl', "$Watts")).Code -eq 0 }

function Start-BnetJob {
    param([Parameter(Mandatory, Position = 0)][string]$Kind, [Parameter(Mandatory, Position = 1)][hashtable]$Cfg)
    if ($Kind -ne 'ollama') { return $false }   # phase 1 only routes Ollama
    if ($Cfg.Silence) {
        # The limit must hold before any load starts; if it cannot be set, this PC takes no work.
        $def = Get-BnetDefaultPowerLimit
        $ok = $def -and (Set-BnetPowerLimit ([int][math]::Floor($def * $Cfg.SilencePowerPct / 100)))
        $Cfg.SilenceOk = [bool]$ok
        if (-not $ok) { return $false }
    }
    Start-BnetService 'ollama'
    $Cfg.Job = $Kind
    @{ job = $Kind; since = (Get-Date).ToString('o') } | ConvertTo-Json -Compress |
        Set-Content (Join-Path $Cfg.SessionDir 'job.json')
    $true
}

function Stop-BnetJob {
    param([Parameter(Mandatory, Position = 0)][hashtable]$Cfg)
    $ps = Invoke-BnetOllama @('ps')
    foreach ($line in @($ps.Out -split "`n" | Select-Object -Skip 1)) {
        $model = ($line.Trim() -split '\s+')[0]
        if ($model) { Invoke-BnetOllama @('stop', $model) | Out-Null }
    }
    Stop-BnetService 'ollama'
    if ($Cfg.Silence) { $def = Get-BnetDefaultPowerLimit; if ($def) { Set-BnetPowerLimit $def | Out-Null } }
    Remove-Item (Join-Path $Cfg.SessionDir 'job.json') -ErrorAction SilentlyContinue
    $Cfg.Job = $null
}

function Update-BnetJob {
    # Called on every 5-s tick: the job must not outlive the permission to run.
    param([Parameter(Mandatory, Position = 0)]$Result, [Parameter(Mandatory, Position = 1)][hashtable]$Cfg)
    if ($Cfg.Job -and -not $Result.JobAllowed) { Stop-BnetJob $Cfg }
}

function Get-BnetJobAllowed {
    param([Parameter(Mandatory, Position = 0)]$Result, [Parameter(Mandatory, Position = 1)][hashtable]$Cfg)
    [bool]$Result.JobAllowed -and (-not $Cfg.Silence -or $Cfg.SilenceOk)
}

function Get-BnetUserLoad {
    # While our own job runs, its GPU use and its CPU share are not the user's: without this the job
    # would read its own load as "heavy" and stop itself. Fullscreen and input still stop it at once.
    param([double]$CpuTotal, [double]$CpuOllama, [double]$Gpu, [bool]$JobRunning)
    if (-not $JobRunning) { return @{ CpuPct = $CpuTotal; GpuPct = $Gpu } }
    @{ CpuPct = [math]::Max(0, $CpuTotal - $CpuOllama); GpuPct = 0 }
}

Export-ModuleMember -Function Start-BnetJob, Stop-BnetJob, Update-BnetJob, Get-BnetJobAllowed, Get-BnetUserLoad
