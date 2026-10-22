# One-shot setup from a clean clone: extract your disc image, fetch + patch the SDK, build.
# Players double-click setup.bat (runs this). Disc image: the one .iso in "game iso\", or -Iso <path>.
# Usage: pwsh tools/setup.ps1 [-Iso "D:\path\to\Dead or Alive 4.iso"]
# Re-runnable: finished steps are skipped. The disc image is only read until the game is extracted.
param([string]$Iso)
$ErrorActionPreference = 'Stop'
# Players read this in the setup.bat window: the message alone, not PowerShell's error view with line numbers.
trap { Write-Host "`nERROR: $($_.Exception.Message)" -ForegroundColor Red; exit 1 }

$root      = Split-Path $PSScriptRoot -Parent
$isoDir    = Join-Path $root 'game iso'
$extracted = Join-Path $root 'original rom\extracted'
$xex       = Join-Path $extracted 'default.xex'
# default.xex of Dead or Alive 4, title 544307D1. The manifest's function
# addresses only match this exact executable.
$xexSha256 = '56B68DEC68991F007639D796B04CB88C9AA7B484C1FCE54641CDDA5DE4F2B98F'
# Locked SDK + tested toolchain (deps.lock); changes only via the SDK upgrade procedure.
$lock = @{}
Get-Content (Join-Path $root 'deps.lock') | Where-Object { $_ -match '^\s*(\w+)\s*=\s*([^#\s]*)' } | ForEach-Object { $lock[$Matches[1]] = $Matches[2] }
$sdkDir    = if ($env:REXGLUE_SDK) { $env:REXGLUE_SDK } else { Join-Path $root 'thirdparty\rexglue-sdk' }
$vswhere   = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
# Fresh installs land in the registry PATH, not this process's: re-read it, plus the default install dirs of
# tools whose installers don't add themselves to PATH.
function Update-Path {
    $env:Path = (@("$env:ProgramFiles\LLVM\bin", "$env:ProgramFiles\CMake\bin", "$env:ProgramFiles\Git\cmd",
                   "$env:LOCALAPPDATA\Programs\Python\Python312", "$env:LOCALAPPDATA\Microsoft\WinGet\Links",
                   [Environment]::GetEnvironmentVariable('Path', 'Machine'), [Environment]::GetEnvironmentVariable('Path', 'User'),
                   $env:Path) -join ';')
}
Update-Path

function Step($msg) { "`n== $msg" }
# A tool counts as present only if it runs: Windows ships a 'python' alias that just opens the Store.
function Test-Tool($name) { if (Get-Command $name -ErrorAction SilentlyContinue) { & $name --version *> $null; $LASTEXITCODE -eq 0 } }
function Test-VS { (Test-Path $vswhere) -and (& $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath) }

Step 'Build tools'
# Same packages as the README's manual table.
$winget = [ordered]@{ git = 'Git.Git'; python = 'Python.Python.3.12'; cmake = 'Kitware.CMake'; ninja = 'Ninja-build.Ninja'; clang = 'LLVM.LLVM' }
$need = @($winget.Keys | Where-Object { -not (Test-Tool $_) })
if (-not (Test-VS)) { $need += 'vs' }
if ($need) {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { throw "Missing: $($need -join ', '), and winget is not available to install them. Install 'App Installer' from the Microsoft Store, or the tools by hand (README.md > Prerequisites)." }
    foreach ($t in $need) {
        "  installing $t (Windows may ask for permission)"
        $wg = '-e', '--source', 'winget', '--silent', '--accept-package-agreements', '--accept-source-agreements'
        if ($t -eq 'vs') {
            winget install --id Microsoft.VisualStudio.2022.BuildTools @wg --override '--quiet --wait --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended'
        } else {
            winget install --id $winget[$t] @wg
        }
    }
    Update-Path
}
# Re-check instead of trusting winget's exit code (it is non-zero for e.g. "already installed").
$missing = @($winget.Keys | Where-Object { -not (Test-Tool $_) })
if (-not (Test-VS)) { $missing += 'Visual Studio 2022 Build Tools (C++ workload)' }
if ($missing) { throw "Still missing after install: $($missing -join ', '). Install by hand (README.md > Prerequisites), then run setup.bat again." }
"  all present"
$py = [version]((python -c "import platform; print(platform.python_version())") -replace '[^\d.]')
if ($py -lt [version]$lock.min_python) { throw "Python $($lock.min_python)+ required (found $py)." }
$cm = [version](((cmake --version)[0] -split ' ')[-1] -replace '[^\d.]')
if ($cm -lt [version]$lock.min_cmake) { throw "CMake $($lock.min_cmake)+ required (found $cm)." }
$llvm = [int](((clang --version)[0] -replace '.*version (\d+).*', '$1'))
if ($llvm -ne [int]$lock.tested_llvm_major) { "  WARNING: clang $llvm; this suite was tested with LLVM $($lock.tested_llvm_major). If the build fails, install that version." }

Step 'Game files'
if (-not (Test-Path $xex)) {
    if (-not $Iso) {
        $isos = @(Get-ChildItem -LiteralPath $isoDir -Filter *.iso -File -ErrorAction SilentlyContinue)
        if (-not $isos) { throw "No disc image found. Put your Dead or Alive 4 disc image (.iso) in '$isoDir', then run setup.bat again." }
        # Any file name works (dumps are named by whoever made them); with several, the player picks one.
        if ($isos.Count -gt 1) {
            Write-Host "  Several disc images in '$isoDir':"
            for ($i = 0; $i -lt $isos.Count; $i++) { Write-Host "    [$($i + 1)] $($isos[$i].Name)" }
            $pick = Read-Host '  Which one is Dead or Alive 4? Type its number and press Enter'
            if ($pick -notmatch '^\d+$' -or [int]$pick -lt 1 -or [int]$pick -gt $isos.Count) {
                throw "No disc image picked ('$pick'). Run setup.bat again and type a number from the list, or keep only one .iso in '$isoDir'."
            }
            $isos = @($isos[[int]$pick - 1])
        }
        $Iso = $isos[0].FullName
        "  disc image: $($isos[0].Name)"
    }
    # -LiteralPath: dump names like "Dead or Alive 4 [PAL][NTSCU].iso" are wildcards to Test-Path.
    if (-not (Test-Path -LiteralPath $Iso)) { throw "ISO not found: $Iso" }
    python (Join-Path $PSScriptRoot 'extract_xiso.py') $Iso $extracted
    if ($LASTEXITCODE) { Remove-Item -LiteralPath $extracted -Recurse -Force -ErrorAction SilentlyContinue; throw "Extracting $Iso failed: not an Xbox 360 disc image?" }
} else { "  already extracted" }
$actual = (Get-FileHash $xex -Algorithm SHA256).Hash
if ($actual -ne $xexSha256) {
    # Drop the wrong extraction, so the next run reads (or asks for) the disc image again instead of failing here forever.
    Remove-Item -LiteralPath $extracted -Recurse -Force
    throw "default.xex SHA-256 is $actual, expected $xexSha256.`nOnly title 544307D1 with this exact executable is supported; a different game, region or title update won't match the manifest. The extracted files were removed; run setup.bat again with the right disc image."
}
"  default.xex verified (544307D1)"

Step "ReXGlue SDK (locked: $($lock.sdk_label) $($lock.sdk_commit.Substring(0, 12)))"
if (-not (Test-Path (Join-Path $sdkDir '.git'))) {
    if ($lock.sdk_archive_url) {
        # Primary: our verified snapshot (locked commit + submodules), independent of upstream.
        $archive = Join-Path $root "thirdparty\rexglue-sdk-$($lock.sdk_commit.Substring(0, 12)).tar.gz"
        if (-not (Test-Path $archive)) {
            New-Item -ItemType Directory -Force (Split-Path $archive) | Out-Null
            Invoke-WebRequest $lock.sdk_archive_url -OutFile $archive
        }
        if ((Get-FileHash $archive -Algorithm SHA256).Hash -ne $lock.sdk_archive_sha256) {
            Remove-Item $archive; throw 'SDK snapshot SHA-256 mismatch (download corrupted or replaced). Re-run setup.'
        }
        New-Item -ItemType Directory -Force $sdkDir | Out-Null
        # Python tarfile: Windows tar.exe crashes on a non-ASCII file name in the snapshot.
        # 'data' filter (Python 3.12+) where available; the archive is SHA-checked either way.
        python -c @'
import sys, tarfile
with tarfile.open(sys.argv[1]) as t:
    t.extractall(sys.argv[2], **({'filter': 'data'} if hasattr(tarfile, 'data_filter') else {}))
'@ $archive $sdkDir
        if ($LASTEXITCODE) { throw 'Extracting the SDK snapshot failed.' }
        # A repo so git am can apply the patch series (and format-patch works for devs).
        git -C $sdkDir -c core.autocrlf=false init -q -b doa4-fixes
        git -C $sdkDir -c core.autocrlf=false add -A
        git -C $sdkDir -c user.name=doa4-setup -c user.email=doa4-setup@localhost commit -q -m "SDK snapshot $($lock.sdk_commit)"
    } else {
        # Fallback / dev path: upstream at the locked commit. Fails loudly if it's gone.
        # Symlinks off on every PC (no Developer Mode); link_copies.ps1 then turns the placeholders into plain
        # copies (libmspack compiles symlinked sources). The -c reaches submodule clones via GIT_CONFIG_PARAMETERS.
        git clone -c core.symlinks=false --no-checkout $lock.sdk_url $sdkDir; if ($LASTEXITCODE) { throw 'Cloning the SDK failed.' }
        git -C $sdkDir checkout -b doa4-fixes $lock.sdk_commit; if ($LASTEXITCODE) { throw "Locked SDK commit $($lock.sdk_commit) not found upstream. Use the snapshot (sdk_archive_url)." }
        git -C $sdkDir -c core.symlinks=false submodule update --init --recursive; if ($LASTEXITCODE) { throw 'SDK submodules failed (a submodule repo may be gone). Use the snapshot (sdk_archive_url).' }
        & (Join-Path $PSScriptRoot 'link_copies.ps1') -Dir $sdkDir
    }
    # Committer identity is only needed by git am; the patches keep their own authors.
    $patches = Get-ChildItem (Join-Path $root 'patches\sdk\*.patch') | Sort-Object Name
    if ($patches) {
        git -C $sdkDir -c user.name=doa4-setup -c user.email=doa4-setup@localhost am --keep-non-patch --whitespace=nowarn $patches.FullName
        if ($LASTEXITCODE) { throw 'Applying SDK patches failed.' }
    }
} else { "  using existing $sdkDir" }

Step 'Building SDK + game (first build takes a while: SDK, then codegen of the whole game)'
$env:REXGLUE_SDK = $sdkDir
& (Join-Path $PSScriptRoot 'build.ps1') -Sdk

Step 'Game folder'
& (Join-Path $PSScriptRoot 'package.ps1')

"`nDone. Double-click 'Dead or Alive 4.exe' in $(Join-Path $root 'Dead or Alive 4') to play (the first launch opens the settings)."
