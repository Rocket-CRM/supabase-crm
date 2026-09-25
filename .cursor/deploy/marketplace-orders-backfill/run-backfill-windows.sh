#!/usr/bin/env bash
# Paced marketplace historical backfill → staging, then promote until drained.
# Usage:
#   export SUPABASE_SERVICE_ROLE_KEY=...
#   DRY_RUN=false PROMOTE=true ./run-backfill-windows.sh
set -uo pipefail

URL="${SUPABASE_URL:-https://wkevmsedchftztoolkmi.supabase.co}/functions/v1/marketplace-orders-backfill"
REST="${SUPABASE_URL:-https://wkevmsedchftztoolkmi.supabase.co}/rest/v1/rpc/fn_promote_marketplace_backfill"
KEY="${SUPABASE_SERVICE_ROLE_KEY:?set SUPABASE_SERVICE_ROLE_KEY}"
DRY_RUN="${DRY_RUN:-true}"
PROMOTE="${PROMOTE:-false}"
SLEEP_BETWEEN_WINDOWS="${SLEEP_BETWEEN_WINDOWS:-10}"

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
  echo "$(date -u +%H:%M:%S) ==> $platform shop=$shop days≈$days ge=$ge lt=$lt dry_run=$DRY_RUN"
  local resp
  resp=$(curl -sS --max-time 140 -X POST "$URL" \
    -H "Authorization: Bearer $KEY" \
    -H "Content-Type: application/json" \
    -d "{\"platform\":\"$platform\",\"shop_id\":\"$shop\",\"create_time_ge\":$ge,\"create_time_lt\":$lt,\"dry_run\":$DRY_RUN,\"max_pages\":100}" \
    || echo '{"success":false,"error":"curl_failed"}')
  echo "$resp" | python3 -c 'import sys,json
try:
  d=json.load(sys.stdin)
  print(json.dumps({k:d.get(k) for k in ("success","platform","orders_listed","already_in_ledger","staged","stage_errors","detail_fetched_target","error","duration_ms") if k in d or True}, ensure_ascii=False))
except Exception as e:
  print(json.dumps({"success":False,"parse_error":str(e),"raw":sys.stdin.read()[:300] if False else "see_above"}))
' 2>/dev/null || echo "$resp" | head -c 500
  echo
  sleep "$SLEEP_BETWEEN_WINDOWS"
}

promote_drain() {
  local merchant="$1" platform="$2" label="$3"
  echo "$(date -u +%H:%M:%S) ==> promote drain $label $platform"
  local rounds=0
  while (( rounds < 50 )); do
    rounds=$((rounds + 1))
    local resp
    resp=$(curl -sS --max-time 120 -X POST "$REST" \
      -H "Authorization: Bearer $KEY" \
      -H "apikey: $KEY" \
      -H "Content-Type: application/json" \
      -d "{\"p_batch_size\":500,\"p_merchant_id\":\"$merchant\",\"p_platform\":\"$platform\"}" \
      || echo '{"success":false}')
    echo "$resp"
    read -r inserted skipped errors <<<"$(echo "$resp" | python3 -c 'import sys,json
d=json.load(sys.stdin)
print(int(d.get("inserted") or 0), int(d.get("skipped_exists") or 0), int(d.get("errors") or 0))' 2>/dev/null || echo "0 0 0")"
    if (( inserted + skipped + errors == 0 )); then
      echo "promote idle after $rounds round(s)"
      break
    fi
    sleep 2
  done
}

for entry in "${shops[@]}"; do
  IFS='|' read -r platform shop merchant label <<<"$entry"
  echo "######## $label $platform $(date -u +%Y-%m-%dT%H:%M:%SZ) ########"
  if [[ "$platform" == "shopee" ]]; then step=15; else step=7; fi
  ge=$START
  while (( ge < NOW )); do
    lt=$(( ge + step * 86400 ))
    if (( lt > NOW )); then lt=$NOW; fi
    if (( lt <= ge )); then break; fi
    call_window "$platform" "$shop" "$ge" "$lt" || echo "WARN window failed ge=$ge lt=$lt"
    ge=$lt
  done

  if [[ "$PROMOTE" == "true" && "$DRY_RUN" == "false" ]]; then
    promote_drain "$merchant" "$platform" "$label" || echo "WARN promote failed"
  fi
done

echo "DONE $(date -u +%Y-%m-%dT%H:%M:%SZ)"
