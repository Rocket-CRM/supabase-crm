# Execute Jorakay wallet/lot data fix (153 users)

**Open:** `plugins/rocket-eng` + `~/Documents/rocket/supabase-crm`  
**Merchant:** `7522af2c-a7f6-4ab8-8493-6875a3b19544` · Supabase `wkevmsedchftztoolkmi`  
**Do not** run chokepoint, expiry batch, TTL repair functions, or migration waves.

## 1. Refresh live Mongo (frozen — Jorakay no longer writes Mongo)

Mongo MCP: **`user-mongodb`** → `loyaltydb` (CRM). Storefront MCP is not used for points.

**Skip this block** only when `data/live-mongo-snapshot.json` already has **153** keys in `point_balance_by_user` **and** `python3 scripts/verify-mongo-vs-staging.py` reports **0** `live_missing` flags (staging vs live diffs are OK).

1. **Two bulk exports** (not per-user finds): `data/mongo-pipeline-headlines-all.json` on `users` → `data/live-mongo-headlines-export.json` (expect 153 rows); `data/mongo-pipeline-given-all.json` on `points` → `data/live-mongo-given-export.json`. If a single `given` export fails or truncates, merge `data/mongo-pipeline-given-{0,1,2,3}.json` batch exports instead.
2. **Exception users** missing from the headlines export: one targeted aggregate per user (headline and/or GIVEN count parity), append to the export JSON, then re-import.
3. `python3 scripts/import-live-mongo-exports.py` → `data/live-mongo-snapshot.json` (**gate: 153** users in `point_balance_by_user`).
4. `python3 scripts/build-apply-pack-all-153.py` → regenerates `*-all-153.*`
5. `python3 scripts/verify-mongo-vs-staging.py` → `data/mongo-verify-report.md`, `data/mongo-verify-mismatches.csv`

## 2. Read before apply

| File | Purpose |
|------|---------|
| `Plan.md` | End-state rules |
| `data/user-targets-all-153.json` | Per-user wallet/lots targets |
| `data/user-end-state-all-153.csv` | Before/after summary |
| `data/row-level-targets-all-153.csv` | Earn `deductible_balance` UPDATEs (`cohort` = pilot_15 \| remaining_138) |
| `data/wallet-updates-all-153.csv` | `user_wallet` UPDATEs only |
| `data/ledger-inserts-all-153.csv` | Full `wallet_ledger` earn INSERT rows (operational columns) |
| `DATA-ADJUSTMENT-MANIFEST-ALL-153.md` | Row counts |

Re-export Supabase earns if stale: `sql/export-earn-rows-for-adjustment.sql`, `sql/export-earn-rows-remaining-138.sql`, native ledger SQL siblings.

## 3. Apply order (per user, one transaction)

1. **UPDATE** `wallet_ledger` earns from `row-level-targets-all-153.csv` (set `deductible_balance` = `target_deductible`; set `expiry_processed_at` only when reason includes expiry FIFO and row policy requires it).
2. **INSERT** earns from `ledger-inserts-all-153.csv` when present for that `mongo_id` (use all columns in CSV — must look like normal ledger rows in admin/history).
3. **UPDATE** `user_wallet.points_balance` only if row exists in `wallet-updates-all-153.csv`.
4. Verify: `user_wallet.points_balance` = Σ `deductible_balance` on point earns.

**Burn / purchase_ledger:** Do not INSERT duplicate burns. Only touch `purchase_ledger` if a missing earn is traced to a purchase (none in current pack).

## 4. Pilot users in the same CSV

All **15** pilot users are rows in `row-level-targets-all-153.csv` (`cohort=pilot_15`). No separate pilot file.

## 5. After apply

Run `drift-list.sql` — fixed users should drop off when wallet = lots.

## 6. Gate

Do not execute on prod until product says **approved apply**.
