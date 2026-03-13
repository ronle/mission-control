#!/bin/bash
set -e

echo ""
echo "  ========================================"
echo "   Mission Control - Setup"
echo "  ========================================"
echo ""

# ── Check Python ──────────────────────────────────────────────────────────

echo "[1/4] Checking Python..."
if command -v python3 &> /dev/null; then
    PYTHON=python3
elif command -v python &> /dev/null; then
    PYTHON=python
else
    echo ""
    echo "  ERROR: Python is not installed."
    echo ""
    echo "  Install Python 3.9 or later:"
    echo "    macOS:  brew install python"
    echo "    Ubuntu: sudo apt install python3 python3-pip"
    echo "    Other:  https://www.python.org/downloads/"
    echo ""
    exit 1
fi
PYVER=$($PYTHON --version 2>&1)
echo "       Found $PYVER"

# ── Install Python dependencies ───────────────────────────────────────────

echo ""
echo "[2/4] Installing Python dependencies..."
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
$PYTHON -m pip install -r "$SCRIPT_DIR/requirements.txt" --quiet 2>/dev/null || \
    $PYTHON -m pip install flask --quiet
echo "       Dependencies installed."

# ── Check Claude CLI ──────────────────────────────────────────────────────

echo ""
echo "[3/4] Checking Claude CLI..."
if command -v claude &> /dev/null; then
    CLVER=$(claude --version 2>&1 || echo "unknown")
    echo "       Found Claude CLI: $CLVER"
else
    echo ""
    echo "  WARNING: Claude CLI is not installed or not in PATH."
    echo ""
    echo "  The dashboard will work, but you won't be able to dispatch"
    echo "  agents until Claude CLI is installed."
    echo ""
    echo "  Install from: https://docs.anthropic.com/en/docs/claude-code"
    echo ""
fi

# ── Create data directories ───────────────────────────────────────────────

echo ""
echo "[4/4] Setting up data directories..."
mkdir -p "$SCRIPT_DIR/data/projects"
mkdir -p "$SCRIPT_DIR/data/uploads"
echo "       Data directories ready."

# ── Create start.sh launcher ─────────────────────────────────────────────

echo ""
echo "Creating launcher script (start.sh)..."

cat > "$SCRIPT_DIR/start.sh" << 'LAUNCHER'
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
LAUNCHER

chmod +x "$SCRIPT_DIR/start.sh"
echo "       Created start.sh"

# ── Done ──────────────────────────────────────────────────────────────────

echo ""
echo "  ========================================"
echo "   Setup complete!"
echo "  ========================================"
echo ""
echo "  To start Mission Control:"
echo "    1. Run: ./start.sh"
echo "    2. Or run: python3 server.py"
echo "    3. Open http://localhost:5199 in your browser"
echo ""
echo "  Configuration: edit config.json to customize"
echo "  settings (created on first server start)."
echo ""
