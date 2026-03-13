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

:: ── Check / Install Claude CLI ────────────────────────────────────────────

echo.
echo [3/5] Checking Claude CLI...
set CLAUDE_INSTALLED=0
claude --version >nul 2>&1
if %ERRORLEVEL% equ 0 (
    for /f "tokens=*" %%v in ('claude --version 2^>^&1') do set CLVER=%%v
    echo        Found Claude CLI: !CLVER!
    set CLAUDE_INSTALLED=1
) else (
    echo.
    echo  Claude CLI is not installed.
    echo.
    set /p "INSTALL_CLAUDE=  Would you like to install it now? [Y/n]: "
    if /i "!INSTALL_CLAUDE!" neq "n" (
        echo.
        echo  Checking for npm...
        npm --version >nul 2>&1
        if !ERRORLEVEL! equ 0 (
            echo  Installing Claude CLI via npm...
            npm install -g @anthropic-ai/claude-code
            if !ERRORLEVEL! equ 0 (
                echo        Claude CLI installed successfully.
                set CLAUDE_INSTALLED=1
            ) else (
                echo  ERROR: npm install failed.
                echo  Try manually: npm install -g @anthropic-ai/claude-code
            )
        ) else (
            echo.
            echo  npm is not available. Please install Claude CLI manually:
            echo.
            echo    Option 1: Install Node.js from https://nodejs.org/
            echo              then run: npm install -g @anthropic-ai/claude-code
            echo.
            echo    Option 2: Visit https://docs.anthropic.com/en/docs/claude-code
            echo              for alternative installation methods
            echo.
        )
    ) else (
        echo.
        echo  Skipping Claude CLI installation.
        echo  You can install it later to enable agent dispatch.
    )
)

:: ── Claude CLI Login ──────────────────────────────────────────────────────

if %CLAUDE_INSTALLED% equ 1 (
    echo.
    set /p "DO_LOGIN=  Would you like to log in to Claude now? [y/N]: "
    if /i "!DO_LOGIN!" equ "y" (
        echo.
        echo  Opening Claude login...
        claude login
        echo.
    )
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
echo  ========================================
echo   Setup Menu
echo  ========================================
echo.
echo  Configure your Mission Control settings.
echo  Press Enter to accept the default shown in [brackets].
echo.

:: Port
set "CFG_PORT=5199"
set /p "CFG_PORT=  1. Server port [5199]: "

:: Projects base directory
set "CFG_PROJECTS=%USERPROFILE%\Projects"
echo.
echo  The root folder where your coding projects live.
set /p "CFG_PROJECTS=  2. Projects directory [%USERPROFILE%\Projects]: "

:: Shared rules path
set "CFG_RULES=%~dp0data\SHARED_RULES.md"
echo.
echo  Markdown file with rules injected into every agent prompt.
set /p "CFG_RULES=  3. Shared rules path [data\SHARED_RULES.md]: "

:: Claude model
echo.
echo  Claude model for agent dispatch:
echo    - Leave empty for CLI default
echo    - claude-sonnet-4-5-20250929  (fast, recommended)
echo    - claude-opus-4-6             (most capable)
echo    - claude-haiku-4-5-20251001   (fastest, cheapest)
set "CFG_MODEL="
set /p "CFG_MODEL=  4. Agent model [default]: "

:: Max turns
echo.
echo  Maximum agent turns per task (0 = unlimited).
set "CFG_MAXTURNS=0"
set /p "CFG_MAXTURNS=  5. Max turns [0]: "

:: Desktop mode
echo.
echo  Desktop mode launches the Tauri native window.
echo  Browser mode opens Mission Control in your web browser.
set "CFG_DESKTOP=n"
set /p "CFG_DESKTOP=  6. Enable desktop mode? [y/N]: "
if /i "!CFG_DESKTOP!" equ "y" (
    set CFG_DESKTOP_BOOL=true
) else (
    set CFG_DESKTOP_BOOL=false
)

:: Write config.json
echo.
echo  Writing config.json...

python -c "import json,sys; json.dump({'port':int(sys.argv[1]),'projects_base':sys.argv[2],'shared_rules_path':sys.argv[3],'agent_model':sys.argv[4],'agent_max_turns':int(sys.argv[5]),'agent_permission_mode':'','desktop_mode':sys.argv[6]=='true'},open('config.json','w',encoding='utf-8'),indent=2,ensure_ascii=False)" "%CFG_PORT%" "%CFG_PROJECTS%" "%CFG_RULES%" "%CFG_MODEL%" "%CFG_MAXTURNS%" "%CFG_DESKTOP_BOOL%"
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

if /i "%CFG_DESKTOP_BOOL%" equ "true" (
    (
    echo @echo off
    echo cd /d "%%~dp0"
    echo set PYTHONIOENCODING=utf-8
    echo echo.
    echo echo  Mission Control starting ^(desktop mode^)...
    echo echo  Press Ctrl+C to stop the server.
    echo echo.
    echo start "" /b python server.py
    echo timeout /t 2 /nobreak ^>nul
    echo npm run tauri dev
    ) > "%~dp0start.bat"
) else (
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
)

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
if defined CFG_MODEL if not "%CFG_MODEL%" == "" (
echo    Agent model:    %CFG_MODEL%
) else (
echo    Agent model:    (CLI default^)
)
if "%CFG_MAXTURNS%" neq "0" (
echo    Max turns:      %CFG_MAXTURNS%
) else (
echo    Max turns:      unlimited
)
if /i "%CFG_DESKTOP_BOOL%" equ "true" (
echo    Mode:           Desktop (Tauri^)
) else (
echo    Mode:           Browser
)
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
