# Smoke test: play each input_scripts/smoke_*.txt from launch (via "Dead or Alive 4.exe"), then fail on a new
# crash bundle, a script that never logs 'input_script: done', or a game that exits early.
# Saves a game-window screenshot per script in shots/. Use it after SDK upgrades and big fixes.
# Usage: pwsh tools/smoke.ps1 [-Only smoke_boot] [-TimeoutSeconds 120] [-SettleSeconds 3]
param([string]$Only = 'smoke_*', [int]$TimeoutSeconds = 120, [int]$SettleSeconds = 3, [string]$Preset = 'win-amd64-relwithdebinfo')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$logs = Join-Path $root "out\build\$Preset\logs"
$scripts = Get-ChildItem (Join-Path $root "input_scripts\$Only.txt")
if (-not $scripts) { throw "No input_scripts\$Only.txt. Record one with .\run.bat --use_input_rec (F9) and name it smoke_<path>.txt." }
if (Get-Process doa4 -ErrorAction SilentlyContinue) { throw 'Close the game first' }

$failed = 0
foreach ($s in $scripts) {
    $start = Get-Date
    Start-Process (Join-Path $root 'Dead or Alive 4.exe') "--input_script=$($s.BaseName)"
    $result = 'TIMEOUT'
    while (((Get-Date) - $start).TotalSeconds -lt $TimeoutSeconds) {
        Start-Sleep -Milliseconds 500
        # The logs folder doesn't exist until the game's first launch (fresh clone).
        $log = Get-ChildItem "$logs\*.log" -ErrorAction SilentlyContinue | Where-Object LastWriteTime -ge $start | Sort-Object LastWriteTime | Select-Object -Last 1
        if (Get-ChildItem (Join-Path $root 'crashes') -Directory -ErrorAction SilentlyContinue | Where-Object CreationTime -ge $start) { $result = 'CRASH'; break }
        if ($log -and (Select-String -Quiet -SimpleMatch 'input_script: done' $log.FullName)) { Start-Sleep $SettleSeconds; $result = 'PASS'; break }
        if (((Get-Date) - $start).TotalSeconds -gt 10 -and -not (Get-Process doa4 -ErrorAction SilentlyContinue)) { $result = 'EXITED'; break }
    }
    # A crash during the settle time still counts.
    if ($result -eq 'PASS' -and (Get-ChildItem (Join-Path $root 'crashes') -Directory -ErrorAction SilentlyContinue | Where-Object CreationTime -ge $start)) { $result = 'CRASH' }
    $shot = if (Get-Process doa4 -ErrorAction SilentlyContinue) { & "$PSScriptRoot\shot.ps1" -Out (Join-Path $root "shots\$($s.BaseName).png") }
    Stop-Process -Name doa4 -Force -ErrorAction SilentlyContinue
    Start-Sleep 2
    "{0,-8} {1}  {2:n0}s  {3}" -f $result, $s.BaseName, ((Get-Date) - $start).TotalSeconds, $shot
    if ($result -ne 'PASS') { $failed++; if ($log) { "  log: $($log.FullName)" } }
}
if ($failed) { "SMOKE FAILED: $failed of $($scripts.Count)"; exit 1 }
"SMOKE OK ($($scripts.Count) script(s))"
