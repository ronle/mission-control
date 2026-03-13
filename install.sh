#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo ""
echo "  ========================================"
echo "   Mission Control - Setup"
echo "  ========================================"
echo ""

# ── Check Python ──────────────────────────────────────────────────────────

echo "[1/5] Checking Python..."
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
echo "[2/5] Installing Python dependencies..."
$PYTHON -m pip install -r "$SCRIPT_DIR/requirements.txt" --quiet 2>/dev/null || \
    $PYTHON -m pip install flask --quiet
echo "       Dependencies installed."

# ── Check Claude CLI ──────────────────────────────────────────────────────

echo ""
echo "[3/5] Checking Claude CLI..."
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
echo "[4/5] Setting up data directories..."
mkdir -p "$SCRIPT_DIR/data/projects"
mkdir -p "$SCRIPT_DIR/data/uploads"
echo "       Data directories ready."

# ── Configuration ─────────────────────────────────────────────────────────

echo ""
echo "[5/5] Configuration"
echo ""
echo "  ----------------------------------------"
echo "   Setup Menu"
echo "  ----------------------------------------"
echo ""
echo "  Configure your Mission Control settings."
echo "  Press Enter to accept the default value shown in [brackets]."
echo ""

# Port
DEFAULT_PORT=5199
read -p "  Server port [$DEFAULT_PORT]: " CFG_PORT
CFG_PORT=${CFG_PORT:-$DEFAULT_PORT}

# Projects base directory
DEFAULT_PROJECTS="$HOME/Projects"
echo ""
echo "  Projects base directory:"
echo "  This is the root folder where your coding projects live."
echo "  Used for path validation when the agent accesses project files."
echo ""
read -p "  Projects directory [$DEFAULT_PROJECTS]: " CFG_PROJECTS
CFG_PROJECTS=${CFG_PROJECTS:-$DEFAULT_PROJECTS}

# Shared rules path
DEFAULT_RULES="$SCRIPT_DIR/data/SHARED_RULES.md"
echo ""
echo "  Shared rules file:"
echo "  A markdown file with rules/instructions injected into every"
echo "  agent prompt. Leave as default to use the built-in location."
echo ""
read -p "  Shared rules path [$DEFAULT_RULES]: " CFG_RULES
CFG_RULES=${CFG_RULES:-$DEFAULT_RULES}

# Write config.json
echo ""
echo "  Writing config.json..."
$PYTHON -c "
import json, sys
config = {
    'port': int(sys.argv[1]),
    'projects_base': sys.argv[2],
    'shared_rules_path': sys.argv[3],
}
with open('$SCRIPT_DIR/config.json', 'w', encoding='utf-8') as f:
    json.dump(config, f, indent=2, ensure_ascii=False)
" "$CFG_PORT" "$CFG_PROJECTS" "$CFG_RULES"

if [ $? -eq 0 ]; then
    echo "       Saved config.json"
else
    echo "  WARNING: Could not write config.json. Using defaults."
fi

# Create projects base dir if it doesn't exist
if [ ! -d "$CFG_PROJECTS" ]; then
    echo ""
    read -p "  Projects directory does not exist. Create it? [Y/n]: " MKPROJECTS
    MKPROJECTS=${MKPROJECTS:-Y}
    if [[ "$MKPROJECTS" =~ ^[Yy] ]]; then
        mkdir -p "$CFG_PROJECTS"
        echo "       Created $CFG_PROJECTS"
    fi
fi

# ── Create start.sh launcher ─────────────────────────────────────────────

echo ""
echo "Creating launcher script (start.sh)..."

cat > "$SCRIPT_DIR/start.sh" << LAUNCHER
#!/bin/bash
cd "\$(dirname "\$0")"
export PYTHONIOENCODING=utf-8

echo ""
echo "  Mission Control starting..."
echo "  Open your browser to: http://localhost:$CFG_PORT"
echo "  Press Ctrl+C to stop the server."
echo ""

# Try to open browser automatically
if command -v open &> /dev/null; then
    (sleep 2 && open http://localhost:$CFG_PORT) &
elif command -v xdg-open &> /dev/null; then
    (sleep 2 && xdg-open http://localhost:$CFG_PORT) &
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
echo "  Your configuration:"
echo "    Port:           $CFG_PORT"
echo "    Projects dir:   $CFG_PROJECTS"
echo "    Shared rules:   $CFG_RULES"
echo ""
echo "  To start Mission Control:"
echo "    1. Run: ./start.sh"
echo "    2. Or run: $PYTHON server.py"
echo "    3. Open http://localhost:$CFG_PORT in your browser"
echo ""
echo "  To change settings later, edit config.json"
echo "  or run install.sh again."
echo ""
