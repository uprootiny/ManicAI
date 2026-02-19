# ManicAI

ManicAI is a macOS control console for AI-session sprawl: too many panes, too many agent loops, too many half-finished interventions.

It is built for one outcome:
- convert noisy parallel activity into bounded, smoke-verified progress.

## The Common Failure

You open a project and see:
- 20+ tmux sessions
- several AI chats in different states
- mixed local/remote endpoints
- repeated prompts, stalled approval gates, unclear ownership

Without a control plane, this becomes:
- vibes instead of verification
- interventions without feedback loops
- big diffs and low confidence

## What ManicAI Does

ManicAI treats this as an operations problem, not a chat problem.

It gives you:
- live surface recon across known hosts
- state-aware takeover candidates and pane captures
- mode-gated actions (`Verify`, `Plan`, `Act`)
- bounded loops: classify -> intervene -> smoke -> delta
- timeline replay of prompt/service/git/file events
- recentering prompts for runaway agent behavior

## Concept -> Execution -> Concept -> Execution

### 1) Concept: Observe reality first
### 1) Execution:
- probe real hosts/ports (`8788`, `8421`, `9801`, `9750`)
- classify state schema (`hyperpanel` vs `coggy`)
- expose tmux dashboard reachability directly in UI

### 2) Concept: Bound interventions
### 2) Execution:
- explicit `Verify/Plan/Act` behavior
- preflight blocker reasons before actions fire
- panic/degraded controls stay visible and enforceable

### 3) Concept: Keep attention on the bug, not the fantasy
### 3) Execution:
- built-in recentering interrupt library
- auto-suggest prompt based on live capture symptoms
- enforce micro-loop discipline through operator flow

### 4) Concept: Prove progress
### 4) Execution:
- smoke-first control plane routes
- artifact/event timeline
- CI matrix builds with downloadable app artifacts

## A Typical Operator Flow

1. Run `Recon Scan + Auto Select`.
2. Confirm live surface (`state kind`, `tmux`, latency).
3. Pick mode:
   - `Verify` for diagnosis
   - `Plan` for bounded proposals
   - `Act` for guarded execution
4. Run one bounded cycle.
5. Inspect smoke delta and timeline artifacts.
6. Commit the smallest verified fix.

## The “Wow” Moment

The wow is not animation.

It is this:
- you walk into chaos
- within minutes, you know which surface is real, which loop is blocked, and which intervention is safe
- after one bounded cycle, the smoke output changes for the better

That is the product.

## Screenshots

Add release screenshots here and keep names stable:

- `docs/screenshots/01-recon.png` (live surface recon)
- `docs/screenshots/02-candidates.png` (takeover candidates + liveness)
- `docs/screenshots/03-modes.png` (`Verify/Plan/Act` + gating)
- `docs/screenshots/04-timeline.png` (DAW-like timeline)
- `docs/screenshots/05-recentering.png` (recentering prompt palette)

Then reference them:

![Surface Recon](docs/screenshots/01-recon.png)
![Takeover Candidates](docs/screenshots/02-candidates.png)
![Modes and Gating](docs/screenshots/03-modes.png)
![Timeline](docs/screenshots/04-timeline.png)
![Recentering Prompts](docs/screenshots/05-recentering.png)

## Install (macOS)

```bash
cd /path/to/ManicAI
brew install xcodegen
xcodegen generate
open ManicAI.xcodeproj
```

## Build Artifacts

Workflow:
- `.github/workflows/build-macos.yml`

Targets:
- `tahoe-compat` (`MACOSX_DEPLOYMENT_TARGET=15.0`)
- `intel-baseline` (`MACOSX_DEPLOYMENT_TARGET=13.0`)
- `legacy-10-11` (`ManicAILegacy`)

Download portal:
- `docs/download/index.html`
- intended domain: `manicai.hypersticial.art`

## Docs

- Design: `docs/DESIGN_DOC.md`
- Critique: `docs/UX_ENGINEERING_CRITIQUE.md`
- Surface reality: `docs/SURFACE_REALITY.md`
- Recentering prompts: `docs/RECENTERING_PROMPTS.md`
- Release page: `docs/release/GITHUB_RELEASE_PAGE.md`
