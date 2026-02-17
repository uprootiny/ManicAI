#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${1:-http://173.212.203.211:8788}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOG_DIR="${ROOT_DIR}/logs/cadence"
mkdir -p "${LOG_DIR}"

TMP="$(mktemp)"
crontab -l > "${TMP}" 2>/dev/null || true

grep -v "ManicAI cadence" "${TMP}" > "${TMP}.clean" || true

cat >> "${TMP}.clean" <<EOF
# ManicAI cadence: 15-min feed health
*/15 * * * * cd ${ROOT_DIR} && ./scripts/cadence/feed_health_check.sh ${BASE_URL} >> ${LOG_DIR}/cron-feed-health.log 2>&1
# ManicAI cadence: daily state snapshot
5 1 * * * cd ${ROOT_DIR} && ./scripts/cadence/daily_snapshot.sh ${BASE_URL} >> ${LOG_DIR}/cron-daily-snapshot.log 2>&1
# ManicAI cadence: weekly benchmark drift (Mon 02:10 UTC)
10 2 * * 1 cd ${ROOT_DIR} && ./scripts/cadence/weekly_benchmark_drift.py >> ${LOG_DIR}/cron-weekly-drift.log 2>&1
# ManicAI cadence: nightly log wrangling
25 2 * * * cd ${ROOT_DIR} && KEEP_DAYS=14 MAX_MB=256 ./scripts/cadence/wrangle_logs.sh >> ${LOG_DIR}/cron-log-wrangle.log 2>&1
EOF

crontab "${TMP}.clean"
rm -f "${TMP}" "${TMP}.clean"
echo "[cron] installed ManicAI cadence jobs"
