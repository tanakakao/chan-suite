@echo off
setlocal EnableExtensions

set "SUITE_ROOT=%~dp0.."
set "APPS_DIR=%SUITE_ROOT%\apps"
set "FAILED=0"
set "USE_UV=0"
set "BASE_PYTHON="

where pnpm >nul 2>&1
if errorlevel 1 (
    echo [ERROR] pnpm was not found on PATH.
    echo Install pnpm first; each frontend pins its required version in package.json.
    exit /b 1
)

where uv >nul 2>&1
if not errorlevel 1 set "USE_UV=1"
if "%USE_UV%"=="0" (
    where py >nul 2>&1
    if not errorlevel 1 set "BASE_PYTHON=py -3"
)
if "%USE_UV%"=="0" if not defined BASE_PYTHON (
    where python >nul 2>&1
    if not errorlevel 1 set "BASE_PYTHON=python"
)
if "%USE_UV%"=="0" if not defined BASE_PYTHON (
    echo [ERROR] Neither uv, py, nor python was found on PATH.
    exit /b 1
)

call :setup_frontend "chan-portal" "."
call :setup_python "bochan" ".[web]"
call :setup_frontend "bochan" "web"
call :setup_python "malchan" ".[web,models,inverse,visualization]"
call :setup_frontend "malchan" "frontend"
call :setup_python "cauchan" "."
call :setup_frontend "cauchan" "web"
call :setup_python "dchan" "."
call :setup_frontend "dchan" "frontend"

if not "%FAILED%"=="0" (
    echo.
    echo [ERROR] One or more application setups failed.
    exit /b 1
)

echo.
echo [OK] All available applications are set up.
exit /b 0

:setup_python
set "APP=%~1"
set "SPEC=%~2"
set "APP_DIR=%APPS_DIR%\%APP%"
if not exist "%APP_DIR%\pyproject.toml" (
    echo [SKIP] %APP% Python: pyproject.toml not found.
    exit /b 0
)

pushd "%APP_DIR%" >nul
if not exist ".venv\Scripts\python.exe" (
    echo [SETUP] %APP% Python virtual environment
    if "%USE_UV%"=="1" (
        uv venv .venv
    ) else (
        call %BASE_PYTHON% -m venv .venv
    )
    if errorlevel 1 (
        echo [ERROR] %APP%: failed to create .venv.
        set "FAILED=1"
        popd >nul
        exit /b 0
    )
)

echo [SETUP] %APP% Python dependencies: %SPEC%
if "%USE_UV%"=="1" (
    uv pip install --python ".venv\Scripts\python.exe" --upgrade -e "%SPEC%"
) else (
    ".venv\Scripts\python.exe" -m pip install --upgrade pip
    if not errorlevel 1 ".venv\Scripts\python.exe" -m pip install --upgrade -e "%SPEC%"
)
if errorlevel 1 (
    echo [ERROR] %APP%: Python dependency installation failed.
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
echo [SETUP] %APP% frontend
call pnpm install --frozen-lockfile
if errorlevel 1 (
    echo [ERROR] %APP%: pnpm install failed.
    set "FAILED=1"
) else (
    echo [OK] %APP% frontend
)
popd >nul
exit /b 0
