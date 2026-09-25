#!/usr/bin/env bash
# Paced marketplace historical backfill → staging, then promote.
# Usage:
#   export SUPABASE_SERVICE_ROLE_KEY=...
#   ./run-backfill-windows.sh                 # dry_run all windows
#   DRY_RUN=false ./run-backfill-windows.sh   # stage for real
#   PROMOTE=true DRY_RUN=false ./run-backfill-windows.sh
set -euo pipefail

URL="${SUPABASE_URL:-https://wkevmsedchftztoolkmi.supabase.co}/functions/v1/marketplace-orders-backfill"
KEY="${SUPABASE_SERVICE_ROLE_KEY:?set SUPABASE_SERVICE_ROLE_KEY}"
DRY_RUN="${DRY_RUN:-true}"
PROMOTE="${PROMOTE:-false}"
SLEEP_BETWEEN_WINDOWS="${SLEEP_BETWEEN_WINDOWS:-8}"

# Bangkok midnight 2026-01-01 = 2025-12-31 17:00 UTC = 1767193200
# Use UTC Jan 1 00:00 for simplicity: 1767225600
START=1767225600
NOW=$(date +%s)

shops=(
  "tiktok|7496054762932308455|8c6a1c5a-478c-4e62-b272-842ed8e918cb|SleepingCloud"
  "shopee|1420214577|8c6a1c5a-478c-4e62-b272-842ed8e918cb|SleepingCloud"
  "lazada|101014448309|8c6a1c5a-478c-4e62-b272-842ed8e918cb|SleepingCloud"
  "tiktok|7495742491657210722|57fe222b-04f7-4ce8-8cd3-427ac9ff3b2a|GrandCru"
  "shopee|364905051|57fe222b-04f7-4ce8-8cd3-427ac9ff3b2a|GrandCru"
  "lazada|100128462|57fe222b-04f7-4ce8-8cd3-427ac9ff3b2a|GrandCru"
)

call_window() {
  local platform="$1" shop="$2" ge="$3" lt="$4"
  local days=$(( (lt - ge + 86399) / 86400 ))
  echo "==> $platform shop=$shop window_days≈$days ge=$ge lt=$lt dry_run=$DRY_RUN"
  curl -sS -X POST "$URL" \
    -H "Authorization: Bearer $KEY" \
    -H "Content-Type: application/json" \
    -d "{\"platform\":\"$platform\",\"shop_id\":\"$shop\",\"create_time_ge\":$ge,\"create_time_lt\":$lt,\"dry_run\":$DRY_RUN,\"max_pages\":100}" \
    | python3 -m json.tool
  sleep "$SLEEP_BETWEEN_WINDOWS"
}

for entry in "${shops[@]}"; do
  IFS='|' read -r platform shop merchant label <<<"$entry"
  echo "######## $label $platform ########"
  step=$(( platform == "shopee" ? 15 : 7 ))
  # bash arithmetic without ternary:
  if [[ "$platform" == "shopee" ]]; then step=15; else step=7; fi
  ge=$START
  while (( ge < NOW )); do
    lt=$(( ge + step * 86400 ))
    if (( lt > NOW )); then lt=$NOW; fi
    if (( lt <= ge )); then break; fi
    call_window "$platform" "$shop" "$ge" "$lt"
    ge=$lt
  done

  if [[ "$PROMOTE" == "true" && "$DRY_RUN" == "false" ]]; then
    echo "==> promote $label $platform"
    # Promote via PostgREST RPC
    curl -sS -X POST "${SUPABASE_URL:-https://wkevmsedchftztoolkmi.supabase.co}/rest/v1/rpc/fn_promote_marketplace_backfill" \
      -H "Authorization: Bearer $KEY" \
      -H "apikey: $KEY" \
      -H "Content-Type: application/json" \
      -d "{\"p_batch_size\":500,\"p_merchant_id\":\"$merchant\",\"p_platform\":\"$platform\"}" \
      | python3 -m json.tool
  fi
done

echo "Done. If PROMOTE=false, drain with: SELECT fn_promote_marketplace_backfill(500, merchant_id, platform);"
