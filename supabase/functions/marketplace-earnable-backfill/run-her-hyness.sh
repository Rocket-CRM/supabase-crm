#!/usr/bin/env bash
# Pace unclaimed mkp earnable backfill for Her Hyness (one platform per invocation).
set -euo pipefail

PLATFORM="${1:?platform: shopee|lazada|tiktok}"
LOG_FILE="${BACKFILL_LOG_FILE:-}"

log_line() {
  if [ -n "$LOG_FILE" ]; then
    echo "$@" >> "$LOG_FILE"
  else
    echo "$@"
  fi
}
BASE_URL="${SUPABASE_URL:-https://wkevmsedchftztoolkmi.supabase.co}"
SECRET="${MARKETPLACE_BACKFILL_SECRET:-}"
MERCHANT_ID="ffe8519e-49a2-467b-a0ec-57d28ba8be49"
SINCE_DATE="${SINCE_DATE:-2026-08-10}"

case "$PLATFORM" in
  shopee) SHOP_ID="224882570" ;;
  lazada) SHOP_ID="100184574113" ;;
  tiktok) SHOP_ID="7495127669839399750" ;;
  *) echo "unknown platform: $PLATFORM" >&2; exit 1 ;;
esac

AFTER_ID=""
TOTAL_UPDATED=0
BATCH=0

while true; do
  BATCH=$((BATCH + 1))
  PAYLOAD=$(jq -n \
    --arg platform "$PLATFORM" \
    --arg shop_id "$SHOP_ID" \
    --arg merchant_id "$MERCHANT_ID" \
    --arg since_date "$SINCE_DATE" \
    --arg after_id "$AFTER_ID" \
    '{platform:$platform, shop_id:$shop_id, merchant_id:$merchant_id, since_date:$since_date}
     + (if $after_id != "" then {after_id:$after_id} else {} end)
     + {dry_run:false}')

  CURL_ARGS=(-sS -X POST "$BASE_URL/functions/v1/marketplace-earnable-backfill" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD")
  if [ -n "$SECRET" ]; then
    CURL_ARGS+=(-H "x-marketplace-backfill-secret: $SECRET")
  fi

  RESP=""
  ATTEMPT=0
  while [ "$ATTEMPT" -lt 5 ]; do
    ATTEMPT=$((ATTEMPT + 1))
    RESP=$(curl "${CURL_ARGS[@]}" || true)
    if echo "$RESP" | jq -e '.success == true' >/dev/null 2>&1; then
      break
    fi
    log_line "batch=$BATCH attempt=$ATTEMPT retry error: $RESP"
    sleep $((ATTEMPT * 5))
  done

  if ! echo "$RESP" | jq -e '.success == true' >/dev/null 2>&1; then
    log_line "batch=$BATCH failed after retries: $RESP"
    exit 1
  fi
  log_line "batch=$BATCH $RESP"

  UPDATED=$(echo "$RESP" | jq -r '.updated // 0')
  TOTAL_UPDATED=$((TOTAL_UPDATED + UPDATED))
  HAS_MORE=$(echo "$RESP" | jq -r '.has_more // false')
  AFTER_ID=$(echo "$RESP" | jq -r '.next_after_id // empty')

  if [ "$HAS_MORE" != "true" ] || [ -z "$AFTER_ID" ]; then
    break
  fi
  sleep 1
done

log_line "done platform=$PLATFORM updated=$TOTAL_UPDATED batches=$BATCH"
