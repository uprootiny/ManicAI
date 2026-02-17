# OnyX Lessons Applied

This app follows an OnyX-like operator philosophy: diagnose first, then choose controlled maintenance actions.

## Applied lessons

1. Stage operations
- Verify (read-only)
- Plan (no-write blocker analysis)
- Act (guarded intervention)

2. Keep interventions legible
- Show candidate sessions and their blocker signals before action.
- Require explicit mode selection for intervention-heavy actions.

3. Prefer safe defaults
- Diagnostics and smoke checks first.
- Approval/actuation paths are constrained and auditable.

4. Build for old + new environments
- Modern target for latest macOS runner.
- Legacy deployment target track for long-tail compatibility.

## Public references used

- GitHub Actions runner images / macOS labels:
  - https://github.com/actions/runner-images
  - https://github.com/actions/runner-images/blob/main/images/macos/macos-26-Readme.md
- Xcode setup action:
  - https://github.com/maxim-lobanov/setup-xcode
- Existing uprootiny macOS workflow pattern:
  - https://github.com/uprootiny/Flycut/blob/master/.github/workflows/build.yml
- OnyX product context:
  - https://www.titanium-software.fr/en/onyx.html
