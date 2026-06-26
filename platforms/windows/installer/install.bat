@echo off
REM =====================================================================
REM  GitHub RDP Mega Toolkit v9.0.0 — Batch wrapper for install.ps1
REM  Usage: install.bat [args passed to install.ps1]
REM =====================================================================
setlocal enableextensions

set "SCRIPT_DIR=%~dp0"
set "PS1=%SCRIPT_DIR%install.ps1"

if not exist "%PS1%" (
    echo [error] install.ps1 not found at: %PS1%
    exit /b 1
)

REM Detect Windows PowerShell (powershell.exe) or PowerShell Core (pwsh.exe)
where pwsh.exe >nul 2>&1 && (
    set "PS_EXE=pwsh.exe"
    goto :run
)
set "PS_EXE=powershell.exe"

:run
echo [install.bat] Launching %PS_EXE% -ExecutionPolicy Bypass -File "%PS1%" %*
"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*
set "RC=%ERRORLEVEL%"
echo [install.bat] PowerShell exited with code %RC%
exit /b %RC%
