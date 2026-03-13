@echo off
setlocal EnableDelayedExpansion
title Mission Control - Setup
color 0F

echo.
echo  ========================================
echo   Mission Control - Setup
echo  ========================================
echo.

:: ── Check Python ──────────────────────────────────────────────────────────

echo [1/4] Checking Python...
python --version >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo.
    echo  ERROR: Python is not installed or not in PATH.
    echo.
    echo  Please install Python 3.9 or later from:
    echo  https://www.python.org/downloads/
    echo.
    echo  IMPORTANT: During installation, check the box that says
    echo  "Add Python to PATH"
    echo.
    pause
    exit /b 1
)
for /f "tokens=2 delims= " %%v in ('python --version 2^>^&1') do set PYVER=%%v
echo        Found Python %PYVER%

:: ── Install Python dependencies ───────────────────────────────────────────

echo.
echo [2/4] Installing Python dependencies...
pip install -r "%~dp0requirements.txt" >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo        Trying with pip3...
    pip3 install -r "%~dp0requirements.txt" >nul 2>&1
    if %ERRORLEVEL% neq 0 (
        echo.
        echo  ERROR: Failed to install Python dependencies.
        echo  Try running manually: pip install flask
        echo.
        pause
        exit /b 1
    )
)
echo        Dependencies installed.

:: ── Check Claude CLI ──────────────────────────────────────────────────────

echo.
echo [3/4] Checking Claude CLI...
claude --version >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo.
    echo  WARNING: Claude CLI is not installed or not in PATH.
    echo.
    echo  The dashboard will work, but you won't be able to dispatch
    echo  agents until Claude CLI is installed.
    echo.
    echo  Install from: https://docs.anthropic.com/en/docs/claude-code
    echo.
) else (
    for /f "tokens=*" %%v in ('claude --version 2^>^&1') do set CLVER=%%v
    echo        Found Claude CLI: !CLVER!
)

:: ── Create data directories ───────────────────────────────────────────────

echo.
echo [4/4] Setting up data directories...
if not exist "%~dp0data\projects" mkdir "%~dp0data\projects"
if not exist "%~dp0data\uploads" mkdir "%~dp0data\uploads"
echo        Data directories ready.

:: ── Create start.bat launcher ─────────────────────────────────────────────

echo.
echo Creating launcher script (start.bat)...

(
echo @echo off
echo cd /d "%%~dp0"
echo set PYTHONIOENCODING=utf-8
echo echo.
echo echo  Mission Control starting...
echo echo  Open your browser to: http://localhost:5199
echo echo  Press Ctrl+C to stop the server.
echo echo.
echo start "" http://localhost:5199
echo python server.py
) > "%~dp0start.bat"

echo        Created start.bat

:: ── Done ──────────────────────────────────────────────────────────────────

echo.
echo  ========================================
echo   Setup complete!
echo  ========================================
echo.
echo  To start Mission Control:
echo    1. Double-click start.bat
echo    2. Or run: python server.py
echo    3. Open http://localhost:5199 in your browser
echo.
echo  Configuration: edit config.json to customize
echo  settings (created on first server start).
echo.
pause
