#!/usr/bin/env python3
import argparse
import json
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

HOSTS = [
    "173.212.203.211",
    "149.102.153.201",
    "hyle.hyperstitious.org",
    "hyperstitious.art",
]
PORTS = [8788, 8421, 9801, 9750]


def fetch(url: str, timeout: float = 4.0):
    req = urllib.request.Request(url, headers={"User-Agent": "manicai-surface-scan"})
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            data = resp.read()
            return {
                "ok": True,
                "status": getattr(resp, "status", 200),
                "ms": int((time.time() - t0) * 1000),
                "bytes": len(data),
                "body": data.decode("utf-8", errors="replace"),
            }
    except urllib.error.HTTPError as e:
        body = ""
        try:
            body = e.read().decode("utf-8", errors="replace")
        except Exception:
            pass
        return {"ok": False, "status": e.code, "ms": int((time.time() - t0) * 1000), "bytes": len(body), "error": str(e), "body": body}
    except Exception as e:
        return {"ok": False, "status": 0, "ms": int((time.time() - t0) * 1000), "bytes": 0, "error": str(e), "body": ""}


def scan_surface(base: str):
    state = fetch(f"{base}/api/state")
    health = fetch(f"{base}/health")
    tmux = fetch(f"{base}/tmux")

    sessions = None
    candidates = None
    smoke = None
    if state["ok"]:
        try:
            doc = json.loads(state["body"])
            sessions = len(doc.get("sessions", []))
            candidates = len(doc.get("takeover_candidates", []))
            smoke = (doc.get("smoke") or {}).get("status")
        except Exception:
            pass

    return {
        "base": base,
        "state_ok": state["ok"],
        "state_status": state["status"],
        "state_ms": state["ms"],
        "health_ok": health["ok"],
        "health_status": health["status"],
        "tmux_ok": tmux["ok"],
        "tmux_status": tmux["status"],
        "tmux_title_hint": "COGGY TMUX" if "COGGY TMUX" in tmux.get("body", "") else ("TMUX" if "TMUX" in tmux.get("body", "") else ""),
        "sessions": sessions,
        "candidates": candidates,
        "smoke": smoke,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out-dir", default="docs/surfaces")
    args = ap.parse_args()

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H-%M-%SZ")
    rows = []
    for host in HOSTS:
        for port in PORTS:
            base = f"http://{host}:{port}"
            rows.append(scan_surface(base))

    payload = {
        "timestamp": ts,
        "rows": rows,
    }

    json_path = out_dir / f"live-surfaces-{ts}.json"
    latest_path = out_dir / "live-surfaces-latest.json"
    json_path.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    latest_path.write_text(json.dumps(payload, indent=2), encoding="utf-8")

    md = ["# Live Surfaces Scan", "", f"- Timestamp: `{ts}`", "", "| Base | State | Health | Tmux | Sessions | Candidates | Smoke |", "|---|---:|---:|---:|---:|---:|---|"]
    for r in rows:
        state = f"{r['state_status']} ({r['state_ms']}ms)" if r["state_ok"] else f"{r['state_status']}"
        health = f"{r['health_status']}" if r["health_ok"] else f"{r['health_status']}"
        tmux = f"{r['tmux_status']} {r['tmux_title_hint']}".strip()
        md.append(f"| {r['base']} | {state} | {health} | {tmux} | {r.get('sessions','')} | {r.get('candidates','')} | {r.get('smoke','')} |")

    md_path = out_dir / f"live-surfaces-{ts}.md"
    md_latest = out_dir / "live-surfaces-latest.md"
    txt = "\n".join(md) + "\n"
    md_path.write_text(txt, encoding="utf-8")
    md_latest.write_text(txt, encoding="utf-8")

    print(f"WROTE={json_path}")
    print(f"WROTE={latest_path}")
    print(f"WROTE={md_path}")
    print(f"WROTE={md_latest}")


if __name__ == "__main__":
    main()
