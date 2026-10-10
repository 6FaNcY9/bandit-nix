# Dot-sourced by watch.ps1 and train\run-guarded.ps1; expects $base, $TestPort and $GpuPercent in the caller's scope.
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
function Busy {
    # -Remote: caller runs outside the interactive session (ssh): skip the console-session and
    # fullscreen probes, which only make sense there. -IgnorePids: caller's own GPU users.
    param([int[]]$IgnorePids = @(), [switch]$Remote)
    if (-not $Remote -and -not $TestPort -and [BanditWindow]::WTSGetActiveConsoleSessionId() -ne (Get-Process -Id $PID).SessionId) { return 'another console session (or no console)' }
    # Light games never count as games and do not trigger the fullscreen rule while focused.
    $light = @('isaac-ng.exe', 'isaac.exe', 'wallpaper64.exe', 'wallpaper32.exe', 'chrome.exe', 'msedge.exe', 'firefox.exe', 'brave.exe', 'vlc.exe')
    if (Test-Path "$base\light-games.txt") {
        $light += @(Get-Content "$base\light-games.txt" | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') })
    }
    $lightForeground = $false
    if (-not $Remote) {
        $foreground = Get-CimInstance Win32_Process -Filter "ProcessId=$([BanditWindow]::ForegroundPid())"
        $lightForeground = $null -ne $foreground -and $light -contains $foreground.Name
        if (-not $lightForeground -and [BanditWindow]::Fullscreen()) { return 'fullscreen window' }
    }
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
        # Light games (Minecraft, Isaac, browsers) may use the GPU next to Andy: their load does not count either.
        $llama += @(Get-CimInstance Win32_Process | Where-Object { $light -contains $_.Name } | ForEach-Object ProcessId)
        $counters = @(Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine)
        if (-not $counters.Count) { throw 'No GPU engine counters; refusing inference' }
        $engines = @{}
        foreach ($counter in $counters) {
            if ($counter.Name -notmatch '^pid_(\d+)_(.+)$') { throw 'Unrecognized GPU counter' }
            if ($llama -contains [int]$Matches[1] -or $IgnorePids -contains [int]$Matches[1]) { continue }
            $engine = $Matches[2]
            $engines[$engine] += [int]$counter.UtilizationPercentage
        }
        $usage = ($engines.Values | Measure-Object -Maximum).Maximum
    }
    if ($usage -ge 20) { return "non-llama GPU $usage%" }
    return $null
}
