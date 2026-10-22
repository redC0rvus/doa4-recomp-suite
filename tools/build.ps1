# Build the game (and optionally the SDK) and keep SDK DLLs in sync with the exe.
# Usage: pwsh tools/build.ps1 [-Sdk] [-Preset win-amd64-relwithdebinfo]
# SDK location: $env:REXGLUE_SDK if set, else thirdparty\rexglue-sdk (cloned by tools/setup.ps1; one clone per project).
param([switch]$Sdk, [string]$Preset = 'win-amd64-relwithdebinfo')
$ErrorActionPreference = 'Stop'

$root   = Split-Path $PSScriptRoot -Parent
$sdkDir = if ($env:REXGLUE_SDK) { $env:REXGLUE_SDK } else { Join-Path $root 'thirdparty\rexglue-sdk' }
if (-not (Test-Path $sdkDir)) { throw "ReXGlue SDK not found at $sdkDir. Run tools/setup.ps1 first, or set `$env:REXGLUE_SDK." }
$sdkDir = (Resolve-Path $sdkDir).Path
$sdkInstall = Join-Path $sdkDir 'out\install\win-amd64'

$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$vs = if (Test-Path $vswhere) { & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath }
if (-not $vs) { throw 'Visual Studio 2022 (or Build Tools) with the C++ workload not found.' }
$vcvars = Join-Path $vs 'VC\Auxiliary\Build\vcvars64.bat'
$config = @{ 'win-amd64-debug' = 'Debug'; 'win-amd64-release' = 'Release'; 'win-amd64-relwithdebinfo' = 'RelWithDebInfo' }[$Preset]
$env:Path = "C:\Program Files\LLVM\bin;$env:LOCALAPPDATA\Microsoft\WinGet\Links;$env:Path"

function Invoke-VS([string]$dir, [string]$cmd) {
    cmd /c "`"$vcvars`" >nul 2>nul && cd /d `"$dir`" && $cmd 2>&1" |
        # 'Performing Test ... - Failed': CMake probing for POSIX/GCC features Windows lacks; expected, not an error.
        Select-String -NotMatch 'vswhere|operable program|Up-to-date:|Installing:|Performing Test' |
        Select-String 'error:|CMake Error|FAILED|Codegen summary|Unresolved|not in any function|ninja: no work' | ForEach-Object Line
    if ($LASTEXITCODE) { throw "Build failed in $dir" }
}

if ($Sdk) {
    if (-not (Test-Path "$sdkDir\out\build\win-amd64\CMakeCache.txt")) { Invoke-VS $sdkDir 'cmake --preset win-amd64' }
    Invoke-VS $sdkDir "cmake --build out/build/win-amd64 --config $config --target install"
    # The SDK installs its codegen tool (rexglue.exe) only from Release, and the game's
    # build runs it. ponytail: one full Release SDK build on first setup, kept after that.
    if (-not (Test-Path "$sdkInstall\bin\rexglue.exe")) {
        Invoke-VS $sdkDir 'cmake --build out/build/win-amd64 --config Release --target install'
    }
}
$outDir = Join-Path $root "out\build\$Preset"
if (-not (Test-Path "$outDir\CMakeCache.txt")) {
    Invoke-VS $root "cmake --preset $Preset `"-Drexglue_DIR=$sdkInstall\lib\cmake\rexglue`""
}
# generated/rexglue.cmake only adds the recompiled sources if codegen ran before
# configure, so a fresh tree runs codegen alone, then reconfigures.
if (-not (Select-String -Quiet -SimpleMatch 'doa4_recomp' "$outDir\build.ninja")) {
    Invoke-VS $root "cmake --build --preset $Preset --target doa4_codegen"
    Invoke-VS $root "cmake --preset $Preset"
}
Invoke-VS $root "cmake --build --preset $Preset"

# The exe's post-build copy only runs when the exe relinks, so SDK-only changes
# would otherwise leave stale DLLs next to the game.
$suffix = @{ Debug = 'd'; Release = ''; RelWithDebInfo = 'rd' }[$config]
foreach ($dll in "rexruntime$suffix.dll", "rexgpu-xenos$suffix.dll", "TracyClient$suffix.dll") {
    Copy-Item (Join-Path $sdkInstall "bin\$dll") $outDir -Force
}
# Commit hashes for crash bundles (the SDK copies this file into each bundle).
$hash = { param($d) $h = git -C $d rev-parse --short HEAD; if (git -C $d status --porcelain) { "$h-dirty" } else { $h } }
"game $(& $hash $root)`nsdk  $(& $hash $sdkDir)" | Set-Content (Join-Path $outDir 'build_info.txt')

# Every SDK change must ship as patches/sdk/*.patch. Warn (don't fail: troubleshooting
# iterates on dirty edits) when the clone has edits or commits the patch series lacks.
# ponytail: compares counts only; an amended commit with the same count slips through.
$lock = (Select-String '^sdk_commit\s*=\s*(\w+)' (Join-Path $root 'deps.lock')).Matches[0].Groups[1].Value
git -C $sdkDir cat-file -e "$lock^{commit}" 2>$null
$base = if ($LASTEXITCODE -eq 0) { $lock } else { git -C $sdkDir rev-list --max-parents=0 HEAD }  # snapshot clones lack the lock commit
$commits = [int](git -C $sdkDir rev-list --count "$base..HEAD")
$patches = @(Get-ChildItem (Join-Path $root 'patches\sdk\*.patch')).Count
$dirty = @(git -C $sdkDir status --porcelain).Count
if ($dirty -or $commits -ne $patches) {
    Write-Warning "SDK NOT IN PATCHES: $dirty uncommitted file(s), $commits SDK commit(s) vs $patches patch(es). Commit on doa4-fixes and export it to patches/sdk, or the change is lost on the next setup."
}
"BUILD_OK ($Preset)"
