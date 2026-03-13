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

echo [1/5] Checking Python...
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
echo [2/5] Installing Python dependencies...
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
echo [3/5] Checking Claude CLI...
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
echo [4/5] Setting up data directories...
if not exist "%~dp0data\projects" mkdir "%~dp0data\projects"
if not exist "%~dp0data\uploads" mkdir "%~dp0data\uploads"
echo        Data directories ready.

:: ── Configuration ─────────────────────────────────────────────────────────

echo.
echo [5/5] Configuration
echo.
echo  ----------------------------------------
echo   Setup Menu
echo  ----------------------------------------
echo.
echo  Configure your Mission Control settings.
echo  Press Enter to accept the default value shown in [brackets].
echo.

:: Port
set "CFG_PORT=5199"
set /p "CFG_PORT=  Server port [5199]: "

:: Projects base directory
set "CFG_PROJECTS=%USERPROFILE%\Projects"
echo.
echo  Projects base directory:
echo  This is the root folder where your coding projects live.
echo  Used for path validation when the agent accesses project files.
echo.
set /p "CFG_PROJECTS=  Projects directory [%USERPROFILE%\Projects]: "

:: Shared rules path
set "CFG_RULES=%~dp0data\SHARED_RULES.md"
echo.
echo  Shared rules file:
echo  A markdown file with rules/instructions injected into every
echo  agent prompt. Leave as default to use the built-in location.
echo.
set /p "CFG_RULES=  Shared rules path [%~dp0data\SHARED_RULES.md]: "

:: Write config.json
echo.
echo  Writing config.json...

:: Use Python to write proper JSON (handles escaping)
python -c "import json,sys; json.dump({'port':int(sys.argv[1]),'projects_base':sys.argv[2],'shared_rules_path':sys.argv[3]},open('config.json','w',encoding='utf-8'),indent=2,ensure_ascii=False)" "%CFG_PORT%" "%CFG_PROJECTS%" "%CFG_RULES%"
if %ERRORLEVEL% neq 0 (
    echo  WARNING: Could not write config.json. Using defaults.
) else (
    echo        Saved config.json
)

:: Create projects base dir if it doesn't exist
if not exist "%CFG_PROJECTS%" (
    echo.
    set /p "MKPROJECTS=  Projects directory does not exist. Create it? [Y/n]: "
    if /i "!MKPROJECTS!" neq "n" (
        mkdir "%CFG_PROJECTS%" 2>nul
        if exist "%CFG_PROJECTS%" (
            echo        Created %CFG_PROJECTS%
        )
    )
)

:: ── Create start.bat launcher ─────────────────────────────────────────────

echo.
echo Creating launcher script (start.bat)...

(
echo @echo off
echo cd /d "%%~dp0"
echo set PYTHONIOENCODING=utf-8
echo echo.
echo echo  Mission Control starting...
echo echo  Open your browser to: http://localhost:%CFG_PORT%
echo echo  Press Ctrl+C to stop the server.
echo echo.
echo start "" http://localhost:%CFG_PORT%
echo python server.py
) > "%~dp0start.bat"

echo        Created start.bat

:: ── Done ──────────────────────────────────────────────────────────────────

echo.
echo  ========================================
echo   Setup complete!
echo  ========================================
echo.
echo  Your configuration:
echo    Port:           %CFG_PORT%
echo    Projects dir:   %CFG_PROJECTS%
echo    Shared rules:   %CFG_RULES%
echo.
echo  To start Mission Control:
echo    1. Double-click start.bat
echo    2. Or run: python server.py
echo    3. Open http://localhost:%CFG_PORT% in your browser
echo.
echo  To change settings later, edit config.json
echo  or run install.bat again.
echo.
pause
