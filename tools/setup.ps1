# One-shot setup from a clean clone: extract your disc image, fetch + patch the SDK, build.
# Usage: pwsh tools/setup.ps1 -Iso "D:\path\to\Dead or Alive 4.iso"
# Re-runnable: finished steps are skipped. -Iso is only needed until the game is extracted.
param([string]$Iso)
$ErrorActionPreference = 'Stop'

$root      = Split-Path $PSScriptRoot -Parent
$extracted = Join-Path $root 'original rom\extracted'
$xex       = Join-Path $extracted 'default.xex'
# default.xex of Dead or Alive 4, title 544307D1. The manifest's function
# addresses only match this exact executable.
$xexSha256 = '56B68DEC68991F007639D796B04CB88C9AA7B484C1FCE54641CDDA5DE4F2B98F'
# Locked SDK + tested toolchain (deps.lock); changes only via the SDK upgrade procedure.
$lock = @{}
Get-Content (Join-Path $root 'deps.lock') | Where-Object { $_ -match '^\s*(\w+)\s*=\s*([^#\s]*)' } | ForEach-Object { $lock[$Matches[1]] = $Matches[2] }
$sdkDir    = if ($env:REXGLUE_SDK) { $env:REXGLUE_SDK } else { Join-Path $root 'thirdparty\rexglue-sdk' }
$env:Path  = "C:\Program Files\LLVM\bin;$env:LOCALAPPDATA\Microsoft\WinGet\Links;$env:Path"

function Step($msg) { "`n== $msg" }

Step 'Checking tools'
$missing = 'git', 'python', 'cmake', 'ninja', 'clang' | Where-Object { -not (Get-Command $_ -ErrorAction SilentlyContinue) }
if ($missing) { throw "Missing on PATH: $($missing -join ', '). See README.md > Prerequisites." }
$py = [version]((python -c "import platform; print(platform.python_version())") -replace '[^\d.]')
if ($py -lt [version]$lock.min_python) { throw "Python $($lock.min_python)+ required (found $py)." }
$cm = [version](((cmake --version)[0] -split ' ')[-1] -replace '[^\d.]')
if ($cm -lt [version]$lock.min_cmake) { throw "CMake $($lock.min_cmake)+ required (found $cm)." }
$llvm = [int](((clang --version)[0] -replace '.*version (\d+).*', '$1'))
if ($llvm -ne [int]$lock.tested_llvm_major) { "  WARNING: clang $llvm; this suite was tested with LLVM $($lock.tested_llvm_major). If the build fails, install that version." }

Step 'Game files'
if (-not (Test-Path $xex)) {
    if (-not $Iso) { throw "No extracted game at '$extracted'. Pass -Iso <your disc image>." }
    # -LiteralPath: dump names like "Dead or Alive 4 [PAL][NTSCU].iso" are wildcards to Test-Path.
    if (-not (Test-Path -LiteralPath $Iso)) { throw "ISO not found: $Iso" }
    python (Join-Path $PSScriptRoot 'extract_xiso.py') $Iso $extracted
    if ($LASTEXITCODE) { throw 'Extraction failed.' }
} else { "  already extracted" }
$actual = (Get-FileHash $xex -Algorithm SHA256).Hash
if ($actual -ne $xexSha256) {
    throw "default.xex SHA-256 is $actual, expected $xexSha256.`nOnly title 544307D1 with this exact executable is supported; a different region or title update won't match the manifest."
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
        # libmspack compiles symlinked sources: without real symlinks (Git's default on Windows) lzxd.c
        # is a one-line path and the build fails, so check that this account may create them first.
        $probe = Join-Path ([IO.Path]::GetTempPath()) "doa4-symlink-$PID"
        try { New-Item -ItemType SymbolicLink $probe -Target $PSCommandPath -ErrorAction Stop | Out-Null; Remove-Item $probe }
        catch { throw 'Cannot create symlinks. Turn on Developer Mode (Settings > System > For developers), then re-run setup.' }
        git clone -c core.symlinks=true --no-checkout $lock.sdk_url $sdkDir; if ($LASTEXITCODE) { throw 'Cloning the SDK failed.' }
        git -C $sdkDir checkout -b doa4-fixes $lock.sdk_commit; if ($LASTEXITCODE) { throw "Locked SDK commit $($lock.sdk_commit) not found upstream. Use the snapshot (sdk_archive_url)." }
        git -C $sdkDir -c core.symlinks=true submodule update --init --recursive; if ($LASTEXITCODE) { throw 'SDK submodules failed (a submodule repo may be gone). Use the snapshot (sdk_archive_url).' }
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

"`nDone. Double-click 'Dead or Alive 4.exe' in $root to play (the first launch opens the settings)."
