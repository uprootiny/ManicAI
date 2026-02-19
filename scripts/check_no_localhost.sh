#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TARGETS=(
  "ManicAI/DemoCatalog.swift"
)

if rg -n "127\\.0\\.0\\.1|localhost" "${TARGETS[@]}"; then
  echo "ERROR: localhost endpoint found in user-facing demo catalog."
  exit 1
fi

echo "No localhost endpoints found in demo catalog."
