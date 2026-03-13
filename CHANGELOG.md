# Mission Control — Changelog

## [2026-03-13] — Open-source release preparation

### Done
- Replaced hardcoded user paths (`C:\Users\levir\...`) with `config.json` configuration system
- `config.json` auto-created on first run with sensible defaults (gitignored)
- Server port configurable via `config.json` or `MC_PORT` environment variable (default 5199)
- Set Flask `debug=False` for production
- Removed test injection function (`injectTestPlan`)
- Deleted personal/temporary files (helper scripts, session context, zip artifacts)
- Created `.gitignore`, `requirements.txt`, `LICENSE` (MIT), comprehensive `README.md`
- Created installer scripts: `install.bat` (Windows) and `install.sh` (macOS/Linux)
- Created launcher scripts: `start.bat` (Windows) and `start.sh` (macOS/Linux)
- Installers check prerequisites (Python, pip, Claude CLI), install dependencies, create data dirs
- Added `.gitkeep` files for `data/projects/` and `data/uploads/` directories

### Files Changed
- server.py: Replaced hardcoded `SHARED_RULES_PATH` and `PROJECTS_BASE` with config.json loader; port from config/env; `debug=False`
- static/index.html: Removed `injectTestPlan()` test function

### Files Added
- `.gitignore`, `requirements.txt`, `LICENSE`, `README.md`
- `install.bat`, `install.sh`, `start.bat`, `start.sh`
- `data/projects/.gitkeep`, `data/uploads/.gitkeep`

### Files Removed
- `fix_feed.py`, `patch_attachments.py`, `files.zip`, `frve.json`
- `patch_err.txt`, `patch_out.txt`, `.claude_session_context.md`, `SHARED_RULES_SNIPPET.md`

---

## [2026-03-13 16:30 ET] — Tab search/filter field

### Done
- Search input in the tab bar (right-aligned) for Backlog, Agent Log, and Activity tabs
- Live filtering on keystroke — hides non-matching items via DOM (no re-render)
- Searches backlog item text, agent log task+summary, activity log messages
- Per-project state persists across tab switches and auto-refreshes
- Clear (X) button appears when query is active
- Hidden on Agent tab (agent output is better served by different UX)

### How it works
- `modalSearchQuery[projectId]` stores the filter string per project
- `applyTabFilter()` reads query + active tab, shows/hides matching DOM elements
- Filter reapplied at end of `refreshModalById()` so it survives periodic re-renders
- Input focus and value preserved via extended textarea save/restore in refresh cycle

### Files Changed
- static/index.html: CSS `.modal-tab-search`, search input in tab bar template, `applyTabFilter()` / `clearTabSearch()` / `findModalIdForProject()` functions, `refreshModalById()` filter reapplication + input preservation

---

## [2026-03-13 16:15 ET] — Fix agent session hang on server restart

### Problem
When `server.py` was edited (triggering Flask's debug auto-reloader), the server process restarted and wiped all in-memory `agent_sessions`. Running agent sessions in the browser UI would freeze in a permanent "running" state because:
1. SSE connection broke → frontend retried indefinitely with no cap
2. Polling fallback silently skipped sessions not found on the server (`if (!ss) continue`)
3. No code path transitioned "running" → error when the server lost the session

### Fixes
- **Polling fallback** — when a session the frontend thinks is "running" is missing from the server entirely, mark it as `error` and refresh the UI (instead of silently skipping)
- **SSE reconnect retry cap** — max 3 retries with increasing delay (2s, 4s, 6s); after that, mark the session as errored and stop retrying
- **Retry counter cleanup** — `sseRetryCount[sessionId]` resets on successful data, and is deleted on normal completion or error

### Files Changed
- static/index.html: polling fallback (setInterval block), `connectAgentStream()` es.onerror/onmessage handlers, new `sseRetryCount` state variable

---

## [2026-03-13 16:00 ET] — Continue session from Agent Log

### Done
- "Continue" button on each Agent Log entry (when claude_session_id exists)
- Clicking expands an inline textarea to type a follow-up message
- Dispatches a new agent session that resumes the old conversation via `claude -r <id>`
- Automatically switches to Agent tab to show the running session
- Ctrl+Enter shortcut to send from the textarea

### How it works
- Backend `agent_dispatch()` accepts optional `resume_conversation_id` in POST body
- When present, builds `claude -r <id> -p <message>` instead of `claude -p <task>` (skips `--append-system-prompt` since resumed conversation already has context)
- Frontend `dispatchContinue()` mirrors `dispatchAgent()` but passes `resume_conversation_id` and switches tab

### Files Changed
- server.py: `agent_dispatch()` — read `resume_conversation_id`, conditional cmd build
- static/index.html: CSS for `.agent-log-continue-btn` and `.agent-log-continue-input`, updated `agentLogPanelHTML()` entries, new `toggleContinueInput()` and `dispatchContinue()` functions

---

## [2026-03-13 14:30 ET] — Plan file viewer button

### Done
- When an agent edits a `.md` file and then calls `ExitPlanMode`, a purple button with the filename appears in the agent status row
- Clicking the button opens the actual plan file content in a dedicated viewer modal (reads the `.md` file from disk)
- Separate from the "Pop Out" button which still shows the full conversation
- Button persists across page refreshes (plan_file stored in session status)

### How it works
- Server tracks the last `.md` file touched by Write/Edit tool calls during agent stream
- When `ExitPlanMode` is called, the tracked file path is stored as `plan_file` on the session
- New endpoint `GET /api/project/{pid}/agent/plan-file?session={sid}` reads and returns the file content
- Frontend detects the plan file both on live SSE (fetches status after ExitPlanMode) and on re-render (from cached status)

### Files Changed
- server.py: Track `.md` edits in `_read_agent_stream()`, new `/agent/plan-file` endpoint, `plan_file` in status response
- static/index.html: `openPlanFileViewer()` function, `.btn-plan-file` CSS, plan file button in status row, live detection on ExitPlanMode

---

## [2026-03-13 10:39 ET] — Ctrl+Scroll zoom on agent output

### Done
- Ctrl+Scroll over agent chat output areas zooms text in/out (8px–24px range, default 12px)
- Applies to both `.agent-output` and `.ac-session-output` elements
- Zoom level is per-modal — each window maintains its own independent zoom
- Zoom persists through content refreshes (SSE updates, tab switches, etc.)

### Files Changed
- static/index.html: Added `modalZoomLevels` state (per-modal), `wheel` event listener on `#modal-layer` with Ctrl detection, zoom reapply in `refreshModalById()`

---

## [2026-03-12 15:00 ET] — Plan Viewer window

### Done
- Agent plan output is now hidden from the chat window — replaced by a purple **"Show Plan"** button
- Clicking the button opens a dedicated **Plan Viewer** modal (1000px wide, 85vh tall) for easier reading
- Detection: when `[tool: ExitPlanMode]` appears in the stream, all preceding non-tool text lines are identified as the plan and collapsed
- Plan viewer renders with full rich formatting: markdown headers, tables, code blocks, lists
- **"Pop Out"** button always visible in the agent panel status row — opens any session's output in the wider viewer
- Works on page refresh: static HTML builder also detects and collapses plan content
- Plan viewer is draggable, minimizable, resizable — follows the same modal system as project windows

### Files Changed
- static/index.html: Added `.plan-viewer-content`, `.plan-show-btn`, `.plan-hidden-block`, `.btn-popout` CSS; added `planViewerContent` state; modified `appendAgentLine()` to detect `[tool: ExitPlanMode]`; new `collapseIntoPlanButton()` function; modified static output builder in `agentPanelHTML()` for refresh-safe plan detection; new `openPlanViewer()` function; added Pop Out button to agent status row

---

## [2026-03-12 14:00 ET] — Tabbed modal layout + auto-size name input

### Done
- Modal sections now organized into 4 tabs: **Backlog**, **Agent**, **Agent Log**, **Activity**
- Tab bar sits between the header/summary and scrollable content area
- Header (name, status, domain, path, description) and summary (current task, next action) stay always visible above tabs
- Each tab gets full scroll area — no more scrolling past unrelated sections
- Agent Log tab lazy-loads completed sessions on first click
- Rules panel stays inside Agent tab (collapsible)
- Activity log expanded from 6 to 20 entries
- Project name input auto-sizes to fit text content (removed `flex: 1`)
- More drag area in header since name input no longer stretches full-width
- Backlog count badge shown in tab bar
- Modal structure changed from single scroll to flex column (fixed header + tab bar, scrollable body)

### Files Changed
- static/index.html: Added `modalActiveTab` state, `switchModalTab()`, `autoSizeNameInput()` functions; new CSS for `.modal-tab-bar`, `.modal-tab`, `.modal-tab-content`, `.modal-scroll-body`, `.name-measure`; restructured `modalContentHTML()` return template; `.modal-content` now flex column with `overflow: hidden`; `.modal-header` no longer sticky (not needed — it's in non-scrolling region); simplified `agentLogPanelHTML()` (removed collapsible wrapper); updated `refreshModalById()`, `minimizeModal()`, `restoreModal()` for new scroll container

---

## [2026-03-12 13:15 ET] — Proper HTML table rendering for pipe-delimited tables

### Done
- Pipe-delimited markdown tables (`| col | col |`) now render as actual HTML `<table>` elements with proper column alignment
- Header rows detected via separator lines (`|---|---|`) and styled with blue text + bold weight
- Box-drawing tables (Unicode `┌─┬─┐`) still render as pre-formatted blocks with colored borders
- Sticky modal header: project name, status, domain, path all stay pinned at top when scrolling modal content
- Modal header has distinct background (`#1e2230`) to visually separate from content
- Minimize/close buttons moved inside the sticky header
- User prompts with `\n` wrapping (follow-ups) now correctly match prompt styling via `trim()`
- Queued follow-up detection fixed (check order was shadowed by general `> ` match)
- Page refresh no longer kills running agent processes (removed `sendBeacon` kill in `beforeunload`)

### Files Changed
- static/index.html: Replaced `formatTableLine` pre-rendering with `buildPipeTable()` HTML table parser; added `isPipeTable()`, `isSeparatorLine()` helpers; updated all 4 render paths; new `.hl-table table/th/td` CSS; `.hl-table-pre` for box-drawing fallback; sticky `.modal-header`; controls moved inside header; `agentLineCls` uses `trim()` and reordered checks; removed `sendBeacon` kill from `beforeunload`

---

## [2026-03-12 12:35 ET] — Fix agent chat resize direction

### Done
- Moved resize handle from top edge to bottom edge of agent chat box
- Flipped drag direction so dragging down = expand, dragging up = shrink (matches visual result)

### Files Changed
- static/index.html: Changed `.agent-chat-resize` from `top: -4px` to `bottom: -4px`; flipped `dy` calculation in mousemove handler

---

## [2026-03-12 12:30 ET] — ASCII table rendering in agent chat

### Done
- ASCII tables (pipe-delimited and Unicode box-drawing) now render in a styled block with preserved alignment
- Consecutive table lines are grouped into a single `<div class="hl-table">` with `white-space: pre` and `overflow-x: auto`
- Blank lines between table rows stay inside the table block instead of breaking it apart
- Pipes colored blue, border characters in slate gray for visual clarity
- Table lines skip `formatAgentText()` regex to prevent corruption (e.g., `-` as bullet, `*` as bold)
- Applied to all 4 render paths: modal live stream, console live stream, modal batch, console batch
- Added `overflow-x: hidden` and `min-width: 0` on `.agent-output` so wide tables scroll within their own `.hl-table` block instead of clipping
- Added `max-width: 100%` on `.hl-table` to constrain to parent and show horizontal scrollbar

### Files Changed
- static/index.html: Added `.hl-table` CSS for both `.agent-output` and `.ac-session-output`; added `isTableLine()` and `formatTableLine()` functions; updated `appendAgentLine()`, `updateConsoleOutput()`, and both batch renderers to group table lines; added overflow containment on `.agent-output`

---

## [2026-03-12 11:15 ET] — Resizable agent chat panel

### Done
- Agent chat area (`.agent-chat`) now has a draggable resize handle at its bottom edge
- Drag downward to expand, upward to shrink (min 120px, max 80vh)
- Handle shows a subtle bar indicator that highlights blue on hover

### Files Changed
- static/index.html: Changed `.agent-chat` from `max-height: 450px` to `height: 450px` with `min-height`/`max-height`; added `.agent-chat-resize` handle element + CSS; added `chatResize` mousedown/mousemove/mouseup logic

---

## [2026-03-12 11:00 ET] — Multi-modal windows with minimize

### Done
- Converted single-overlay modal to floating window manager: multiple project modals can be open simultaneously
- Each modal top bar now has minimize (horizontal bar) + close (X) buttons
- Minimize collapses modal to a chip in a bottom tray; click chip to restore, chip X to close
- Focus management: clicking a modal brings it to front (accent border), ESC closes only the focused modal
- Modals cascade-offset (+30px) when opened so they don't stack directly on top of each other
- Grid remains visible and scrollable underneath open modals (no blocking overlay)
- Drag-to-move and resize preserved per-modal
- Shared Rules editor and New Project form also participate in the multi-modal system
- All existing features preserved: agent panels, editable fields, textarea value preservation across refresh

### Files Changed
- static/index.html: Replaced `.modal-overlay` with `.modal-layer` + `.modal-window` system; added `.minimized-tray` and `.minimized-chip` CSS; new state (`openModals` Map, `focusedModalId`, `nextModalZ`); new functions (`openProjectModal`, `closeModalById`, `minimizeModal`, `restoreModal`, `focusModal`, `refreshModalById`, `centerModalElement`); updated drag handler for multi-modal delegation; converted `openSharedRulesEditor` and `openNewProjectForm`

---

## [2026-03-11 20:30 ET] — Agent log: Claude session ID tracking

### Done
- Capture real Claude CLI session UUID from stream-json `init`/`result` messages
- Persist `claude_session_id` in agent log entries and agent status API
- Display session ID in agent log UI with `claude -r <uuid>` hint and copy button
- Feed last 5 agent sessions (with resume IDs) into agent context prompt for continuity

### Files Changed
- server.py: `_read_agent_stream` (capture UUID), `_log_agent_completion` (persist), `agent_status` (expose), `_build_agent_context` (include in prompt)
- static/index.html: CSS for `.agent-log-session-id`, agent log entry template updated

---

## [2026-03-11 20:20 ET] — Project changelog created

### Done
- Created CHANGELOG.md for Mission Control project

### State
- Mission Control is a Tauri v2 desktop app with a Flask (Python) backend on port 5199
- Single-page dashboard (static/index.html) with dark theme, Inter/JetBrains Mono fonts
- Backend features: project CRUD, backlog management, file attachments, agent dispatch via Claude CLI, SSE streaming, follow-up/stop, agent log, project import from CHANGELOG.md, rules editor (AGENT_RULES.md + SHARED_RULES.md), project reordering
- Data stored as JSON files in data/projects/, uploads in data/uploads/

### Next
- Multi-session agent tabs, agent log, image paste, project import (current task per system context)

### Files Changed
- CHANGELOG.md (created)
