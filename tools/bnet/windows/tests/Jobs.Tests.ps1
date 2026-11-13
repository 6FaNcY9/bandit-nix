BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'BnetJobs.psm1') -Force
    function Cfg([bool]$silence) {
        @{ Silence = $silence; SilencePowerPct = 40; SessionDir = $TestDrive; Job = $null; SilenceOk = $true }
    }
}

Describe 'Start-BnetJob' {
    BeforeEach {
        Mock -ModuleName BnetJobs Invoke-BnetNvidia {
            if ($Arguments -contains '--query-gpu=power.default_limit') { return @{ Code = 0; Out = '575.00' } }
            @{ Code = 0; Out = '' }
        }
        Mock -ModuleName BnetJobs Start-BnetService {}
        Mock -ModuleName BnetJobs Stop-BnetService {}
        Mock -ModuleName BnetJobs Invoke-BnetOllama { @{ Code = 0; Out = '' } }
    }
    It 'with silence it sets the power limit to 40 % of the default before starting ollama' {
        $c = Cfg $true
        Start-BnetJob 'ollama' $c | Should -BeTrue
        Should -Invoke -ModuleName BnetJobs Invoke-BnetNvidia -ParameterFilter { $Arguments -join ' ' -eq '-pl 230' }
        Should -Invoke -ModuleName BnetJobs Start-BnetService -ParameterFilter { $Name -eq 'ollama' }
        $c.Job | Should -Be 'ollama'
    }
    It 'refuses the job when the power limit cannot be set' {
        Mock -ModuleName BnetJobs Invoke-BnetNvidia {
            if ($Arguments -contains '--query-gpu=power.default_limit') { return @{ Code = 0; Out = '575.00' } }
            @{ Code = 1; Out = 'Insufficient Permissions' }
        }
        $c = Cfg $true
        Start-BnetJob 'ollama' $c | Should -BeFalse
        Should -Invoke -ModuleName BnetJobs Start-BnetService -Times 0
        $c.SilenceOk | Should -BeFalse
        $c.Job | Should -BeNullOrEmpty
    }
    It 'without silence it does not touch the power limit' {
        Start-BnetJob 'ollama' (Cfg $false) | Should -BeTrue
        Should -Invoke -ModuleName BnetJobs Invoke-BnetNvidia -Times 0 -ParameterFilter { $Arguments -contains '-pl' }
    }
    It 'writes a visible notice file while the job runs' {
        $c = Cfg $false
        Start-BnetJob 'ollama' $c | Out-Null
        (Get-Content (Join-Path $TestDrive 'job.json') -Raw | ConvertFrom-Json).job | Should -Be 'ollama'
    }
}

Describe 'Stop-BnetJob' {
    BeforeEach {
        Mock -ModuleName BnetJobs Invoke-BnetNvidia {
            if ($Arguments -contains '--query-gpu=power.default_limit') { return @{ Code = 0; Out = '575.00' } }
            @{ Code = 0; Out = '' }
        }
        Mock -ModuleName BnetJobs Stop-BnetService {}
        Mock -ModuleName BnetJobs Invoke-BnetOllama {
            if ($Arguments[0] -eq 'ps') { return @{ Code = 0; Out = "NAME          ID    SIZE   PROCESSOR  UNTIL`nqwen3:32b     abc   20 GB  100% GPU   4 minutes from now`nllama3:8b     def   5 GB   100% GPU   now" } }
            @{ Code = 0; Out = '' }
        }
    }
    It 'unloads every model, stops ollama, restores the default limit and removes the notice' {
        $c = Cfg $true; $c.Job = 'ollama'
        Set-Content (Join-Path $TestDrive 'job.json') '{"job":"ollama"}'
        Stop-BnetJob $c
        Should -Invoke -ModuleName BnetJobs Invoke-BnetOllama -ParameterFilter { $Arguments -join ' ' -eq 'stop qwen3:32b' }
        Should -Invoke -ModuleName BnetJobs Invoke-BnetOllama -ParameterFilter { $Arguments -join ' ' -eq 'stop llama3:8b' }
        Should -Invoke -ModuleName BnetJobs Stop-BnetService -ParameterFilter { $Name -eq 'ollama' }
        Should -Invoke -ModuleName BnetJobs Invoke-BnetNvidia -ParameterFilter { $Arguments -join ' ' -eq '-pl 575' }
        Join-Path $TestDrive 'job.json' | Should -Not -Exist
        $c.Job | Should -BeNullOrEmpty
    }
}

Describe 'Update-BnetJob' {
    It 'stops a running job as soon as the PC leaves the allowed state' {
        Mock -ModuleName BnetJobs Stop-BnetJob {}
        $c = Cfg $false; $c.Job = 'ollama'
        Update-BnetJob ([pscustomobject]@{ State = 'heavy'; JobAllowed = $false }) $c
        Should -Invoke -ModuleName BnetJobs Stop-BnetJob -Times 1
    }
    It 'leaves a job alone while still allowed' {
        Mock -ModuleName BnetJobs Stop-BnetJob {}
        $c = Cfg $false; $c.Job = 'ollama'
        Update-BnetJob ([pscustomobject]@{ State = 'idle'; JobAllowed = $true }) $c
        Should -Invoke -ModuleName BnetJobs Stop-BnetJob -Times 0
    }
}

Describe 'Get-BnetJobAllowed' {
    It 'is false on a silent PC whose power limit failed' {
        $c = Cfg $true; $c.SilenceOk = $false
        Get-BnetJobAllowed ([pscustomobject]@{ JobAllowed = $true }) $c | Should -BeFalse
    }
    It 'follows the classifier otherwise' {
        Get-BnetJobAllowed ([pscustomobject]@{ JobAllowed = $true }) (Cfg $true) | Should -BeTrue
        Get-BnetJobAllowed ([pscustomobject]@{ JobAllowed = $false }) (Cfg $false) | Should -BeFalse
    }
}

Describe 'Get-BnetUserLoad' {
    It 'without a job the measured load is the user load' {
        $l = Get-BnetUserLoad -CpuTotal 90 -CpuOllama 0 -Gpu 95 -JobRunning $false
        $l.CpuPct | Should -Be 90
        $l.GpuPct | Should -Be 95
    }
    It 'while our job runs its own CPU share and the GPU do not count' {
        $l = Get-BnetUserLoad -CpuTotal 90 -CpuOllama 70 -Gpu 95 -JobRunning $true
        $l.CpuPct | Should -Be 20
        $l.GpuPct | Should -Be 0
    }
    It 'never goes below zero' {
        (Get-BnetUserLoad -CpuTotal 10 -CpuOllama 30 -Gpu 0 -JobRunning $true).CpuPct | Should -Be 0
    }
}
