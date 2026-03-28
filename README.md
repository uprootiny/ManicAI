# ManicAI

[![Build ManicAI macOS app](https://github.com/uprootiny/ManicAI/actions/workflows/build-macos.yml/badge.svg)](https://github.com/uprootiny/ManicAI/actions/workflows/build-macos.yml)

ManicAI is a macOS-native operator app for agent-heavy project orchestration. It provides a control plane for taming sprawling AI sessions -- too many tmux panes, too many agent loops, too many half-finished interventions -- and converts that noisy parallel activity into bounded, smoke-verified progress through live surface recon, mode-gated actions (Verify / Plan / Act), and DAW-style timeline replay.

---

## Get a working .app

### Option 1: Download a pre-built artifact (fastest)

1. Open the [latest CI run](https://github.com/uprootiny/ManicAI/actions/workflows/build-macos.yml) and pick a green build.
2. Scroll to **Artifacts** and download the one that matches your Mac:

   | Your Mac | Artifact to download |
   |----------|---------------------|
   | Apple Silicon (M1/M2/M3/M4), macOS 15+ | `ManicAI-dmg-tahoe-compat` |
   | Intel Mac, macOS 13+ | `ManicAI-dmg-intel-13_0` |
   | Intel Mac, macOS 10.11+ (El Capitan) | `ManicAI-dmg-legacy-10_11` |

3. Mount the `.dmg` and drag **ManicAI.app** (or **ManicAILegacy.app**) to `/Applications`.
4. On first launch, right-click the app and choose **Open** to bypass Gatekeeper (unsigned builds).

The [download page](https://uprootiny.github.io/ManicAI/download/) also lists the latest artifacts.

### Option 2: Build locally

```bash
# Prerequisites: Xcode 15+ and XcodeGen
brew install xcodegen

git clone https://github.com/uprootiny/ManicAI.git
cd ManicAI
xcodegen generate
open ManicAI.xcodeproj
# Cmd+R to build and run, or from the terminal:
xcodebuild -project ManicAI.xcodeproj -scheme ManicAI -configuration Release build
```

The `.app` bundle lands in `build/Build/Products/Release/ManicAI.app`.

---

## Features

- **Live surface recon** -- probes known hosts for `/api/state`, tmux dashboards, and API capabilities; surfaces session counts, takeover candidates, and smoke status at a glance.
- **Ops-mode gating (Verify / Plan / Act)** -- each mode gates which actions are allowed, preventing accidental writes during observation phases.
- **Cadence profiles** -- Stabilize (conservative, single-target), Throughput (fast, multi-target fan-out), and Deep Work (isolated single-session focus) each set their own refresh interval, cooldown, action delay, and scripted intervention steps.
- **Scope contracts** -- configurable objective, done-criteria, attention budget, max cycles, intent latch, and drift-freeze to keep agent loops bounded.
- **Circuit breakers** -- per-route and per-node-route breakers with configurable sample window, failure-rate trip threshold, and cooldown; automatic cadence back-off under pressure.
- **DAW-style timeline** -- every prompt, duplex exchange, ontology event, git op, file op, and service call is recorded as a `PromptEvent` and grouped into per-target `TimelineTracks` for scrubbing, range-selection, and replay.
- **Telemetry with exponential decay** -- per-route API call stats (success/failure/fluency) persisted with configurable half-life so stale data fades naturally.
- **Commutation planner** -- lane assignment (Primary / Secondary / Quarantine) by fluency and throughput, with autopilot vs. pane+smoke fallback routing.
- **Panic and degraded modes** -- automatic detection and UI surfacing when critical routes fail or interaction health drops.
- **Interaction health scoring** -- composite score with human-readable label and notes, recomputed on every refresh cycle.
- **Session profile export** -- snapshot layer counts, cadence stats, breaker state, and health to JSON or Markdown for post-session review.
- **Built-in project catalog** -- demo entries for hyle, coggy, hyperpanel, corpora, demesne, webdash, and ManicAI itself, each with spinup commands, diagnostics, smoke commands, and default prompts.
- **Recentering prompts** -- interrupt palette with live symptom auto-suggest to pull a drifting session back on track.
- **Legacy target** -- AppKit (Cocoa) fallback app targeting macOS 10.11+ with three-pane NSSplitView: prompt queue, pane liveness, and smoke output.

---

## Build requirements

| Tool | Version |
|------|---------|
| Xcode | 15+ (Swift 5.9) |
| XcodeGen | latest (`brew install xcodegen`) |
| macOS SDK | 13.0+ (main target), 10.11+ (legacy target) |

The project is defined in `project.yml` and the Xcode project is generated via `xcodegen generate`.

---

## Architecture

```
ManicAI/
  ManicAIApp.swift      App entry point. SwiftUI WindowGroup with hidden title bar.
  DashboardView.swift   Main UI -- surface recon, ops-mode selector (Verify/Plan/Act),
                        cadence profiles, pane liveness, timeline, telemetry panels.
  PanelClient.swift     @MainActor ObservableObject that drives all network state:
                        surface probes, API capabilities, circuit breakers, panic/degraded
                        modes, scope contracts, and interaction health scoring.
  Models.swift          Decodable data layer -- PanelState, PaneInfo, SurfaceProbe,
                        ScopeContract, BreakerState, PromptEvent, TimelineKind, etc.
  TimelineEngine.swift  Pure functions for sorting, grouping, and range-selecting
                        PromptEvents into per-target TimelineTracks (DAW-style replay).
  ControlSpecs.swift    Route catalog (/api/state, /api/autopilot/run, /api/smoke, ...)
                        and critical-route gating logic.
  TelemetryMemory.swift Exponential-decay persistence for per-route API call statistics.
  DemoCatalog.swift     Built-in project catalog (hyle, coggy, ...) with spinup commands,
                        diagnostics, smoke commands, and default prompts.

ManicAILegacy/
  main.swift            AppKit (Cocoa) fallback app targeting macOS 10.11+. Three-pane
                        NSSplitView with prompt queue, pane liveness, and smoke output.

ManicAITests/
  ControlSpecsTests.swift
  PanelStateDecodingTests.swift
  TimelineEngineTests.swift
```

---

## CI pipeline

The GitHub Actions workflow (`.github/workflows/build-macos.yml`) runs a **3-target matrix build** on every push to `main`/`master`, on pull requests, and on manual dispatch.

| Target ID | Runner | Deployment Target | Scheme | Tests | Notes |
|-----------|--------|-------------------|--------|-------|-------|
| `tahoe-compat` | `macos-15` | 15.0 | ManicAI | yes | Current macOS, Apple Silicon (arm64) |
| `intel-baseline` | `macos-15-intel` | 13.0 | ManicAI | yes | Intel (x86_64) compatibility baseline |
| `legacy-10-11` | `macos-15-intel` | 10.11 | ManicAILegacy | no | El Capitan fallback (AppKit, no SwiftUI) |

Each target produces three artifacts (retained 30 days):

- **DMG** -- compressed disk image (`ManicAI-<suffix>.dmg`)
- **ZIP** -- ditto-compressed app bundle (`ManicAI-<suffix>.zip`)
- **App bundle** -- raw `.app` directory

A pre-build step (`scripts/check_no_localhost.sh`) guards against shipping localhost endpoints in user-facing code.

### Triggering a build manually

Go to [Actions > Build ManicAI macOS app](https://github.com/uprootiny/ManicAI/actions/workflows/build-macos.yml), click **Run workflow**, and select your branch.

---

## Code signing and notarization

The CI pipeline supports optional Apple Developer signing and notarization. When the required secrets are configured, signed and notarized artifacts are uploaded alongside the unsigned ones.

### Required GitHub Actions secrets

| Secret | Description |
|--------|-------------|
| `APPLE_DEVELOPER_ID_APP_CERT_BASE64` | Base64-encoded `.p12` export of your "Developer ID Application" certificate and private key. |
| `APPLE_DEVELOPER_ID_APP_CERT_PASSWORD` | Password used when exporting the `.p12` file. |
| `APPLE_KEYCHAIN_PASSWORD` | Arbitrary password for the temporary CI keychain (can be any strong random string). |
| `APPLE_NOTARY_KEY_ID` | App Store Connect API key ID (from the Keys page in App Store Connect). |
| `APPLE_NOTARY_ISSUER_ID` | App Store Connect API issuer ID. |
| `APPLE_NOTARY_API_KEY_BASE64` | Base64-encoded `.p8` private key file from App Store Connect. |

### What happens when secrets are present

1. The Developer ID certificate is imported into a temporary keychain.
2. The app bundle is code-signed with `codesign --options runtime --timestamp`.
3. A signed DMG is submitted to `notarytool` and the ticket is stapled.
4. Separate `*-notarized` DMG and ZIP artifacts are uploaded.

### What happens without secrets

All builds complete successfully as unsigned. Users must right-click and choose **Open** on first launch to bypass Gatekeeper.

---

## API routes (control plane)

ManicAI talks to a backend control plane (e.g., hyperpanel). The route catalog:

| Route | Method | Critical | Purpose |
|-------|--------|----------|---------|
| `/api/state` | GET | yes | Fetch full panel state (sessions, panes, candidates, smoke, vibe) |
| `/api/autopilot/run` | POST | yes | Launch a bounded autopilot intervention |
| `/api/smoke` | POST | yes | Trigger smoke checks |
| `/api/queue/add` | POST | no | Enqueue a prompt |
| `/api/queue/run` | POST | no | Execute queued prompts |
| `/api/pane/send` | POST | no | Send keystrokes to a tmux pane |
| `/api/nudge` | POST | no | Nudge an idle session |
| `/api/spawn` | POST | no | Spawn a new agent session |
| `/api/snapshot/ingest` | POST | no | Ingest a session profile snapshot |

Critical routes must all be reachable for full functionality; the app degrades gracefully when non-critical routes are unavailable.

---

## Screenshots

No screenshots have been added yet. When available, place them at:

- `docs/screenshots/01-recon.png` -- live surface recon
- `docs/screenshots/02-candidates.png` -- takeover candidates and liveness
- `docs/screenshots/03-modes.png` -- Verify / Plan / Act mode gating
- `docs/screenshots/04-timeline.png` -- DAW-style timeline
- `docs/screenshots/05-recentering.png` -- recentering prompt palette

---

## Documentation

- Design: `docs/DESIGN_DOC.md`
- Critique: `docs/UX_ENGINEERING_CRITIQUE.md`
- Surface reality: `docs/SURFACE_REALITY.md`
- Recentering prompts: `docs/RECENTERING_PROMPTS.md`
- Control plane spec: `docs/CONTROL_PLANE_SPEC.md`
- Release page: `docs/release/GITHUB_RELEASE_PAGE.md`
- Deployment: `docs/release/DEPLOYMENT.md`
- Download page (GitHub Pages): `docs/download/index.html`

---

## License

See repository for license details.
