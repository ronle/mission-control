@echo off
cd /d "%~dp0"
set PYTHONIOENCODING=utf-8
echo.
echo  Mission Control starting...
echo  Open your browser to: http://localhost:5199
echo  Press Ctrl+C to stop the server.
echo.
start "" http://localhost:5199
python server.py
