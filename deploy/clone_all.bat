@echo off
setlocal EnableExtensions

set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%..") do set "SUITE_ROOT=%%~fI"
set "APPS_DIR=%SUITE_ROOT%\apps"

if not defined CHAN_GITHUB_OWNER set "CHAN_GITHUB_OWNER=tanakakao"

where git >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Git was not found on PATH.
    exit /b 1
)

if not exist "%APPS_DIR%" (
    mkdir "%APPS_DIR%"
    if errorlevel 1 (
        echo [ERROR] Failed to create "%APPS_DIR%".
        exit /b 1
    )
)

set "FAILED=0"

for %%R in (chan-portal bochan malchan cauchan dchan) do call :clone_repo %%R

if "%FAILED%"=="1" (
    echo.
    echo [ERROR] One or more repositories could not be cloned.
    exit /b 1
)

echo.
echo [OK] chan-suite repositories are ready under "%APPS_DIR%".
exit /b 0

:clone_repo
set "REPO=%~1"
set "TARGET=%APPS_DIR%\%REPO%"
set "REMOTE=https://github.com/%CHAN_GITHUB_OWNER%/%REPO%.git"

if exist "%TARGET%\.git" (
    echo [SKIP] %REPO% already exists.
    exit /b 0
)

if exist "%TARGET%" (
    echo [ERROR] "%TARGET%" exists but is not a Git repository.
    set "FAILED=1"
    exit /b 0
)

echo [CLONE] %REMOTE%
git clone "%REMOTE%" "%TARGET%"
if errorlevel 1 (
    echo [ERROR] Failed to clone %REPO%.
    set "FAILED=1"
) else (
    echo [OK] %REPO%
)
exit /b 0
