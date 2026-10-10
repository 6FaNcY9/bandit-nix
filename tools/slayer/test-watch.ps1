$ErrorActionPreference = 'Stop'
$base = 'C:\bandit-ai'
$port = 28083
$session = 1
$pidFile = Join-Path $env:TEMP "bandit-watch-test-$PID.pid"
$tokens = $null
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'watch.ps1'), [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw $errors[0] }
foreach ($name in @('Listeners', 'Servers')) {
    $definition = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true)
    . ([scriptblock]::Create($definition.Extent.Text))
}
function Get-NetTCPConnection { param($State, $ErrorAction) $script:sockets }
function Get-CimInstance { param($ClassName, $Filter) $script:processes }
# PowerShell 7 parses JSON dates automatically; emulate Windows PowerShell 5.1.
function ConvertFrom-Json {
    param([Parameter(ValueFromPipeline)]$InputObject)
    process {
        $record = Microsoft.PowerShell.Utility\ConvertFrom-Json $InputObject
        $record.CreationDate = ([datetime]$record.CreationDate).ToString('o')
        $record
    }
}
function Assert($condition, $message) { if (-not $condition) { throw $message } }
$created = [datetime]'2026-10-10T13:00:00'
$script:processes = @(
    [pscustomobject]@{ ProcessId = 10; SessionId = 0; ExecutablePath = "$base\llama\llama-server.exe"; CommandLine = $null; CreationDate = $created },
    [pscustomobject]@{ ProcessId = 11; SessionId = 1; ExecutablePath = "$base\llama\llama-server.exe"; CommandLine = "llama-server.exe --port $port"; CreationDate = $created },
    [pscustomobject]@{ ProcessId = 12; SessionId = 1; ExecutablePath = 'C:\other\llama-server.exe'; CommandLine = "llama-server.exe --port $port"; CreationDate = $created }
)
try {
    $script:sockets = @([pscustomobject]@{ LocalPort = $port; OwningProcess = 10 })
    $listeners = @(Listeners)
    Assert ($listeners.Count -eq 1) 'Hidden command line must not hide a listener'
    Assert ((@(Servers $listeners).ProcessId -join ',') -eq '10,11') 'Stop only identified executable/session or socket owners'
    $script:sockets = @([pscustomobject]@{ LocalPort = $port; OwningProcess = 12 })
    Assert ((@(Servers (Listeners)).ProcessId -join ',') -eq '11') 'Other executable must never be stopped'
    $script:sockets = @()
    Assert (@(Listeners).Count -eq 0) 'Unused port must be empty'
    Assert ((@(Servers @()).ProcessId -join ',') -eq '11') 'Unowned cross-session process must be left alone'
    @{ ProcessId = 10; CreationDate = $created.ToString('o') } | ConvertTo-Json | Set-Content $pidFile
    Assert ((@(Servers @()).ProcessId -join ',') -eq '10,11') 'Recorded child must be recognized before it listens'
    $script:processes[0].CreationDate = $created.AddMinutes(1)
    Assert ((@(Servers @()).ProcessId -join ',') -eq '11') 'Stale record must not authorize a reused PID'
    'PASS: listener detection, session/path ownership, loading child, stale PID'
} finally {
    Remove-Item $pidFile -ErrorAction SilentlyContinue
}
