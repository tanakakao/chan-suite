@echo off
setlocal EnableExtensions

set "PROFILE=Local"
set "SERVER_HOST="
if not "%~1"=="" set "PROFILE=%~1"
if not "%~2"=="" set "SERVER_HOST=%~2"

if /i not "%PROFILE%"=="Local" if /i not "%PROFILE%"=="Intranet" (
    echo [ERROR] Profile must be Local or Intranet.
    echo Usage: %~nx0 [Local^|Intranet] [server-host]
    exit /b 1
)

where powershell.exe >nul 2>&1
if errorlevel 1 (
    echo [ERROR] powershell.exe was not found on PATH.
    exit /b 1
)

if /i "%PROFILE%"=="Intranet" (
    if defined SERVER_HOST (
        powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0start_all.ps1" -Profile Intranet -ServerHost "%SERVER_HOST%"
    ) else (
        powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0start_all.ps1" -Profile Intranet
    )
) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0start_all.ps1" -Profile Local
)

exit /b %ERRORLEVEL%
