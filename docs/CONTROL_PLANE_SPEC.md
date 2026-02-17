# Control Plane Spec

## Critical routes
- `GET /api/state`
- `POST /api/autopilot/run`
- `POST /api/smoke`

## Extended routes
- `POST /api/queue/add`
- `POST /api/queue/run`
- `POST /api/pane/send`
- `POST /api/nudge`
- `POST /api/spawn`
- `POST /api/snapshot/ingest`

## Validation suite
- Script: `scripts/validate_control_plane.py`
- Safe mode (no mutating probes):  
  `python3 scripts/validate_control_plane.py --base http://173.212.203.211:8788`
- Active probing mode (issues POSTs):  
  `python3 scripts/validate_control_plane.py --base http://173.212.203.211:8788 --probe-post`

## Node API fluency
- Score formula: `success / (success + failure) * 100`
- Tracked by:
  - Route globally (`apiStatsByRoute`)
  - Node-route pair (`apiStatsByNodeRoute`, key = `node|route`)
- Goal:
  - Use commutation to prioritize high-fluency nodes first.
  - Demote low-fluency nodes to secondary/quarantine lanes.

## Adaptive commutation scheduler
- Ranking order in commuted mode:
  1. lane priority (`Primary`, `Secondary`, `Quarantine`)
  2. node fluency for `autopilot/run`
  3. live throughput
- Auto-tune behavior (when enabled):
  - promote node to `Primary` after >=3 samples and fluency >= configured threshold
  - demote node to `Quarantine` after >=3 samples and low fluency
  - recover quarantined nodes back to `Secondary` when fluency improves
- Commutation plan preview:
  - explicit per-node plan with `target`, `lane`, `strategy`, `fluency`, and reason string
  - used before execution to inspect ordering and fallback choices
- Fallback strategy:
  - when node fluency is below threshold or autopilot/smoke routes are unavailable:
    - route action as `pane/send` followed by `smoke`

## Persistent telemetry memory
- Persisted across app restarts:
  - global route stats
  - node-route stats
  - action log
  - scheduler notes
- Decay model:
  - half-life based attenuation (`4h..96h` in UI)
  - keeps recent behavior dominant while preserving continuity

## Circuit breakers and degraded mode
- Breakers are tracked:
  - per route (`routeBreakers`)
  - per node-route pair (`nodeRouteBreakers`)
- Trip condition (configurable):
  - sample window
  - minimum failures
  - failure-rate threshold
  - open cooldown duration
- Degraded mode auto-engages when breaker pressure is high:
  - >=2 open route breakers, or
  - >=5 open node-route breakers
- In degraded mode, commuted autopilot is suppressed and operator can inspect/reset breakers.

## Diagnostic profiles
- `LLM Duplex`:
  - diagnose drift loops, repeated prompts, and approval stalls
  - short cadence, shorter telemetry half-life
- `Architected`:
  - diagnose contract breaks, deterministic stage failures, and smoke regressions
  - stronger throughput cadence, less fallback
- `Hybrid`:
  - blend drift controls with contract/smoke-first execution

## Timeline event model
- Timeline now stores typed events:
  - `prompt`: duplex/raw prompt supply
  - `duplex`: explicit duplex-feed shaping operations
  - `ontology`: ontology-grounding/inference layer operations
  - `service`: API interactions
  - `git`: commit/branch/diff artifacts
  - `file`: file modification artifacts
- Event tracks can be filtered by target and kind, then replayed/scrubbed in the DAW-style view.

## Hyle/Coggy stack profiles
- `Hyle Duplex`:
  - emphasizes rapid duplex-feed shaping and API vessel routing
- `Coggy Ontology`:
  - emphasizes ontology parsing/grounding before action
- `Hyle + Coggy`:
  - duplex shaping -> ontology grounding -> smoke-verified crystallization

## Session profile export
- Exports layered session profile snapshots to:
  - `session-profile.json`
  - `session-profile.md`
- Snapshot includes:
  - layer counts
  - cadence stats
  - breaker/degraded state
  - interaction health
  - top transform edges
