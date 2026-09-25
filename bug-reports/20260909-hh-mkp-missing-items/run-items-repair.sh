#!/usr/bin/env bash
# Driver for marketplace-items-repair.
# Loops one (platform, shop, tier) until nothing is left in that tier, optionally as N parallel workers.
#
# Usage:
#   export SUPABASE_SERVICE_ROLE_KEY=...
#   ./run-items-repair.sh shopee 224882570 claimed                 # single worker
#   WORKERS=4 ./run-items-repair.sh tiktok 7495127669839399750 active   # 4 parallel workers (hash-partitioned, no overlap)
#   DRY_RUN=true ./run-items-repair.sh shopee 224882570 claimed   # preview only
#
# Tuning: WORKERS (default 1), TIME_BUDGET_MS (default 100000), SLEEP_MS (default 200), MAX_CALLS (default 2000)
set -euo pipefail

PLATFORM="${1:?platform shopee|tiktok|lazada}"
SHOP_ID="${2:?shop_id}"
TIER="${3:-claimed}"
URL="${SUPABASE_URL:-https://wkevmsedchftztoolkmi.supabase.co}/functions/v1/marketplace-items-repair"
KEY="${SUPABASE_SERVICE_ROLE_KEY:?set SUPABASE_SERVICE_ROLE_KEY}"
DRY_RUN="${DRY_RUN:-false}"
WORKERS="${WORKERS:-1}"
TIME_BUDGET_MS="${TIME_BUDGET_MS:-100000}"
SLEEP_MS="${SLEEP_MS:-200}"
MAX_CALLS="${MAX_CALLS:-2000}"

tier_key="$TIER"
[[ "$TIER" == "all" ]] && tier_key="all_unclaimed"

worker() {
  local part="$1"
  for ((i=1; i<=MAX_CALLS; i++)); do
    local resp
    resp=$(curl -sS --max-time 130 -X POST "$URL" \
      -H "Authorization: Bearer $KEY" \
      -H "Content-Type: application/json" \
      -d "{\"platform\":\"$PLATFORM\",\"shop_id\":\"$SHOP_ID\",\"tier\":\"$TIER\",\"dry_run\":$DRY_RUN,\"time_budget_ms\":$TIME_BUDGET_MS,\"sleep_ms\":$SLEEP_MS,\"partitions\":$WORKERS,\"partition\":$part}")
    echo "[w$part #$i] $(echo "$resp" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(json.dumps({"totals":d.get("totals"),"remaining":d.get("remaining"),"error":d.get("error"),"samples":(d.get("samples") or [])[:2]}))')"
    if echo "$resp" | python3 -c 'import sys,json; d=json.load(sys.stdin); sys.exit(0 if d.get("error") else 1)'; then
      echo "[w$part] stopping: function returned an error"; return 1
    fi
    [[ "$DRY_RUN" == "true" ]] && return 0
    local picked
    picked=$(echo "$resp" | python3 -c "import sys,json; d=json.load(sys.stdin); print((d.get('totals') or {}).get('picked', 0))")
    if [[ "$picked" == "0" ]]; then
      echo "[w$part] done: nothing left in my partition of tier=$TIER"; return 0
    fi
    sleep 1
  done
  echo "[w$part] hit MAX_CALLS=$MAX_CALLS; re-run to continue"
}

if [[ "$WORKERS" -le 1 ]]; then
  worker 0
else
  pids=()
  for ((p=0; p<WORKERS; p++)); do
    worker "$p" &
    pids+=($!)
  done
  rc=0
  for pid in "${pids[@]}"; do wait "$pid" || rc=1; done
  exit $rc
fi
