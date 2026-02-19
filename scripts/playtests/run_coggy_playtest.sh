#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export MANICAI_COGGY_BASE="${MANICAI_COGGY_BASE:-http://173.212.203.211:8421}"
exec python3 "$ROOT_DIR/scripts/playtests/coggy_playtest.py" --out-dir "$ROOT_DIR" "$@"
