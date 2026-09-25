#!/usr/bin/env bash
# Run earnable backfill for all Her Hyness platforms sequentially.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${DIR}/logs"
mkdir -p "$LOG_DIR"

STAMP=$(date -u +%Y%m%dT%H%M%SZ)
MASTER_LOG="$LOG_DIR/all-${STAMP}.log"
LOCK_FILE="$LOG_DIR/backfill.lock"

if [ -f "$LOCK_FILE" ] && kill -0 "$(cat "$LOCK_FILE")" 2>/dev/null; then
  echo "Backfill already running (pid $(cat "$LOCK_FILE"))" >&2
  exit 1
fi

echo $$ > "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT

{
  echo "=== marketplace-earnable-backfill ALL start $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
  echo "since_date=${SINCE_DATE:-2026-08-10}"

  for PLATFORM in shopee tiktok lazada; do
    PLATFORM_LOG="$LOG_DIR/${PLATFORM}-${STAMP}.log"
    echo "--- platform=$PLATFORM start $(date -u +%Y-%m-%dT%H:%M:%SZ) ---"
    BACKFILL_LOG_FILE="$PLATFORM_LOG" "$DIR/run-her-hyness.sh" "$PLATFORM"
    echo "--- platform=$PLATFORM end $(date -u +%Y-%m-%dT%H:%M:%SZ) ---"
  done

  echo "=== marketplace-earnable-backfill ALL done $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
} >> "$MASTER_LOG" 2>&1
