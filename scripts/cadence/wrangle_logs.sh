#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOG_ROOT="${ROOT_DIR}/logs"
KEEP_DAYS="${KEEP_DAYS:-14}"
MAX_MB="${MAX_MB:-256}"

mkdir -p "${LOG_ROOT}"

# Remove old logs
find "${LOG_ROOT}" -type f -mtime +"${KEEP_DAYS}" -print -delete || true

# Cap total log size with oldest-first deletion
total_kb() { du -sk "${LOG_ROOT}" | awk '{print $1}'; }
limit_kb=$((MAX_MB * 1024))

while [ "$(total_kb)" -gt "${limit_kb}" ]; do
  oldest="$(find "${LOG_ROOT}" -type f -printf '%T@ %p\n' | sort -n | head -n1 | cut -d' ' -f2-)"
  [ -n "${oldest}" ] || break
  rm -f "${oldest}"
done

echo "[wrangle-logs] kept <=${KEEP_DAYS} days and <=${MAX_MB}MB under ${LOG_ROOT}"
