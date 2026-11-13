# bnet agent: request handling and sensor-file reading (testable on any OS).
# The Windows-only parts (sensors, listener loop, service) live in bnet-agent.ps1 / bnet-sensor.ps1.

$SensorMaxAgeSec = 30
$OllamaLocal = 'http://127.0.0.1:11435'   # own instance, so a user's Ollama app on 11434 is untouched

function Test-BnetToken([hashtable]$Headers, [string]$Token) {
    $auth = $Headers['Authorization']
    if (-not $Token -or -not $auth -or -not $auth.StartsWith('Bearer ')) { return $false }
    $a = [Text.Encoding]::UTF8.GetBytes($auth.Substring(7))
    $b = [Text.Encoding]::UTF8.GetBytes($Token)
    [Security.Cryptography.CryptographicOperations]::FixedTimeEquals($a, $b)
}

function Invoke-BnetRequest {
    # Returns @{ Status; Body } or, for /ollama/*, @{ Status = 200; ProxyTo = <url> } for the listener to stream.
    param([Parameter(Mandatory, Position = 0)][hashtable]$Request, [Parameter(Mandatory, Position = 1)][hashtable]$Context)

    $json = { param($status, $obj) @{ Status = $status; Body = ($obj | ConvertTo-Json -Compress) } }
    if (-not (Test-BnetToken $Request.Headers $Context.Token)) { return & $json 401 @{ error = 'unauthorized' } }

    $s = & $Context.GetState
    switch -Regex ("$($Request.Method) $($Request.Path)") {
        '^GET /state$' {
            return & $json 200 ([ordered]@{
                host = $Context.HostName; state = $s.State; job_allowed = [bool]$s.JobAllowed
                since = $s.Since.ToString('o'); gpu_pct = $s.GpuPct; cpu_pct = $s.CpuPct
                job = $Context.Job; silence = [bool]$Context.Silence })
        }
        '^POST /job/start$' {
            if (-not $s.JobAllowed) { return & $json 409 @{ error = "not allowed in state $($s.State)" } }
            $kind = 'ollama'
            if ($Request.Body) { $k = ($Request.Body | ConvertFrom-Json).kind; if ($k) { $kind = $k } }
            if (-not (& $Context.StartJob $kind)) { return & $json 409 @{ error = 'job could not start' } }
            return & $json 200 @{ job = $kind }
        }
        '^POST /job/stop$' { & $Context.StopJob; return & $json 200 @{ job = $null } }
        '^(GET|POST|DELETE) /ollama(/.*)$' {
            if ($Context.Job -ne 'ollama') { return & $json 409 @{ error = 'no ollama job running' } }
            return @{ Status = 200; ProxyTo = $OllamaLocal + $Matches[2] }
        }
    }
    & $json 404 @{ error = 'not found' }
}

function Read-BnetSession {
    # The sensor runs in the user's session and rewrites this file every 5 s; stale or missing = nobody there.
    param([Parameter(Mandatory, Position = 0)][string]$Path, [Parameter(Position = 1)][datetime]$Now = (Get-Date))
    $none = @{ SessionActive = $false; Locked = $false; InputIdleSec = 0; Fullscreen = $false; MediaPlaying = $false }
    if (-not (Test-Path $Path)) { return $none }
    try { $j = Get-Content $Path -Raw | ConvertFrom-Json -AsHashtable } catch { return $none }
    if (-not $j.Time -or ($Now - [datetime]$j.Time).TotalSeconds -gt $SensorMaxAgeSec) { return $none }
    @{ SessionActive = [bool]$j.SessionActive; Locked = [bool]$j.Locked; InputIdleSec = [int]$j.InputIdleSec
       Fullscreen = [bool]$j.Fullscreen; MediaPlaying = [bool]$j.MediaPlaying }
}

function Get-BnetPowerRequests {
    # Parses `powercfg /requests` (needs admin): a DISPLAY request means video/fullscreen keep-awake,
    # an "audio stream" line under SYSTEM means sound is playing. Either way somebody is watching/listening.
    param([Parameter(Mandatory, Position = 0)][AllowEmptyString()][string]$Text)
    $sections = @{}; $cur = $null
    foreach ($line in $Text -split "`r?`n") {
        if ($line -match '^([A-Z]+):\s*$') { $cur = $Matches[1]; $sections[$cur] = @(); continue }
        if ($cur -and $line.Trim()) { $sections[$cur] += $line.Trim() }
    }
    $busy = { param($name) $l = $sections[$name]; $l -and -not ($l.Count -eq 1 -and $l[0] -eq 'None.') }
    @{
        DisplayRequired = [bool](& $busy 'DISPLAY')
        MediaPlaying    = [bool](@($sections['SYSTEM']) -match 'audio stream')
    }
}

Export-ModuleMember -Function Invoke-BnetRequest, Read-BnetSession, Test-BnetToken, Get-BnetPowerRequests
