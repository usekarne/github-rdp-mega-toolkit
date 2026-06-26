@echo off
REM =====================================================================
REM  GitHub RDP Mega Toolkit v9.0.0 — Batch wrapper for uninstall.ps1
REM  Usage: uninstall.bat [args passed to uninstall.ps1]
REM =====================================================================
setlocal enableextensions

set "SCRIPT_DIR=%~dp0"
set "PS1=%SCRIPT_DIR%uninstall.ps1"

if not exist "%PS1%" (
    echo [error] uninstall.ps1 not found at: %PS1%
    exit /b 1
)

REM Detect Windows PowerShell (powershell.exe) or PowerShell Core (pwsh.exe)
where pwsh.exe >nul 2>&1 && (
    set "PS_EXE=pwsh.exe"
    goto :run
)
set "PS_EXE=powershell.exe"

:run
echo [uninstall.bat] Launching %PS_EXE% -ExecutionPolicy Bypass -File "%PS1%" %*
"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*
set "RC=%ERRORLEVEL%"
echo [uninstall.bat] PowerShell exited with code %RC%
exit /b %RC%
