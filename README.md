# Dead or Alive 4 Recomp
<img width="2081" height="709" alt="github-banner" src="https://github.com/user-attachments/assets/e24568a6-ed53-4df5-9988-0495ca7531d8" />

Play Dead or Alive 4 natively on Windows, from your own Xbox 360 disc. The game's code is statically recompiled from the disc's `default.xex` with the [ReXGlue SDK](https://github.com/rexglue/rexglue-sdk) and rendered with Direct3D 12, at up to 4K.

**Bring your own disc.** This repository contains no game code or data. You need your own disc image of Dead or Alive 4 (title ID 544307D1); everything is built on your machine.

## Prerequisites
- Windows 10 or 11, 64-bit, with a Direct3D 12 GPU
- About 15 GB free disk space
- These tools, installed and on PATH (open a **new** terminal after installing):

| Tool | Install with winget |
|---|---|
| Visual Studio 2022 Build Tools, C++ workload | `winget install Microsoft.VisualStudio.2022.BuildTools --override "--quiet --wait --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"` |
| LLVM / Clang (tested with 23) | `winget install LLVM.LLVM` |
| CMake 3.25+ | `winget install Kitware.CMake` |
| Ninja | `winget install Ninja-build.Ninja` |
| Python 3.8+ | `winget install Python.Python.3.12` |
| Git | `winget install Git.Git` |

PowerShell 7 (`pwsh`) runs the setup: `winget install Microsoft.PowerShell`.

Turn on **Developer Mode** (Settings > System > For developers): the SDK source uses symlinks.

## Setup
Clone, then one command builds everything:

```powershell
git clone https://github.com/redC0rvus/doa4-recomp-suite.git
cd doa4-recomp-suite
pwsh tools/setup.ps1 -Iso "D:\path\to\Dead or Alive 4.iso"
```

It checks your tools, extracts the disc image and verifies `default.xex`, downloads the ReXGlue SDK at the tested version, applies this project's SDK patches (`patches/sdk/`), and builds the SDK and the game. The first build takes about 10-30 minutes. Re-running it skips the steps that are already done; `-Iso` is only needed until the game is extracted.

## Play
```powershell
.\run.bat
```
The first launch opens the settings menu; after that the game starts directly. `.\run.bat --config` reopens the menu.

### Settings (`.\run.bat --config`)
Saved to `doa4.toml` in the repository folder.
- **Resolution:** 720p (native), 1440p or 4K internal rendering. The default is the largest that fits your tallest monitor.
- **Fullscreen**
- **Keyboard as pad:** play with keyboard and mouse (keys below).
- **Gamertag:** your in-game name (up to 15 characters).
- **Mute**

Any game flag can also be given on the command line, and wins over `doa4.toml`: `.\run.bat --resolution_scale=1`.

### Controls
Xbox and other gamepads work out of the box. With **Keyboard as pad** on:

| Pad | Keyboard |
|---|---|
| Start | Enter |
| A / B | Space or `;` / Backspace or `'` |
| X / Y | L / P |
| Left stick | WASD |
| Right stick | Arrow keys |
| D-pad | Shift + arrow keys |
| Back | Z or Tab |

## Troubleshooting
- **`Missing on PATH: ...`**: install that tool (table above), then open a new terminal.
- **`default.xex SHA-256 is ..., expected ...`**: your disc image is a different release or has a title update applied. Only the release this project was built for is supported, because the recompiled code must match that exact executable.
- **`WARNING: clang N; this suite was tested with LLVM 23`**: usually fine. If the build fails, install LLVM 23.
- **`Cannot create symlinks`**: turn on Developer Mode (Prerequisites), then run setup again.
- **`SDK snapshot SHA-256 mismatch`**: the download was corrupted; run setup again.
- **`doa4.toml is invalid (line N: ...)`**: the game starts with default settings; run `.\run.bat --config` to fix them.
- **The game crashes:** it writes a folder `crashes\<timestamp>\` (log, stack, last frame). Attach that folder to your bug report.
- **Bug report checklist:** the `crashes\<timestamp>` folder if there is one, a screenshot (`pwsh tools/shot.ps1` prints its path while the game runs), and the result of `pwsh tools/smoke.ps1` with the game closed (it boots to the mode-select screen and prints PASS or what failed).

## Rebuilding
After pulling a new version: `pwsh tools/build.ps1 -Sdk`.

## License
BSD-3-Clause (`LICENSE`). Third-party components and their licenses: `THIRD_PARTY_NOTICES.md`. Dead or Alive is a trademark of Koei Tecmo; this project is not affiliated with or endorsed by Koei Tecmo or Microsoft.
