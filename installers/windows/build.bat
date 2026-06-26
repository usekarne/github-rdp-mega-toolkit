@echo off
REM =====================================================================
REM  RDP Mega Toolkit v9.0.0 - NSIS build wrapper
REM  Usage: build.bat
REM =====================================================================
setlocal enabledelayedexpansion
set "SCRIPT_DIR=%~dp0"
set "NSI=%SCRIPT_DIR%installer.nsi"
set "EXIT_CODE=0"

echo.
echo [build] Looking for NSIS (makensis.exe)...
where makensis >nul 2>&1
if %ERRORLEVEL%==0 (
    set "MAKENSIS=makensis"
    goto :found
)

REM Try common install paths
if exist "%ProgramFiles%\NSIS\makensis.exe" (
    set "MAKENSIS=%ProgramFiles%\NSIS\makensis.exe"
    goto :found
)
if exist "%ProgramFiles(x86)%\NSIS\makensis.exe" (
    set "MAKENSIS=%ProgramFiles(x86)%\NSIS\makensis.exe"
    goto :found
)

echo.
echo ERROR: makensis.exe not found on PATH or in Program Files.
echo        Install NSIS 3.x from https://nsis.sourceforge.io/
echo.
exit /b 2

:found
echo [build] Using NSIS: !MAKENSIS!
echo [build] Building: !NSI!
echo.

"!MAKENSIS!" "!NSI!"
set "EXIT_CODE=!ERRORLEVEL!"

if not "!EXIT_CODE!"=="0" (
    echo.
    echo ==================================================
    echo  BUILD FAILED  exit code: !EXIT_CODE!
    echo ==================================================
    exit /b !EXIT_CODE!
)

if not exist "%SCRIPT_DIR%rdp-toolkit-setup-9.0.0.exe" (
    echo.
    echo ERROR: makensis reported success but installer .exe is missing.
    exit /b 3
)

echo.
echo ==================================================
echo  BUILD SUCCESS
echo ==================================================
echo  Output: %SCRIPT_DIR%rdp-toolkit-setup-9.0.0.exe
for %%I in ("%SCRIPT_DIR%rdp-toolkit-setup-9.0.0.exe") do echo  Size:   %%~zI bytes
echo  Install: run the .exe on a Windows machine
echo ==================================================
exit /b 0
