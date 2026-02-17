# ManicAI (macOS)

A styled macOS operator app for agent-heavy development environments.

## What it does

- Connects to `hyperpanel` (`/api/state`)
- Displays takeover candidates, pane grid, and smoke/vibe status
- Triggers autopilot (`/api/autopilot/run`) from a terminal-style control card
- Keeps the UI legible while many agent sessions are active
- Supports remote endpoint presets (`173`, `149`, `hyle.hyperstitious.org`) and recon scan auto-selection
- Sends autopilot requests with project context to avoid no-op engagement
- Adds cadence profiles (`Stabilize`, `Throughput`, `Deep Work`) with throttled commutation controls
- Supports scripted nudges (multi-step prompt sequence with per-step pause)

## Run locally (macOS)

```bash
cd /path/to/ManicAI
brew install xcodegen
xcodegen generate
open ManicAI.xcodeproj
```

## CI/CD

Workflow: `.github/workflows/build-macos.yml`

Derived from the existing macOS build pipeline patterns in `uprootiny/Flycut`, adapted for:

- dual target matrix:
  - `tahoe-compat` on `macos-15` with `MACOSX_DEPLOYMENT_TARGET=15.0`
  - `intel-baseline` on `macos-15-intel` with `MACOSX_DEPLOYMENT_TARGET=13.0`
  - `legacy-10-11` on `macos-15-intel` with `MACOSX_DEPLOYMENT_TARGET=10.11` (AppKit target: `ManicAILegacy`)
- SwiftUI app build + unit tests
- AppKit fallback shell for El Capitan compatibility
- unsigned build on GitHub macOS runners
- DMG/ZIP artifact packaging
  - ZIP via `ditto --sequesterRsrc --keepParent` to preserve app bundle metadata

### Gatekeeper-safe artifacts (sign + notarize)

The workflow can now produce notarized artifacts when these repo secrets are configured:

- `APPLE_DEVELOPER_ID_APP_CERT_BASE64` (base64 `.p12` for Developer ID Application cert)
- `APPLE_DEVELOPER_ID_APP_CERT_PASSWORD`
- `APPLE_KEYCHAIN_PASSWORD` (optional; fallback temp value used if omitted)
- `APPLE_NOTARY_KEY_ID`
- `APPLE_NOTARY_ISSUER_ID`
- `APPLE_NOTARY_API_KEY_BASE64` (base64 App Store Connect API key `.p8`)

When secrets are present, CI uploads additional artifacts suffixed with `-notarized`.
If secrets are missing, CI still uploads unsigned artifacts (which trigger the macOS "cannot verify malware" warning).

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
