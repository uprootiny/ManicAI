#!/usr/bin/env python3
from __future__ import annotations

import glob
import json
import os
from datetime import datetime, timezone


def load(path: str) -> dict:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def main() -> int:
    root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
    snap_dir = os.path.join(root, "logs", "snapshots")
    out_dir = os.path.join(root, "logs", "cadence")
    os.makedirs(out_dir, exist_ok=True)

    snaps = sorted(glob.glob(os.path.join(snap_dir, "state-*.json")))
    if len(snaps) < 2:
        print("need >=2 snapshots for drift report")
        return 1

    prev_path, cur_path = snaps[-2], snaps[-1]
    prev, cur = load(prev_path), load(cur_path)

    def n(x, key):
        return len(x.get(key, []) or [])

    report = {
        "ts": datetime.now(timezone.utc).isoformat(),
        "previous": os.path.basename(prev_path),
        "current": os.path.basename(cur_path),
        "sessions_delta": n(cur, "sessions") - n(prev, "sessions"),
        "panes_delta": n(cur, "panes") - n(prev, "panes"),
        "candidates_delta": n(cur, "takeover_candidates") - n(prev, "takeover_candidates"),
        "queue_delta": n(cur, "queue") - n(prev, "queue"),
        "smoke_prev": (prev.get("smoke") or {}).get("status", "unknown"),
        "smoke_cur": (cur.get("smoke") or {}).get("status", "unknown"),
    }

    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H-%M-%SZ")
    out = os.path.join(out_dir, f"weekly-drift-{ts}.json")
    with open(out, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2)
    print(f"[weekly-drift] wrote {out}")
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
