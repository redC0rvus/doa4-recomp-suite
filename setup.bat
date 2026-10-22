@echo off
rem Double-click: installs missing build tools (winget), extracts the disc image from "game iso\", fetches and patches
rem the ReXGlue SDK, builds the game, then starts it. Re-running skips finished steps.
rem Extra arguments pass to tools\setup.ps1 (devs: setup.bat -Iso "D:\path\to\disc.iso").
cd /d "%~dp0"
set "PWSH=%ProgramFiles%\PowerShell\7\pwsh.exe"
if not exist "%PWSH%" where pwsh >nul 2>nul && set "PWSH=pwsh"
if "%PWSH%"=="pwsh" goto run
if exist "%PWSH%" goto run
where winget >nul 2>nul || (echo winget not found: install "App Installer" from the Microsoft Store, then run setup.bat again. & pause & exit /b 1)
echo == Installing PowerShell 7
winget install -e --id Microsoft.PowerShell --silent --accept-package-agreements --accept-source-agreements
if not exist "%PWSH%" (echo Installing PowerShell 7 failed. & pause & exit /b 1)
:run
"%PWSH%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\setup.ps1" %*
if errorlevel 1 (echo. & echo SETUP FAILED: see the message above. & pause & exit /b 1)
start "" "%~dp0Dead or Alive 4.exe"
