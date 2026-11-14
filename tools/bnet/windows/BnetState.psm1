# bnet state classifier: decides whether this PC may take lab work right now.
# Pure function so it can be tested without Windows; the agent feeds it one sample every 5 s.
# History is newest first; the newest entry that carries a .Result is the previous decision.

$IdleAfterSec   = 600   # 10 min without mouse/keyboard
$WindowSec      = 180   # load window for light/heavy
$LoadLimitPct   = 50    # any sample at or above this in CPU or GPU = heavy
$SettleSec      = 60    # state must hold this long before a job may (re)start

function Get-BnetState {
    param(
        [Parameter(Mandatory, Position = 0)][hashtable]$Sample,
        [Parameter(Position = 1)][object[]]$History = @(),
        [Parameter(Position = 2)][datetime]$Now = (Get-Date)
    )

    $state =
        if (-not $Sample.SessionActive -or $Sample.Locked) { 'unavailable' }
        elseif ($Sample.MediaPlaying -or $Sample.DisplayRequired -or $Sample.Fullscreen) { 'media' }
        else {
            # Load is checked before idle: a gamepad game or a long render has no mouse/keyboard input.
            $window = @($History | Where-Object { $_ -and ($Now - $_.Time).TotalSeconds -le $WindowSec }) + $Sample
            $peak = ($window | ForEach-Object { [math]::Max([double]$_.CpuPct, [double]$_.GpuPct) } | Measure-Object -Maximum).Maximum
            if ($peak -ge $LoadLimitPct) { 'heavy' }
            elseif ($Sample.InputIdleSec -ge $IdleAfterSec) { 'idle' }
            else { 'light' }
        }

    # idle and light both allow work, so moving between them keeps the settle clock running.
    $usable = 'idle', 'light'
    $prev = @($History | Where-Object { $_ -and $_.Result }) | Select-Object -First 1
    $since = $Now
    if ($prev) {
        $p = $prev.Result
        if ($p.State -eq $state -or ($p.State -in $usable -and $state -in $usable)) { $since = $p.Since }
    }

    [pscustomobject]@{
        State      = $state
        JobAllowed = ($state -in $usable) -and (($Now - $since).TotalSeconds -ge $SettleSec)
        Since      = $since
    }
}

Export-ModuleMember -Function Get-BnetState
