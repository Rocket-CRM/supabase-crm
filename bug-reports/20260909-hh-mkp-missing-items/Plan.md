# Her Hyness — repair missing marketplace line items (Lucky Fans not counting)

**Status:** ready to execute. Two independent parts, run in this order:

| Part | What | Urgency | Files |
|---|---|---|---|
| **A — Repair old data** | Re-fetch item lines for orders ingested since 2026-09-03 22:25 BKK, claimed orders first; rebuild purchase items for claimed orders | **Now** — Lucky Fans campaign ends 2026-09-12 00:00 BKK | `02-items-repair-rpcs.sql`, `edge/marketplace-items-repair/`, `run-items-repair.sh`, `03-repair-claimed-purchase-items.sql` |
| **B — Fix the code going forward** | One `CREATE OR REPLACE` of `upsert_marketplace_order` so new orders get items on first insert | Same day, separate thread/approval | `01-fix-upsert-marketplace-order.sql` |

Part A does not depend on Part B. Until B ships, new orders keep arriving without items; Part A's picker keeps finding them, so re-running Tier 2 after B is the sweep.

## Why (one paragraph)

Every Shopee and TikTok order ingested through the webhook path since **2026-09-03 22:25 BKK** landed in `order_ledger_mkp` with **zero rows in `order_items_ledger_mkp`**. Lucky Fans (`custom_hh_lb_eligible_lines`) matches SKU / product name on those item rows, so claimed orders earn no draw entries. Root cause is one PL/pgSQL bug in `upsert_marketplace_order`: for a **new** order the `SELECT … INTO v_existing_id, v_synced` finds no row and sets `v_synced` to NULL; `IF NOT v_synced AND …` is then NULL → items skipped. The item data is **not in the DB anywhere** (staging tables have zero coverage), so each affected order must be re-fetched from the platform once.

## Facts the executor needs (do not invent others)

| Item | Value |
|---|---|
| Supabase project | `wkevmsedchftztoolkmi` (only this one; never `list_projects`) |
| Merchant | Her Hyness `herhynessreward`, `merchant_id = ffe8519e-49a2-467b-a0ec-57d28ba8be49` |
| Shopee shop_id | `224882570` |
| TikTok shop_id | `7495127669839399750` |
| Lazada shop_id | `100184574113` (optional, Tier 3) |
| Cutoff | `2026-09-03 15:25:00+00` — all selection uses `order_ledger_mkp.updated_at >= cutoff` |
| Baseline (2026-09-09 14:00 BKK) | Shopee: 16,049 item-less, **142 claimed**, 13,674 active. TikTok: 35,674 item-less, **210 claimed** (182 with a purchase row), 25,869 active. Lazada: 176, 0 claimed. |
| Claimed purchases with zero `purchase_items_ledger` rows | 142 Shopee + 182 TikTok |
| Lucky Fans cache | `custom_hh_lb_eligible_lines_cache`, cron `herhyness-lucky-fans-eligible-lines-refresh` every 5 min — self-heals once items exist |
| Owning clone | `~/Documents/rocket/supabase-crm` |

## Hard rules for the executing thread

- Do **not** edit or redeploy `inngest-marketplace-serve` (live ingest path).
- Do **not** use `marketplace-orders-backfill --fetch_order_sns` (older normaliser without escrow financials would overwrite header amounts on unclaimed orders; Shopee-only).
- Do **not** delete or update rows in `order_ledger_mkp`, `purchase_ledger`, or existing item rows. Every write in this plan is an **INSERT of missing rows** or a `CREATE OR REPLACE FUNCTION`.
- Supabase MCP `apply_migration` for the SQL files, `deploy_edge_function` for the edge function, `execute_sql` for checks. Shell only for the curl driver.
- Report counts after every step; stop and report if a count moves the wrong way.

---

# PART A — Repair old data (urgent)

## A0 — Baseline (read-only)

```sql
SELECT o.platform,
       COUNT(*) AS item_less,
       COUNT(*) FILTER (WHERE o.synced_to_transaction) AS claimed_item_less,
       COUNT(*) FILTER (WHERE NOT o.synced_to_transaction
                          AND upper(o.order_status) NOT IN ('CANCELLED','CANCEL','IN_CANCEL','CANCELED','UNPAID','TO_RETURN')) AS active_item_less
FROM order_ledger_mkp o
WHERE o.merchant_id = 'ffe8519e-49a2-467b-a0ec-57d28ba8be49'
  AND o.platform IN ('shopee','tiktok','lazada')
  AND o.updated_at >= '2026-09-03 15:25:00+00'
  AND NOT EXISTS (SELECT 1 FROM order_items_ledger_mkp i WHERE i.order_id = o.id)
GROUP BY 1 ORDER BY 1;
```

Record it. Numbers grow until Part B ships.

## GATE A — ask once: "Install the repair RPCs (02) and deploy `marketplace-items-repair`?"

## A1 — Install the repair RPCs (≈1 min)

`apply_migration` name `mkp_items_repair_rpcs`, contents = **`02-items-repair-rpcs.sql`**. Creates:

- `stg_mkp_items_repair_log` — attempt log; an SN is retired after 3 failed attempts
- `fn_mkp_items_repair_pick(merchant, platform, shop, tier, limit, partitions, partition)` — next ≤50 item-less SNs for a tier; `partitions/partition` hash-split the backlog so parallel workers never pick the same order
- `fn_mkp_items_repair_remaining(merchant, platform, shop)` — remaining counts per tier
- `fn_mkp_repair_order_items(p_order)` — inserts missing item rows only (`ON CONFLICT DO NOTHING`), header untouched
- `fn_mkp_repair_order_items_batch(p_orders)` — one round-trip for a whole batch; logs failures

Verify (expect ≈142 and a JSON with `claimed`/`active` counts):

```sql
SELECT COUNT(*) FROM fn_mkp_items_repair_pick('ffe8519e-49a2-467b-a0ec-57d28ba8be49','shopee','224882570','claimed',50);
SELECT fn_mkp_items_repair_remaining('ffe8519e-49a2-467b-a0ec-57d28ba8be49','tiktok','7495127669839399750');
```

## A2 — Deploy the repair edge function (≈5 min)

1. In the clone create `supabase/functions/marketplace-items-repair/` and copy in:
   - `bug-reports/20260909-hh-mkp-missing-items/edge/marketplace-items-repair/index.ts`
   - **all four** files from `supabase/functions/inngest-marketplace-serve/adapters/` (`types.ts`, `shopee-adapter.ts`, `tiktok-adapter.ts`, `lazada-adapter.ts`) → `supabase/functions/marketplace-items-repair/adapters/`. Copy verbatim — the repair must normalise exactly like the live ingest.
2. `deploy_edge_function` with `name: marketplace-items-repair`, `entrypoint_path: index.ts`, `files` = those five (`index.ts`, `adapters/types.ts`, `adapters/shopee-adapter.ts`, `adapters/tiktok-adapter.ts`, `adapters/lazada-adapter.ts`). Keep JWT verification on; the driver sends the service-role key. Platform secrets (`SHOPEE_PARTNER_KEY`, TikTok app keys) are project-level and already visible to edge functions.
3. Dry run (no writes):

```bash
export SUPABASE_SERVICE_ROLE_KEY=...   # ask the owner; never paste into chat or files
cd ~/Documents/rocket/supabase-crm/bug-reports/20260909-hh-mkp-missing-items
chmod +x run-items-repair.sh
DRY_RUN=true ./run-items-repair.sh shopee 224882570 claimed
```

Expect `totals.picked ≈ 50`, `remaining.claimed ≈ 142`, no `error`.

4. Real test on 5 claimed orders:

```bash
curl -sS -X POST "https://wkevmsedchftztoolkmi.supabase.co/functions/v1/marketplace-items-repair" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" -H "Content-Type: application/json" \
  -d '{"platform":"shopee","shop_id":"224882570","tier":"claimed","batch_size":5,"time_budget_ms":20000}' | python3 -m json.tool
```

Expect `totals.repaired = 5`, `items_inserted ≥ 5`, `failed_in_rpc = 0`, `not_returned_by_platform = 0`. Then:

```sql
SELECT o.order_sn, COUNT(i.id) AS items, string_agg(i.item_name, ' | ') AS names
FROM order_ledger_mkp o JOIN order_items_ledger_mkp i ON i.order_id=o.id
WHERE o.merchant_id='ffe8519e-49a2-467b-a0ec-57d28ba8be49' AND o.platform='shopee' AND o.synced_to_transaction
  AND o.updated_at >= '2026-09-03 15:25:00+00'
GROUP BY 1 ORDER BY 1 DESC LIMIT 5;
```

If `repaired = 0` with `fetch_error` samples or `not_returned_by_platform > 0` → **stop**, paste the sample to the owner (credential / API problem).

## A3 — Tier 1: claimed orders (≈1–2 minutes total)

Run both in parallel (separate shops, separate platform rate limits):

```bash
./run-items-repair.sh shopee 224882570 claimed &
./run-items-repair.sh tiktok 7495127669839399750 claimed &
wait
```

Each worker ends with `done: nothing left in my partition of tier=claimed`. Then confirm `remaining.claimed = 0` for both shops:

```sql
SELECT fn_mkp_items_repair_remaining('ffe8519e-49a2-467b-a0ec-57d28ba8be49','shopee','224882570'),
       fn_mkp_items_repair_remaining('ffe8519e-49a2-467b-a0ec-57d28ba8be49','tiktok','7495127669839399750');
```

Lucky Fans check (was 0 before; cache follows within 5 min, or run `SELECT public.custom_hh_lb_refresh_eligible_lines();` once):

```sql
SELECT COUNT(*) AS mkp_lines, COUNT(DISTINCT user_id) AS members
FROM custom_hh_lb_eligible_lines
WHERE transaction_number ~ '^MKP-(SHOPEE|TIKTOK)-' AND transaction_date >= '2026-09-03 15:25:00+00';
```

## GATE B — show the preview from 5a, ask once: "Insert purchase item rows for these N claimed purchases?"

## A4 — Rebuild `purchase_items_ledger` for the claimed purchases (≈1 min)

**`03-repair-claimed-purchase-items.sql`**, three statements via `execute_sql`, in order:

- **5a preview** → ≈142 Shopee + ≈182 TikTok, `repairable_now` = count (Tier 1 done).
- **5b apply** (after GATE B) → one `purchase_items_ledger` row per marketplace line, same shape the claim RPC would have written (`line_total = COALESCE(earnable_amount, line_total)`, `status = completed`, `completed_by_source = 'repair_20260909_mkp_items'`, SKU resolved via `product_sku_master`, NULL when unknown). Idempotent.
- **5c verify** → `still_without_items = 0`.

Lucky Fans reads `order_items_ledger_mkp`, not `purchase_items_ledger`; this step is for ledger consistency and does not gate the draw count.

## A5 — Tier 2: active (unclaimed, not cancelled) orders — same day, background

These become draw entries the moment a member claims them, so they matter before the campaign closes.

```bash
WORKERS=4 ./run-items-repair.sh shopee 224882570 active &      # ≈13.7k orders
WORKERS=4 ./run-items-repair.sh tiktok 7495127669839399750 active &   # ≈25.9k orders
wait
```

Expected wall time ≈15–25 min for both. If `samples` show platform rate-limit errors (HTTP 429 / Shopee `error_limit` / TikTok code 429xx), rerun with `WORKERS=2 SLEEP_MS=1000`.

## A6 — Tier 3 (optional, no draw impact): cancelled/unpaid leftovers and Lazada

```bash
WORKERS=4 ./run-items-repair.sh shopee 224882570 all
WORKERS=4 ./run-items-repair.sh tiktok 7495127669839399750 all
./run-items-repair.sh lazada 100184574113 all
```

Only if the owner wants the ledger complete.

## A7 — Closeout report (paste in chat)

Re-run A0 and `fn_mkp_items_repair_remaining` for both shops. Report: baseline → now per tier, `gave_up_after_3_attempts` with a sample of `last_error` from `stg_mkp_items_repair_log`, Lucky Fans `mkp_lines`/`members` from A3, and 5c = 0. Remind the owner that Part B is still pending if it has not shipped.

---

# PART B — Fix the code going forward (separate approval)

## GATE C — ask once: "Apply the `upsert_marketplace_order` fix (01)?"

## B1 — Apply the fix

`apply_migration` name `upsert_mkp_order_items_null_synced_fix`, contents = **`01-fix-upsert-marketplace-order.sql`**.

What changes vs live (everything else identical): `v_synced := COALESCE(v_synced,false)` after the lookup; items are written whenever the payload has them; "frozen once claimed" now only stops the `ON CONFLICT` amount refresh. The new `ON CONFLICT … WHERE NOT v_synced` clause was parse-checked against the live schema on 2026-09-09.

Verify:

```sql
SELECT pg_get_functiondef('public.upsert_marketplace_order'::regproc) LIKE '%v_synced:=COALESCE(v_synced,false)%' AS fixed;
```

After ~10 minutes (expect `still_item_less` = 0 or near 0):

```sql
SELECT o.platform, COUNT(*) AS new_orders,
       COUNT(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM order_items_ledger_mkp i WHERE i.order_id=o.id)) AS still_item_less
FROM order_ledger_mkp o
WHERE o.merchant_id='ffe8519e-49a2-467b-a0ec-57d28ba8be49' AND o.platform IN ('shopee','tiktok')
  AND o.updated_at >= now() - interval '10 minutes'
GROUP BY 1;
```

## B2 — Sweep

Re-run A5 once (`active` tier, both shops) to pick up orders that arrived between the Tier 2 run and B1.

## B3 — Follow-ups (not blocking)

- Add an `ops_daily_recon` check: marketplace orders from the last 24h with zero item rows, per platform.
- Commit `01`, `02`, and `supabase/functions/marketplace-items-repair/` into `supabase-crm` when the owner asks (the 2026-09-03 `marketplace_net_earnable_*` migrations and live `inngest-marketplace-serve` code are currently not in the repo).
- Same driver, other webhook-path merchants (Purefoods, Munasoul, Biowoman, Double A, Champion Bags, Jorakay, CHY, Cloudfriends, Outdoorshield — ≈60 claimed orders total) once the owner prioritises them.

---

## Open questions (do not block Part A)

- 28 TikTok orders are `synced_to_transaction = true` with `claimed_user_id` NULL and no `MKP-TIKTOK-…` purchase row. Tier 1 repairs their items anyway; why they are flagged synced is a separate check.

## Out of scope

- Any change to `inngest-marketplace-serve`, `marketplace-orders-backfill`, Lucky Fans views, or claim RPCs.
