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
