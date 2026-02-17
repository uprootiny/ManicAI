#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${1:-http://173.212.203.211:8788}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOG_DIR="${ROOT_DIR}/logs/cadence"
mkdir -p "${LOG_DIR}"
TS="$(date -u +"%Y-%m-%dT%H-%M-%SZ")"
OUT="${LOG_DIR}/feed-health-${TS}.log"

{
  echo "[feed-health] ts=${TS} base=${BASE_URL}"
  "${ROOT_DIR}/scripts/validate_control_plane.py" --base "${BASE_URL}"
} | tee "${OUT}"

echo "[feed-health] wrote ${OUT}"
