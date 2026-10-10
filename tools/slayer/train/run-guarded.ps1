<#
Runs train.py only while the PC is free. Every 15 s it asks the watcher's Busy probe (busy.ps1,
shared with watch.ps1; in -Remote mode, because this runs outside the player's desktop session, so
the console-session and fullscreen checks are skipped but running games and non-llama GPU load still
count; the training process's own GPU use is ignored).
  free  -> create C:\bandit-ai\training.lock (the watcher then stops its llama-server within 15 s and
           does not start it while the lock is fresh), wait up to 3 min for the server to be gone,
           start train.py
  busy  -> stop the training process tree (train.py resumes from its last checkpoint on the next
           free start; you lose at most --save-every steps) and remove the lock
It never touches llama-server or any process that is not its own training child. The lock is removed
in finally; the watcher ignores a lock older than 24 h, and this script refreshes it every poll.
Usage:  .\run-guarded.ps1 -Run andy-lora-1 [-Data A:\bandit-ai\train\data\sft.jsonl] [-TrainArgs '--max-steps','3']
Stop:   create A:\bandit-ai\train\STOP (graceful, within 15 s), or Ctrl+C in a foreground session.
Exits 0 when train.py has finished (runs\<Run>\summary.json exists).
Run it detached from ssh, e.g.:
  Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','<path>\run-guarded.ps1','-Run','andy-lora-1'
#>
param(
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9_][A-Za-z0-9_.-]*$')][string]$Run,
    [string]$Data = 'A:\bandit-ai\train\data\sft.jsonl',
    [string[]]$TrainArgs = @()
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\common.ps1"
$base = 'C:\bandit-ai'
$TestPort = 0
$GpuPercent = $null
. "$base\busy.ps1"
$lock = "$base\training.lock"
$stop = "$Root\STOP"
$runDir = "$Root\runs\$Run"
New-Item -ItemType Directory -Force $runDir | Out-Null
$guardLog = "$runDir.guard.log"
function Write-Log($m) { Add-Content $guardLog "$(Get-Date -Format o) $m" }
$mutex = New-Object Threading.Mutex($false, 'Global\bandit-ai-train-guard')
if (-not $mutex.WaitOne(0)) { throw 'Another run-guarded.ps1 is already running.' }

function Get-Tree([int]$RootPid) {
    $all = @(Get-CimInstance Win32_Process)
    $ids = @($RootPid)
    do {
        $more = @($all | Where-Object { $ids -contains $_.ParentProcessId -and $ids -notcontains $_.ProcessId } | ForEach-Object ProcessId)
        $ids += $more
    } while ($more.Count)
    $ids
}
function Stop-Training($proc) {
    & taskkill.exe /PID $proc.Id /T /F | Out-Null
    $null = $proc.WaitForExit(30000)
}
function Test-Busy($proc) {
    $ignore = @()
    if ($proc -and -not $proc.HasExited) { $ignore = @(Get-Tree $proc.Id) }
    try { return Busy -Remote -IgnorePids $ignore } catch { return "probe failed: $($_.Exception.Message)" }
}

$proc = $null
$failures = 0
try {
    while ($true) {
        if (Test-Path "$runDir\summary.json") { Write-Log 'summary.json present: training finished'; break }
        if (Test-Path $stop) { Write-Log 'STOP file: leaving'; break }
        $reason = Test-Busy $proc
        if ($proc -and $proc.HasExited) {
            if ($proc.ExitCode -ne 0) {
                $failures++
                Write-Log "train.py exited $($proc.ExitCode) (failure $failures); see $Root\runs\$Run.err.*.log"
                if ($failures -ge 3) { throw 'train.py failed 3 times; fix it before retrying (the checkpoints are kept).' }
            }
            $proc = $null
            Remove-Item $lock -Force -ErrorAction SilentlyContinue
            continue
        }
        if ($proc) {
            if ($reason) {
                Write-Log "busy ($reason): stopping training"
                Stop-Training $proc; $proc = $null
                Remove-Item $lock -Force -ErrorAction SilentlyContinue
            } else {
                Set-Content $lock "run-guarded pid $PID $(Get-Date -Format o)"
            }
        } elseif (-not $reason) {
            Set-Content $lock "run-guarded pid $PID $(Get-Date -Format o)"
            # The watcher polls every 15 s and then stops its server; wait for the GPU memory.
            $deadline = (Get-Date).AddMinutes(3)
            while ((Get-Date) -lt $deadline -and (Get-CimInstance Win32_Process -Filter "Name='llama-server.exe'" | Where-Object ExecutablePath -eq "$base\llama\llama-server.exe")) { Start-Sleep -Seconds 5 }
            $reason = Test-Busy $null
            if ($reason -or (Get-CimInstance Win32_Process -Filter "Name='llama-server.exe'" | Where-Object ExecutablePath -eq "$base\llama\llama-server.exe")) {
                Write-Log "not starting ($reason $(if (-not $reason) { 'llama-server still running' }))"
                Remove-Item $lock -Force -ErrorAction SilentlyContinue
            } else {
                $stamp = Get-Date -Format yyyyMMdd-HHmmss
                $argList = @("`"$PSScriptRoot\train.py`"", '--run', $Run, '--data', "`"$Data`"") + $TrainArgs
                $proc = Start-Process $Py -ArgumentList $argList -WorkingDirectory $Root -WindowStyle Hidden -PassThru -RedirectStandardOutput "$Root\runs\$Run.out.$stamp.log" -RedirectStandardError "$Root\runs\$Run.err.$stamp.log"
                $proc.PriorityClass = 'BelowNormal'
                Write-Log "started train.py PID $($proc.Id)"
            }
        }
        Start-Sleep -Seconds 15
    }
} finally {
    if ($proc -and -not $proc.HasExited) { Stop-Training $proc; Write-Log 'stopped training on exit' }
    Remove-Item $lock -Force -ErrorAction SilentlyContinue
    Remove-Item $stop -Force -ErrorAction SilentlyContinue
    $mutex.ReleaseMutex(); $mutex.Dispose()
}
