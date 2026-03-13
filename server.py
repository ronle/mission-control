#!/usr/bin/env python3
import json
import os
import uuid
import mimetypes
import subprocess
import threading
import time as _time
from pathlib import Path
from datetime import datetime, timezone
from flask import Flask, jsonify, send_from_directory, request, send_file, abort, Response

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
STATIC_DIR = os.path.join(BASE_DIR, 'static')

app = Flask(__name__, static_folder=STATIC_DIR)
app.config['MAX_CONTENT_LENGTH'] = 50 * 1024 * 1024  # 50 MB max upload

# ── Configuration ────────────────────────────────────────────────────────────

CONFIG_PATH = Path(BASE_DIR) / 'config.json'

def _load_config():
    """Load config.json, creating with defaults if it doesn't exist."""
    defaults = {
        'port': 5199,
        'shared_rules_path': str(Path(BASE_DIR) / 'data' / 'SHARED_RULES.md'),
        'projects_base': str(Path.home()),
    }
    if CONFIG_PATH.exists():
        try:
            with open(CONFIG_PATH, encoding='utf-8') as f:
                saved = json.load(f)
            # Merge: saved values override defaults
            for k, v in saved.items():
                defaults[k] = v
        except Exception:
            pass
    else:
        # Create default config for the user to customize
        with open(CONFIG_PATH, 'w', encoding='utf-8') as f:
            json.dump(defaults, f, indent=2, ensure_ascii=False)
    return defaults

CONFIG = _load_config()
PORT = int(os.environ.get('MC_PORT', CONFIG.get('port', 5199)))

ALLOWED_ORIGINS = {
    'https://tauri.localhost',
    'tauri://localhost',
    f'http://localhost:{PORT}',
}

@app.after_request
def add_cors_headers(response):
    origin = request.headers.get('Origin', '')
    if origin in ALLOWED_ORIGINS:
        response.headers['Access-Control-Allow-Origin'] = origin
        response.headers['Access-Control-Allow-Methods'] = 'GET, POST, PUT, PATCH, DELETE, OPTIONS'
        response.headers['Access-Control-Allow-Headers'] = 'Content-Type'
    if request.method == 'OPTIONS':
        response.status_code = 204
    return response

DATA_DIR = Path(BASE_DIR) / 'data' / 'projects'
DATA_DIR.mkdir(parents=True, exist_ok=True)

UPLOADS_DIR = Path(BASE_DIR) / 'data' / 'uploads'
UPLOADS_DIR.mkdir(parents=True, exist_ok=True)

SHARED_RULES_PATH = Path(CONFIG.get('shared_rules_path', ''))
PROJECTS_BASE = Path(CONFIG.get('projects_base', str(Path.home())))

# ── Agent session tracking ───────────────────────────────────────────────────
# session_id → {proc, status, task, log_lines, started_at, session_id, project_id}
agent_sessions = {}
agent_lock = threading.Lock()  # single global lock for session creation


def load_project(project_id):
    filepath = DATA_DIR / f'{project_id}.json'
    if not filepath.exists():
        return None
    return json.loads(filepath.read_text(encoding='utf-8'))


def save_project(project_id, data):
    filepath = DATA_DIR / f'{project_id}.json'
    filepath.write_text(json.dumps(data, indent=2, ensure_ascii=False), encoding='utf-8')


def load_projects():
    projects = []
    for f in DATA_DIR.glob('*.json'):
        if f.name.endswith('_agent_log.json'):
            continue
        try:
            p = json.loads(f.read_text(encoding='utf-8'))
            if not isinstance(p, dict):
                continue
            p.setdefault('status', 'unknown')
            p.setdefault('blocked', False)
            p.setdefault('activity_log', [])
            p.setdefault('current_task', '')
            p.setdefault('next_action', '')
            p.setdefault('domain', 'general')
            p.setdefault('blocked_reason', None)
            p.setdefault('backlog', [])
            p.setdefault('project_path', '')
            projects.append(p)
        except Exception as e:
            print(f"Error loading {f}: {e}")
    projects.sort(key=lambda p: (p.get('display_order', 9999), p.get('last_updated', '1970-01-01T00:00:00Z')))
    # Secondary sort: within same display_order, most recently updated first
    projects.sort(key=lambda p: p.get('last_updated', '1970-01-01T00:00:00Z'), reverse=True)
    projects.sort(key=lambda p: p.get('display_order', 9999))
    return projects


def time_ago(ts_str):
    if not ts_str:
        return 'never'
    try:
        ts = datetime.fromisoformat(ts_str.replace('Z', '+00:00'))
        now = datetime.now(timezone.utc)
        secs = int((now - ts).total_seconds())
        if secs < 60:      return f'{secs}s ago'
        elif secs < 3600:  return f'{secs // 60}m ago'
        elif secs < 86400: return f'{secs // 3600}h ago'
        else:              return f'{secs // 86400}d ago'
    except:
        return ts_str


def now_iso():
    return datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')


def file_type(filename):
    """Return a simple type hint for UI rendering."""
    ext = Path(filename).suffix.lower()
    images = {'.png', '.jpg', '.jpeg', '.gif', '.webp', '.svg', '.bmp'}
    if ext in images:
        return 'image'
    if ext == '.pdf':
        return 'pdf'
    return 'file'


# ── Project endpoints ────────────────────────────────────────────────────────

@app.route('/api/projects')
def api_projects():
    projects = load_projects()
    for p in projects:
        p['last_updated_relative'] = time_ago(p.get('last_updated'))
        for entry in p.get('activity_log', []):
            entry['ts_relative'] = time_ago(entry.get('ts'))
        for item in p.get('backlog', []):
            item['ts_relative'] = time_ago(item.get('created_at'))
    return jsonify(projects)


@app.route('/api/project/<project_id>', methods=['POST'])
def update_project(project_id):
    data = request.get_json()
    if not data:
        return jsonify({'error': 'no data'}), 400

    filepath = DATA_DIR / f'{project_id}.json'
    existing = json.loads(filepath.read_text(encoding='utf-8')) if filepath.exists() else {'id': project_id}
    existing.setdefault('backlog', [])

    for k, v in data.items():
        if k not in ('log_msg', 'backlog'):
            existing[k] = v

    existing['last_updated'] = now_iso()

    if 'log_msg' in data:
        log = existing.setdefault('activity_log', [])
        log.insert(0, {'ts': existing['last_updated'], 'msg': data['log_msg']})
        existing['activity_log'] = log[:20]

    save_project(project_id, existing)
    return jsonify({'ok': True, 'id': project_id})


# ── Backlog endpoints ────────────────────────────────────────────────────────

@app.route('/api/project/<project_id>/backlog', methods=['GET'])
def get_backlog(project_id):
    p = load_project(project_id)
    if p is None:
        return jsonify({'error': 'not found'}), 404
    return jsonify(p.get('backlog', []))


@app.route('/api/project/<project_id>/backlog', methods=['POST'])
def add_backlog_item(project_id):
    data = request.get_json()
    if not data or not data.get('text', '').strip():
        return jsonify({'error': 'text required'}), 400

    p = load_project(project_id)
    if p is None:
        return jsonify({'error': 'not found'}), 404

    item = {
        'id': str(uuid.uuid4())[:8],
        'text': data['text'].strip(),
        'priority': data.get('priority', 'normal'),
        'status': 'open',
        'created_at': now_iso(),
        'done_at': None,
        'source': data.get('source', 'dashboard'),
        'attachments': [],
    }

    backlog = p.setdefault('backlog', [])
    backlog.insert(0, item)
    p['last_updated'] = now_iso()
    save_project(project_id, p)
    return jsonify({'ok': True, 'item': item})


@app.route('/api/project/<project_id>/backlog/<item_id>', methods=['PATCH'])
def update_backlog_item(project_id, item_id):
    data = request.get_json()
    if not data:
        return jsonify({'error': 'no data'}), 400

    p = load_project(project_id)
    if p is None:
        return jsonify({'error': 'project not found'}), 404

    backlog = p.get('backlog', [])
    item = next((i for i in backlog if i['id'] == item_id), None)
    if item is None:
        return jsonify({'error': 'item not found'}), 404

    if 'text' in data:
        item['text'] = data['text'].strip()
    if 'priority' in data:
        item['priority'] = data['priority']
    if 'status' in data:
        item['status'] = data['status']
        if data['status'] == 'done' and not item.get('done_at'):
            item['done_at'] = now_iso()
        elif data['status'] == 'open':
            item['done_at'] = None

    p['last_updated'] = now_iso()
    save_project(project_id, p)
    return jsonify({'ok': True, 'item': item})


@app.route('/api/project/<project_id>/backlog/<item_id>', methods=['DELETE'])
def delete_backlog_item(project_id, item_id):
    p = load_project(project_id)
    if p is None:
        return jsonify({'error': 'not found'}), 404

    # Also delete any attachments for this item
    item = next((i for i in p.get('backlog', []) if i['id'] == item_id), None)
    if item:
        for att in item.get('attachments', []):
            att_path = UPLOADS_DIR / att['stored_name']
            if att_path.exists():
                att_path.unlink()

    before = len(p.get('backlog', []))
    p['backlog'] = [i for i in p.get('backlog', []) if i['id'] != item_id]
    if len(p['backlog']) == before:
        return jsonify({'error': 'item not found'}), 404

    p['last_updated'] = now_iso()
    save_project(project_id, p)
    return jsonify({'ok': True})


# ── Attachment endpoints ─────────────────────────────────────────────────────

@app.route('/api/project/<project_id>/backlog/<item_id>/attachments', methods=['POST'])
def upload_attachment(project_id, item_id):
    """Upload a file and attach it to a backlog item."""
    p = load_project(project_id)
    if p is None:
        return jsonify({'error': 'project not found'}), 404

    item = next((i for i in p.get('backlog', []) if i['id'] == item_id), None)
    if item is None:
        return jsonify({'error': 'item not found'}), 404

    if 'file' not in request.files:
        return jsonify({'error': 'no file'}), 400

    f = request.files['file']
    if not f.filename:
        return jsonify({'error': 'empty filename'}), 400

    original_name = f.filename
    ext = Path(original_name).suffix.lower()
    stored_name = f'{project_id}_{item_id}_{uuid.uuid4().hex[:8]}{ext}'
    dest = UPLOADS_DIR / stored_name
    f.save(str(dest))

    att = {
        'id': str(uuid.uuid4())[:8],
        'original_name': original_name,
        'stored_name': stored_name,
        'size': dest.stat().st_size,
        'type': file_type(original_name),
        'uploaded_at': now_iso(),
    }

    item.setdefault('attachments', []).append(att)
    p['last_updated'] = now_iso()
    save_project(project_id, p)
    return jsonify({'ok': True, 'attachment': att})


@app.route('/api/attachments/<stored_name>')
def serve_attachment(stored_name):
    """Serve an attachment file."""
    safe = Path(stored_name).name  # prevent path traversal
    att_path = UPLOADS_DIR / safe
    if not att_path.exists():
        abort(404)
    return send_file(str(att_path), as_attachment=False)


@app.route('/api/project/<project_id>/backlog/<item_id>/attachments/<att_id>', methods=['DELETE'])
def delete_attachment(project_id, item_id, att_id):
    p = load_project(project_id)
    if p is None:
        return jsonify({'error': 'project not found'}), 404

    item = next((i for i in p.get('backlog', []) if i['id'] == item_id), None)
    if item is None:
        return jsonify({'error': 'item not found'}), 404

    atts = item.get('attachments', [])
    att = next((a for a in atts if a['id'] == att_id), None)
    if att is None:
        return jsonify({'error': 'attachment not found'}), 404

    att_path = UPLOADS_DIR / att['stored_name']
    if att_path.exists():
        att_path.unlink()

    item['attachments'] = [a for a in atts if a['id'] != att_id]
    p['last_updated'] = now_iso()
    save_project(project_id, p)
    return jsonify({'ok': True})


# ── Project import ────────────────────────────────────────────────────────────

def _parse_changelog(text):
    """Parse the most recent CHANGELOG.md entry into structured sections."""
    lines = text.split('\n')
    # Find first ## heading (most recent entry)
    start = None
    for i, line in enumerate(lines):
        if line.startswith('## '):
            if start is None:
                start = i
            else:
                # Hit the next entry, stop
                lines = lines[start:i]
                break
    else:
        if start is not None:
            lines = lines[start:]
        else:
            return {}

    title = lines[0].lstrip('# ').strip() if lines else ''
    sections = {}
    current_section = None
    current_lines = []

    for line in lines[1:]:
        if line.startswith('### '):
            if current_section:
                sections[current_section] = current_lines
            current_section = line.lstrip('# ').strip().lower()
            current_lines = []
        elif current_section:
            stripped = line.strip()
            if stripped and stripped != '---':
                # Remove leading "- " or "* "
                if stripped.startswith('- ') or stripped.startswith('* '):
                    stripped = stripped[2:]
                if stripped:
                    current_lines.append(stripped)

    if current_section:
        sections[current_section] = current_lines

    return {'title': title, 'sections': sections}


@app.route('/api/project/<project_id>/import', methods=['POST'])
def import_from_project(project_id):
    p = load_project(project_id)
    if not p:
        return jsonify({'error': 'project not found'}), 404

    pp = p.get('project_path', '')
    if not pp or not Path(pp).is_dir():
        return jsonify({'error': 'project_path not set or invalid'}), 400

    imported = {}

    # Parse CHANGELOG.md
    changelog_path = Path(pp) / 'CHANGELOG.md'
    if changelog_path.exists():
        parsed = _parse_changelog(changelog_path.read_text(encoding='utf-8'))
        sections = parsed.get('sections', {})
        title = parsed.get('title', '')

        # Done → activity log entries
        done_items = sections.get('done', [])
        if done_items:
            log = p.setdefault('activity_log', [])
            ts = now_iso()
            for item in done_items:
                if not any(e.get('msg') == item for e in log):
                    log.insert(0, {'ts': ts, 'msg': item})
            p['activity_log'] = log[:50]
            imported['activity_log'] = len(done_items)

        # State → description
        state_items = sections.get('state', [])
        if state_items:
            p['description'] = '\n'.join(state_items)
            imported['description'] = True

        # Next → backlog + next_action
        next_items = sections.get('next', [])
        if next_items:
            p['next_action'] = next_items[0]
            backlog = p.setdefault('backlog', [])
            existing_texts = {i['text'] for i in backlog}
            added = 0
            for item in next_items:
                if item not in existing_texts:
                    backlog.insert(0, {
                        'id': str(uuid.uuid4())[:8],
                        'text': item,
                        'priority': 'normal',
                        'status': 'open',
                        'created_at': now_iso(),
                        'done_at': None,
                        'source': 'changelog',
                        'attachments': [],
                    })
                    added += 1
            imported['backlog'] = added

        # Title → current_task if present
        if title and not p.get('current_task'):
            p['current_task'] = title
            imported['current_task'] = True

    p['last_updated'] = now_iso()
    save_project(project_id, p)
    return jsonify({'ok': True, 'imported': imported})


# ── Agent image upload ────────────────────────────────────────────────────────

@app.route('/api/agent/upload-image', methods=['POST'])
def agent_upload_image():
    """Save a pasted image and return its absolute path for agent consumption."""
    if 'file' not in request.files:
        return jsonify({'error': 'no file'}), 400
    f = request.files['file']
    if not f.filename:
        return jsonify({'error': 'empty filename'}), 400
    ext = Path(f.filename).suffix.lower() or '.png'
    stored_name = f'agent_{uuid.uuid4().hex[:10]}{ext}'
    dest = UPLOADS_DIR / stored_name
    f.save(str(dest))
    return jsonify({'ok': True, 'path': str(dest.resolve())})


# ── Agent endpoints ──────────────────────────────────────────────────────────

def _build_agent_context(project):
    """Build system prompt context for the agent."""
    parts = []
    parts.append(f"You are working on {project.get('name', project['id'])}.")
    pp = project.get('project_path', '')
    if pp:
        parts.append(f"Project root: {pp}")

    # Load rules
    if pp:
        agent_rules_path = Path(pp) / 'AGENT_RULES.md'
        if agent_rules_path.exists():
            parts.append(f"--- AGENT_RULES.md ---\n{agent_rules_path.read_text(encoding='utf-8')}")
    if SHARED_RULES_PATH.exists():
        parts.append(f"--- SHARED_RULES.md ---\n{SHARED_RULES_PATH.read_text(encoding='utf-8')}")

    # Recent activity
    log = project.get('activity_log', [])[:5]
    if log:
        lines = [f"  - {e.get('ts','')}: {e.get('msg','')}" for e in log]
        parts.append("Recent activity:\n" + "\n".join(lines))

    # Recent agent sessions (for continuity if prior conversation hung)
    agent_log = _load_agent_log(project['id'])[:5]
    if agent_log:
        sess_lines = []
        for e in agent_log:
            csid = e.get('claude_session_id', '')
            sid_part = f" | claude -r {csid}" if csid else ''
            sess_lines.append(f"  - [{e.get('status','')}] {e.get('task','')[:80]}{sid_part}")
        parts.append("Recent agent sessions (use 'claude -r <id>' to resume a prior conversation):\n" + "\n".join(sess_lines))

    ct = project.get('current_task', '')
    if ct:
        parts.append(f"Current task: {ct}")

    return "\n\n".join(parts)


def _format_tool_activity(name, inp):
    """Format a tool_use block into a compact activity line."""
    if name in ('Read', 'Edit', 'Write'):
        fp = inp.get('file_path', '')
        short = Path(fp).name if fp else '?'
        return f'[tool: {name}] {short}'
    elif name == 'Bash':
        cmd = (inp.get('command', '') or inp.get('description', '') or '')[:80]
        return f'[tool: Bash] {cmd}'
    elif name in ('Grep', 'Glob'):
        pat = inp.get('pattern', '')
        return f'[tool: {name}] {pat}'
    elif name == 'Task':
        desc = (inp.get('description', '') or '')[:50]
        return f'[tool: Task] {desc}'
    elif name == 'WebSearch':
        q = (inp.get('query', '') or '')[:60]
        return f'[tool: WebSearch] {q}'
    else:
        return f'[tool: {name}]'


def _read_agent_stream(proc, session):
    """Reader thread: captures stdout lines into session log_lines."""
    # Snapshot the proc we were launched with so we can detect if a follow-up
    # replaced us with a newer process while we were still draining stdout.
    my_proc = proc
    try:
        for raw_line in proc.stdout:
            # If session proc changed, a follow-up superseded us — stop writing.
            if session.get('proc') is not my_proc:
                break
            line = raw_line.rstrip('\n\r')
            if not line:
                continue
            # Try to parse stream-json output
            try:
                msg = json.loads(line)
                msg_type = msg.get('type', '')
                # Capture Claude CLI session UUID from init or result messages
                if 'session_id' in msg:
                    session['claude_session_id'] = msg['session_id']
                if msg_type == 'assistant' and 'message' in msg:
                    for block in msg['message'].get('content', []):
                        if block.get('type') == 'text':
                            session['log_lines'].append(block['text'])
                        elif block.get('type') == 'tool_use':
                            tool_name = block.get('name', '')
                            tool_input = block.get('input', {})
                            activity = _format_tool_activity(tool_name, tool_input)
                            session['log_lines'].append(activity)
                            # Track .md file edits for plan file detection
                            if tool_name in ('Write', 'Edit'):
                                fp = tool_input.get('file_path', '')
                                if fp.lower().endswith('.md'):
                                    session['_last_md_file'] = fp
                            elif tool_name == 'ExitPlanMode' and session.get('_last_md_file'):
                                session['plan_file'] = session['_last_md_file']
                elif msg_type == 'result':
                    # Capture session_id from result as fallback
                    if 'session_id' in msg:
                        session['claude_session_id'] = msg['session_id']
            except json.JSONDecodeError:
                session['log_lines'].append(line)
    except Exception as e:
        # Only log stream errors if we're still the active reader
        if session.get('proc') is my_proc:
            session['log_lines'].append(f"[stream error: {e}]")
    finally:
        rc = proc.wait()
        # Only update session status if we're still the active reader.
        # If a follow-up replaced us, the new reader owns status updates.
        if session.get('proc') is my_proc:
            if session['status'] == 'running':
                session['status'] = 'completed' if rc == 0 else 'error'
                if rc != 0:
                    session['log_lines'].append(f"[exited with code {rc}]")
            _log_agent_completion(session)

            # Auto-dispatch pending follow-ups
            pending = session.get('pending_followups', [])
            if pending:
                session['_dispatching_followup'] = True
                followup_msg = pending.pop(0)
                _auto_dispatch_followup(session, followup_msg)
                session.pop('_dispatching_followup', None)


def _log_agent_activity(project_id, msg):
    """Add an entry to the project's activity_log."""
    p = load_project(project_id)
    if not p:
        return
    log = p.setdefault('activity_log', [])
    log.insert(0, {'ts': now_iso(), 'msg': msg})
    p['activity_log'] = log[:20]
    p['last_updated'] = now_iso()
    save_project(project_id, p)


def _load_agent_log(project_id):
    """Load the agent summary log for a project."""
    filepath = DATA_DIR / f'{project_id}_agent_log.json'
    if not filepath.exists():
        return []
    try:
        return json.loads(filepath.read_text(encoding='utf-8'))
    except Exception:
        return []


def _save_agent_log(project_id, log):
    filepath = DATA_DIR / f'{project_id}_agent_log.json'
    filepath.write_text(json.dumps(log, indent=2, ensure_ascii=False), encoding='utf-8')


def _log_agent_completion(session):
    """Save a summary entry when an agent session finishes."""
    project_id = session.get('project_id')
    if not project_id:
        return
    # Take the last non-empty text block as the summary
    lines = session.get('log_lines', [])
    # Find the last substantial text (skip tool/status markers)
    summary = ''
    for line in reversed(lines):
        if line and not line.startswith('[') and not line.startswith('\n---'):
            summary = line
            break
    if not summary and lines:
        summary = lines[-1]

    entry = {
        'ts': now_iso(),
        'task': session.get('task', ''),
        'status': session.get('status', 'unknown'),
        'summary': summary[:2000],
        'session_id': session.get('session_id', ''),
        'claude_session_id': session.get('claude_session_id', ''),
        'started_at': session.get('started_at', ''),
    }
    log = _load_agent_log(project_id)
    log.insert(0, entry)
    _save_agent_log(project_id, log)


def _auto_dispatch_followup(session, message):
    """Auto-dispatch a queued follow-up after the current task completes."""
    project_id = session.get('project_id')
    p = load_project(project_id)
    if not p:
        session['log_lines'].append('[follow-up skipped: project not found]')
        return
    pp = p.get('project_path', '')
    if not pp or not Path(pp).is_dir():
        session['log_lines'].append('[follow-up skipped: project path invalid]')
        return

    claude_sid = session.get('claude_session_id')
    if claude_sid:
        resume_flags = ['-r', claude_sid]
    else:
        resume_flags = ['--continue']

    cmd = [
        'claude', *resume_flags, '-p', message,
        '--print', '--verbose', '--output-format', 'stream-json',
        '--dangerously-skip-permissions',
    ]

    try:
        proc = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            cwd=pp,
            text=True,
            encoding='utf-8',
            errors='replace',
        )
    except Exception as e:
        session['log_lines'].append(f'[follow-up failed: {e}]')
        return

    session['proc'] = proc
    session['status'] = 'running'
    session['log_lines'].append(f"> Ron: {message}")

    t = threading.Thread(target=_read_agent_stream, args=(proc, session), daemon=True)
    t.start()


@app.route('/api/project/<project_id>/agent/dispatch', methods=['POST'])
def agent_dispatch(project_id):
    p = load_project(project_id)
    if not p:
        return jsonify({'error': 'project not found'}), 404

    pp = p.get('project_path', '')
    if not pp or not Path(pp).is_dir():
        return jsonify({'error': 'project_path not set or invalid'}), 400

    data = request.get_json() or {}
    task = data.get('task', '').strip()
    if not task:
        return jsonify({'error': 'task required'}), 400

    resume_id = data.get('resume_conversation_id', '').strip()

    with agent_lock:
        session_id = uuid.uuid4().hex[:12]

        if resume_id:
            cmd = [
                'claude', '-r', resume_id, '-p', task,
                '--print', '--verbose', '--output-format', 'stream-json',
                '--dangerously-skip-permissions',
            ]
        else:
            context = _build_agent_context(p)
            cmd = [
                'claude', '-p', task,
                '--print', '--verbose', '--output-format', 'stream-json',
                '--dangerously-skip-permissions',
                '--append-system-prompt', context,
            ]

        proc = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            cwd=pp,
            text=True,
            encoding='utf-8',
            errors='replace',
        )

        session = {
            'proc': proc,
            'status': 'running',
            'task': task,
            'log_lines': [],
            'started_at': now_iso(),
            'session_id': session_id,
            'project_id': project_id,
        }
        agent_sessions[session_id] = session

        t = threading.Thread(target=_read_agent_stream, args=(proc, session), daemon=True)
        t.start()

    _log_agent_activity(project_id, f"Agent dispatched: {task[:100]}")
    return jsonify({'ok': True, 'session_id': session_id})


@app.route('/api/project/<project_id>/agent/stream')
def agent_stream(project_id):
    """SSE endpoint streaming agent output for a specific session."""
    session_id = request.args.get('session', '')

    def generate():
        session = agent_sessions.get(session_id)
        if not session or session['project_id'] != project_id:
            yield f"data: {json.dumps({'type': 'error', 'msg': 'no active session'})}\n\n"
            return

        sent = 0
        tick = 0
        while True:
            lines = session['log_lines']
            if sent < len(lines):
                for line in lines[sent:]:
                    yield f"data: {json.dumps({'type': 'output', 'text': line})}\n\n"
                sent = len(lines)

            if session['status'] != 'running':
                # Don't close if follow-ups are pending or being dispatched
                if not session.get('pending_followups') and not session.get('_dispatching_followup'):
                    yield f"data: {json.dumps({'type': 'status', 'status': session['status']})}\n\n"
                    break
                # Else: wait for follow-up auto-dispatch to restart the session

            # Heartbeat every ~15s to keep connection alive
            tick += 1
            if tick % 50 == 0:
                yield ": heartbeat\n\n"

            _time.sleep(0.3)

    return Response(generate(), mimetype='text/event-stream',
                    headers={'Cache-Control': 'no-cache', 'X-Accel-Buffering': 'no'})


@app.route('/api/project/<project_id>/agent/followup', methods=['POST'])
def agent_followup(project_id):
    p = load_project(project_id)
    if not p:
        return jsonify({'error': 'project not found'}), 404

    pp = p.get('project_path', '')
    if not pp or not Path(pp).is_dir():
        return jsonify({'error': 'project_path not set'}), 400

    data = request.get_json() or {}
    message = data.get('message', '').strip()
    session_id = data.get('session_id', '')
    if not message:
        return jsonify({'error': 'message required'}), 400
    if not session_id:
        return jsonify({'error': 'session_id required'}), 400

    with agent_lock:
        existing = agent_sessions.get(session_id)
        if not existing or existing['project_id'] != project_id:
            return jsonify({'error': 'session not found'}), 404

        # If agent is still running, queue the follow-up instead of killing
        if existing['status'] == 'running':
            pending = existing.setdefault('pending_followups', [])
            pending.append(message)
            existing['log_lines'].append(f"> [queued] Ron: {message}")
            _log_agent_activity(project_id, f"Agent follow-up queued: {message[:100]}")
            return jsonify({'ok': True, 'queued': True, 'session_id': session_id})

        # Agent is not running — send follow-up immediately via resume
        claude_sid = existing.get('claude_session_id')
        if claude_sid:
            resume_flags = ['-r', claude_sid]
        else:
            resume_flags = ['--continue']

        cmd = [
            'claude', *resume_flags, '-p', message,
            '--print', '--verbose', '--output-format', 'stream-json',
            '--dangerously-skip-permissions',
        ]

        proc = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            cwd=pp,
            text=True,
            encoding='utf-8',
            errors='replace',
        )

        existing['proc'] = proc
        existing['status'] = 'running'
        existing['log_lines'].append(f"\n> Ron: {message}\n")

        t = threading.Thread(target=_read_agent_stream, args=(proc, existing), daemon=True)
        t.start()

    _log_agent_activity(project_id, f"Agent follow-up: {message[:100]}")
    return jsonify({'ok': True, 'session_id': session_id})


@app.route('/api/project/<project_id>/agent/stop', methods=['POST'])
def agent_stop(project_id):
    data = request.get_json() or {}
    session_id = data.get('session_id', '')
    if not session_id:
        return jsonify({'error': 'session_id required'}), 400

    with agent_lock:
        session = agent_sessions.get(session_id)
        if not session or session['project_id'] != project_id:
            return jsonify({'error': 'session not found'}), 404
        if session['status'] != 'running':
            return jsonify({'error': 'agent not running'}), 400
        proc = session['proc']
        try:
            proc.kill()
        except Exception:
            pass
        session['status'] = 'stopped'
        session['log_lines'].append('[Agent stopped by user]')

    # Wait outside lock so reader thread can update session
    try:
        proc.wait(timeout=5)
    except Exception:
        pass

    _log_agent_activity(project_id, "Agent stopped by user")
    return jsonify({'ok': True})


@app.route('/api/project/<project_id>/agent/session', methods=['DELETE', 'POST'])
def agent_session_delete(project_id):
    """Kill process (if running), wait for exit, and remove session entirely.
    Accepts POST in addition to DELETE for navigator.sendBeacon compatibility."""
    data = request.get_json(force=True, silent=True) or {}
    session_id = data.get('session_id', '')
    if not session_id:
        return jsonify({'error': 'session_id required'}), 400

    proc = None
    with agent_lock:
        session = agent_sessions.get(session_id)
        if not session or session['project_id'] != project_id:
            return jsonify({'ok': True})  # Already gone — idempotent
        if session['status'] == 'running':
            proc = session['proc']
            try:
                proc.kill()
            except Exception:
                pass
            session['status'] = 'stopped'
            session['log_lines'].append('[Agent stopped — tab closed]')

    # Wait outside lock for process to fully exit
    if proc:
        try:
            proc.wait(timeout=5)
        except Exception:
            pass

    # Remove session from tracking
    with agent_lock:
        agent_sessions.pop(session_id, None)

    return jsonify({'ok': True})


@app.route('/api/project/<project_id>/agent/plan-file')
def agent_plan_file(project_id):
    """Read and return the plan .md file content for a session."""
    session_id = request.args.get('session', '')
    session = agent_sessions.get(session_id)
    if not session or session['project_id'] != project_id:
        return jsonify({'error': 'session not found'}), 404
    plan_path = session.get('plan_file', '')
    if not plan_path:
        return jsonify({'error': 'no plan file'}), 404
    p = Path(plan_path)
    if not p.is_file():
        return jsonify({'error': 'file not found'}), 404
    try:
        content = p.read_text(encoding='utf-8')
    except Exception as e:
        return jsonify({'error': str(e)}), 500
    return jsonify({'path': str(p), 'filename': p.name, 'content': content})


@app.route('/api/project/<project_id>/agent/status')
def agent_status(project_id):
    sessions = []
    for sid, s in agent_sessions.items():
        if s['project_id'] == project_id:
            sessions.append({
                'session_id': s['session_id'],
                'claude_session_id': s.get('claude_session_id', ''),
                'status': s['status'],
                'task': s['task'],
                'log_lines': s['log_lines'],
                'started_at': s['started_at'],
                'plan_file': s.get('plan_file', ''),
            })
    # Sort: running first, then newest first (ISO timestamps sort lexically)
    sessions.sort(key=lambda s: (
        0 if s['status'] == 'running' else 1,
        '~' if not s.get('started_at') else s['started_at']
    ), reverse=False)
    # Within each group, newest first
    sessions.sort(key=lambda s: s.get('started_at', ''), reverse=True)
    sessions.sort(key=lambda s: 0 if s['status'] == 'running' else 1)
    return jsonify({'sessions': sessions})


# ── Agent log endpoint ────────────────────────────────────────────────────────

@app.route('/api/project/<project_id>/agent/log')
def get_agent_log(project_id):
    log = _load_agent_log(project_id)
    for entry in log:
        entry['ts_relative'] = time_ago(entry.get('ts'))
        entry['started_relative'] = time_ago(entry.get('started_at'))
    return jsonify(log)


# ── Rules endpoints ─────────────────────────────────────────────────────────

def _validate_project_path(pp):
    """Ensure path is under PROJECTS_BASE to prevent traversal."""
    try:
        resolved = Path(pp).resolve()
        return resolved.is_relative_to(PROJECTS_BASE.resolve())
    except Exception:
        return False


@app.route('/api/project/<project_id>/rules')
def get_rules(project_id):
    p = load_project(project_id)
    if not p:
        return jsonify({'error': 'project not found'}), 404

    agent_rules = ''
    pp = p.get('project_path', '')
    if pp and _validate_project_path(pp):
        agent_path = Path(pp) / 'AGENT_RULES.md'
        if agent_path.exists():
            agent_rules = agent_path.read_text(encoding='utf-8')

    shared_rules = ''
    if SHARED_RULES_PATH.exists():
        shared_rules = SHARED_RULES_PATH.read_text(encoding='utf-8')

    return jsonify({'agent_rules': agent_rules, 'shared_rules': shared_rules})


@app.route('/api/project/<project_id>/rules', methods=['PUT'])
def save_rules(project_id):
    p = load_project(project_id)
    if not p:
        return jsonify({'error': 'project not found'}), 404

    pp = p.get('project_path', '')
    if not pp or not _validate_project_path(pp):
        return jsonify({'error': 'project_path not set or invalid'}), 400

    data = request.get_json() or {}
    agent_rules = data.get('agent_rules')
    if agent_rules is None:
        return jsonify({'error': 'agent_rules required'}), 400

    agent_path = Path(pp) / 'AGENT_RULES.md'
    agent_path.write_text(agent_rules, encoding='utf-8')
    return jsonify({'ok': True})


@app.route('/api/rules/shared')
def get_shared_rules():
    content = ''
    if SHARED_RULES_PATH.exists():
        content = SHARED_RULES_PATH.read_text(encoding='utf-8')
    return jsonify({'shared_rules': content})


@app.route('/api/rules/shared', methods=['PUT'])
def save_shared_rules():
    data = request.get_json() or {}
    content = data.get('shared_rules')
    if content is None:
        return jsonify({'error': 'shared_rules required'}), 400

    SHARED_RULES_PATH.parent.mkdir(parents=True, exist_ok=True)
    SHARED_RULES_PATH.write_text(content, encoding='utf-8')
    return jsonify({'ok': True})


# ── Project order ────────────────────────────────────────────────────────────

@app.route('/api/projects/order', methods=['POST', 'OPTIONS'])
def save_project_order():
    if request.method == 'OPTIONS':
        return '', 204
    data = request.get_json()
    if not data or 'order' not in data:
        return jsonify({'error': 'order array required'}), 400
    order = data['order']
    for i, project_id in enumerate(order):
        p = load_project(project_id)
        if p:
            p['display_order'] = i
            save_project(project_id, p)
    return jsonify({'ok': True})


# ── Static ───────────────────────────────────────────────────────────────────

@app.route('/')
def index():
    return send_from_directory(STATIC_DIR, 'index.html')


if __name__ == '__main__':
    print(f"Mission Control running at http://localhost:{PORT}")
    app.run(host='0.0.0.0', port=PORT, debug=False)
