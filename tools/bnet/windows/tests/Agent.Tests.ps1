BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'BnetAgent.psm1') -Force
    $script:now = [datetime]'2026-11-13T12:00:00'
    $script:tok = 'secret-token'

    function Ctx([bool]$allowed = $true) {
        $n = $script:now
        $c = @{
            Token    = $script:tok
            HostName = 'albert'
            Silence  = $true
            Job      = $null
            Started  = 0
            GetState = { [pscustomobject]@{ State = 'idle'; JobAllowed = $allowed; Since = $n; CpuPct = 4; GpuPct = 3 } }.GetNewClosure()
        }
        $c.StartJob = { param($kind) $c.Started++; $c.Job = $kind; $true }.GetNewClosure()
        $c.StopJob  = { $c.Job = $null }.GetNewClosure()
        $c
    }
    function Req($method, $path, $token = $script:tok, $body = $null) {
        $h = @{}; if ($token) { $h['Authorization'] = "Bearer $token" }
        @{ Method = $method; Path = $path; Headers = $h; Body = $body }
    }
}

Describe 'Invoke-BnetRequest' {
    It 'GET /state without token is 401' {
        (Invoke-BnetRequest (Req GET /state $null) (Ctx)).Status | Should -Be 401
    }
    It 'GET /state with a wrong token is 401' {
        (Invoke-BnetRequest (Req GET /state 'nope') (Ctx)).Status | Should -Be 401
    }
    It 'GET /state with token is 200 with all fields' {
        $r = Invoke-BnetRequest (Req GET /state) (Ctx)
        $r.Status | Should -Be 200
        $b = $r.Body | ConvertFrom-Json -AsHashtable
        foreach ($k in 'host', 'state', 'job_allowed', 'since', 'gpu_pct', 'cpu_pct', 'job', 'silence') { $b.Keys | Should -Contain $k }
        $b.host | Should -Be 'albert'
        $b.state | Should -Be 'idle'
    }
    It 'POST /job/start is 409 when no job is allowed' {
        $c = Ctx $false
        (Invoke-BnetRequest (Req POST /job/start $script:tok '{"kind":"ollama"}') $c).Status | Should -Be 409
        $c.Started | Should -Be 0
    }
    It 'POST /job/start starts the job when allowed' {
        $c = Ctx $true
        (Invoke-BnetRequest (Req POST /job/start $script:tok '{"kind":"ollama"}') $c).Status | Should -Be 200
        $c.Job | Should -Be 'ollama'
    }
    It 'ollama path without a running job is 409' {
        (Invoke-BnetRequest (Req POST /ollama/api/generate) (Ctx)).Status | Should -Be 409
    }
    It 'ollama path with a running job is handed to the local ollama' {
        $c = Ctx; $c.Job = 'ollama'
        $r = Invoke-BnetRequest (Req POST /ollama/api/generate) $c
        $r.ProxyTo | Should -Be 'http://127.0.0.1:11435/api/generate'
    }
    It 'ollama path without token is 401' {
        $c = Ctx; $c.Job = 'ollama'
        (Invoke-BnetRequest (Req POST /ollama/api/generate $null) $c).Status | Should -Be 401
    }
    It 'unknown path is 404' {
        (Invoke-BnetRequest (Req GET /nope) (Ctx)).Status | Should -Be 404
    }
}

Describe 'Read-BnetSession' {
    It 'missing file is no session' {
        (Read-BnetSession (Join-Path $TestDrive 'none.json') $script:now).SessionActive | Should -BeFalse
    }
    It 'a sensor file older than 30 s is no session' {
        $p = Join-Path $TestDrive 's.json'
        @{ Time = $script:now.AddSeconds(-31).ToString('o'); SessionActive = $true; Locked = $false; InputIdleSec = 3
           Fullscreen = $false; MediaPlaying = $false } | ConvertTo-Json | Set-Content $p
        (Read-BnetSession $p $script:now).SessionActive | Should -BeFalse
    }
    It 'a fresh sensor file is passed through' {
        $p = Join-Path $TestDrive 's.json'
        @{ Time = $script:now.AddSeconds(-4).ToString('o'); SessionActive = $true; Locked = $false; InputIdleSec = 700
           Fullscreen = $true; MediaPlaying = $false } | ConvertTo-Json | Set-Content $p
        $s = Read-BnetSession $p $script:now
        $s.SessionActive | Should -BeTrue
        $s.InputIdleSec | Should -Be 700
        $s.Fullscreen | Should -BeTrue
    }
}

Describe 'Get-BnetPowerRequests' {
    It 'video wake lock and audio stream are seen' {
        $t = "DISPLAY:`n[PROCESS] \Device\HarddiskVolume3\Program Files\Mozilla Firefox\firefox.exe`nVideo Wake Lock`n`nSYSTEM:`n[DRIVER] Realtek High Definition Audio (HDAUDIO\FUNC_01)`nAn audio stream is currently in use.`n`nAWAYMODE:`nNone.`n"
        $r = Get-BnetPowerRequests $t
        $r.DisplayRequired | Should -BeTrue
        $r.MediaPlaying | Should -BeTrue
    }
    It 'nothing requested is nothing' {
        $t = "DISPLAY:`nNone.`n`nSYSTEM:`nNone.`n`nAWAYMODE:`nNone.`n`nEXECUTION:`nNone.`n"
        $r = Get-BnetPowerRequests $t
        $r.DisplayRequired | Should -BeFalse
        $r.MediaPlaying | Should -BeFalse
    }
    It 'a system request without audio is not media' {
        $t = "DISPLAY:`nNone.`n`nSYSTEM:`n[SERVICE] \Device\HarddiskVolume3\Windows\System32\svchost.exe (wuauserv)`nWindows Update`n"
        (Get-BnetPowerRequests $t).MediaPlaying | Should -BeFalse
    }
}
