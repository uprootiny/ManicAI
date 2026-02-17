#!/usr/bin/env python3
"""Analyze prompt cadence from NDJSON prompt history."""

from __future__ import annotations

import argparse
import json
from collections import defaultdict
from statistics import mean


def pct(xs: list[float], q: float) -> float:
    if not xs:
        return 0.0
    xs = sorted(xs)
    i = round((len(xs) - 1) * q)
    return xs[int(i)]


def load_events(path: str) -> list[dict]:
    out = []
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                out.append(json.loads(line))
            except json.JSONDecodeError:
                pass
    return sorted(out, key=lambda e: e.get("ts", 0))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("path", help="NDJSON file exported by ManicAI")
    args = ap.parse_args()

    events = load_events(args.path)
    if len(events) < 2:
        print("insufficient data: need >=2 events")
        return 1

    deltas = [max(0.0, events[i]["ts"] - events[i - 1]["ts"]) for i in range(1, len(events))]
    print(f"events={len(events)}")
    print(f"mean_interval={mean(deltas):.2f}s")
    print(f"p50_interval={pct(deltas, 0.5):.2f}s")
    print(f"p90_interval={pct(deltas, 0.9):.2f}s")
    print(f"burst_ratio(<10s)={100.0 * sum(1 for d in deltas if d < 10)/len(deltas):.2f}%")
    print(f"longest_idle={max(deltas):.2f}s")

    by_route: dict[str, list[float]] = defaultdict(list)
    by_track: dict[str, list[float]] = defaultdict(list)
    for i in range(1, len(events)):
        d = max(0.0, events[i]["ts"] - events[i - 1]["ts"])
        by_route[events[i].get("route", "-")].append(d)
        by_track[events[i].get("target") or "-"].append(d)

    print("\nper-route:")
    for k in sorted(by_route):
        xs = by_route[k]
        print(f"- {k}: n={len(xs)} mean={mean(xs):.2f}s p90={pct(xs, 0.9):.2f}s")

    print("\nper-track:")
    for k in sorted(by_track):
        xs = by_track[k]
        print(f"- {k}: n={len(xs)} mean={mean(xs):.2f}s p90={pct(xs, 0.9):.2f}s")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
