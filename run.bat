@echo off
rem Launch Dead or Alive 4. Every flag below is commented with why it is set.
rem Extra flags pass through and win over these and over doa4.toml: run.bat --resolution_scale=1
rem User settings (resolution, fullscreen, keyboard, gamertag, mute) live in doa4.toml next to this file, written by
rem tools\config.ps1: it opens on the first plain launch with no doa4.toml, and with run.bat --config.
set "OUT=%~dp0out\build\win-amd64-relwithdebinfo"
if /i "%~1"=="--config" (call :config & call :launch & exit /b)
if "%~1"=="" if not exist "%~dp0doa4.toml" call :config
call :launch %*
exit /b

:config
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\config.ps1"
exit /b

:launch
rem doa4.toml in the project root is the source of truth: copy it next to the exe (the SDK reads <exe dir>\doa4.toml),
rem or remove a stale copy when it is missing or invalid, so the game starts on defaults.
del "%OUT%\doa4.toml" 2>nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\config.ps1" -Check && if exist "%~dp0doa4.toml" copy /y "%~dp0doa4.toml" "%OUT%\doa4.toml" >nul
rem Required: the game does not work right without these.
rem   Extracted disc (setup.ps1 puts it here).
set FLAGS=--game_data_root="%~dp0original rom\extracted"
rem   Buffers above 256 MB so the game's "offset < base -> relocate" check works (Brad/Hayabusa motion, SDK 0015).
set FLAGS=%FLAGS% --guest_low_reserve_mb=256
rem   CPU reads of GPU resolves: replay-camera autofocus and photo encode (SDK 0020); ~40 fps vs ~16 with fast.
set FLAGS=%FLAGS% --readback_resolve=lazy
rem Crash reports: a crash writes crashes\<timestamp>\ (logs, stack, last frame); attach it to a bug report.
set FLAGS=%FLAGS% --crash_bundle_dir="%~dp0crashes" --flight_recorder=true
rem Convenience: skips the Team Ninja logo movie (src/doa4_app.h).
set FLAGS=%FLAGS% --skip_boot_movies=true
rem Start in the project root so input_scripts/ (--input_script=NAME, --use_input_rec) resolves here.
pushd "%~dp0"
"%OUT%\doa4.exe" %FLAGS% %*
popd
exit /b
