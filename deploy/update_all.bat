@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SUITE_ROOT=%~dp0.."
set "APPS_DIR=%SUITE_ROOT%\apps"
set "FAILED=0"

where git >nul 2>&1
if errorlevel 1 (
    echo [ERROR] git was not found on PATH.
    exit /b 1
)

for %%R in (chan-portal bochan malchan cauchan dchan) do call :update_repo "%%R"

if not "%FAILED%"=="0" (
    echo.
    echo [ERROR] One or more repositories could not be updated.
    exit /b 1
)

echo.
echo [OK] All cloned repositories are up to date.
exit /b 0

:update_repo
set "REPO=%~1"
set "REPO_DIR=%APPS_DIR%\%REPO%"

if not exist "%REPO_DIR%\" (
    echo [SKIP] %REPO%: directory not found.
    exit /b 0
)
if not exist "%REPO_DIR%\.git\" (
    echo [ERROR] %REPO%: directory exists but is not a Git repository.
    set "FAILED=1"
    exit /b 0
)

pushd "%REPO_DIR%" >nul
set "DIRTY=0"
for /f "delims=" %%S in ('git status --porcelain') do set "DIRTY=1"
if "!DIRTY!"=="1" (
    echo [SKIP] %REPO%: working tree has local changes. Commit or stash them first.
    set "FAILED=1"
    popd >nul
    exit /b 0
)

git symbolic-ref --quiet --short HEAD >nul 2>&1
if errorlevel 1 (
    echo [SKIP] %REPO%: detached HEAD. Check out a branch first.
    set "FAILED=1"
    popd >nul
    exit /b 0
)

echo [UPDATE] %REPO%
git pull --ff-only
if errorlevel 1 (
    echo [ERROR] %REPO%: git pull --ff-only failed.
    set "FAILED=1"
) else (
    echo [OK] %REPO%
)
popd >nul
exit /b 0
