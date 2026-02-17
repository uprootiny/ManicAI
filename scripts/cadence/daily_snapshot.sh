#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${1:-http://173.212.203.211:8788}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SNAP_DIR="${ROOT_DIR}/logs/snapshots"
mkdir -p "${SNAP_DIR}"
DAY="$(date -u +"%Y-%m-%d")"
OUT="${SNAP_DIR}/state-${DAY}.json"

curl -fsS "${BASE_URL%/}/api/state" > "${OUT}"
echo "[daily-snapshot] wrote ${OUT}"
