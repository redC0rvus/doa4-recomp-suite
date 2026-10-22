@echo off
rem Double-click: installs missing build tools (winget), extracts the disc image from "game iso\", fetches and patches
rem the ReXGlue SDK, builds the game, then starts it. Re-running skips finished steps.
rem Extra arguments pass to tools\setup.ps1 (devs: setup.bat -Iso "D:\path\to\disc.iso").
cd /d "%~dp0"
call :findpwsh
if defined PWSH goto run
where winget >nul 2>nul || (echo winget not found: install "App Installer" from the Microsoft Store, then run setup.bat again. & pause & exit /b 1)
echo == Installing PowerShell 7
winget install -e --id Microsoft.PowerShell --source winget --silent --accept-package-agreements --accept-source-agreements
call :findpwsh
if not defined PWSH (echo PowerShell 7 was installed, but pwsh.exe was not found yet. Close this window and double-click setup.bat again. & pause & exit /b 1)
:run
"%PWSH%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\setup.ps1" %*
if errorlevel 1 (echo. & echo SETUP FAILED: see the message above. & pause & exit /b 1)
start "" "%~dp0Dead or Alive 4.exe"
exit /b 0

rem Sets PWSH to pwsh.exe: the MSI install dir, the MSIX app alias (what winget installs now), or anything on PATH.
:findpwsh
set "PWSH="
if exist "%ProgramFiles%\PowerShell\7\pwsh.exe" set "PWSH=%ProgramFiles%\PowerShell\7\pwsh.exe" & exit /b 0
if exist "%LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe" set "PWSH=%LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe" & exit /b 0
for /f "delims=" %%p in ('where pwsh 2^>nul') do if not defined PWSH set "PWSH=%%p"
exit /b 0
