$ErrorActionPreference = 'Stop'
function Assert($ok, $message) { if (-not $ok) { throw $message } }
function LlamaIds { @(Get-CimInstance Win32_Process -Filter "Name='llama-server.exe'" | ForEach-Object ProcessId) }
function RunWatch($gpu) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\watch.ps1" -Once -TestPort 28083 -GpuPercent $gpu
    Assert ($LASTEXITCODE -eq 0) 'Watcher failed'
}
$originalId = @(Get-NetTCPConnection -State Listen | Where-Object LocalPort -eq 8081)[0].OwningProcess
$original = Get-Process -Id $originalId
$originalStart = $original.StartTime
Assert ((Invoke-RestMethod http://127.0.0.1:8081/health).status -eq 'ok') 'Original server unhealthy before test'
Assert (-not @(Get-NetTCPConnection -State Listen | Where-Object LocalPort -eq 28083).Count) 'Test port already occupied'
$baseline = @(LlamaIds)
$listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 28083)
$childId = $null
try {
    $listener.Start()
    RunWatch 0
    Assert ((@(LlamaIds) -join ',') -eq ($baseline -join ',')) 'Duplicate start with existing listener'
    RunWatch 99
    Assert ($listener.Server.IsBound) 'Unowned listener stopped'
    'PASS: existing non-llama listener blocks start and is left alone when busy'
    $listener.Stop()
    RunWatch 0
    $record = Get-Content C:\bandit-ai\runtime\watch-28083.pid -Raw | ConvertFrom-Json
    $childId = [int]$record.ProcessId
    Assert ($baseline -notcontains $childId) 'Missing new child'
    Assert ((Get-Process -Id $childId).Path -eq 'C:\bandit-ai\llama\llama-server.exe') 'Unexpected child executable'
    RunWatch 0
    Assert (@(LlamaIds).Count -eq ($baseline.Count + 1)) 'Duplicate start during loading'
    "PASS: unused port starts PID $childId; immediate repeat starts no duplicate"
    $deadline = (Get-Date).AddSeconds(60)
    do {
        try { $healthy = (Invoke-RestMethod http://127.0.0.1:28083/health).status -eq 'ok' } catch { $healthy = $false }
        if (-not $healthy) { Start-Sleep -Seconds 1 }
    } until ($healthy -or (Get-Date) -gt $deadline)
    Assert $healthy 'CPU test server did not become healthy'
    # Remove the record to exercise a server started outside the watcher.
    Remove-Item C:\bandit-ai\runtime\watch-28083.pid
    RunWatch 0
    Assert (@(LlamaIds).Count -eq ($baseline.Count + 1)) 'Duplicate start with healthy listener and no PID record'
    "PASS: healthy listener PID $childId blocks start without a PID record"
    RunWatch 99
    Wait-Process -Id $childId -Timeout 5 -ErrorAction SilentlyContinue
    $stopped = Get-Process -Id $childId -ErrorAction SilentlyContinue
    Assert (-not $stopped -or $stopped.HasExited) 'Busy watcher did not stop identified socket owner'
    Assert (-not @(Get-NetTCPConnection -State Listen | Where-Object LocalPort -eq 28083).Count) 'Stopped server still listening'
    'PASS: busy watcher stops identified external listener'
} finally {
    $listener.Stop()
    if ($childId -and $baseline -notcontains $childId) {
        $child = Get-Process -Id $childId -ErrorAction SilentlyContinue
        if ($child -and $child.Path -eq 'C:\bandit-ai\llama\llama-server.exe') { Stop-Process -Id $childId }
    }
    Assert ((Get-Process -Id $originalId).StartTime -eq $originalStart) 'Original PID changed'
    Assert ((Invoke-RestMethod http://127.0.0.1:8081/health).status -eq 'ok') 'Original server unhealthy after test'
    "PASS: PID $originalId unchanged and /health=ok; spare-port child cleaned up"
}
