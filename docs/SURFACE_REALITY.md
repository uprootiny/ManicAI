# Surface Reality Scan

Use this to observe actual reachable AI-session surfaces across known hosts.

## Run

```bash
python3 scripts/surfaces/scan_live_surfaces.py --out-dir docs/surfaces
```

Outputs:
- `docs/surfaces/live-surfaces-<timestamp>.json`
- `docs/surfaces/live-surfaces-latest.json`
- `docs/surfaces/live-surfaces-<timestamp>.md`
- `docs/surfaces/live-surfaces-latest.md`

## Most recent external check (from this dev session)

- `http://173.212.203.211:8421` -> `/api/state` reachable (Coggy schema), `/tmux` reachable (`COGGY TMUX`).
- `http://hyle.hyperstitious.org:8421` -> `/api/state` reachable (Coggy schema), `/tmux` reachable (`COGGY TMUX`).
- `:8788` was not consistently reachable during this check window.

Interpretation:
- live sprawl currently appears centered on `:8421` tmux/coggy surfaces.
- recon and UI must treat multiple state schemas as first-class (`hyperpanel`, `coggy`).
