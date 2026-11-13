BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'BnetState.psm1') -Force
    $script:t = [datetime]'2026-11-13T12:00:00'

    function S([hashtable]$o = @{}) {
        $s = @{ SessionActive = $true; Locked = $false; InputIdleSec = 0; Fullscreen = $false
                MediaPlaying = $false; DisplayRequired = $false; CpuPct = 10; GpuPct = 10; Time = $script:t }
        foreach ($k in $o.Keys) { $s[$k] = $o[$k] }
        $s
    }
    # 36 samples = 3 min at 5 s; -Spike puts one sample at 80 % in the middle.
    function Hist([double]$cpu, [double]$gpu, [switch]$Spike) {
        $h = foreach ($i in 1..36) {
            $c = $cpu; $g = $gpu
            if ($Spike -and $i -eq 18) { $g = 80 }
            @{ CpuPct = $c; GpuPct = $g; Time = $script:t.AddSeconds(-5 * $i) }
        }
        ,@($h)
    }
    function Prev([string]$state, [datetime]$since) {
        ,@(@{ CpuPct = 5; GpuPct = 5; Time = $script:t.AddSeconds(-5)
              Result = [pscustomobject]@{ State = $state; JobAllowed = $false; Since = $since } })
    }
}

Describe 'Get-BnetState' {
    It 'no session or locked is unavailable' {
        (Get-BnetState (S @{ SessionActive = $false }) @() $t).State | Should -Be 'unavailable'
        (Get-BnetState (S @{ Locked = $true }) @() $t).State | Should -Be 'unavailable'
    }
    It 'fullscreen with no input for 30 min is media' {
        (Get-BnetState (S @{ InputIdleSec = 1800; Fullscreen = $true }) @() $t).State | Should -Be 'media'
    }
    It 'media or display-required is media' {
        (Get-BnetState (S @{ MediaPlaying = $true }) @() $t).State | Should -Be 'media'
        (Get-BnetState (S @{ DisplayRequired = $true }) @() $t).State | Should -Be 'media'
    }
    It '10 min no input is idle, 9 min under load is heavy' {
        (Get-BnetState (S @{ InputIdleSec = 600 }) @() $t).State | Should -Be 'idle'
        (Get-BnetState (S @{ InputIdleSec = 540; CpuPct = 80; GpuPct = 80 }) (Hist 80 80) $t).State | Should -Be 'heavy'
    }
    It 'both under 50% over 3 min with input is light' {
        (Get-BnetState (S @{ InputIdleSec = 5; CpuPct = 20; GpuPct = 30 }) (Hist 20 30) $t).State | Should -Be 'light'
    }
    It 'one spike over 50% in the window is heavy' {
        (Get-BnetState (S @{ InputIdleSec = 5; CpuPct = 20; GpuPct = 30 }) (Hist 20 30 -Spike) $t).State | Should -Be 'heavy'
    }
    It 'job allowed only after 60 s in idle/light' {
        $r = Get-BnetState (S @{ InputIdleSec = 600 }) (Prev 'heavy' $t.AddSeconds(-5)) $t
        $r.JobAllowed | Should -BeFalse
        $r = Get-BnetState (S @{ InputIdleSec = 600 }) (Prev 'idle' $t.AddSeconds(-61)) $t
        $r.JobAllowed | Should -BeTrue
    }
    It 'light to idle keeps the clock running' {
        $r = Get-BnetState (S @{ InputIdleSec = 600 }) (Prev 'light' $t.AddSeconds(-90)) $t
        $r.JobAllowed | Should -BeTrue
        $r.Since | Should -Be $t.AddSeconds(-90)
    }
}
