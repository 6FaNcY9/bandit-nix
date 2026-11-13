# bnet sensor: runs in the logged-in user's session (scheduled task at logon) because idle time and the
# foreground window cannot be read from the SYSTEM service. Writes C:\ProgramData\bnet\session\session.json every 5 s
# (session\ is user-writable; the token in C:\ProgramData\bnet stays SYSTEM/Administrators only).
$ErrorActionPreference = 'Stop'
$Dir = 'C:\ProgramData\bnet\session'

Add-Type @'
using System; using System.Runtime.InteropServices;
public static class BnetWin {
  [StructLayout(LayoutKind.Sequential)] struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [StructLayout(LayoutKind.Sequential)] struct MONITORINFO { public uint cbSize; public RECT rcMonitor, rcWork; public uint dwFlags; }
  [DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LASTINPUTINFO p);
  [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] static extern IntPtr MonitorFromWindow(IntPtr h, uint f);
  [DllImport("user32.dll")] static extern bool GetMonitorInfo(IntPtr m, ref MONITORINFO i);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, System.Text.StringBuilder s, int n);
  public static uint IdleSeconds() {
    var i = new LASTINPUTINFO(); i.cbSize = (uint)Marshal.SizeOf(i); GetLastInputInfo(ref i);
    return ((uint)Environment.TickCount - i.dwTime) / 1000;
  }
  public static bool ForegroundIsFullscreen() {
    IntPtr h = GetForegroundWindow(); if (h == IntPtr.Zero) return false;
    var c = new System.Text.StringBuilder(64); GetClassName(h, c, 64);
    if (c.ToString() == "Progman" || c.ToString() == "WorkerW") return false;  // the desktop itself
    RECT w; if (!GetWindowRect(h, out w)) return false;
    var m = new MONITORINFO(); m.cbSize = (uint)Marshal.SizeOf(m);
    if (!GetMonitorInfo(MonitorFromWindow(h, 2), ref m)) return false;
    return w.L <= m.rcMonitor.L && w.T <= m.rcMonitor.T && w.R >= m.rcMonitor.R && w.B >= m.rcMonitor.B;
  }
}
'@

# Visible notice: a tray icon while the lab uses this PC (job.json is written by the SYSTEM agent).
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$tray = [Windows.Forms.NotifyIcon]::new()
$tray.Icon = [Drawing.SystemIcons]::Information
$tray.Text = 'bandit-lab rechnet hier (stoppt bei Nutzung)'   # max 63 chars

while ($true) {
    $busy = Test-Path "$Dir\job.json"
    if ($busy -and -not $tray.Visible) {
        $tray.Visible = $true
        $tray.ShowBalloonTip(5000, 'bandit-lab', 'Dieser PC rechnet gerade im Leerlauf fuer das Lab.', 'Info')
    } elseif (-not $busy -and $tray.Visible) { $tray.Visible = $false }
    [Windows.Forms.Application]::DoEvents()

    $locked = [bool](Get-Process LogonUI -ErrorAction SilentlyContinue)
    @{
        Time          = (Get-Date).ToString('o')
        SessionActive = $true
        Locked        = $locked
        InputIdleSec  = [int][BnetWin]::IdleSeconds()
        Fullscreen    = (-not $locked) -and [BnetWin]::ForegroundIsFullscreen()
        MediaPlaying  = $false   # the SYSTEM agent adds audio/display requests from powercfg
    } | ConvertTo-Json -Compress | Set-Content -Path "$Dir\session.json.tmp" -Encoding utf8
    Move-Item -Force "$Dir\session.json.tmp" "$Dir\session.json"
    Start-Sleep -Seconds 5
}
