param(
    [switch]$Once,
    [Nullable[int]]$GpuPercent = $null,
    [int]$TestPort = 0
)
$ErrorActionPreference = 'Stop'
$base = 'C:\bandit-ai'
$runtime = "$base\runtime"
if (-not (Test-Path $runtime)) { $null = New-Item -ItemType Directory $runtime }
$model = "$base\models\andy.gguf"
$modelSha256 = '3cfccaa17be8d2ded998fab8bd4b7032f91f2a916ac2aa03a412908342228eb1'
$script:modelFailureLogged = $false
$port = 8081
$layers = 99
# A CPU-only second server lets checks leave the replay's GPU server alone.
if ($TestPort) {
    if ($TestPort -le 1024 -or $TestPort -gt 65535 -or $TestPort -eq 8081) { throw 'Invalid test port' }
    $port = $TestPort
    $layers = 0
}
$mutex = New-Object Threading.Mutex($false, "Local\bandit-ai-watch-$port")
if (-not $mutex.WaitOne(0)) { exit }
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class BanditWindow {
    [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left, Top, Right, Bottom; }
    [DllImport("kernel32.dll")] public static extern uint WTSGetActiveConsoleSessionId();
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern IntPtr GetShellWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out Rect r);
    [DllImport("user32.dll")] public static extern IntPtr MonitorFromWindow(IntPtr h, uint flags);
    [StructLayout(LayoutKind.Sequential)] public struct Monitor { public int Size; public Rect Bounds, Work; public uint Flags; }
    [DllImport("user32.dll")] public static extern bool GetMonitorInfo(IntPtr h, ref Monitor m);
    public static uint ForegroundPid() { uint pid; GetWindowThreadProcessId(GetForegroundWindow(), out pid); return pid; }
    public static bool Fullscreen() {
        var h = GetForegroundWindow();
        if (h == IntPtr.Zero || h == GetShellWindow()) return false;
        Rect r; var m = new Monitor(); m.Size = Marshal.SizeOf(m);
        if (!GetWindowRect(h, out r) || !GetMonitorInfo(MonitorFromWindow(h, 2), ref m)) throw new Exception("Window probe failed");
        return r.Left <= m.Bounds.Left && r.Top <= m.Bounds.Top && r.Right >= m.Bounds.Right && r.Bottom >= m.Bounds.Bottom;
    }
}
'@
function Write-Log($message) {
    $log = "$runtime\watch.log"
    if ((Test-Path $log) -and (Get-Item $log).Length -ge 5MB) { Move-Item $log "$log.1" -Force }
    Add-Content $log "$(Get-Date -Format o) port=$port $message"
}
$pidFile = "$runtime\watch-$port.pid"
$session = (Get-Process -Id $PID).SessionId
function Listeners {
    # Enumerate first: querying an unused LocalPort reports an error, not an empty list.
    @(Get-NetTCPConnection -State Listen -ErrorAction Stop | Where-Object { $_.LocalPort -eq $port })
}
function Servers($listeners) {
    $record = $null
    if (Test-Path $pidFile) { $record = Get-Content $pidFile -Raw | ConvertFrom-Json }
    @(Get-CimInstance Win32_Process -Filter "Name='llama-server.exe'" | Where-Object {
        $_.ExecutablePath -eq "$base\llama\llama-server.exe" -and
        ((($_.SessionId -eq $session) -and $_.CommandLine -match "--port\s+$port(?:\s|$)") -or
         ($listeners.OwningProcess -contains $_.ProcessId) -or
         ($record -and $_.ProcessId -eq $record.ProcessId -and
          $_.CreationDate.ToString('o') -eq $record.CreationDate))
    })
}
function Busy {
    if (-not $TestPort -and [BanditWindow]::WTSGetActiveConsoleSessionId() -ne (Get-Process -Id $PID).SessionId) { return 'another console session (or no console)' }
    # Light games never count as games and do not trigger the fullscreen rule while focused.
    $light = @('isaac-ng.exe', 'isaac.exe', 'wallpaper64.exe', 'wallpaper32.exe', 'chrome.exe', 'msedge.exe', 'firefox.exe', 'brave.exe', 'vlc.exe')
    if (Test-Path "$base\light-games.txt") {
        $light += @(Get-Content "$base\light-games.txt" | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') })
    }
    $foreground = Get-CimInstance Win32_Process -Filter "ProcessId=$([BanditWindow]::ForegroundPid())"
    $lightForeground = $null -ne $foreground -and $light -contains $foreground.Name
    if (-not $lightForeground -and [BanditWindow]::Fullscreen()) { return 'fullscreen window' }
    $games = @(Get-CimInstance Win32_Process | Where-Object {
        $_.Name -notin $light -and (
            $_.Name -match '^(Minecraft|javaw|RobloxPlayerBeta|FortniteClient-Win64-Shipping|VALORANT-Win64-Shipping|cs2|GTA5|RocketLeague)\.exe$' -or
            $_.ExecutablePath -match '\\(steamapps\\common|Epic Games|Riot Games)\\'
        )
    })
    if ($games.Count) { return "game $($games[0].Name)" }
    if ($null -ne $GpuPercent) { $usage = $GpuPercent }
    else {
        $llama = @(Get-CimInstance Win32_Process -Filter "Name='llama-server.exe'" | ForEach-Object ProcessId)
        $counters = @(Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine)
        if (-not $counters.Count) { throw 'No GPU engine counters; refusing inference' }
        $engines = @{}
        foreach ($counter in $counters) {
            if ($counter.Name -notmatch '^pid_(\d+)_(.+)$') { throw 'Unrecognized GPU counter' }
            if ($llama -contains [int]$Matches[1]) { continue }
            $engine = $Matches[2]
            $engines[$engine] += [int]$counter.UtilizationPercentage
        }
        $usage = ($engines.Values | Measure-Object -Maximum).Maximum
    }
    if ($usage -ge 20) { return "non-llama GPU $usage%" }
    return $null
}
$script:modelCheck = $null
function ModelVerified {
    $item = Get-Item $model -ErrorAction SilentlyContinue
    if (-not $item -or $item.PSIsContainer) { return $false }
    $stamp = "$($item.Length):$($item.LastWriteTimeUtc.Ticks)"
    if ($script:modelCheck -and $script:modelCheck.Stamp -eq $stamp) { return $script:modelCheck.Verified }
    $verified = (Get-FileHash $model -Algorithm SHA256).Hash.ToLowerInvariant() -eq $modelSha256
    $script:modelCheck = @{ Stamp = $stamp; Verified = $verified }
    return $verified
}

try {
    do {
        $cycle = [Diagnostics.Stopwatch]::StartNew()
        try {
            $reason = Busy
        } catch { $reason = "probe failed: $($_.Exception.Message)" }
        try {
            $listeners = @(Listeners)
            $servers = @(Servers $listeners)
            if ($reason) {
                foreach ($server in $servers) {
                    Stop-Process -Id $server.ProcessId -ErrorAction Stop
                    Write-Log "stopped PID $($server.ProcessId): $reason"
                }
                foreach ($listener in $listeners) {
                    if ($servers.ProcessId -notcontains $listener.OwningProcess) {
                        Write-Log "left listener PID $($listener.OwningProcess): not ours to stop ($reason)"
                    }
                }
            } elseif (-not $listeners.Count -and -not $servers.Count -and (ModelVerified)) {
                # Verification can take seconds; a game may have started during hashing.
                if (Busy) { throw 'Game appeared during model verification; launch deferred' }
                $env:LLAMA_ARG_CHAT_TEMPLATE_KWARGS = '{"enable_thinking":false}'
                $arguments = "--model $base\models\andy.gguf --alias andy-4.2-baseline --host 127.0.0.1 --port $port --jinja --ctx-size 8192 --parallel 1 --n-gpu-layers $layers --temp 0.6 --top-k 20 --top-p 0.95 --min-p 0 --repeat-penalty 1.0"
                $server = Start-Process "$base\llama\llama-server.exe" -ArgumentList $arguments -WorkingDirectory "$base\llama" -WindowStyle Hidden -PassThru -RedirectStandardOutput "$runtime\watch-$port.out.log" -RedirectStandardError "$runtime\watch-$port.err.log"
                # Creation time prevents a stale PID file from authorizing a reused PID.
                $started = Get-CimInstance Win32_Process -Filter "ProcessId=$($server.Id)"
                @{ ProcessId = $server.Id; CreationDate = $started.CreationDate.ToString('o') } | ConvertTo-Json | Set-Content $pidFile
                Write-Log "started PID $($server.Id)"
            } elseif (-not $listeners.Count -and -not $servers.Count) {
                if (-not $script:modelFailureLogged) { Write-Log "model missing or checksum mismatch; inference disabled"; $script:modelFailureLogged = $true }
            }
        } catch { Write-Log "error: $($_.Exception.Message)" }
        if (-not $Once) { Start-Sleep -Milliseconds ([Math]::Max(0, 15000 - [int]$cycle.ElapsedMilliseconds)) }
    } while (-not $Once)
} finally {
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}
