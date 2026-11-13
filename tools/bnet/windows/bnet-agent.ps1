# bnet agent (SYSTEM, scheduled task at startup): classifies the PC every 5 s, stops lab work the moment
# the PC is needed, and answers the lab router on the Tailscale address only (port 47800, bearer token).
#Requires -Version 7
$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
$Dir = 'C:\ProgramData\bnet'
Import-Module "$Here\BnetState.psm1", "$Here\BnetAgent.psm1", "$Here\BnetJobs.psm1" -Force

$conf = Get-Content "$Dir\config.json" -Raw | ConvertFrom-Json
$Cfg = [hashtable]::Synchronized(@{
    Token           = (Get-Content "$Dir\token" -Raw).Trim()
    HostName        = $env:COMPUTERNAME.ToLower()
    Silence         = [bool]$conf.silence
    SilencePowerPct = if ($conf.silence_power_pct) { [int]$conf.silence_power_pct } else { 40 }
    SessionDir      = "$Dir\session"
    Job             = $null
    SilenceOk       = $true
    State           = $null
})
Stop-BnetJob $Cfg   # never start with leftovers from a crash: no lab Ollama, default power limit

$ip = (& 'C:\Program Files\Tailscale\tailscale.exe' ip -4 | Select-Object -First 1).Trim()
$listener = [Net.HttpListener]::new()
$listener.Prefixes.Add("http://${ip}:47800/")
$listener.Start()

# Listener thread: each request runs in its own thread job so a long Ollama stream never blocks /state.
$null = Start-ThreadJob -Name bnet-listener -ArgumentList $listener, $Cfg, $Here -ScriptBlock {
    param($listener, $Cfg, $Here)
    while ($listener.IsListening) {
        $hc = $listener.GetContext()
        $null = Start-ThreadJob -ThrottleLimit 16 -ArgumentList $hc, $Cfg, $Here -ScriptBlock {
            param($hc, $Cfg, $Here)
            Import-Module "$Here\BnetAgent.psm1", "$Here\BnetJobs.psm1"
            $rq = $hc.Request; $rs = $hc.Response
            try {
                $headers = @{}; foreach ($k in $rq.Headers.AllKeys) { $headers[$k] = $rq.Headers[$k] }
                $isOllama = $rq.Url.AbsolutePath.StartsWith('/ollama/')
                $body = if (-not $isOllama -and $rq.HasEntityBody) { [IO.StreamReader]::new($rq.InputStream).ReadToEnd() }
                $ctx = @{
                    Token = $Cfg.Token; HostName = $Cfg.HostName; Silence = $Cfg.Silence; Job = $Cfg.Job
                    GetState = { $Cfg.State }
                    StartJob = { param($k) Start-BnetJob $k $Cfg }
                    StopJob  = { Stop-BnetJob $Cfg }
                }
                $r = Invoke-BnetRequest @{ Method = $rq.HttpMethod; Path = $rq.Url.AbsolutePath; Headers = $headers; Body = $body } $ctx
                if ($r.ProxyTo) {
                    $client = [Net.Http.HttpClient]::new(); $client.Timeout = [TimeSpan]::FromMinutes(30)
                    $msg = [Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::new($rq.HttpMethod), $r.ProxyTo)
                    if ($rq.HasEntityBody) {
                        $msg.Content = [Net.Http.StreamContent]::new($rq.InputStream)
                        $msg.Content.Headers.ContentType = 'application/json'
                    }
                    $up = $client.SendAsync($msg, [Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
                    $rs.StatusCode = [int]$up.StatusCode
                    $rs.ContentType = "$($up.Content.Headers.ContentType)"
                    $rs.SendChunked = $true
                    $up.Content.ReadAsStream().CopyTo($rs.OutputStream)   # streams token by token
                } else {
                    $rs.StatusCode = $r.Status; $rs.ContentType = 'application/json'
                    $b = [Text.Encoding]::UTF8.GetBytes($r.Body); $rs.OutputStream.Write($b, 0, $b.Length)
                }
            } catch { try { $rs.StatusCode = 502 } catch {} }
            finally { $rs.Close() }
        }
    }
}

# Tick: sample, classify, enforce. Runs on the main thread so stopping a job never waits for a request.
$hist = [Collections.Generic.List[object]]::new()
$cores = [Environment]::ProcessorCount
while ($true) {
    $now = Get-Date
    try {
        $s = Read-BnetSession "$Dir\session\session.json" $now
        $p = Get-BnetPowerRequests ((powercfg /requests) -join "`n")
        $s.MediaPlaying = $s.MediaPlaying -or $p.MediaPlaying
        $s.DisplayRequired = $p.DisplayRequired
        # CIM perf classes are locale-independent (counter paths are translated on German Windows).
        $cpu = (Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'").PercentProcessorTime
        $own = (Get-CimInstance Win32_PerfFormattedData_PerfProc_Process -Filter "Name LIKE 'ollama%'" |
                Measure-Object PercentProcessorTime -Sum).Sum / $cores
        $g = & nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>$null
        $gpu = if ($LASTEXITCODE -eq 0) { [double]($g | Select-Object -First 1) } else { 0 }
        $load = Get-BnetUserLoad -CpuTotal $cpu -CpuOllama $own -Gpu $gpu -JobRunning ([bool]$Cfg.Job)
        $s.CpuPct = $load.CpuPct; $s.GpuPct = $load.GpuPct; $s.Time = $now

        $res = Get-BnetState $s $hist.ToArray() $now
        $Cfg.State = [pscustomobject]@{
            State = $res.State; JobAllowed = (Get-BnetJobAllowed $res $Cfg); Since = $res.Since
            CpuPct = [math]::Round($cpu); GpuPct = [math]::Round($gpu)
        }
        Update-BnetJob $Cfg.State $Cfg
        $s.Result = $res
        $hist.Insert(0, $s)                       # newest first, as Get-BnetState expects
        if ($hist.Count -gt 40) { $hist.RemoveAt($hist.Count - 1) }
    } catch {
        # A sensor failure must never leave lab work running unobserved.
        if ($Cfg.Job) { Stop-BnetJob $Cfg }
        $Cfg.State = [pscustomobject]@{ State = 'unavailable'; JobAllowed = $false; Since = $now; CpuPct = 0; GpuPct = 0 }
    }
    Start-Sleep -Seconds 5
}
