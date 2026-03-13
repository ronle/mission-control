# Mission Control

A multi-project management dashboard for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) agents. Manage, dispatch, and monitor AI coding agents across all your projects from a single interface.

## What It Does

Mission Control gives you a centralized dashboard to:

- **Manage multiple projects** with status tracking, descriptions, and domains
- **Dispatch Claude Code agents** to work on tasks across any project
- **Monitor agent activity in real-time** via streaming output
- **Maintain project backlogs** with priorities, drag-and-drop ordering, and file attachments
- **Review agent session history** and completed work
- **Open multiple project windows** simultaneously (multi-modal windowing system)
- **View agent plans** in a dedicated wide-format viewer
- **Share baseline rules** across all projects (SHARED_RULES.md)

## Prerequisites

- **Python 3.9+** — [Download](https://www.python.org/downloads/)
- **Claude CLI** — [Installation guide](https://docs.anthropic.com/en/docs/claude-code/getting-started)
- **Node.js 18+** (optional, for Tauri desktop app) — [Download](https://nodejs.org/)

## Quick Start

### Option A: Automated Setup

**Windows:**
```
install.bat
```

**macOS / Linux:**
```bash
chmod +x install.sh
./install.sh
```

The installer checks prerequisites, installs dependencies, and creates launcher scripts.

### Option B: Manual Setup

```bash
# 1. Clone the repository
git clone https://github.com/ronle/mission-control.git
cd mission-control

# 2. Install Python dependencies
pip install -r requirements.txt

# 3. Start the server
python server.py

# 4. Open in your browser
# Navigate to http://localhost:5199
```

### Option C: Tauri Desktop App

```bash
# Requires Node.js and Rust toolchain
npm install
npm run tauri dev
```

## Configuration

On first run, a `config.json` file is created with defaults:

```json
{
  "port": 5199,
  "shared_rules_path": "data/SHARED_RULES.md",
  "projects_base": "/home/you"
}
```

| Setting | Description | Default |
|---------|-------------|---------|
| `port` | Server port | `5199` |
| `shared_rules_path` | Path to shared rules file (injected into all agent prompts) | `data/SHARED_RULES.md` |
| `projects_base` | Base directory for project path validation | User home directory |

You can also set the port via environment variable: `MC_PORT=8080 python server.py`

## Features

### Project Dashboard
- Tile-based overview of all projects with status indicators
- Drag-and-drop reordering
- Domain categorization and color coding
- Activity stream across all projects

### Agent Management
- Dispatch tasks to Claude Code agents with one click
- Real-time streaming output with syntax highlighting
- Send follow-up messages to running agents
- Multiple concurrent agent sessions per project
- Stop/resume agent sessions
- Paste screenshots directly into agent prompts

### Backlog
- Per-project task backlog with priorities (low/normal/high/critical)
- Drag-and-drop reordering
- File attachments with drag-and-drop upload
- Mark items done/reopen

### Plan Viewer
- Agent plans open in a dedicated wider window for easier reading
- Auto-detection of plan mode output
- Pop-out button for viewing any agent output in a larger window
- Ctrl+scroll zoom support

### Multi-Window System
- Open multiple project modals simultaneously
- Drag, resize, minimize, and restore windows
- Keyboard navigation (Escape to close)
- Minimized tray at bottom of screen

## Architecture

```
mission-control/
  server.py              Flask backend (API + static serving)
  static/
    index.html           Single-page app (HTML + CSS + JS, no build step)
  data/
    projects/            Project JSON files (auto-created)
    uploads/             File attachments
  src-tauri/             Tauri desktop app wrapper (optional)
  config.json            User configuration (auto-created, gitignored)
```

- **Backend**: Python Flask server on configurable port (default 5199)
- **Frontend**: Vanilla HTML/CSS/JS single-page app (no framework, no build step)
- **Data**: JSON files on disk (no database required)
- **Agent**: Spawns `claude` CLI as subprocess with streaming JSON output
- **Desktop**: Optional Tauri wrapper for native window experience

## Contributing

Contributions are welcome! Here's how to get started:

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Make your changes
4. Test locally: `python server.py` and verify in browser
5. Submit a pull request

### Development Notes

- The entire frontend is in a single `static/index.html` file — no build step needed
- The server is a single `server.py` file with Flask
- Data is stored as JSON files in `data/projects/`
- Agent sessions use Server-Sent Events (SSE) for real-time streaming
- The `claude` CLI is invoked via `subprocess.Popen` with `--output-format stream-json`

## License

[MIT](LICENSE)
