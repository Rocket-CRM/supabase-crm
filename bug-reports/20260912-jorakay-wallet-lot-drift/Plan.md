# Jorakay — wallet vs open lots drift (investigation plan)

**Scope:** Read-only until product approves per-user fix sheets. **Out of scope:** staging orphan remediation SQL, merchant-wide TTL repair re-runs, any writes.

**Merchant:** Jorakay — Postgres `7522af2c-a7f6-4ab8-8493-6875a3b19544`, Mongo merchant `649e9524f43a5fc2f9705850`.

**Invariant we want at the end (not a shortcut to get there):** `user_wallet.points_balance` = Σ `deductible_balance` on open point earns. Both sides are derived independently with correct treatment; equality is the check, not the adjustment knob.

---

## Principles

1. **Every lot change has a reason** — expiry (with or without wallet movement), redemption FIFO (New CRM only for deductible), or explicit earn/adjustment. No “shrink lots until wallet matches.”
2. **Mongo redemptions** — already consumed lot balance in migration (`GIVEN.balance` / `deductible_balance`). **No re-FIFO for migrated redemption history.**
3. **New CRM redemptions / burns** — must consume `deductible_balance` FIFO on open earns (same as live chokepoint). If ledger rows exist but lots were not allocated, that is a fix target.
4. **Expiry (old CRM semantics)**
   - **Triggered expiry:** Member had a points **change** in Mongo after the earn’s expiry date → old CRM zeroed those lots and reduced wallet on that activity. **New CRM:** zero `deductible_balance` on those earns only; **do not** reduce wallet again.
   - **Inactive expiry:** Earn expired, no later Mongo points activity → old CRM never ran expiry. **New CRM:** zero those lots **and** reduce wallet (expiry burn on ledger + balance).
5. **Wallet** — built from headline Mongo balance at cutover, then **only** real events: New CRM earns/adjustments, New CRM redemptions/burns, inactive expiry burns, and corrections for documented gaps (missing migrated row, duplicate row). **Never** credit wallet to match lots.

---

## Where data lives

| What | Mongo | New CRM |
|------|--------|---------|
| Headline balance | `loyaltydb.contacts.pointBalance` | `user_wallet.points_balance` |
| Point ledger | `loyaltydb.points` (`type`: GIVEN, REDEEMED, …; `balance`, `expiredDate`, `createdAt`) | `wallet_ledger` (`mongo_id` = Mongo `_id` when migrated) |
| Receipts / purchases | `loyaltydb.receipts` | `purchase_ledger`, `purchase_receipt_upload` |
| Migration mirror (optional cross-check) | — | `stg_mongo_points` |

Member key: `user_accounts.mongo_id` ↔ Mongo `userId` on points / contact.

---

## Step 1 — Identify users

**Query:** Same as daily recon for migrated TTL — users where `points_balance` ≠ sum of `deductible_balance` on `currency = 'points'`, `transaction_type = 'earn'`.

**Known snapshot (2026-09-12):** 153 drift users (83 wallet > lots, 70 lots > wallet) of ~24.6k wallets.

**Deliverable:** One table (CSV or sheet tab) with:

- `user_id`, `mongo_id`
- `wallet`, `lots`, `delta` (= wallet − lots)
- `has_new_crm_points_activity` — any points `wallet_ledger` row with `mongo_id` IS NULL and `source_type` ≠ expiry

No other columns required for v1 list.

---

## Step 2 — Method to compute **correct** state (per user)

Work in order. Stop when a step explains the drift; still run the final check.

### A. Mongo baseline (frozen old CRM)

For the member’s Mongo `userId`:

1. Read `contacts.pointBalance` (expected wallet **before** New CRM-only events).
2. List `points` where `type = 'GIVEN'` and `balance > 0` — each row is an open lot in old CRM with amount and expiry (`expiredDate`).
3. Find **last Mongo points activity** — max `createdAt` on `type` IN (`GIVEN`, `REDEEMED`) (exclude pure expiry-type rows if present; use same rule as migrated ledger: non-expiry).

Apply **lot treatment on paper** (each GIVEN → one logical earn lot):

| Condition | Lot (`deductible_balance`) | Wallet |
|-----------|----------------------------|--------|
| Expiry date ≤ last Mongo activity day | **0** (already expired on that activity) | unchanged vs prior step |
| Expiry date > last Mongo activity and expiry &lt; today | **0** (inactive expiry) | reduce by that lot’s remaining balance |
| Otherwise | **Mongo `balance`** | unchanged |

Redemptions in Mongo: reflected in remaining `GIVEN.balance`; **no extra lot shrink**.

**Output A:** `wallet_after_mongo_rules`, list of lots with **target deductible** and **reason** per lot.

### B. Migrated rows on New CRM

Map each Mongo GIVEN `_id` to `wallet_ledger` earn by `mongo_id`.

- Compare **target deductible** (from A) to **current `deductible_balance`** per row.
- Flag missing earns (Mongo GIVEN with balance &gt; 0, no ledger row) and orphan ledger earns (no Mongo GIVEN).

Purchases/receipts: only needed when tracing **why** an earn exists or support asks; not required to close wallet/lot math if ledger + Mongo points agree.

### C. New CRM activity after cutover

Inspect existing points `wallet_ledger` rows with `mongo_id` IS NULL (not repair noise). For each row, derive what wallet and earn `deductible_balance` should be:

| Event | Wallet | Lots |
|-------|--------|------|
| Earn / adjustment (credit) | +amount | +new earn row or increase per row rules |
| Redeem / burn (non-expiry) | −amount | FIFO reduce `deductible_balance` on open earns |
| Expiry (inactive batch or single) | −amount | reduce/zero affected earns to match existing burn row |

**Do not call** chokepoint, expiry batch, or migration scripts. If a burn row exists, fix **earn** rows only unless the burn itself is missing (then **INSERT** burn + wallet adjustment).

**Output C:** `wallet_target`, per-earn `deductible_target`, list of **INSERT/UPDATE** on `wallet_ledger` / `user_wallet`.

### D. Consistency check

- `wallet_target` = Σ `deductible_target` over open earns.
- If not equal, the treatment is incomplete — do not force-balance; extend A–C (usually missing event or duplicate row).

---

## Step 3 — Compare to current data

For each user, one short diff:

| Field | Current | Target | Delta |
|-------|---------|--------|-------|
| Wallet | | | |
| Sum open lots | | | |
| Per earn (`ledger_id` / `mongo_id`) | deductible | deductible_target | reason if ≠ |

Optional: count of purchases only if earn trace needed for that user.

---

## Step 4 — Identify inserts / edits (proposal only)

From the diff, classify **actions** (no SQL in this phase):

| Action type | When |
|-------------|------|
| `UPDATE` earn `deductible_balance`, optionally `expiry_processed_at` | Lot reason = triggered expiry, inactive expiry, or FIFO should have run on New CRM redeem |
| `INSERT` expiry burn + wallet delta | Inactive expiry not posted on New CRM |
| `INSERT` / fix earn | Missing migrated GIVEN |
| `DELETE` or reverse duplicate | Extra earn not in Mongo and not a valid New CRM earn |
| `UPDATE` `user_wallet` | Only when ledger replay proves wallet wrong **after** all ledger rows are correct (rare if chokepoint was used) |

Each proposed change must cite **reason** (same vocabulary as Step 2). No row without a reason.

---

## Execution order (minimal)

1. Export **153-user list** (Step 1).
2. Pick **5 users** (mix of wallet&gt;lots and lots&gt;wallet; include at least one with New CRM activity).
3. For each of 5: run Step 2 A→D, Step 3, Step 4 → **one-page fix proposal**.
4. Review pattern across 5 → decide if bulk fixes are safe or all 153 stay manual.
5. Only then: approved SQL per user.

---

## Explicitly not doing

- Staging orphan remediation waves.
- `fn_ttl_points_repair_apply_step2` style “FIFO excess until wallet matches.”
- Merchant-wide repair without per-user replay.
- Forcing wallet = lots by one-sided adjustment.
- Full purchase backfill unless an earn gap requires it.

---

## References

- Expiry / cutover semantics: `bug-reports/20260902-points-historical-repair/Plan.md` (use **step 1 / step 3 logic**, not blind step 2 shrink).
- Recon metric: `docs/OPS_DAILY_RECON.md` (`balance_vs_lots` for Jorakay).
- Mongo fields: `loyaltydb.points`, `loyaltydb.contacts` (see `newcrm-migration-prompt.md` for loader intent).
