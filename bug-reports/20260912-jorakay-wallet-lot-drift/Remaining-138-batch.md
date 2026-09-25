# Jorakay drift — remaining 138 users (batch classification)

**As of:** 2026-09-12  
**Scope:** All drift users except the 15 in `Five-users-deep-dive.md` + `Ten-more-users-deep-dive.md`.  
**No writes** — manifests only. At apply time use **live Mongo `GIVEN.balance`** per `mongo_id` (staging columns here are triage only).

## Artifacts

- `remaining-138-classification.csv` — **138** rows (`mongo_id`, `user_id`, wallet, lots, delta, pattern, fix class, native/expiry signals)
- `remaining-138-classification.sql` — full batch query (run in chunks if the editor truncates results)

## Target wallet (triage)

`stg_point_balance` + native earns − native burns − expiry burns on existing `wallet_ledger` (`mongo_id` IS NULL).  
**134/138** users already match current `user_wallet` on that formula (excluding the 10 with **no** points ledger rows).

## Primary pattern (heuristic)

| Pattern | Count |
|---------|-------|
| MIGRATED_LOTS_UNDER_STG_OPEN | 61 |
| WALLET_UNDER_LEDGER | 40 |
| NATIVE_BURN_MISSING_FIFO | 15 |
| NO_POINTS_LEDGER | 10 |
| NATIVE_ACTIVITY_LOTS_HIGH | 5 |
| MIGRATED_LOTS_OVER_STG_OPEN | 3 |
| ZERO_LOTS_NATIVE_ACTIVITY | 3 |
| TTL_ZERO_LOTS_MIGRATION | 1 |

## Fix class (rollup)

| Fix class | Count |
|-----------|-------|
| UPDATE earn deductible_balance from live Mongo GIVEN.balance per mongo_id | 85 |
| UPDATE user_wallet to ledger_net | 40 |
| INSERT earn wallet_ledger rows so sum deductible_balance = wallet (confirm live Mongo first) | 10 |
| UPDATE earn deductible FIFO to match existing burn rows | 2 |
| UPDATE earn deductibles to sum wallet (post-repair allocation) | 1 |

## Same buckets as the first 15

| Bucket | ~Count | Action |
|--------|--------|--------|
| Migrated lots ≠ live Mongo | majority | `UPDATE` earn `deductible_balance` per `mongo_id` |
| Wallet below ledger net | 40 | `UPDATE user_wallet` then earns |
| Native burn, lots still high | 15 | `UPDATE` FIFO on earns (burn rows stay) |
| Expiry burn, lots not allocated | (in mongo-sync bucket) | `UPDATE` earns to match existing expiry burns |
| Lots = 0, wallet > 0 | 4 | Re-allocate deductible across earns |
| **No points `wallet_ledger` at all** | 10 | **INSERT** earn row(s); wallet is orphaned |

The **10 `65b1c…` / `6563f123…`** accounts are wallet-only (50 or 400 pts, **zero** ledger rows) — not the usual “wrong deductible” shape.

## Per-user manifest (standard)

1. **Target wallet** = `target_wallet_stg` (cross-check live Mongo `contacts.pointBalance` + native ledger).
2. **Target lots** = target wallet.
3. **`user_wallet`:** update only when pattern is `WALLET_UNDER_LEDGER` or ledger proves under-credit after earn fixes.
4. **`wallet_ledger` earns:** `UPDATE` / `INSERT` with named reasons; FIFO against **existing** burn rows only.
5. **`purchase_ledger`:** only if tracing a missing earn to a purchase.

**Apply-ready (same depth as the 15):** `DATA-ADJUSTMENT-MANIFEST-REMAINING-138.md` + `data/user-end-state-remaining-138.csv` + `data/row-level-targets-remaining-138.csv` + `data/ledger-inserts-remaining-138.csv`. Re-run `scripts/compute-remaining-138-targets.py` after refreshing exports.

See `Plan.md`, `Five-users-deep-dive.md`, `Ten-more-users-deep-dive.md`.
