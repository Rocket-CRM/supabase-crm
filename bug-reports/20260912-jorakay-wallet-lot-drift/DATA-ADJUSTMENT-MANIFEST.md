# Jorakay wallet/lot — data adjustment manifest (15 users)

**Purpose:** Single source of truth for a **future apply thread** (manual SQL / approved script). **No RPCs**, no migration waves, no expiry batch re-run.

**Repo path:** `supabase-crm/bug-reports/20260912-jorakay-wallet-lot-drift/`

| Artifact | Use |
|----------|-----|
| This file | Targets + action class per user |
| `data/user-targets.json` | Machine-readable targets |
| `data/earn-rows-export.json` | All earn rows (current deductible + staging Mongo balance) |
| `data/native-ledger-export.json` | Native earns/burns/expiry for FIFO |
| `sql/export-earn-rows-for-adjustment.sql` | Re-export earns before apply |
| `sql/export-native-ledger-for-adjustment.sql` | Re-export native ledger |
| `NEW-THREAD-APPLY-PROMPT.md` | Paste into apply thread |
| `Five-users-deep-dive.md` / `Ten-more-users-deep-dive.md` | Human rationale |

**Before apply:** For migrated earns, **verify `stg_mongo_balance` against live Mongo** `loyaltydb.points` (`GIVEN.balance` per `_id`). Staging can lag; live Mongo wins.

**Apply order per user:** (1) UPDATE earn `deductible_balance` (+ `expiry_processed_at` if needed), (2) UPDATE `user_wallet` only if manifest says so, (3) verify wallet = Σ lots.

---

## User targets (15)

| # | mongo_id | user_id | wallet now → target | lots now → target | `user_wallet` | Earn / FIFO |
|---|----------|---------|---------------------|-------------------|---------------|-------------|
| 1 | `65413f78d6b1732a1ec616f1` | `465dae9a-01fa-49ca-b3f1-957deb899d5d` | 43361 → **43361** | 125473 → **43361** | none | See user-1 target breakdown below |
| 2 | `6811e84c6fc1032760808710` | `6cce9025-1504-49f5-a51a-02c0aefd576b` | 9859 → **9859** | 1632 → **9859** | none | Migrated → live Mongo Σ9259 + native 600 |
| 3 | `65e992956fdff6649db70844` | `2e9794f1-5f7b-4e41-ab8d-43e6b2c03779` | 3415 → **3415** | 0 → **3415** | none | Allocate 3415 deductible across earns (inactive-expired 318 stays 0 on two GIVEN); see deep-dive |
| 4 | `65413f89d6b1732a1ec6255d` | `d093dcaf-0507-4d3f-a899-4ab57adf5444` | 12544 → **12544** | 13695 → **12544** | none | Per-id deductible → live Mongo (Σ12544) |
| 5 | `67cd2a13865b399021ce9895` | `6d60ddf9-c4b2-4186-9714-6cfe86aca1d4` | 7469 → **7469** | 4028 → **7469** | none | Mongo balances + allocate existing expiry burns 228+188 on earns |
| 6 | `67510f45a33a4dc033969a91` | `ff511b13-f049-40fd-925f-0ef12ee595cb` | 118172 → **128882** | 128882 → **128882** | **+10710** | none (lots OK) |
| 7 | `699efc2f2ec2d76e1eae0dd6` | `75b78f9f-5219-4021-9364-c24009c8264a` | 13694 → **13694** | 23222 → **13694** | none | Live Mongo + FIFO native burn **168400** |
| 8 | `65e54b99d3d42fdf0cf61c93` | `509d2ec8-bc6f-4e8b-b69b-a130363090d8` | 9428 → **9428** | 17735 → **9428** | none | Live Mongo + FIFO **3000** |
| 9 | `681421cab1e202f9103ec1a0` | `41ffe054-bc16-4d3a-9120-bc551b76991c` | 157 → **157** | 8453 → **157** | none | Live Mongo + FIFO **94300** |
| 10 | `669f3ec760ab0274d8e31ed4` | `a8b16c7b-9930-4e67-8ae3-f8a219ca51c6` | 13063 → **13063** | 4916 → **13063** | none | Restore migrated Σ15647 + FIFO **10500** |
| 11 | `67c917a2c336839338cc12a8` | `6ac3a95a-0f78-4603-800d-3354c9a2b345` | 2436 → **2436** | 8330 → **2436** | none | Live Mongo Σ6010 + FIFO **16500** |
| 12 | `6a4869e18a5ea7b763b65992` | `07313983-05d3-46a1-8549-75fc6d087ec5` | 510 → **510** | 6110 → **510** | none | FIFO burn `5fd6c5ad-8660-413c-a1a8-b7bac8836614` (5600) on migrated earn |
| 13 | `66aa305cddfe1420692eff91` | `e5961962-0b82-404b-8aee-e7e793d4ec3a` | 105230 → **105230** | 110093 → **105230** | none | Live Mongo + FIFO **26500** |
| 14 | `65413f4fd6b1732a1ec5f415` | `7e16a591-c38f-4c79-904a-bc99e2b1eab1` | 57280 → **57280** | 54008 → **57280** | none | Live Mongo + native burns **62962** + expiry **8962** on earns |
| 15 | `6787827bb0d6038e49a36ed6` | `8e9f72fb-b005-492d-8f90-dc9b81aca7bf` | 16514 → **16514** | 14098 → **16514** | none | Live Mongo + allocate expiry burns Σ**4082** on earns |

### User 1 — single target (no extra “pass”)

| Field | Target | Source |
|-------|--------|--------|
| `user_wallet.points_balance` | **43,361** | Already correct: Mongo `pointBalance` **35,313** + New CRM purchase earns **8,048** |
| Σ earn `deductible_balance` | **43,361** | **35,313** on migrated earns + **8,048** on native earns |

**Why not 48,831?** Live Mongo open `GIVEN.balance` sums to **40,783**, which is **5,470 above** Mongo `pointBalance` **35,313**. Old CRM allowed that gap; New CRM cannot (wallet must equal lots). Spendable migrated points are **35,313**, not 40,783.

**Row updates (all `wallet_ledger` earn UPDATEs, no new functions):**

1. **135 earns** — live Mongo `GIVEN.balance` = 0 → `deductible_balance` = **0** (consumed in old CRM).
2. **7 native earns** — leave **8,048** total (already correct).
3. **20 open migrated earns** — set each row’s `deductible_balance` from live Mongo `balance`, then **lower specific rows by 5,470 total** so migrated Σ = **35,313**. Reason per row: **lot balance old CRM still showed on `GIVEN`, but not in `pointBalance`** (inactive / headline mismatch). Pick rows with `expiry_date` already passed and no Mongo points activity after that expiry; if 5,470 doesn’t allocate cleanly, document row list in `row-level-targets.csv` before apply.

**No wallet UPDATE. No INSERT unless a native earn row is missing (there isn’t).**

---

## Tables touched

| Table | Typical action |
|-------|----------------|
| `wallet_ledger` | **UPDATE** `deductible_balance`, optionally `expiry_processed_at` on **earn** rows |
| `wallet_ledger` | **INSERT** burn/expiry only if manifest proves row missing (rare in these 15) |
| `user_wallet` | **UPDATE** `points_balance` — **user 6 only** in this cohort |
| `purchase_ledger` | **None** for these 15 |

---

## Status

- [ ] Live Mongo verified for migrated targets  
- [ ] Row-level `target_deductible` CSV generated from exports + Mongo  
- [ ] Product sign-off on user 1 residual gap  
- [ ] Applied per user in transaction  
- [ ] `drift-list.sql` re-run — users drop off when wallet = lots  
