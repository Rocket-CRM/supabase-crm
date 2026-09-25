# Paste into new thread — apply Jorakay wallet/lot data fixes (15 users)

**Scope:** Data-only fixes for **15 pilot users** already diagnosed. **Do not** run migration waves, `fn_ttl_points_repair_*`, staging orphan scripts, or chokepoint/expiry **functions** to “fix” — only **INSERT/UPDATE** rows as specified.

**Open in workspace:** `plugins/rocket-eng` + `~/Documents/rocket/supabase-crm` (for manifest paths; commits only if I ask).

**Read first (in order):**

1. `supabase-crm/bug-reports/20260912-jorakay-wallet-lot-drift/DATA-ADJUSTMENT-MANIFEST.md`
2. `supabase-crm/bug-reports/20260912-jorakay-wallet-lot-drift/data/user-targets.json`
3. `supabase-crm/bug-reports/20260912-jorakay-wallet-lot-drift/data/earn-rows-export.json`
4. `supabase-crm/bug-reports/20260912-jorakay-wallet-lot-drift/data/native-ledger-export.json`
5. Rationale: `Five-users-deep-dive.md`, `Ten-more-users-deep-dive.md`, `Plan.md`

**Merchant:** `7522af2c-a7f6-4ab8-8493-6875a3b19544` · Supabase `wkevmsedchftztoolkmi`

**Your tasks:**

1. **Re-verify** exports are current (`sql/export-*.sql`) or refresh JSON.
2. For **migrated** earns (`mongo_id` NOT NULL), set target `deductible_balance` from **live Mongo** `loyaltydb.points` (`GIVEN.balance` per `_id`), not staging alone.
3. For **native FIFO** users in `user-targets.json`, reduce `deductible_balance` on earns in `created_at` order to match existing **burn** rows (amounts in manifest / `native-ledger-export.json`). **Do not** insert duplicate burns unless a burn row is provably missing.
4. **User 6 only:** `UPDATE user_wallet.points_balance` by **+10,710** → **128,882** (`67510f45…` / `ff511b13…`).
5. **User 1:** after row fixes, if wallet ≠ lots, apply **named** expiry on specific earns per `Plan.md` (not shrink-to-wallet).
6. Produce **`data/apply-<date>.sql`** with one transaction per user, comments per `ledger_id`, and **`data/row-level-targets.csv`** (`ledger_id`, `current_deductible`, `target_deductible`, `reason`).
7. **Do not execute** on prod until I say “approved apply.” When approved, run in SQL editor, then `drift-list.sql`.

**Invariant after each user:** `user_wallet.points_balance` = Σ `deductible_balance` on point earns.

**Out of scope:** Issue 3 code diagnosis, remaining 138 drift users, purchase_ledger unless an earn gap requires it.
