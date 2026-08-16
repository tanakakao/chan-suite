@echo off
setlocal EnableExtensions

cd /d "%~dp0"
set "START_AFTER_SETUP=0"

if /i "%~1"=="--start" (
    set "START_AFTER_SETUP=1"
) else if not "%~1"=="" (
    echo Usage: install.bat [--start]
    exit /b 2
)

echo ========================================
echo chan-suite initial setup
echo ========================================
echo.

echo Checking required tools...
call :require_tool git "Git"
call :require_tool uv "uv"
call :require_tool node "Node.js"
call :require_tool pnpm "pnpm"

if errorlevel 1 (
    echo.
    echo [ERROR] Required tools are missing.
    echo Install the tools shown above and run install.bat again.
    exit /b 1
)

echo.
echo [1/2] Cloning chan repositories...
call "%~dp0deploy\clone_all.bat"
if errorlevel 1 (
    echo.
    echo [ERROR] Repository clone step failed.
    exit /b 1
)

echo.
echo [2/2] Creating locked application environments...
call "%~dp0deploy\setup_all.bat"
if errorlevel 1 (
    echo.
    echo [ERROR] Environment setup failed.
    exit /b 1
)

echo.
echo ========================================
echo chan-suite setup completed successfully.
echo ========================================
echo.
echo Start all applications later with:
echo   .\deploy\start_all.bat

if "%START_AFTER_SETUP%"=="1" (
    echo.
    echo Starting all applications...
    call "%~dp0deploy\start_all.bat"
    exit /b %ERRORLEVEL%
)

exit /b 0

:require_tool
where %~1 >nul 2>&1
if errorlevel 1 (
    echo [MISSING] %~2 ^(%~1^)
    exit /b 1
)
echo [OK] %~2
exit /b 0
