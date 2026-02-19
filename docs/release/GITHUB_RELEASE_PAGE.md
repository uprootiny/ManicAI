# ManicAI

ManicAI is a macOS operator console for real-world AI session sprawl: it observes live session surfaces, classifies blockers, and runs bounded intervention loops with smoke feedback.

## Why this release matters

- recon now reflects live surfaces across known hosts, including tmux dashboards
- state parsing handles multiple real schemas (`hyperpanel` and `coggy`)
- action gating is mode-aware (`Verify` / `Plan` / `Act`) with explicit preflight reasons
- recentering prompt interrupts are built in, with live symptom auto-suggest

## Download

Use the latest healthy artifacts:

- `ManicAI-dmg-tahoe-compat`
- `ManicAI-zip-tahoe-compat`
- `ManicAI-app-tahoe-compat`
- `ManicAI-dmg-intel-13_0`
- `ManicAI-zip-intel-13_0`
- `ManicAI-app-intel-13_0`
- `ManicAI-dmg-legacy-10_11`
- `ManicAI-zip-legacy-10_11`
- `ManicAI-app-legacy-10_11`

Release workflow:

- https://github.com/uprootiny/ManicAI/actions/workflows/build-macos.yml

## What’s in scope

- remote-first endpoint recon and selection
- tmux observation affordances from the UI
- bounded mutation controls with safety gates
- DAW-style timeline for prompts/service/git/file events
- promptset recentering tools for runaway agent behavior

## What this is not

- not a fully autonomous repo takeover bot
- not a replacement for CI discipline or smoke tests
- not a framework migration tool

## Operator flow (recommended)

1. `Recon Scan + Auto Select`
2. verify live surface + state kind + tmux reachability
3. choose mode: `Verify` / `Plan` / `Act`
4. run one bounded loop: classify -> intervene -> smoke -> delta
5. commit only the smallest verified fix

## Verification

- Build matrix includes Tahoe-compat, Intel baseline, and legacy 10.11 target.
- Safety controls include panic/degraded states and explicit action disable reasons.
- Use control-plane validator before high-velocity runs:
  - `python3 scripts/validate_control_plane.py --base <base-url>`

## Notes on trust and safety

Unsigned artifacts can trigger macOS security warnings. If notarization secrets are configured in GitHub Actions, notarized artifacts are produced and published alongside standard artifacts.

## Reference docs

- Design: `docs/DESIGN_DOC.md`
- Critical critique/remediation: `docs/UX_ENGINEERING_CRITIQUE.md`
- Surface reality scan: `docs/SURFACE_REALITY.md`
- Recentering prompts: `docs/RECENTERING_PROMPTS.md`
