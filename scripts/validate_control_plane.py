#!/usr/bin/env python3
"""Validate ManicAI control-plane endpoint contracts.

Usage:
  python3 scripts/validate_control_plane.py --base http://173.212.203.211:8788
  python3 scripts/validate_control_plane.py --base http://... --probe-post
"""

from __future__ import annotations

import argparse
import json
import urllib.error
import urllib.parse
import urllib.request


ROUTES = [
    ("state", "GET", "/api/state", True),
    ("autopilot", "POST", "/api/autopilot/run", True),
    ("smoke", "POST", "/api/smoke", True),
    ("queue_add", "POST", "/api/queue/add", False),
    ("queue_run", "POST", "/api/queue/run", False),
    ("pane_send", "POST", "/api/pane/send", False),
    ("nudge", "POST", "/api/nudge", False),
    ("spawn", "POST", "/api/spawn", False),
    ("snapshot_ingest", "POST", "/api/snapshot/ingest", False),
]


def request(url: str, method: str = "GET", payload: dict | None = None) -> tuple[int, str]:
    data = None
    headers = {}
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url=url, method=method, data=data, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=4) as resp:
            body = resp.read().decode("utf-8", errors="replace")
            return resp.status, body
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace") if e.fp else ""
        return e.code, body
    except Exception as e:  # noqa: BLE001
        return 0, str(e)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", required=True, help="Base URL, e.g. http://173.212.203.211:8788")
    ap.add_argument("--probe-post", action="store_true", help="Probe POST routes with sample payloads")
    args = ap.parse_args()

    base = args.base.rstrip("/")
    status, html = request(base + "/")
    route_hints = []
    if status == 200 and html:
        for _, _, path, _ in ROUTES:
            if path in html:
                route_hints.append(path)

    state_status, state_body = request(base + "/api/state")
    sample_project = ""
    sample_session = ""
    sample_target = ""
    if state_status == 200:
        try:
            state = json.loads(state_body)
            projects = state.get("projects") or []
            sessions = state.get("sessions") or []
            targets = state.get("takeover_candidates") or state.get("panes") or []
            sample_project = (projects[0] or {}).get("path", "") if projects else ""
            sample_session = (sessions[0] or {}).get("id", "") if sessions else ""
            sample_target = (targets[0] or {}).get("target", "") if targets else ""
        except Exception:
            pass

    payload_by_id = {
        "autopilot": {"prompt": "diagnose only", "project": sample_project, "max_targets": 1, "auto_approve": False},
        "smoke": {"project": sample_project},
        "queue_add": {"prompt": "noop", "project": sample_project, "session_id": sample_session},
        "queue_run": {"project": sample_project, "session_id": sample_session},
        "pane_send": {"target": sample_target, "text": "noop", "enter": True},
        "nudge": {"session_id": sample_session, "text": "noop"},
        "spawn": {"session_name": "noop-validator", "project": sample_project, "command": "echo noop"},
        "snapshot_ingest": {"name": "validator-noop", "text": "noop"},
    }

    report = []
    for rid, method, path, critical in ROUTES:
        url = urllib.parse.urljoin(base + "/", path.lstrip("/"))
        if method == "GET" or args.probe_post:
            payload = payload_by_id.get(rid) if method == "POST" else None
            status_code, body = request(url, method=method, payload=payload)
            ok = 200 <= status_code < 300
            report.append(
                {
                    "id": rid,
                    "method": method,
                    "path": path,
                    "critical": critical,
                    "status": status_code,
                    "ok": ok,
                    "hinted": path in route_hints,
                    "preview": body[:180],
                }
            )
        else:
            report.append(
                {
                    "id": rid,
                    "method": method,
                    "path": path,
                    "critical": critical,
                    "status": None,
                    "ok": path in route_hints,
                    "hinted": path in route_hints,
                    "preview": "skipped (use --probe-post)",
                }
            )

    critical_fail = [r for r in report if r["critical"] and not r["ok"]]
    print(json.dumps({"base": base, "route_hints": route_hints, "report": report}, indent=2))
    if critical_fail:
        print(f"\nFAIL: missing critical routes: {[r['path'] for r in critical_fail]}")
        return 2
    print("\nPASS: critical control-plane routes available")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
