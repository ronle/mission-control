#!/bin/bash
cd "$(dirname "$0")"
export PYTHONIOENCODING=utf-8

echo ""
echo "  Mission Control starting..."
echo "  Open your browser to: http://localhost:5199"
echo "  Press Ctrl+C to stop the server."
echo ""

# Try to open browser automatically
if command -v open &> /dev/null; then
    (sleep 2 && open http://localhost:5199) &
elif command -v xdg-open &> /dev/null; then
    (sleep 2 && xdg-open http://localhost:5199) &
fi

# Prefer python3, fall back to python
if command -v python3 &> /dev/null; then
    python3 server.py
else
    python server.py
fi
