$ErrorActionPreference = 'Stop'
function Assert($ok, $message) { if (-not $ok) { throw $message } }
$installer = Get-Content "$PSScriptRoot\install.ps1" -Raw
$watcher = Get-Content "$PSScriptRoot\watch.ps1" -Raw
$vbs = Get-Content "$PSScriptRoot\watch.vbs" -Raw
foreach ($text in $installer, $watcher) {
    $tokens = $null; $errors = $null
    [Management.Automation.Language.Parser]::ParseInput($text, [ref]$tokens, [ref]$errors) | Out-Null
    Assert (-not $errors.Count) "PowerShell parse failed: $($errors[0])"
}
Assert ($installer -notmatch '(?i)irm\s*\|\s*iex') 'Installer must not use irm|iex'
Assert ($installer -match 'Start-BitsTransfer.*Priority Low') 'Downloads must use low-priority BITS'
Assert ($installer -match 'S-1-5-32-544' -and $installer -match 'S-1-5-18') 'ACLs must use Administrators and SYSTEM SIDs'
Assert ($installer -match '100\.64\.0\.0/10') 'SSH firewall must be tailnet-only'
Assert ($installer -match "wscript\.exe.*watch\.vbs") 'Task must launch the VBS wrapper'
Assert ($watcher -match 'Get-FileHash.*SHA256' -and $watcher -match 'model missing or checksum mismatch') 'Watcher must gate serving on model verification'
Assert ($vbs -match 'shell\.Run.*powershell\.exe.*watch\.ps1.*0, False') 'VBS must launch PowerShell hidden and asynchronously'
foreach ($name in 'watch.ps1', 'watch.vbs', 'light-games.txt') {
    $pattern = "'" + [regex]::Escape($name) + "' = '([^']+)'"
    $payload = [regex]::Match($installer, $pattern).Groups[1].Value
    $source = Get-Content (Join-Path $PSScriptRoot $name) -Raw
    Assert ($payload -and [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload)) -eq $source) "Embedded $name payload is stale"
}

$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseInput($installer, [ref]$tokens, [ref]$errors)
foreach ($name in 'KeyBlob', 'Validate-Key', 'Set-AuthorizedKeys', 'Download-Verified') {
    $definition = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true)
    . ([scriptblock]::Create($definition.Extent.Text))
}
$key = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIQqLzKYo4S6Ldqfyt9kWOUPNg82r8/QsJTKOPsqN1G9 test'
$restricted = 'restrict,port-forwarding,permitopen="127.0.0.1:8081" ' + $key
Validate-Key $key
Assert ((KeyBlob $restricted) -eq (KeyBlob $key)) 'Option-prefixed keys must identify the same blob'
foreach ($bad in @($restricted, "$key`n$key", 'ssh-ed25519 AAAA bad')) {
    $rejected = $false
    try { Validate-Key $bad } catch { $rejected = $true }
    Assert $rejected 'Malformed or multiline public key accepted'
}
$path = Join-Path ([IO.Path]::GetTempPath()) "bandit-install-test-$PID"
New-Item -ItemType Directory $path | Out-Null
function Set-ExactAcl { param($Path, $UserSid) }
try {
    $keys = Join-Path $path 'keys'
    Set-Content $keys @($key, $restricted, '# preserve this line')
    Set-AuthorizedKeys $keys @($restricted)
    Set-AuthorizedKeys $keys @($restricted)
    $lines = @(Get-Content $keys)
    Assert ($lines.Count -eq 2 -and $lines -contains $restricted -and $lines -contains '# preserve this line') 'Key migration/reinstall must remove unrestricted duplicates and preserve unrelated lines'
    $part = Join-Path $path 'download'
    $script:bitsCalls = 0
    function Start-BitsTransfer { param($Source, $Destination, $Priority) Assert ($Priority -eq 'Low') 'BITS priority changed'; $script:bitsCalls++; Set-Content $Destination 'fixture' }
    Start-BitsTransfer 'fixture' $part 'Low'
    $hash = (Get-FileHash $part -Algorithm SHA256).Hash.ToLowerInvariant()
    Download-Verified 'fixture' $part $hash
    Assert ($script:bitsCalls -eq 1) 'Verified existing download must not download again'
    $rejected = $false
    try { Download-Verified 'fixture' $part ('0' * 64) } catch { $rejected = $true }
    Assert ($rejected -and -not (Test-Path $part)) 'Bad download must be discarded for retry'
    Download-Verified 'fixture' $part $hash
    Assert ($script:bitsCalls -eq 2) 'Discarded download must retry'
} finally { Remove-Item $path -Recurse -Force }
Assert ($installer -match 'SetOwner\(\$admin\)' -and $installer -match 'Assert-NoLinks') 'Privileged script owner and reparse guard required'
Assert ($installer -match "light-games.txt' -and \(Test-Path") 'Existing allowlist must be preserved'
$watchAst = [Management.Automation.Language.Parser]::ParseInput($watcher, [ref]$tokens, [ref]$errors)
$definition = $watchAst.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'ModelVerified' }, $true)
. ([scriptblock]::Create($definition.Extent.Text))
$model = 'fixture-model'; $modelSha256 = 'good'; $script:modelCheck = $null; $script:hashCalls = 0
$script:item = [pscustomobject]@{ Length = 10; LastWriteTimeUtc = [datetime]'2026-10-10'; PSIsContainer = $false }
function Get-Item { param($Path, $ErrorAction) $script:item }
function Get-FileHash { param($Path, $Algorithm) $script:hashCalls++; @{ Hash = $script:hashResult } }
function Get-Content { throw 'Verification must not trust a user-writable cache' }
$script:hashResult = 'good'
Assert (ModelVerified) 'Good hash rejected'
Assert (ModelVerified) 'Cached good hash rejected'
Assert ($script:hashCalls -eq 1) 'Unchanged model should hash once per watcher process'
$script:item.Length++
$script:hashResult = 'bad'
Assert (-not (ModelVerified)) 'Changed model must be verified again'
Assert ($script:hashCalls -eq 2) 'Changed model hash skipped'
$start = $watchAst.Find({ param($node) $node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Start-Process' }, $true)
$block = $start.Parent
while ($block -isnot [Management.Automation.Language.StatementBlockAst]) { $block = $block.Parent }
$launch = $block.Extent.Text.Trim()
$launch = [scriptblock]::Create($launch.Substring(1, $launch.Length - 2))
$script:starts = 0
function Start-Process { $script:starts++; throw 'Must not launch during a game' }
function Busy { 'game appeared' }
$deferred = $false
try { & $launch } catch { $deferred = $_.Exception.Message -match 'launch deferred' }
Assert ($deferred -and $script:starts -eq 0) 'Game appearing during hashing must prevent launch'
'PASS: payload parity, key migration, retry checksums, verification cache and game-start race'
