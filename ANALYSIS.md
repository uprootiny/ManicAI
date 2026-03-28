# ManicAI -- Deep Codebase Analysis

## 1. Architecture Overview

ManicAI is a **pure Swift/SwiftUI macOS application** (deployment target macOS 13.0+) that acts as an operator console for managing multiple AI agent sessions running on remote servers. It uses XcodeGen (`project.yml`) to generate the Xcode project. There is no server-side code in this repository -- the app is a pure client.

**Targets:**
- `ManicAI` -- main SwiftUI app (macOS 13+)
- `ManicAILegacy` -- AppKit-based legacy build (macOS 10.11+, limited functionality)
- `ManicAITests` -- unit tests

**Source files (ManicAI target):**
| File | Purpose | Lines |
|------|---------|-------|
| `ManicAIApp.swift` | App entry point, WindowGroup with DashboardView | 12 |
| `DashboardView.swift` | Entire UI -- header, 3-column layout, ~20 GlassCard panels | ~2170 |
| `PanelClient.swift` | All networking, state management, telemetry, scheduling | ~1565 |
| `Models.swift` | All data models (PanelState, PaneInfo, etc.) | ~324 |
| `ControlSpecs.swift` | Route definitions and ProjectRegistry | ~60 |
| `TimelineEngine.swift` | Timeline event processing, cadence stats, layer edges | ~117 |
| `TelemetryMemory.swift` | Telemetry decay model | ~33 |
| `DemoCatalog.swift` | Demo project definitions with server URLs | ~94 |

## 2. What the App Does

ManicAI is a **"Hyper Productivity Panel"** -- a control plane UI for managing autonomous coding agents running in tmux sessions on remote Linux servers. The core workflow is:

1. **Connect** to a remote "hyperpanel" control plane API
2. **Observe** active agent sessions (takeover candidates, pane liveness, throughput)
3. **Classify** blockers via read-only diagnosis
4. **Act** by sending autopilot prompts to agents, running smoke tests
5. **Verify** outcomes via delta summaries and smoke status

The app operates in three modes: **Verify** (read-only), **Plan** (diagnose), and **Act** (execute mutations).

## 3. Backend Dependency -- The Missing Piece

### What backend does ManicAI expect?

The app connects to a **"hyperpanel" HTTP API server** that is NOT part of this repository. The backend is expected to run on the fleet servers, specifically:

**Primary endpoint:** `http://173.212.203.211:8788` (hyle server)

**All endpoint presets hardcoded in `PanelClient.swift`:**
```
http://173.212.203.211:8788   (hyle, port 8788)
http://173.212.203.211:8421   (coggy, port 8421)
http://hyle.hyperstitious.org:8788
http://hyle.hyperstitious.org:8421
http://hyperstitious.art:8788
http://hyperstitious.art:8421
http://149.102.153.201:8788
http://149.102.153.201:8421
http://173.212.203.211:9801
http://173.212.203.211:9750
```

The backend is part of the **hyle** project (`cargo run --bin hyle`), specifically its `make hyperpanel` target. The DemoCatalog confirms this: the hyperpanel backend lives at `/home/uprootiny/dec27/hyle` on the server and is started with `make hyperpanel`.

### Required API Endpoints

The app expects 9 HTTP endpoints. Three are **critical** (app won't function without them):

| Method | Path | Critical | Purpose |
|--------|------|----------|---------|
| GET | `/api/state` | YES | Fetch full panel state (sessions, panes, takeover candidates, smoke status, vibe) |
| POST | `/api/autopilot/run` | YES | Send autopilot prompt to agent sessions |
| POST | `/api/smoke` | YES | Trigger smoke tests for a project |
| POST | `/api/queue/add` | no | Add prompt to queue |
| POST | `/api/queue/run` | no | Run queued prompts |
| POST | `/api/pane/send` | no | Send text to a tmux pane |
| POST | `/api/nudge` | no | Nudge a session with text |
| POST | `/api/spawn` | no | Spawn a new tmux session |
| POST | `/api/snapshot/ingest` | no | Ingest a text snapshot |

Additionally, the app probes:
- `GET /health` -- health check
- `GET /tmux` -- tmux web UI availability
- `GET /` (root) -- scans response HTML for route hints

### Expected `/api/state` Response Shape

```json
{
  "ts": 1234567890,
  "sessions": [{"raw": "session-name"}],
  "panes": [{
    "target": "coggy:0.0",
    "command": "claude",
    "liveness": "warm",
    "idle_sec": 12,
    "throughput_bps": 2.5,
    "auth_rituals": ["token"],
    "capture": "last lines of terminal output"
  }],
  "takeover_candidates": [/* same shape as panes */],
  "projects": [{"path": "/home/uprootiny/coggy", "branch": "main", "dirty_files": 3, "smoke": true}],
  "queue": [{"prompt": "fix blocker", "status": "pending"}],
  "smoke": {"status": "pass", "passes": 5, "fails": 0, "log": "..."},
  "vibe": {
    "pipeline_status": "available",
    "build_latency": "fast",
    "developer_state": "aligned"
  }
}
```

### Expected POST Request Shapes

**`/api/autopilot/run`:**
```json
{"prompt": "run smoke checks...", "project": "/path/to/project", "max_targets": 2, "auto_approve": true}
```

**`/api/smoke`:**
```json
{"project": "/path/to/project"}
```

**`/api/pane/send`:**
```json
{"target": "coggy:0.0", "text": "some command", "enter": true}
```

**`/api/nudge`:**
```json
{"session_id": "session-name", "text": "nudge text"}
```

**`/api/spawn`:**
```json
{"session_name": "agent-1234", "project": "/path", "command": "hyle --free"}
```

**`/api/queue/add`:**
```json
{"prompt": "task prompt", "project": "/path", "session_id": "session-name"}
```

**`/api/queue/run`:**
```json
{"project": "/path", "session_id": "session-name"}
```

**`/api/snapshot/ingest`:**
```json
{"name": "snapshot-name", "text": "captured text"}
```

## 4. Current State of the App

### What works (client-side):
- Full SwiftUI dashboard renders with dark glassmorphism theme
- Endpoint selection and preset picker
- Recon scan probes multiple endpoints and auto-selects best
- Mode switching (Verify/Plan/Act)
- Scope contract management (objective, done criteria, intent latch, attention budget)
- Commutation scheduler with lane management (Primary/Secondary/Quarantine)
- Circuit breakers with configurable trip conditions
- Panic mode (read-only containment)
- Telemetry memory with half-life decay persistence
- Timeline engine with DAW-style scrub/replay/range select
- Cadence profiles (Stabilize/Throughput/Deep Work)
- System profiles (LLM Duplex/Architected/Hybrid)
- Assistant stack templates (Hyle/Coggy/Coupled)
- Pattern library with preset configurations
- Recentering prompts (anti-drift, anti-hallucination, etc.)
- Performance inspector and high-pressure mode detection
- Session profile export (JSON + Markdown)
- Prompt history export (NDJSON + cadence report)
- GitHub project link inference
- Demo project catalog
- Unit tests for PanelState decoding, TimelineEngine, ControlSpecs
- CI/CD with GitHub Actions (multi-arch builds, notarization support)

### What does NOT work:
- **All API interactions fail** because the hyperpanel backend at `173.212.203.211:8788` is not running or not reachable
- Without `/api/state` responding, the app shows "pipeline: unknown", health 50, all sections empty
- Without `/api/autopilot/run` and `/api/smoke`, the app disables Plan and Act modes
- The "API VALIDATION" card shows "Missing critical: /api/state, /api/autopilot/run, /api/smoke"
- Takeover Targets shows "No targets match current filter" (no state loaded)
- Cycle Journal shows "(no cycle events)" (nothing has executed)
- Commutation Plan shows "(no preview yet)" (no candidates to plan against)

## 5. What Needs to Happen

### Option A: Start the existing backend (hyle hyperpanel)

The backend already exists in the `hyle` project (Rust). On the server at `173.212.203.211`:
```bash
cd /home/uprootiny/dec27/hyle && make hyperpanel
```
This should start an HTTP server on port 8788 that provides all the required endpoints. If this server is running and reachable, ManicAI will immediately become functional.

**Diagnosis needed:** SSH into hyle and check if the hyperpanel process is running:
```bash
ssh hyle 'ss -tlnp | grep 8788'
```

### Option B: Write a new backend server

If the hyle hyperpanel backend is lost or needs replacement, a new server must implement the 9 API endpoints listed above. Per user preferences, the backend should be written in **Swift, Rust, Clojure, Haskell, Elixir, or Erlang** (not Python or Node.js).

The backend would need to:
1. Run tmux sessions and capture their output
2. Enumerate tmux panes and their state (liveness, idle time, throughput)
3. Identify "takeover candidates" (panes running AI agents)
4. Execute autopilot prompts by sending text to tmux panes
5. Run smoke tests (project-specific `make smoke` or similar)
6. Manage a prompt queue
7. Track project state (git branch, dirty files)

**Recommended stack for the backend:** Elixir/Phoenix or Rust/Axum. Both are well-suited for this kind of tmux-orchestrating HTTP server.

### Option C: Embedded mock/demo mode

For local development and demos without a live server, ManicAI could be enhanced with an embedded demo mode that returns synthetic data. The `DemoCatalog.swift` already exists and could be extended to power a local mock server or in-process fake.

## 6. Configuration Fixes Available Now

### 6.1 No code changes needed for the base URL

The app already:
- Persists the selected endpoint in UserDefaults (`manicai.baseURL`)
- Has a preset picker with 10 endpoint options
- Has a "Recon Scan + Auto Select" button that probes all known endpoints
- Has a text field for entering custom URLs

The default `http://173.212.203.211:8788` is correct for the hyle server. No URL configuration changes are needed.

### 6.2 Local development fallback

The app blocks localhost/127.0.0.1 URLs unless the environment variable `MANICAI_ALLOW_LOCAL=1` is set (see `PanelClient.init()` and `isLoopbackHost()`). This is enforced both at URL setting time and during endpoint scanning. The `scripts/check_no_localhost.sh` CI guard ensures no localhost URLs leak into the demo catalog.

To develop locally, set `MANICAI_ALLOW_LOCAL=1` in the Xcode scheme's environment variables, or run from terminal with that env var.

## 7. Code Quality Assessment

### Strengths:
- Comprehensive feature set with thoughtful operational guardrails
- Resilient JSON decoding (all fields use `decodeIfPresent` with defaults)
- Circuit breaker pattern for API reliability
- Debounced persistence and recompute to avoid UI stalls
- High-pressure mode detection prevents runaway resource usage
- Clean separation: Models / Client / View / Engine

### Areas for improvement:
- `DashboardView.swift` is a 2170-line monolith. Should be decomposed into sub-views (AccessCard, AutopilotCard, TakeoverTargetsCard, etc.)
- `PanelClient.swift` at 1565 lines combines networking, state management, scheduling, telemetry, and persistence. Should be split into focused classes.
- No dependency injection -- `PanelClient` creates its own `URLSession`, making testing harder
- The `@StateObject private var client = PanelClient()` pattern in DashboardView means no way to inject a mock client for previews
- Some computed properties in DashboardView recalculate on every render (e.g., `sessionProfileLayers`, `materiaMetrics`)

### Build system:
- Uses XcodeGen with `project.yml` -- clean and reproducible
- CI matrix covers macOS 15 (ARM), macOS 15 Intel, and Legacy (10.11)
- Includes notarization pipeline (conditional on secrets)
- NSAppTransportSecurity allows arbitrary HTTP loads (required for plain HTTP to fleet servers)

## 8. Live Endpoint Status (tested 2026-03-27)

| Endpoint | Status | Notes |
|----------|--------|-------|
| `173.212.203.211:8788` (hyperpanel) | **DOWN** | Connection refused / no response. HTTP status 000. |
| `173.212.203.211:8421` (coggy) | **UP** | Returns coggy-format data (atoms/ontology), NOT hyperpanel format. ManicAI detects this as `stateKind: "coggy"` and shows limited data. |
| `173.212.203.211:9801` | **UP** | Running a server but returns 404 on `/api/state`. Not the hyperpanel. |
| `173.212.203.211:9750` | Not tested | |

**The hyperpanel backend (port 8788) is not running.** This is the root cause of all the "Missing critical" errors in ManicAI. The hyle process that serves the hyperpanel API needs to be started on the server.

The coggy endpoint (8421) IS alive, and ManicAI can partially connect to it -- the probe logic in `PanelClient.probe()` recognizes coggy responses by detecting `atoms` or `turn` keys in the JSON. However, coggy returns a fundamentally different data shape (ontology atoms) so most ManicAI features (takeover targets, smoke status, commutation plans) will show as empty.

## 9. Summary of Immediate Actions

| Priority | Action | Effort |
|----------|--------|--------|
| P0 | **Hyperpanel is down.** SSH into hyle and start it: `ssh hyle 'cd /home/uprootiny/dec27/hyle && make hyperpanel'` | 5 min |
| P0 | If hyle hyperpanel binary is missing/broken, diagnose: `ssh hyle 'ls -la /home/uprootiny/dec27/hyle/Makefile && grep hyperpanel /home/uprootiny/dec27/hyle/Makefile'` | 15 min |
| P1 | If hyle backend is lost, implement minimal control plane server in Elixir or Rust | 2-4 days |
| P1 | Add embedded demo/mock mode so ManicAI works without a live backend | 1 day |
| P2 | Decompose DashboardView.swift into sub-views | 1 day |
| P2 | Split PanelClient.swift into Client + Scheduler + Telemetry | 1 day |
| P3 | Add SwiftUI Previews with mock data | 0.5 day |
| P3 | Add keyboard shortcuts for top actions | 0.5 day |
