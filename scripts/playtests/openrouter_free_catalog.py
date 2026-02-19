#!/usr/bin/env python3
import json
import os
import urllib.request
from datetime import datetime, timezone
from pathlib import Path


def fetch_json(url, headers=None, timeout=20):
    req = urllib.request.Request(url, headers=headers or {})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8", errors="replace"))


def key_from_env_or_file():
    key = os.environ.get("OPENROUTER_API_KEY", "").strip()
    if key:
        return key
    coggy_dir = os.environ.get("MANICAI_COGGY_DIR", "/home/uprootiny/coggy").strip() or "/home/uprootiny/coggy"
    p = Path(coggy_dir) / ".env"
    if p.exists():
        for line in p.read_text(encoding="utf-8", errors="replace").splitlines():
            if line.startswith("OPENROUTER_API_KEY="):
                return line.split("=", 1)[1].strip()
    return ""


def main():
    root = Path(".").resolve()
    out_dir = root / "docs" / "playtests"
    out_dir.mkdir(parents=True, exist_ok=True)

    key = key_from_env_or_file()
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    rows = []
    status = "ok"
    reason = ""
    if not key:
        status = "error"
        reason = "missing_openrouter_api_key"
    else:
        try:
            data = fetch_json(
                "https://openrouter.ai/api/v1/models",
                headers={"Authorization": f"Bearer {key}"},
                timeout=25,
            )
            for m in data.get("data", []):
                mid = str(m.get("id", ""))
                if not mid.endswith(":free"):
                    continue
                pricing = m.get("pricing") or {}
                rows.append({
                    "id": mid,
                    "context_length": m.get("context_length"),
                    "prompt_price": pricing.get("prompt"),
                    "completion_price": pricing.get("completion"),
                })
            rows.sort(key=lambda r: r["id"])
        except Exception as e:
            status = "error"
            reason = type(e).__name__

    lines = []
    lines.append("# OpenRouter Free Models Catalog")
    lines.append("")
    lines.append(f"- Generated: `{ts}`")
    lines.append(f"- Status: `{status}`")
    if reason:
        lines.append(f"- Reason: `{reason}`")
    lines.append("")
    lines.append("| Model | Context | Prompt Price | Completion Price |")
    lines.append("|---|---:|---:|---:|")
    if rows:
        for r in rows:
            lines.append(
                f"| {r['id']} | {r['context_length'] or ''} | {r['prompt_price'] or ''} | {r['completion_price'] or ''} |"
            )
    else:
        lines.append("| (none) | - | - | - |")
    lines.append("")

    latest = out_dir / "openrouter-free-models-latest.md"
    stamped = out_dir / f"openrouter-free-models-{ts.replace(':', '-')}.md"
    content = "\n".join(lines) + "\n"
    latest.write_text(content, encoding="utf-8")
    stamped.write_text(content, encoding="utf-8")
    print(f"WROTE={latest}")
    print(f"WROTE={stamped}")


if __name__ == "__main__":
    main()
