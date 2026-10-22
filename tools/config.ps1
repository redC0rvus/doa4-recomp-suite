# DOA4 settings menu: writes doa4.toml in the project root (untracked). run.bat copies it next to doa4.exe
# at every launch, so rebuilds never lose it. Opens on first launch, or with .\run.bat --config.
# Usage: tools\config.ps1          (menu)
#        tools\config.ps1 -Check   (validate doa4.toml; exit 1 with a message if invalid; run.bat uses this)
# Runs on the stock Windows PowerShell 5.1, no dependencies.
param([switch]$Check)
$root = Split-Path $PSScriptRoot -Parent
$toml = Join-Path $root 'doa4.toml'

# Resolution presets: scale -> label. Only presets verified on DOA4 to the title screen are listed.
$presets = [ordered]@{ '1' = '720p  (native, 1280x720)'; '2' = '1440p (2560x1440)'; '3' = '4K    (3840x2160)' }
$presetHeight = @{ '1' = 720; '2' = 1440; '3' = 2160 }

# One "key = value" line: bool, integer or a plain double-quoted string. That is all this tool writes.
$lineRx = '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(true|false|-?\d+|"[^"\\]*")\s*(#.*)?$'

function Read-Toml {
    $values = @{}
    $n = 0
    foreach ($line in Get-Content $toml) {
        $n++
        if ($line -match '^\s*(#.*)?$') { continue }
        if ($line -notmatch $lineRx) { throw "line ${n}: '$line' is not key = true, false, a number or text in double quotes" }
        $values[$Matches[1]] = $Matches[2].Trim('"')
    }
    $s = $values['resolution_scale']
    if ($s -and -not $presets.Contains($s)) { throw "resolution_scale = $s (allowed: $($presets.Keys -join ', '))" }
    $g = $values['gamertag']
    if ($null -ne $g -and ($g.Length -lt 1 -or $g.Length -gt 15)) { throw "gamertag must be 1-15 characters" }
    $values
}

if ($Check) {
    if (-not (Test-Path $toml)) { exit 0 }
    try { Read-Toml | Out-Null; exit 0 }
    catch { Write-Host "doa4.toml is invalid ($_). Starting with default settings; fix it with .\run.bat --config"; exit 1 }
}

# Defaults: preset from the largest monitor, gamertag from the old gamertag.txt if there is one.
$monitor = (Get-CimInstance Win32_VideoController | Measure-Object CurrentVerticalResolution -Maximum).Maximum
$scale = '1'
foreach ($k in $presets.Keys) { if ($presetHeight[$k] -le $monitor) { $scale = $k } }
$cfg = @{ resolution_scale = "$scale"; fullscreen = 'true'; mnk_mode = 'false'; audio_mute = 'false'; gamertag = 'User' }
$old = Join-Path $root 'gamertag.txt'
if (Test-Path $old) { $first = Get-Content $old -TotalCount 1; if ($first) { $cfg.gamertag = $first.Trim() } }
if (Test-Path $toml) {
    try { $existing = Read-Toml; foreach ($k in $existing.Keys) { $cfg[$k] = $existing[$k] } }
    catch { Write-Host "Existing doa4.toml is invalid ($_); starting from defaults." -ForegroundColor Yellow }
} else {
    Write-Host 'No doa4.toml yet: pick your settings (S saves the defaults shown).' -ForegroundColor Cyan
}

function OnOff($v) { if ($v -eq 'true') { 'on' } else { 'off' } }
function Flip($k) { $cfg[$k] = if ($cfg[$k] -eq 'true') { 'false' } else { 'true' } }

while ($true) {
    Write-Host ''
    Write-Host 'Dead or Alive 4 settings' -ForegroundColor Cyan
    Write-Host "  1) Resolution          $($presets[$cfg.resolution_scale])   (monitor: ${monitor}p)"
    Write-Host "  2) Fullscreen          $(OnOff $cfg.fullscreen)"
    Write-Host "  3) Keyboard as pad     $(OnOff $cfg.mnk_mode)   (Enter=Start Space=A Backspace=B L=X P=Y WASD=stick)"
    Write-Host "  4) Gamertag            $($cfg.gamertag)"
    Write-Host "  5) Mute audio          $(OnOff $cfg.audio_mute)"
    Write-Host '  S) Save    Q) Quit without saving'
    switch ((Read-Host 'Choice').Trim().ToUpper()) {
        '1' {
            $keys = @($presets.Keys)
            $cfg.resolution_scale = "$($keys[($keys.IndexOf($cfg.resolution_scale) + 1) % $keys.Count])"
            Write-Host '  (A GPU without tiled resources stays at 720p; the log then says the scale was clamped.)'
        }
        '2' { Flip 'fullscreen' }
        '3' { Flip 'mnk_mode' }
        '4' {
            $name = (Read-Host '  Gamertag (1-15 characters)').Trim()
            if ($name -match '^[ !#-\[\]-~]{1,15}$') { $cfg.gamertag = $name } else { Write-Host '  Not changed: 1-15 plain ASCII characters, no " or \.' -ForegroundColor Yellow }
        }
        '5' { Flip 'audio_mute' }
        'S' {
            @(
                '# Dead or Alive 4 settings, written by tools\config.ps1 (.\run.bat --config to change).'
                '# run.bat copies this file next to doa4.exe before every launch.'
                "resolution_scale = $($cfg.resolution_scale)"
                "fullscreen = $($cfg.fullscreen)"
                "mnk_mode = $($cfg.mnk_mode)"
                "gamertag = `"$($cfg.gamertag)`""
                "audio_mute = $($cfg.audio_mute)"
                # Keep any other cvar someone added by hand.
                $cfg.Keys | Where-Object { $_ -notin 'resolution_scale', 'fullscreen', 'mnk_mode', 'gamertag', 'audio_mute' } |
                    ForEach-Object { if ($cfg[$_] -match '^(true|false|-?\d+)$') { "$_ = $($cfg[$_])" } else { "$_ = `"$($cfg[$_])`"" } }
            ) | Set-Content -Encoding ASCII $toml
            Write-Host "Saved $toml"
            exit 0
        }
        'Q' { exit 0 }
    }
}
