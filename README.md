# ManicAI (macOS)

A styled macOS operator app for agent-heavy development environments.

## What it does

- Connects to `hyperpanel` (`/api/state`)
- Displays takeover candidates, pane grid, and smoke/vibe status
- Triggers autopilot (`/api/autopilot/run`) from a terminal-style control card
- Keeps the UI legible while many agent sessions are active

## Run locally (macOS)

```bash
cd apps/ManicAI
brew install xcodegen
xcodegen generate
open ManicAI.xcodeproj
```

## CI/CD

Workflow: `.github/workflows/manicai-macos.yml`

Derived from the existing macOS build pipeline patterns in `uprootiny/Flycut`, adapted for:

- dual target matrix:
  - `tahoe-beta` on `macos-26`
  - `legacy-10-11` on `macos-15-intel` with `MACOSX_DEPLOYMENT_TARGET=10.11`
- SwiftUI app build + unit tests
- unsigned build on GitHub macOS runners
- DMG/ZIP artifact packaging
  - ZIP via `ditto --sequesterRsrc --keepParent` to preserve app bundle metadata

## OnyX-inspired operating model

- `Verify`: inspect only, no interventions
- `Plan`: classify blockers and propose safe next actions
- `Act`: guarded autopilot + smoke loop

The app surfaces this as a mode switch in the control pane so operators can stage actions safely.

## Suggested first milestone

- Add ownership/blocker badges per candidate (`owner`, `blocker`, `authority`)
- Add explicit interventions in app UI:
  - approve safe command
  - freeze session
  - promote primary session
