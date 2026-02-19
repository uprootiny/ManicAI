# ManicAI UX + Engineering Critique

## Purpose
This is intentionally adversarial: how ManicAI fails, why, and what to fix.

## Failure Modes
1. Control overload without clear next action.
2. Hidden gating logic (button appears available, then fails on click).
3. Mode semantics blur (`Verify`/`Plan`/`Act` not consistently reflected in controls).
4. Local-vs-remote endpoint ambiguity causing unreliable recon behavior.
5. Timeline power with weak onboarding/discoverability.
6. Telemetry-heavy views with insufficient synthesis.

## Engineering Risks
1. Policy logic split across UI and runtime paths.
2. No single preflight contract exposed to UI for action gating reasons.
3. Endpoint regressions (localhost reintroduced) without hard guards.
4. Safety loop can be bypassed by ad-hoc operator flows.

## Mastery Standards
1. Primary CTA must always answer: can execute now, if not why, and how to unblock.
2. Mode must be explicit in behavior and copy.
3. Preflight policy should be centralized and reusable.
4. Remote-first behavior must be deterministic and testable.
5. Classify -> Act -> Smoke -> Delta loop must be visible and logged.

## Addressed In This Iteration
1. Main CTA now uses explicit preflight reasoning.
2. Verify mode is not blocked by mutation endpoint requirements.
3. Degraded+commutation conflict is surfaced with actionable disabled reason.

## Next Remediations
1. Add a dedicated "Next Action" card with one recommended intervention.
2. Mode-specific CTA labels:
   - Verify: `Refresh + Reassess`
   - Plan: `Diagnose Blocker`
   - Act: `Run Bounded Loop`
3. Add disabled-reason affordances for queue/nudge/pane/spawn controls.
4. Add first-run timeline coaching for replay/scrub/range operations.
5. Add UI tests for mode + gating semantics.
