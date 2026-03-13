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

# ── Check / Install Claude CLI ────────────────────────────────────────────

echo ""
echo "[3/5] Checking Claude CLI..."
CLAUDE_INSTALLED=0
if command -v claude &> /dev/null; then
    CLVER=$(claude --version 2>&1 || echo "unknown")
    echo "       Found Claude CLI: $CLVER"
    CLAUDE_INSTALLED=1
else
    echo ""
    echo "  Claude CLI is not installed."
    echo ""
    read -p "  Would you like to install it now? [Y/n]: " INSTALL_CLAUDE
    INSTALL_CLAUDE=${INSTALL_CLAUDE:-Y}
    if [[ "$INSTALL_CLAUDE" =~ ^[Yy] ]]; then
        echo ""
        if command -v npm &> /dev/null; then
            echo "  Installing Claude CLI via npm..."
            npm install -g @anthropic-ai/claude-code && CLAUDE_INSTALLED=1 && \
                echo "       Claude CLI installed successfully." || \
                echo "  ERROR: npm install failed. Try: npm install -g @anthropic-ai/claude-code"
        else
            echo "  npm is not available. Trying native installer..."
            echo ""
            if command -v curl &> /dev/null; then
                curl -fsSL https://claude.ai/install.sh | bash && CLAUDE_INSTALLED=1 || \
                    echo "  Native installer failed."
            fi
            if [ $CLAUDE_INSTALLED -eq 0 ]; then
                echo ""
                echo "  Please install Claude CLI manually:"
                echo ""
                echo "    Option 1: Install Node.js then run:"
                echo "              npm install -g @anthropic-ai/claude-code"
                echo ""
                echo "    Option 2: Visit https://docs.anthropic.com/en/docs/claude-code"
                echo ""
            fi
        fi
    else
        echo ""
        echo "  Skipping Claude CLI installation."
        echo "  You can install it later to enable agent dispatch."
    fi
fi

# ── Claude CLI Login ──────────────────────────────────────────────────────

if [ $CLAUDE_INSTALLED -eq 1 ]; then
    echo ""
    read -p "  Would you like to log in to Claude now? [y/N]: " DO_LOGIN
    if [[ "$DO_LOGIN" =~ ^[Yy] ]]; then
        echo ""
        echo "  Opening Claude login..."
        claude login || true
        echo ""
    fi
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
echo "  ========================================"
echo "   Setup Menu"
echo "  ========================================"
echo ""
echo "  Configure your Mission Control settings."
echo "  Press Enter to accept the default shown in [brackets]."
echo ""

# 1. Port
DEFAULT_PORT=5199
read -p "  1. Server port [$DEFAULT_PORT]: " CFG_PORT
CFG_PORT=${CFG_PORT:-$DEFAULT_PORT}

# 2. Projects base directory
DEFAULT_PROJECTS="$HOME/Projects"
echo ""
echo "  The root folder where your coding projects live."
read -p "  2. Projects directory [$DEFAULT_PROJECTS]: " CFG_PROJECTS
CFG_PROJECTS=${CFG_PROJECTS:-$DEFAULT_PROJECTS}

# 3. Shared rules path
DEFAULT_RULES="$SCRIPT_DIR/data/SHARED_RULES.md"
echo ""
echo "  Markdown file with rules injected into every agent prompt."
read -p "  3. Shared rules path [data/SHARED_RULES.md]: " CFG_RULES
CFG_RULES=${CFG_RULES:-$DEFAULT_RULES}

# 4. Claude model
echo ""
echo "  Claude model for agent dispatch:"
echo "    - Leave empty for CLI default"
echo "    - claude-sonnet-4-5-20250929  (fast, recommended)"
echo "    - claude-opus-4-6             (most capable)"
echo "    - claude-haiku-4-5-20251001   (fastest, cheapest)"
read -p "  4. Agent model [default]: " CFG_MODEL
CFG_MODEL=${CFG_MODEL:-}

# 5. Max turns
echo ""
echo "  Maximum agent turns per task (0 = unlimited)."
read -p "  5. Max turns [0]: " CFG_MAXTURNS
CFG_MAXTURNS=${CFG_MAXTURNS:-0}

# 6. Desktop mode
echo ""
echo "  Desktop mode launches the Tauri native window."
echo "  Browser mode opens Mission Control in your web browser."
read -p "  6. Enable desktop mode? [y/N]: " CFG_DESKTOP
if [[ "$CFG_DESKTOP" =~ ^[Yy] ]]; then
    CFG_DESKTOP_BOOL=true
else
    CFG_DESKTOP_BOOL=false
fi

# Write config.json
echo ""
echo "  Writing config.json..."
$PYTHON -c "
import json, sys
config = {
    'port': int(sys.argv[1]),
    'projects_base': sys.argv[2],
    'shared_rules_path': sys.argv[3],
    'agent_model': sys.argv[4],
    'agent_max_turns': int(sys.argv[5]),
    'agent_permission_mode': '',
    'desktop_mode': sys.argv[6] == 'true',
}
with open('$SCRIPT_DIR/config.json', 'w', encoding='utf-8') as f:
    json.dump(config, f, indent=2, ensure_ascii=False)
" "$CFG_PORT" "$CFG_PROJECTS" "$CFG_RULES" "$CFG_MODEL" "$CFG_MAXTURNS" "$CFG_DESKTOP_BOOL"

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

if [ "$CFG_DESKTOP_BOOL" = "true" ]; then
    cat > "$SCRIPT_DIR/start.sh" << LAUNCHER
#!/bin/bash
cd "\$(dirname "\$0")"
export PYTHONIOENCODING=utf-8

echo ""
echo "  Mission Control starting (desktop mode)..."
echo "  Press Ctrl+C to stop."
echo ""

# Start Flask in background
if command -v python3 &> /dev/null; then
    python3 server.py &
else
    python server.py &
fi
FLASK_PID=\$!
sleep 2

# Launch Tauri
npm run tauri dev

# Clean up Flask when Tauri exits
kill \$FLASK_PID 2>/dev/null
LAUNCHER
else
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
fi

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
if [ -n "$CFG_MODEL" ]; then
    echo "    Agent model:    $CFG_MODEL"
else
    echo "    Agent model:    (CLI default)"
fi
if [ "$CFG_MAXTURNS" != "0" ]; then
    echo "    Max turns:      $CFG_MAXTURNS"
else
    echo "    Max turns:      unlimited"
fi
if [ "$CFG_DESKTOP_BOOL" = "true" ]; then
    echo "    Mode:           Desktop (Tauri)"
else
    echo "    Mode:           Browser"
fi
echo ""
echo "  To start Mission Control:"
if [ "$CFG_DESKTOP_BOOL" = "true" ]; then
    echo "    1. Run: ./start.sh"
else
    echo "    1. Run: ./start.sh"
    echo "    2. Or run: $PYTHON server.py"
    echo "    3. Open http://localhost:$CFG_PORT in your browser"
fi
echo ""
echo "  To change settings later, edit config.json"
echo "  or run install.sh again."
echo ""
