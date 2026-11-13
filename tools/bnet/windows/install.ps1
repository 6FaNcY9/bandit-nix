# bnet installer: run once at the PC, in an elevated PowerShell 7, from this folder:
#   pwsh -File install.ps1 -Config config.albert.json -Token <token from the lab>
# Re-running it updates the scripts and keeps the token unless a new one is given.
#Requires -Version 7
#Requires -RunAsAdministrator
param([Parameter(Mandatory)][string]$Config, [string]$Token)
$ErrorActionPreference = 'Stop'

$Code = 'C:\Program Files\bnet'
$Data = 'C:\ProgramData\bnet'
$pwsh = (Get-Command pwsh).Source

# Code: replaced on every run.
New-Item -ItemType Directory -Force $Code | Out-Null
Copy-Item "$PSScriptRoot\*.psm1", "$PSScriptRoot\bnet-agent.ps1", "$PSScriptRoot\bnet-sensor.ps1" $Code -Force

# Data: token and config readable only by SYSTEM and Administrators; session\ writable by the sensor (users).
New-Item -ItemType Directory -Force $Data, "$Data\session", "$Data\models" | Out-Null
icacls $Data /inheritance:r /grant:r 'SYSTEM:(OI)(CI)F' 'Administrators:(OI)(CI)F' | Out-Null
icacls "$Data\session" /grant 'Users:(OI)(CI)M' | Out-Null
Copy-Item $Config "$Data\config.json" -Force
if ($Token) { Set-Content "$Data\token" $Token.Trim() -NoNewline }
if (-not (Test-Path "$Data\token")) { throw 'No token: pass -Token on the first install.' }

# Ollama for the lab: its own instance on 127.0.0.1:11435, started and stopped only by the agent.
$ollama = (Get-Command ollama -ErrorAction SilentlyContinue).Source
if (-not $ollama) {
    winget install --id Ollama.Ollama --scope machine --silent --accept-package-agreements --accept-source-agreements
    $ollama = (Get-Command ollama).Source
}
$serve = "set OLLAMA_HOST=127.0.0.1:11435&& set OLLAMA_MODELS=$Data\models&& `"$ollama`" serve"
$sys = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$keep = New-ScheduledTaskSettingsSet -ExecutionTimeLimit 0 -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -AllowStartIfOnBatteries
Register-ScheduledTask bnet-ollama -Force -Principal $sys -Settings $keep `
    -Action (New-ScheduledTaskAction -Execute 'cmd.exe' -Argument "/c $serve") | Out-Null

Register-ScheduledTask bnet-agent -Force -Principal $sys -Settings $keep -Trigger (New-ScheduledTaskTrigger -AtStartup) `
    -Action (New-ScheduledTaskAction -Execute $pwsh -Argument "-NoProfile -NonInteractive -File `"$Code\bnet-agent.ps1`"") | Out-Null

$users = New-ScheduledTaskPrincipal -GroupId 'BUILTIN\Users' -RunLevel Limited
Register-ScheduledTask bnet-sensor -Force -Principal $users -Settings $keep -Trigger (New-ScheduledTaskTrigger -AtLogOn) `
    -Action (New-ScheduledTaskAction -Execute $pwsh -Argument "-NoProfile -WindowStyle Hidden -File `"$Code\bnet-sensor.ps1`"") | Out-Null

# Reachable only through Tailscale.
Get-NetFirewallRule -DisplayName 'bnet-agent' -ErrorAction SilentlyContinue | Remove-NetFirewallRule
New-NetFirewallRule -DisplayName 'bnet-agent' -Direction Inbound -Protocol TCP -LocalPort 47800 `
    -InterfaceAlias 'Tailscale' -Action Allow | Out-Null

Stop-ScheduledTask bnet-agent -ErrorAction SilentlyContinue
Start-ScheduledTask bnet-agent
Start-ScheduledTask bnet-sensor   # for the session that is logged in now
"bnet installed. Check: Invoke-RestMethod http://$((& 'C:\Program Files\Tailscale\tailscale.exe' ip -4)[0]):47800/state -Headers @{Authorization='Bearer <token>'}"
