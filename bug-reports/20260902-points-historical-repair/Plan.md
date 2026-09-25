# Historical points lot repair (old-CRM TTL merchants)

**Canonical runbook** for wallet ↔ lot reconciliation on migrated merchants with points expiry on. Use this for Kovet, Jorakay, and any later `ttl` / `fixed_frequency` go-live.

| Artifact | Path |
|---|---|
| This plan (read + classify) | `bug-reports/20260902-points-historical-repair/Plan.md` |
| Track A apply — Kovet | `apply-track-a-kovet.sql` |
| Track A apply — Jorakay | `apply-track-a.sql` |
| Hold export | `hold-export.sql` → `hold-export.csv` (Jorakay params — switch `params` for another merchant) |
| New-thread prompt — run Kovet | `run-kovet-prompt.md` |
| New-thread prompt — `newcrm-migration` docs note | `newcrm-migration-prompt.md` |
| DB functions | `supabase/migrations/20260902100000_ttl_points_historical_repair.sql` (Track A) · `…110000_ttl_points_repair_track_b.sql` (holds A/B/C) · `…120000_ttl_points_repair_track_b_f.sql` (holds F) |
| Her Hyness (different path) | `supabase/migrations/20260901044000_hh_wallet_lot_repair.sql` — **do not reuse** |

Supabase project: `wkevmsedchftztoolkmi`. Run heavy SQL in the Supabase SQL editor (manifest build can exceed MCP timeout).

---

## Operator runbook (any merchant)

Replace `merchant_id` in every script. Jorakay is done (2026-09-02, `still_drift = 0`); Kovet is next. For any future merchant, run this once at **cutover** (see § Migration lifecycle) — not during initial load and not while daily sync is active.

### Phase A — Read only (planning)

| # | Action | Where |
|---|---|---|
| A1 | Confirm merchant is `ttl` or `fixed_frequency`, has `mongo_id`, is **not** Her Hyness | § 0 Preconditions |
| A2 | Run drift query (`wallet` vs sum of lots) | § 0 |
| A3 | Run **classification** query — per-step user counts and point deltas | § Classification |
| A4 | Run **hold gate** — split clean vs held cohort | § Hold gate |
| A5 | Export held users (`hold-export.sql`) if any | `hold-export.sql` |
| A6 | Report **`users_wallet_down`** and **`total_wallet_down_pts`** to product | § Wallet reduction summary |

Stop if product has not signed off on wallet-down numbers.

### Phase B — Preconditions (writes)

| # | Action | SQL |
|---|---|---|
| B1 | Pause migration sync | `UPDATE migration_merchant_status SET sync_active = false WHERE merchant_uuid = '<uuid>';` |
| B2 | Confirm repair functions deployed | `SELECT proname FROM pg_proc WHERE proname LIKE 'fn_ttl_points_repair%';` |
| B3 | Build manifest | `SELECT fn_ttl_points_repair_build_manifest('<uuid>'::uuid);` — save `run_id` |
| B4 | Inspect manifest summary | `SELECT summary FROM ttl_points_repair_run WHERE id = '<run_id>';` |

`fn_ttl_points_repair_build_manifest` **refuses to run** while `sync_active = true`.

### Phase C — Track A apply (clean cohort only)

Use `apply-track-a-kovet.sql` or `apply-track-a.sql`. For each step:

1. **Dry-run** (`p_dry_run := true`) once — step 1 returns `lots_updated` / `pts_zeroed`, step 2 `lots_updated` / `pts_reduced`, step 3 `burns` / `wallet_pts_down`. Compare against the manifest `summary`.
2. **Live apply** (`p_dry_run := false`) in batches until the count is zero.
3. **Re-count** before the next step.

| Step | Function | Wallet | Lots |
|---|---|---|---|
| 1 | `fn_ttl_points_repair_apply_step1` | unchanged | down (zero dead lots) |
| 2 | `fn_ttl_points_repair_apply_step2` | unchanged | down (FIFO reallocation) |
| 3 | `fn_ttl_points_repair_apply_step3` | **down** | down or unchanged | 

Step 3 only runs after steps 1–2 are complete for that user (`step1_applied_at` / `step2_applied_at`).

### Phase D — Track B (held users)

Held users were **excluded** from steps 1–3. Per user:

1. Investigate (§ Step 4 checklist).
2. Record resolution A–F in workbook / `ttl_points_repair_hold_resolution`.
3. Apply only approved amounts (Track B migrations + `apply-track-b*.sql`).

### Phase E — Verify and aftercare

| # | Action |
|---|---|
| E1 | Run § Verify query — target `still_drift = 0` except unresolved holds |
| E2 | Confirm no LINE / expiry notifications (`_skip_emit` on repair burns) |
| E3 | **Separate run:** nightly expiry catch-up for dates ≥ 2026-08-31 (post-FIFO cutover) |
| E4 | Leave `sync_active = false` permanently. Daily sync mirrors Mongo lot balances and would undo steps 1–2; a reconciled merchant is past cutover and has no reason to sync (§ Migration lifecycle) |

---

## Summary

Old CRM only applied expiry when a member next earned or redeemed. Migration copied Mongo `GIVEN.balance` onto lots as-is and set the wallet from `contacts.pointBalance`. Those two were never forced to match.

Repair in three steps so **wallet = remaining lots**. The only wallet reductions are expiries old CRM skipped because the member had no later points activity. That is acceptable: the next earn/redeem in old CRM would have taken them anyway.

Do not remigrate. Do not run Her Hyness `fn_hh_repair_*`. Pause migration sync for the merchant before any write.

## Who this is for

Live old-CRM merchants with points expiry on (`ttl` / `fixed_frequency`). First: Kovet, then Jorakay. Same queries for any later merchant in this class.

| Merchant | `merchant_id` | `mongo_id` (`merchant_ref` in staging) |
|---|---|---|
| Kovet | `c0db034a-cabc-44d2-87f0-e660a755237f` | `674566c5fb5f29940476df88` |
| Jorakay Family | `7522af2c-a7f6-4ab8-8493-6875a3b19544` | `649e9524f43a5fc2f9705850` |

In every query, set `params.merchant_id` to the merchant you are running.

## Do not

- Run this on `points_expiry_mode = 'none'`
- Credit the wallet to match lots
- Put expired lots back
- Notify LINE (`_skip_emit`)
- Write `created_at = now()` on historical expiry burns
- Apply while `migration_merchant_status.sync_active` is true

## Model

- **Wallet** = `user_wallet.points_balance` (what they can spend)
- **Lots** = `wallet_ledger.deductible_balance` on earn rows
- **Last old-CRM activity** = latest points earn/redeem with `mongo_id` present, `source_type <> expiry` (`last_ts` + `last_day`)

After last old-CRM activity, old CRM would already have dropped lots due on or before that day from the wallet. Lots that expired later are still in the wallet until we apply them (step 3).

**Two tracks:** Steps 1–3 apply to the **clean cohort** only. Users flagged by the hold gate (§ Hold gate) are investigated and written under **Step 4** — no blind step 3 on holds.

---

## 0. Preconditions (read only)

```sql
WITH params AS (
  SELECT 'c0db034a-cabc-44d2-87f0-e660a755237f'::uuid AS merchant_id  -- Kovet; switch for Jorakay
)
SELECT m.id, m.name, m.points_expiry_mode, m.points_ttl_months, m.mongo_id,
       s.sync_active, s.initial_load_completed_at
FROM merchant_master m
JOIN params p ON p.merchant_id = m.id
LEFT JOIN migration_merchant_status s ON s.merchant_uuid = m.id;
```

Stop if expiry mode is `none` or `sync_active` is true until sync is paused.

```sql
WITH params AS (
  SELECT 'c0db034a-cabc-44d2-87f0-e660a755237f'::uuid AS merchant_id
),
lot AS (
  SELECT user_id, sum(deductible_balance)::numeric AS lots
  FROM wallet_ledger
  JOIN params p ON p.merchant_id = wallet_ledger.merchant_id
  WHERE currency = 'points' AND transaction_type = 'earn'
  GROUP BY 1
)
SELECT
  count(*) AS wallets,
  count(*) FILTER (WHERE w.points_balance IS DISTINCT FROM coalesce(l.lots, 0)) AS drift_users,
  coalesce(sum(GREATEST(coalesce(l.lots, 0) - w.points_balance, 0)), 0) AS lots_over_wallet_pts,
  coalesce(sum(GREATEST(w.points_balance - coalesce(l.lots, 0), 0)), 0) AS wallet_over_lots_pts
FROM user_wallet w
JOIN params p ON p.merchant_id = w.merchant_id
LEFT JOIN lot l ON l.user_id = w.user_id;
```

---

## Classification (one pass — run this before any write)

Per user, simulate the three steps. This is the planning query.

```sql
WITH
params AS (
  SELECT 'c0db034a-cabc-44d2-87f0-e660a755237f'::uuid AS merchant_id,
         CURRENT_DATE AS today
),
last_old AS (
  SELECT wl.user_id, max(wl.created_at)::date AS last_day
  FROM wallet_ledger wl
  JOIN params p ON p.merchant_id = wl.merchant_id
  WHERE wl.currency = 'points'
    AND wl.mongo_id IS NOT NULL
    AND wl.source_type IS DISTINCT FROM 'expiry'::wallet_transaction_source_type
  GROUP BY 1
),
earn AS (
  SELECT wl.user_id,
    coalesce(sum(wl.deductible_balance) FILTER (
      WHERE lo.last_day IS NOT NULL
        AND wl.expiry_date IS NOT NULL
        AND wl.expiry_date <= lo.last_day
    ), 0) AS step1_lots,          -- due at/before last old-CRM activity (still open)
    coalesce(sum(wl.deductible_balance) FILTER (
      WHERE lo.last_day IS NOT NULL
        AND wl.expiry_date IS NOT NULL
        AND wl.expiry_date > lo.last_day
        AND wl.expiry_date < p.today
    ), 0) AS due_after_last,      -- expired after last activity, already due
    coalesce(sum(wl.deductible_balance) FILTER (
      WHERE lo.last_day IS NULL
         OR wl.expiry_date IS NULL
         OR (wl.expiry_date > lo.last_day AND wl.expiry_date >= p.today)
    ), 0) AS valid_lots           -- still not due (or no last_day / no expiry)
  FROM wallet_ledger wl
  JOIN params p ON p.merchant_id = wl.merchant_id
  LEFT JOIN last_old lo ON lo.user_id = wl.user_id
  WHERE wl.currency = 'points' AND wl.transaction_type = 'earn'
  GROUP BY wl.user_id, lo.last_day, p.today
),
sim AS (
  SELECT
    w.user_id,
    w.points_balance AS wallet_0,
    coalesce(e.step1_lots, 0) AS step1_lots,
    coalesce(e.due_after_last, 0) AS due_after_last,
    coalesce(e.valid_lots, 0) AS valid_lots,
    -- after step 1: those lots are 0; wallet unchanged
    (coalesce(e.due_after_last, 0) + coalesce(e.valid_lots, 0)) AS lots_after_1,
    w.points_balance AS wallet_after_1,
    -- step 2: if lots still > wallet, FIFO remaining (due_after first, then valid)
    GREATEST(
      (coalesce(e.due_after_last, 0) + coalesce(e.valid_lots, 0)) - w.points_balance,
      0
    ) AS step2_excess
  FROM params p
  JOIN user_wallet w ON w.merchant_id = p.merchant_id
  LEFT JOIN earn e ON e.user_id = w.user_id
),
sim2 AS (
  SELECT
    s.*,
    GREATEST(s.due_after_last - s.step2_excess, 0) AS due_after_after_2,
    GREATEST(s.step2_excess - s.due_after_last, 0) AS excess_into_valid,
    CASE
      WHEN s.lots_after_1 > s.wallet_after_1 THEN s.wallet_after_1  -- shrunk to wallet
      ELSE s.lots_after_1
    END AS lots_after_2,
    s.wallet_after_1 AS wallet_after_2
  FROM sim s
),
sim3 AS (
  SELECT
    s.*,
    GREATEST(s.valid_lots - s.excess_into_valid, 0) AS valid_after_2,
    -- step 3a: expire leftover due-after-last on BOTH sides
    s.due_after_after_2 AS step3_both_sides,
    -- step 3b: wallet still higher than remaining valid lots (lots already 0)
    GREATEST(
      (s.wallet_after_2 - s.due_after_after_2)
      - GREATEST(s.valid_lots - s.excess_into_valid, 0),
      0
    ) AS step3_wallet_only
  FROM sim2 s
)
SELECT
  count(*) AS wallets,

  count(*) FILTER (WHERE step1_lots > 0) AS step1_users,
  coalesce(sum(step1_lots) FILTER (WHERE step1_lots > 0), 0) AS step1_lots_down_pts,

  count(*) FILTER (WHERE step2_excess > 0) AS step2_users,
  coalesce(sum(step2_excess) FILTER (WHERE step2_excess > 0), 0) AS step2_lots_down_pts,

  count(*) FILTER (WHERE step3_both_sides > 0) AS step3_both_users,
  coalesce(sum(step3_both_sides) FILTER (WHERE step3_both_sides > 0), 0) AS step3_both_pts,

  count(*) FILTER (WHERE step3_wallet_only > 0) AS step3_wallet_only_users,
  coalesce(sum(step3_wallet_only) FILTER (WHERE step3_wallet_only > 0), 0) AS step3_wallet_only_pts,

  count(*) FILTER (WHERE step3_both_sides > 0 OR step3_wallet_only > 0) AS users_wallet_down,
  coalesce(sum(step3_both_sides + step3_wallet_only), 0) AS total_wallet_down_pts
FROM sim3;
```

Optional hold check (same CTEs, then):

```sql
-- Append to sim3:
-- final_wallet = wallet_after_2 - step3_both_sides - step3_wallet_only
-- final_lots   = valid_after_2
-- Hold if they still differ, or last_day is null while step1_lots > 0,
-- or final_wallet < 0.

SELECT count(*) FILTER (
  WHERE (wallet_after_2 - step3_both_sides - step3_wallet_only)
        IS DISTINCT FROM valid_after_2
     OR (wallet_after_2 - step3_both_sides - step3_wallet_only) < 0
) AS hold_users
FROM sim3;
```

A user can sit in more than one step. Totals are not meant to sum to `wallets`.

---

## Hold gate (after classification, before any write)

Split users into **clean** (steps 1–3 as simulated) vs **held** (step 4 only). Do not apply steps 1–3 on held users until each hold has a resolution and approved amounts.

**Hold reasons** (a user can have more than one):

| Code | Meaning |
|---|---|
| `sim_reconcile` | Simulation does not reconcile (`wallet ≠ lots` after sim, or `final_wallet < 0`) |
| `later_newcrm` | Any non-expiry points ledger row after `last_ts` with `mongo_id IS NULL` (post-migration activity) |
| `mongo_sync_gap` | Mongo `GIVEN`/`REDEEMED` in `stg_mongo_points` after `last_ts` (activity in old CRM not reflected as latest `mongo_id` row in Postgres) |
| `manual` | Set during step 4 investigation |

Mongo live check is optional; `stg_mongo_points` + Postgres is enough for the gate. Live `loyaltydb.points` was used to validate Jorakay (2026-09-02).

### Hold detection (merchant summary)

```sql
WITH
params AS (
  SELECT '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AS merchant_id,
         '649e9524f43a5fc2f9705850'::text AS merchant_mongo,
         CURRENT_DATE AS today
),
last_old AS (
  SELECT wl.user_id,
         max(wl.created_at) AS last_ts,
         max(wl.created_at)::date AS last_day
  FROM wallet_ledger wl
  JOIN params p ON p.merchant_id = wl.merchant_id
  WHERE wl.currency = 'points'
    AND wl.mongo_id IS NOT NULL
    AND wl.source_type IS DISTINCT FROM 'expiry'::wallet_transaction_source_type
  GROUP BY 1
),
-- … reuse earn / sim / sim2 / sim3 CTEs from Classification (add last_ts to sim via join on last_old) …
sim3 AS (
  SELECT s.user_id,
         s.wallet_after_2 - s.step3_both_sides - s.step3_wallet_only AS final_wallet,
         s.valid_after_2 AS final_lots,
         s.step3_both_sides + s.step3_wallet_only AS step3_wallet_down
  FROM sim2 s  -- placeholder: use full sim3 from Classification
),
holds AS (
  SELECT
    w.user_id,
    array_remove(array[
      CASE WHEN s3.final_wallet IS DISTINCT FROM s3.final_lots OR s3.final_wallet < 0
           THEN 'sim_reconcile' END,
      CASE WHEN EXISTS (
        SELECT 1 FROM wallet_ledger wl
        JOIN params p ON p.merchant_id = wl.merchant_id
        WHERE wl.user_id = w.user_id AND wl.currency = 'points'
          AND wl.source_type IS DISTINCT FROM 'expiry'
          AND wl.mongo_id IS NULL AND wl.created_at > lo.last_ts
      ) THEN 'later_newcrm' END,
      CASE WHEN EXISTS (
        SELECT 1 FROM stg_mongo_points p
        JOIN params par ON p.merchant_ref = par.merchant_mongo
        JOIN user_accounts ua ON ua.id = w.user_id
        WHERE p.raw->>'userId' = ua.mongo_id
          AND p.raw->>'type' IN ('GIVEN','REDEEMED')
          AND (p.raw->>'createdAt')::timestamptz > lo.last_ts
      ) THEN 'mongo_sync_gap' END
    ], NULL) AS hold_reasons
  FROM params p
  JOIN user_wallet w ON w.merchant_id = p.merchant_id
  LEFT JOIN last_old lo ON lo.user_id = w.user_id
  LEFT JOIN sim3 s3 ON s3.user_id = w.user_id
)
SELECT
  count(*) FILTER (WHERE coalesce(cardinality(hold_reasons), 0) = 0) AS clean_users,
  count(*) FILTER (WHERE coalesce(cardinality(hold_reasons), 0) > 0) AS held_users,
  count(*) FILTER (WHERE 'later_newcrm' = ANY(hold_reasons)) AS held_later_newcrm,
  count(*) FILTER (WHERE 'mongo_sync_gap' = ANY(hold_reasons)) AS held_mongo_sync_gap,
  count(*) FILTER (WHERE 'sim_reconcile' = ANY(hold_reasons)) AS held_sim_reconcile
FROM holds;
```

### Per-user hold export (for step 4 workbook)

Same CTEs; final select `user_id`, `hold_reasons`, `step3_wallet_down`, `last_ts`, `last_day` where `cardinality(hold_reasons) > 0`. Join `user_accounts` for `tel`, `fullname`, `mongo_id`.

**Jorakay classification snapshot (2026-09-02, read-only):**

| Cohort | Users | Step 3 wallet down (pts) |
|---|---:|---:|
| Clean (no hold reasons) | ~13,195 | ~14,159,572 |
| Held — `later_newcrm` (in step 3) | ~157 | ~247,523 |
| Held — `mongo_sync_gap` (in step 3) | ~116 | ~176,255 |
| **All wallets** | 24,576 | — |
| Step 3 wallet down (all, if blind apply) | 13,380 | 14,427,015 |

---

## Step 4 — Hold investigation & resolution

For each held user: investigate → pick one resolution → record approved amounts → apply only that write.

### Investigation checklist

1. List all points ledger rows with `created_at > last_ts` (mongo and non-mongo).
2. If `mongo_sync_gap`: list `stg_mongo_points` `GIVEN`/`REDEEMED` after `last_ts`; check whether rows are missing from `wallet_ledger` or only ordering differs.
3. If `later_newcrm`: list NewCRM earns/redeems/expiry burns after `last_ts`. Did nightly expiry already burn wallet for overlapping `expiry_date`s?
4. Compare `user_wallet.points_balance` vs `stg_mongo_contacts.raw->>'pointBalance'` (stale if sync paused).
5. Re-run classification with **revised `last_day`** if activity clearly moved the anchor forward (see resolution A).

### Resolution codes (one per hold)

| Code | When | Write |
|---|---|---|
| **A — Reclassify & apply** | Revised `last_day` / `last_ts`; new sim reconciles and no longer inactive | Steps 1–3 with revised anchor |
| **B — Lots only** | Wallet correct; only lot drift | Steps 1–2 only |
| **C — Sync then reclassify** | Missing Mongo rows in Postgres | Sync/load missing txns → reclassify → A or B |
| **D — Manual step 3** | Partial wallet burn; specific dates/amounts | Chokepoint burns: backdated `created_at`, `_skip_emit`, per approved `user_id` + `expiry_date` |
| **E — No write** | Already aligned or false positive | Close hold; document |
| **F — Escalate** | Cannot reconcile (wallet vs Mongo vs ledger) | No write until manual ledger review |

No hold row is written until `resolution` and step amounts are approved.

### Persist (workbook or repair table)

| Column | Purpose |
|---|---|
| `user_id` | Member |
| `hold_reasons` | From hold gate |
| `last_ts` / `last_day` | Anchor used in classification |
| `revised_last_ts` | If resolution A |
| `resolution` | A–F |
| `step1_pts` / `step2_pts` / `step3_pts` | Approved write amounts |
| `investigation_notes` | What was checked |
| `approved_at` | Gate before apply |

**Example (Jorakay):** Pitcha 🌻 `+66819048848` — `later_newcrm` + `mongo_sync_gap`; simulated −357 wallet if blind; **resolution F** until Jul–Aug NewCRM activity and Jul-09 Mongo earns are reconciled.

---

## What each step does

### 1. Zero lots already due at last old-CRM activity

Old CRM would already have dropped these from the wallet at that earn/redeem.

| | Wallet | Lots |
|---|---|---|
| Change | **no change** | **down** by `step1_lots` |
| Who | users with open earns `expiry_date <= last_day` | |

Do not write an expiry burn. Set `deductible_balance = 0` (and stamp `expired_amount` / `expiry_processed_at` so nightly does not pick them up).

### 2. Move already-spent points onto lots that were still alive

After step 1, remaining lots (due-after-last + still valid) can still exceed the wallet. That spend already left the wallet but FIFO had hit the lots step 1 zeroed.

FIFO-reduce remaining lots, earliest `expiry_date` first, until lots = wallet. Old CRM or NewCRM spend — same move.

| | Wallet | Lots |
|---|---|---|
| Change | **no change** | **down** by `step2_excess` |
| Who | users with `lots_after_1 > wallet` | |

Do not credit the wallet. Do not notify.

### 3. Apply expiry old CRM never ran (after last activity)

Lots that expired **after** last old-CRM activity, or wallet still holding points whose lots are already 0.

| Slot | Wallet | Lots | Who |
|---|---|---|---|
| 3a leftover due-after-last | **down** | **down** (same pts) | `due_after_after_2 > 0` |
| 3b wallet-only | **down** | no change (already 0) | wallet still above remaining valid lots |

Backdate the burn to that expiry date at 19:00 UTC. `_skip_emit`. Dedup per user+date. Skip FIFO on the burn (lots already adjusted).

This is the only place wallets go down.

---

## Wallet reduction summary (the number to report)

From the classification query:

- **`users_wallet_down`** — members who lose points
- **`total_wallet_down_pts`** — `step3_both_pts + step3_wallet_only_pts`

Product read: these points were already due. Old CRM would have removed them on the next earn or redeem. We are applying that now, with no LINE.

Everyone else: lots only (steps 1–2). Spendable balance unchanged.

---

## Apply (after the counts look right)

Dry-run each step as its own run on the **clean cohort only**. Held users → step 4 first.

1. Pause `sync_active` for this merchant.
2. Run **hold gate**; export held users; do not include them in steps 1–3.
3. Step 1 writes (lots only) — clean users only.
4. Re-count clean cohort. `step1_lots` should be ~0.
5. Step 2 writes (lots only, FIFO) — clean users only.
6. Re-count. `step2_excess` should be ~0.
7. Step 3 writes (wallet burns via chokepoint with backdated `created_at` + `_skip_emit`) — clean users only.
8. **Step 4** — per hold resolution (A–F); apply approved writes.
9. Verify query below.

Need chokepoint support for backdate + `_skip_emit` before step 3 (already added for Her Hyness).

### Track A apply (SQL functions)

Migration: `supabase/migrations/20260902100000_ttl_points_historical_repair.sql`  
Operator script: `bug-reports/20260902-points-historical-repair/apply-track-a.sql`

| Function | Purpose |
|---|---|
| `fn_ttl_points_repair_build_manifest(merchant_id)` | Classify, hold gate, lot FIFO manifest, burn rows (clean only) |
| `fn_ttl_points_repair_apply_step1(run_id, limit, dry_run)` | Zero step-1 lots |
| `fn_ttl_points_repair_apply_step2(run_id, limit, dry_run)` | FIFO step-2 lot reduction |
| `fn_ttl_points_repair_apply_step3(run_id, limit, dry_run)` | Wallet burns via `fn_repair_wallet_expiry_burn` |

Always dry-run (`p_dry_run := true`) then batch live apply (`false`) per step until batch returns zero rows.

## Verify

```sql
WITH params AS (
  SELECT 'c0db034a-cabc-44d2-87f0-e660a755237f'::uuid AS merchant_id
),
lot AS (
  SELECT user_id, sum(deductible_balance)::numeric AS lots
  FROM wallet_ledger
  JOIN params p ON p.merchant_id = wallet_ledger.merchant_id
  WHERE currency = 'points' AND transaction_type = 'earn'
  GROUP BY 1
)
SELECT
  count(*) FILTER (WHERE w.points_balance IS DISTINCT FROM coalesce(l.lots, 0)) AS still_drift,
  count(*) FILTER (WHERE coalesce(l.lots, 0) > w.points_balance) AS lots_gt_wallet,
  count(*) FILTER (WHERE w.points_balance > coalesce(l.lots, 0)) AS wallet_gt_lots
FROM user_wallet w
JOIN params p ON p.merchant_id = w.merchant_id
LEFT JOIN lot l ON l.user_id = w.user_id;
```

Target: `still_drift = 0` except open step-4 holds not yet resolved.

Also confirm no LINE/expiry events were emitted for these burns.

## Jorakay runbook (merchant `7522af2c-a7f6-4ab8-8493-6875a3b19544`)

**Status (2026-09-02): done.** Track A (run `13ede47d…`, 13,902 clean users, 14,159,572 pts step 3) and Track B runs for resolutions B / A / C / F all `complete`; verify query returns `still_drift = 0` on 24,580 wallets. `sync_active = false` — keep it that way. The table below is kept as the record of what was run.

| Phase | Action |
|---|---|
| **0 — Preconditions** | Confirm `ttl` 12mo; pause `sync_active`; drift + classification queries (already run) |
| **Hold split** | ~13,195 clean / ~185 held with step-3 exposure (overlap between hold reasons) |
| **1–3 — Clean cohort** | Lots repair then ~14.16M wallet expiry burns; no LINE |
| **4 — Holds** | Investigate ~157 `later_newcrm` + ~116 `mongo_sync_gap` (+ overlaps); e.g. Pitcha → F until reconciled |
| **Verify** | `still_drift = 0` except unresolved holds |
| **After** | Separate nightly expiry catch-up for dates ≥ 2026-08-31 (~1 user / 540 pts); fix `currency-expiry-daily` if needed |

**Product number to report (clean cohort only):** ~13,195 members lose spendable points; ~14.16M pts total wallet reduction.

## Kovet runbook (merchant `c0db034a-cabc-44d2-87f0-e660a755237f`)

**Status (2026-09-02):** read-only classification done, no writes. `sync_active = false` already. Apply script: `apply-track-a-kovet.sql`.

Classification snapshot (3,150 wallets):

| Measure | Value |
|---|---:|
| Users with `wallet ≠ lots` today | 22 (all `lots > wallet`) |
| Step 1 (zero lots due at last old-CRM activity) | 7 users / 309 pts |
| Step 2 (FIFO lot reduction) | 15 users / 2,835 pts |
| Step 3 (wallet down) — **`users_wallet_down` / `total_wallet_down_pts`** | **702 users / 22,607 pts** |
| Held in scope | 13 (all `later_newcrm`; no `mongo_sync_gap`; sim reconciles for everyone) |

Read this carefully before reporting: almost none of Kovet's step 3 is drift. For ~700 members wallet already equals lots, but the lots are past `expiry_date` and were never expired on either side (old CRM never ran expiry for inactive members; NewCRM nightly has not taken them). Step 3 burns them silently and backdated. Nightly expiry would otherwise take the same points with a LINE notification — so the decision for product is *silent-backdated now* vs *notified by nightly*, not *lose vs keep*.

| Phase | Action |
|---|---|
| **0 — Preconditions** | `ttl`, `sync_active = false` — confirmed |
| **Hold split** | 13 held users, all `later_newcrm`; export via `hold-export.sql` and eyeball |
| **1–3 — Clean cohort** | `apply-track-a-kovet.sql`; dry-run totals should match the snapshot above |
| **4 — Holds** | 13 users, one resolution A–F each (§ Step 4); Track B scripts if any need writes |
| **Verify** | `still_drift = 0` except unresolved holds |
| **After** | Nightly expiry catch-up for post-cutover dates if any |

## Migration lifecycle (`newcrm-migration`) — what to change

Verified against `newcrm-migration` main on 2026-09-02:

- `finalize-run.ts` ends the initial load by setting `migration_merchant_status.sync_active = true`. From then on daily sync mirrors Mongo: `wave-4a-points-old.sql` upserts lots (`amount`, `deductible_balance` from `GIVEN.balance`, ON CONFLICT overwrites both), `wave-4f-wallet-balances.sql` sets `points_balance = pointBalance + native_delta`.
- There is no cutover step in the runner. `sync_active = false` is set by hand.
- While sync is active, **old CRM is the truth for points**. `wallet ≠ lots` in NewCRM during that window is expected, not a defect: old CRM runs FIFO and expiry only on activity, and the loader copies its state as-is.

Reconciliation is therefore a **manual cutover step**, not a loader rule. Jorakay's holds (`later_newcrm`, `mongo_sync_gap`) came from an unclean cutover — NewCRM writing points before the last Mongo rows were synced — not from the 4a/4f mapping.

| Regime | Truth | Loader | Reconcile |
|---|---|---|---|
| Initial load | Mongo | 4a + 4f as today | No |
| Daily sync (dual-run) | Mongo | 4a + 4f as today — keep mirroring `deductible_balance` | No |
| **Cutover** (once per merchant) | Mongo → NewCRM | final sync → `sync_active = false` → this runbook | **Yes** |
| Post-cutover | NewCRM | sync stays off; FIFO chokepoint + nightly expiry keep `wallet = lots` | Only as a repair |

### Cutover procedure (manual, once per merchant)

The loader stays a faithful mirror. Reconciliation is done by hand in the gap between the last Mongo copy and the first NewCRM points write:

1. Freeze points in old CRM for the merchant (no further `GIVEN` / `REDEEMED`). NewCRM must not write points yet.
2. Run one final daily sync.
3. `UPDATE migration_merchant_status SET sync_active = false WHERE merchant_uuid = '<uuid>';`
4. Run Phases A–E above. With 1–3 done in order, `held_users` should be ~0.
5. Go live for points in NewCRM. Never set `sync_active` back to true.

Doing step 4 earlier gets overwritten by the next sync; doing step 5 before step 4 is what produced Jorakay's 457 holds. Kovet and Jorakay are already past cutover — for them this runbook is the one-off repair.

### Why the other loader changes are not needed

- **Do not change 4a ON CONFLICT to stop overwriting `deductible_balance`.** During dual-run an old-CRM redemption lowers Mongo `balance` on the GIVEN it consumed; ignoring that leaves lots above wallet for every redeeming user — the exact step-2 shape this runbook repairs.
- **Do not add a reconcile wave after 4f on initial load.** Sync goes active right after and rewrites the lots; step 3 would also burn wallets for members still transacting in old CRM.
- **Do not add a `wallet_lot_reconciled_at` column.** `sync_active = false` plus a `ttl_points_repair_run` with `status = 'complete'` already records it.
- **Do not set `wallet = sum(lots)` in 4f.** `pointBalance` is what the customer saw in old CRM; lots are corrected to it, not the reverse.
- **Do not zero all `expiry_date < today` lots at load** (the Her Hyness remigrate path). That drops step-2 and step-3 information and produced Face A there.

### Loader changes (`newcrm-migration`)

**During dual-run (initial load + daily sync):** `wave-4a` and `wave-4f` stay as today — faithful Mongo mirror. No reconciliation, no lot zeroing, no `wallet = sum(lots)`.

**At cutover (once per merchant):** add `wave-cutover-points-reconcile.sql` in the migration repo. It calls `fn_ttl_points_repair_*` steps 1–3, including **step 3 wallet deduction** for lots that expired after last old-CRM activity. See `newcrm-migration-prompt.md` for the full change list.

| Failure | Prevention |
|---|---|
| Her Hyness (`wallet >> lots`) | Never zero past-expiry lots in `wave-4a`; audit loader for HH remigrate logic |
| Jorakay (drift + 457 holds) | Run cutover wave after final sync + `sync_active = false`, before NewCRM points go live |

### Open check before the next dual-run merchant with expiry on

`currency-expiry-daily` has no `sync_active` gate. During dual-run it can burn step-1-shaped lots (past `expiry_date`, `deductible_balance > 0`) whose points `pointBalance` already excludes; 4f then adds that burn as `native_delta` and the member is deducted twice. Confirm whether nightly expiry ran for any merchant while `sync_active = true`; if it can, gate it on `sync_active = false` before the next such go-live.

### Staging orphans (positive `GIVEN` never loaded)

Separate from wallet ↔ lot drift. The loader skips zero-balance GIVENs by design; positive-balance staging rows with no ledger earn are a product decision (load or abandon). Do not mix into steps 1–3.

## After this merchant is clean

Nightly expiry catch-up for dates ≥ 2026-08-31 (Jorakay still has a small post-cutover due set). That is a separate run. Do not mix it into steps 1–3.

## Surfaces / owners

- Live DB: Supabase project `wkevmsedchftztoolkmi`
- Mapping: `newcrm-migration` `wave-4a-points-old.sql` (lots = Mongo `balance`), `wave-4f-wallet-balances.sql` (wallet = `pointBalance`)
- Writes: `chokepoint_post_wallet_transaction` for wallet burns only

## Out of scope

- Her Hyness (already repaired)
- Merchants not yet live / expiry off
- Re-running the migration loader
- Fixing pg_cron / Render `currency-expiry-daily` (do after historical repair for this merchant)
- Ticket currency
