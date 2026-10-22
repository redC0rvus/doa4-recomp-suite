# Make the portable game folder: launcher + settings exes, the game exe and DLLs in bin\, the disc in game\.
# The folder runs on its own and can be moved anywhere; saves live in Documents\doa4 either way.
# setup.ps1 runs this after the build. Re-run after a rebuild to update a folder: binaries are overwritten,
# doa4.toml (player settings) and game\ are kept.
# Usage: pwsh tools/package.ps1 [-Preset win-amd64-relwithdebinfo] [-Dest "D:\Games\Dead or Alive 4"]
param([string]$Preset = 'win-amd64-relwithdebinfo', [string]$Dest)
$ErrorActionPreference = 'Stop'
$root      = Split-Path $PSScriptRoot -Parent
$build     = Join-Path $root "out\build\$Preset"
$extracted = Join-Path $root 'original rom\extracted'
$Dest = if ($Dest) { [IO.Path]::GetFullPath($Dest) } else { Join-Path $root 'Dead or Alive 4' }
if (-not (Test-Path -LiteralPath (Join-Path $build 'doa4.exe'))) { throw "No game build in $build. Run setup.bat first." }
if (-not (Test-Path -LiteralPath (Join-Path $extracted 'default.xex'))) { throw "No extracted disc in $extracted. Run setup.bat first." }

$bin = Join-Path $Dest 'bin'
New-Item -ItemType Directory -Force $bin | Out-Null
foreach ($exe in 'Dead or Alive 4.exe', 'Dead or Alive 4 Settings.exe') { Copy-Item -LiteralPath (Join-Path $root $exe) $Dest }
Get-ChildItem -LiteralPath $build -File | Where-Object Name -match '^doa4\.(exe|pdb)$|\.dll$' | Copy-Item -Destination $bin

# MSVC runtime next to the game (app-local copy of the VS redist files), so the folder also starts on a PC
# without the Visual C++ Redistributable.
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
$crt = Get-ChildItem "$vs\VC\Redist\MSVC\*\x64\Microsoft.VC*.CRT" -Directory -ErrorAction SilentlyContinue | Sort-Object FullName | Select-Object -Last 1
if ($crt) { Get-ChildItem -LiteralPath $crt.FullName -Filter *.dll | Copy-Item -Destination $bin }
else { "  WARNING: MSVC runtime DLLs not found under $vs; the folder needs the Visual C++ Redistributable on other PCs." }

# The disc as hard links: no second copy on disk, and the folder keeps the files if the suite is deleted.
# Plain copies where links can't be made (another drive, FAT/exFAT).
$game = Join-Path $Dest 'game'
$linked = $copied = 0
foreach ($f in Get-ChildItem -LiteralPath $extracted -Recurse -File) {
    $to = Join-Path $game $f.FullName.Substring($extracted.Length + 1)
    if (Test-Path -LiteralPath $to) { continue }
    New-Item -ItemType Directory -Force (Split-Path $to) | Out-Null
    try { New-Item -ItemType HardLink -Path $to -Target $f.FullName | Out-Null; $linked++ }
    catch { Copy-Item -LiteralPath $f.FullName $to; $copied++ }
}

# Settings: take the suite's doa4.toml once; after that the folder's own copy is the player's.
$toml = Join-Path $Dest 'doa4.toml'
if (-not (Test-Path -LiteralPath $toml) -and (Test-Path -LiteralPath (Join-Path $root 'doa4.toml'))) { Copy-Item -LiteralPath (Join-Path $root 'doa4.toml') $toml }

"  game folder: $Dest (disc files: $linked linked, $copied copied)"
"  Move it anywhere you like; saves stay in Documents\doa4."
