@echo off
setlocal

:: Claude-Installer -- double-click entry point.

set "REPO=%~dp0"
if "%REPO:~-1%"=="\" set "REPO=%REPO:~0,-1%"

:: Refresh PATH from the registry so freshly-installed tools are visible.
for /f "tokens=2,*" %%A in ('reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v Path 2^>nul') do set "PATH=%%B;%PATH%"
for /f "tokens=2,*" %%A in ('reg query "HKCU\Environment" /v Path 2^>nul') do set "PATH=%%B;%PATH%"

:: npm global shims (claude.cmd) are often not on a fresh shell's PATH.
if exist "%APPDATA%\npm" set "PATH=%APPDATA%\npm;%PATH%"
for /f "delims=" %%I in ('npm prefix -g 2^>nul') do if exist "%%I" set "PATH=%%I;%PATH%"

echo.
echo  ==============================================================
echo    Claude-Installer
echo  ==============================================================
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%REPO%\Claude-Install.ps1"
set "EXITCODE=%ERRORLEVEL%"

echo.

if "%EXITCODE%"=="3" (
    echo  [ACTION REQUIRED] Prerequisites are missing.
    echo.
    echo    Install whatever was listed above, then open a NEW terminal
    echo    and double-click Install-Claude.bat again.
    echo.
    pause
    exit /b 3
)

if not "%EXITCODE%"=="0" (
    echo  [ERROR] Exited with code %EXITCODE%. Review the output above.
    echo.
    pause
    exit /b %EXITCODE%
)

echo  Done. Verify any time with:
echo.
echo      powershell -ExecutionPolicy Bypass -File "%REPO%\Claude-Doctor.ps1"
echo.
echo  Restart Claude Code to pick up MCP and plugin changes.
echo.
pause
endlocal
