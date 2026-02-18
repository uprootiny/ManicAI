#!/usr/bin/env python3
import argparse
import glob
import json
import os
import re
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

DEFAULT_COGGY_BASE = "http://173.212.203.211:8421"

PROMPTSET = [
    ("legal", "Given partially occluded case facts, identify likely controlling authority, what is missing, and next questions with confidence."),
    ("math", "Solve 17*23 mentally, show concise reasoning, and flag uncertainty if any."),
    ("formal", "Propose a compact type-level invariant for a smoke-test state machine and one falsification case."),
    ("smoke", "Run smoke-loop reasoning: detect first blocker class, propose fix, and define done criteria."),
    ("commit", "Suggest one minimal commit message that would reduce present system risk."),
]


def http_json(url, method="GET", payload=None, headers=None, timeout=20):
    data = None
    req_headers = {"Accept": "application/json"}
    if headers:
        req_headers.update(headers)
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
        req_headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, headers=req_headers, method=method)
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        raw = resp.read().decode("utf-8", errors="replace")
        return json.loads(raw)


def discover_coggy_ports(coggy_dir):
    ports = set()
    state_glob = os.path.join(coggy_dir, "state", "coggy-*.pid")
    for pid_file in glob.glob(state_glob):
        m = re.search(r"coggy-(\d+)\.pid$", pid_file)
        if m:
            ports.add(int(m.group(1)))
    ports.update({8421, 59683})
    return sorted(ports)


def normalize_base_url(raw):
    s = (raw or "").strip()
    if not s:
        return ""
    if "://" not in s:
        s = f"http://{s}"
    return s.rstrip("/")


def first_healthy_port(candidates):
    for p in candidates:
        try:
            out = http_json(f"http://127.0.0.1:{p}/health", timeout=2)
            if out.get("status") == "ok":
                return p
        except Exception:
            continue
    return None


def is_healthy_base(base_url):
    try:
        out = http_json(f"{base_url}/health", timeout=2)
        return out.get("status") == "ok"
    except Exception:
        return False


def read_openrouter_key(coggy_dir):
    env_key = os.environ.get("OPENROUTER_API_KEY", "").strip()
    if env_key:
        return env_key
    env_file = Path(coggy_dir) / ".env"
    if env_file.exists():
        for line in env_file.read_text(encoding="utf-8", errors="replace").splitlines():
            if line.startswith("OPENROUTER_API_KEY="):
                return line.split("=", 1)[1].strip()
    return ""


def probe_openrouter_free_models(key, sample_models):
    result = {
        "status": "skipped",
        "reason": "missing_key",
        "free_count": 0,
        "sample": [],
    }
    if not key:
        return result

    headers = {"Authorization": f"Bearer {key}"}
    try:
        models_doc = http_json("https://openrouter.ai/api/v1/models", headers=headers, timeout=15)
    except Exception as e:
        result["status"] = "error"
        result["reason"] = f"models_fetch_failed:{type(e).__name__}"
        return result

    free = [m.get("id") for m in models_doc.get("data", []) if str(m.get("id", "")).endswith(":free")]
    free = [m for m in free if m]
    result["free_count"] = len(free)
    if not free:
        result["status"] = "error"
        result["reason"] = "no_free_models"
        return result

    probes = []
    for model in free[:sample_models]:
        started = time.time()
        payload = {
            "model": model,
            "messages": [{"role": "user", "content": "Reply with just: ok"}],
            "max_tokens": 12,
            "temperature": 0,
        }
        try:
            out = http_json("https://openrouter.ai/api/v1/chat/completions", method="POST", payload=payload, headers=headers, timeout=25)
            elapsed = int((time.time() - started) * 1000)
            content = ""
            choices = out.get("choices") or []
            if choices and isinstance(choices, list):
                content = (((choices[0] or {}).get("message") or {}).get("content") or "").strip()
            probes.append({
                "model": model,
                "ok": bool(content),
                "latency_ms": elapsed,
                "preview": content[:80],
            })
        except Exception as e:
            elapsed = int((time.time() - started) * 1000)
            probes.append({
                "model": model,
                "ok": False,
                "latency_ms": elapsed,
                "error": type(e).__name__,
            })

    result["status"] = "ok"
    result["reason"] = "complete"
    result["sample"] = probes
    return result


def run_coggy_promptset(base_url):
    rows = []
    for name, prompt in PROMPTSET:
        started = time.time()
        row = {"prompt_id": name, "ok": False, "latency_ms": None}
        try:
            out = http_json(f"{base_url}/api/chat", method="POST", payload={"message": prompt}, timeout=30)
            elapsed = int((time.time() - started) * 1000)
            trace = out.get("trace") or {}
            row.update({
                "ok": isinstance(trace, dict) and bool(trace),
                "latency_ms": elapsed,
                "turn": out.get("turn"),
                "atoms": out.get("atom_count"),
                "has_reflect": bool((trace or {}).get("reflect")),
                "has_infer": bool((trace or {}).get("infer")),
            })
        except Exception as e:
            elapsed = int((time.time() - started) * 1000)
            row.update({"ok": False, "latency_ms": elapsed, "error": type(e).__name__})
        rows.append(row)
    return rows


def summarize(play):
    prompt_rows = play["promptset"]
    ok_prompts = sum(1 for r in prompt_rows if r.get("ok"))
    avg_latency = int(sum(r.get("latency_ms") or 0 for r in prompt_rows) / max(len(prompt_rows), 1))

    free = play["openrouter"]
    free_ok = 0
    if free.get("status") == "ok":
        free_ok = sum(1 for r in free.get("sample", []) if r.get("ok"))

    blockers = []
    if ok_prompts < len(prompt_rows):
        blockers.append("promptset_failures")
    if free.get("status") != "ok":
        blockers.append("openrouter_probe_failed")
    if free.get("status") == "ok" and free_ok == 0:
        blockers.append("no_working_free_model")
    if avg_latency > 12000:
        blockers.append("high_prompt_latency")

    return {
        "prompt_pass": ok_prompts,
        "prompt_total": len(prompt_rows),
        "avg_latency_ms": avg_latency,
        "free_models_total": free.get("free_count", 0),
        "free_models_working": free_ok,
        "blockers": blockers,
    }


def write_markdown(path, report):
    s = report["summary"]
    lines = []
    lines.append("# ManicAI Playtest - Coggy")
    lines.append("")
    lines.append(f"- Timestamp (UTC): `{report['timestamp']}`")
    lines.append(f"- Coggy base: `{report.get('coggy_base')}`")
    lines.append(f"- Coggy port: `{report.get('coggy_port')}`")
    lines.append(f"- Promptset pass: `{s['prompt_pass']}/{s['prompt_total']}`")
    lines.append(f"- Avg prompt latency: `{s['avg_latency_ms']}ms`")
    lines.append(f"- OpenRouter free models: `{s['free_models_working']}/{max(len(report['openrouter'].get('sample', [])), 0)}` working probes, `{s['free_models_total']}` total listed")
    lines.append("")

    lines.append("## Promptset Results")
    lines.append("")
    lines.append("| Prompt | OK | Latency (ms) | Turn | Reflect | Infer |")
    lines.append("|---|---:|---:|---:|---:|---:|")
    for r in report["promptset"]:
        lines.append(
            f"| {r.get('prompt_id','?')} | {'yes' if r.get('ok') else 'no'} | {r.get('latency_ms','')} | {r.get('turn','')} | {'yes' if r.get('has_reflect') else 'no'} | {'yes' if r.get('has_infer') else 'no'} |"
        )
    lines.append("")

    lines.append("## OpenRouter Free Model Probes")
    lines.append("")
    lines.append("| Model | OK | Latency (ms) | Preview/Error |")
    lines.append("|---|---:|---:|---|")
    for r in report["openrouter"].get("sample", []):
        lines.append(
            f"| {r.get('model','?')} | {'yes' if r.get('ok') else 'no'} | {r.get('latency_ms','')} | {r.get('preview') or r.get('error','')} |"
        )
    if not report["openrouter"].get("sample"):
        lines.append("| (none) | no | - | missing key or fetch failed |")
    lines.append("")

    lines.append("## Feedback")
    lines.append("")
    if s["blockers"]:
        for b in s["blockers"]:
            lines.append(f"- blocker: `{b}`")
    else:
        lines.append("- no blockers detected in this playtest slice")

    out = "\n".join(lines) + "\n"
    Path(path).write_text(out, encoding="utf-8")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--coggy-dir", default="/home/uprootiny/coggy")
    parser.add_argument("--coggy-base", default=os.environ.get("MANICAI_COGGY_BASE", DEFAULT_COGGY_BASE))
    parser.add_argument("--out-dir", default=".")
    parser.add_argument("--sample-models", type=int, default=3)
    args = parser.parse_args()

    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H-%M-%SZ")
    out_dir = Path(args.out_dir).resolve()
    logs_dir = out_dir / "playtests" / "logs"
    docs_dir = out_dir / "docs" / "playtests"
    logs_dir.mkdir(parents=True, exist_ok=True)
    docs_dir.mkdir(parents=True, exist_ok=True)

    ports = discover_coggy_ports(args.coggy_dir)
    port = None
    base_url = normalize_base_url(args.coggy_base)
    if base_url and not is_healthy_base(base_url):
        base_url = ""
    if not base_url:
        port = first_healthy_port(ports)
        if not port:
            raise SystemExit("No healthy Coggy endpoint detected")
        base_url = f"http://127.0.0.1:{port}"
    if port is None:
        parsed = urllib.parse.urlparse(base_url)
        port = parsed.port

    promptset = run_coggy_promptset(base_url)
    key = read_openrouter_key(args.coggy_dir)
    openrouter = probe_openrouter_free_models(key, args.sample_models)

    report = {
        "timestamp": ts,
        "coggy_base": base_url,
        "coggy_port": port,
        "ports_seen": ports,
        "promptset": promptset,
        "openrouter": openrouter,
    }
    report["summary"] = summarize(report)

    json_path = logs_dir / f"coggy-playtest-{ts}.json"
    md_path = docs_dir / f"coggy-playtest-{ts}.md"
    latest_path = docs_dir / "coggy-playtest-latest.md"

    json_path.write_text(json.dumps(report, indent=2), encoding="utf-8")
    write_markdown(md_path, report)
    write_markdown(latest_path, report)

    print(f"PLAYTEST_JSON={json_path}")
    print(f"PLAYTEST_MD={md_path}")
    print(f"PLAYTEST_LATEST={latest_path}")
    print(json.dumps(report["summary"]))


if __name__ == "__main__":
    main()
