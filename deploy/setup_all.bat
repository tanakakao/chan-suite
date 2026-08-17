@echo off
setlocal EnableExtensions

set "SUITE_ROOT=%~dp0.."
set "APPS_DIR=%SUITE_ROOT%\apps"
set "FAILED=0"
set "PYTHON_VERSION=%CHAN_PYTHON_VERSION%"
if not defined PYTHON_VERSION set "PYTHON_VERSION=3.12"

where pnpm >nul 2>&1
if errorlevel 1 (
    echo [ERROR] pnpm was not found on PATH.
    echo Install pnpm first; each frontend pins its required version in package.json.
    exit /b 1
)

where uv >nul 2>&1
if errorlevel 1 (
    echo [ERROR] uv was not found on PATH.
    echo Python environments in chan-suite are managed from each repository's uv.lock.
    exit /b 1
)

call :setup_frontend "chan-portal" "."
call :setup_python "bochan" "--extra web"
call :setup_frontend "bochan" "web"
call :setup_python "malchan" "--extra web --extra models --extra materials --extra inverse --extra visualization"
call :setup_frontend "malchan" "frontend"
call :setup_python "cauchan" ""
call :setup_frontend "cauchan" "web"
call :setup_python "dchan" ""
call :setup_frontend "dchan" "frontend"

if not "%FAILED%"=="0" (
    echo.
    echo [ERROR] One or more application setups failed.
    exit /b 1
)

echo.
echo [OK] All available applications are set up from committed lockfiles.
exit /b 0

:setup_python
set "APP=%~1"
set "SYNC_ARGS=%~2"
set "APP_DIR=%APPS_DIR%\%APP%"
if not exist "%APP_DIR%\pyproject.toml" (
    echo [SKIP] %APP% Python: pyproject.toml not found.
    exit /b 0
)
if not exist "%APP_DIR%\uv.lock" (
    echo [ERROR] %APP% Python: uv.lock not found.
    echo         Update the repository; do not generate a deployment lockfile implicitly.
    set "FAILED=1"
    exit /b 0
)

pushd "%APP_DIR%" >nul
echo [SETUP] %APP% Python %PYTHON_VERSION% from uv.lock
uv sync --locked --python "%PYTHON_VERSION%" %SYNC_ARGS%
if errorlevel 1 (
    echo [ERROR] %APP%: uv sync --locked failed.
    echo         pyproject.toml and uv.lock must agree.
    set "FAILED=1"
) else (
    echo [OK] %APP% Python
)
popd >nul
exit /b 0

:setup_frontend
set "APP=%~1"
set "RELATIVE_DIR=%~2"
set "APP_DIR=%APPS_DIR%\%APP%"
if "%RELATIVE_DIR%"=="." (
    set "FRONTEND_DIR=%APP_DIR%"
) else (
    set "FRONTEND_DIR=%APP_DIR%\%RELATIVE_DIR%"
)
if not exist "%FRONTEND_DIR%\package.json" (
    echo [SKIP] %APP% frontend: package.json not found.
    exit /b 0
)
if not exist "%FRONTEND_DIR%\pnpm-lock.yaml" (
    echo [ERROR] %APP% frontend: pnpm-lock.yaml not found.
    set "FAILED=1"
    exit /b 0
)

pushd "%FRONTEND_DIR%" >nul
echo [SETUP] %APP% frontend from pnpm-lock.yaml
call pnpm install --frozen-lockfile
if errorlevel 1 (
    echo [ERROR] %APP%: pnpm install failed.
    set "FAILED=1"
) else (
    echo [OK] %APP% frontend
)
popd >nul
exit /b 0
