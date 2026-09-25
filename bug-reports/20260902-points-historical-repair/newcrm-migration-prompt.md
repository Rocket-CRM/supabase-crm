# newcrm-migration — points cutover changes (paste into a thread in the `newcrm-migration` repo)

Prevent recurrence of the **Her Hyness** and **Jorakay** wallet/lot failures. These are two different bugs; the migration project needs changes for both.

## What went wrong (two cases)

| Case | Symptom | Root cause | Migration fix |
|---|---|---|---|
| **Her Hyness** | Lots too low, wallet too high (`wallet >> lots`) | Remigrate zeroed `deductible_balance` for all past-expiry earns at load — destroyed FIFO/expiry information | **Never** zero expired lots in `wave-4a`; audit and remove any such logic if present |
| **Jorakay / Kovet** | `wallet ≠ lots`, or wallet = lots but both include points old CRM never expired; 457 holds after messy cutover | Loader faithfully copied inconsistent Mongo (`pointBalance` vs per-lot `balance`), then went live **without** running the 3-step reconcile at cutover | **Add** a cutover-only wave that runs steps 1–3 (including **step 3 wallet deduction** for inactive-member expiry) |

Step 3 is the case you asked about: members whose lots passed `expiry_date` after their last old-CRM earn/redeem. Old CRM never triggered expiry; `pointBalance` still includes those points. At cutover, NewCRM must burn them from the wallet (backdated, no LINE). That logic already exists in Supabase as `fn_ttl_points_repair_apply_step3` — the migration project must **invoke it at cutover**, not bake it into daily sync.

## What stays the same (dual-run / daily sync)

While `sync_active = true`, old CRM is truth:

- `wave-4a-points-old.sql` — keep copying `GIVEN.balance` → `deductible_balance`; ON CONFLICT keeps overwriting both. Do **not** stop the deductible overwrite (that breaks genuine old-CRM redemptions during dual-run).
- `wave-4f-wallet-balances.sql` — keep `pointBalance + native_delta`. Do **not** force `wallet = sum(lots)`.

Reconciliation during daily sync gets overwritten or double-counts. It runs **once**, after the last sync.

## What to add / change in this repo

### 1. New SQL: `src/migration/sql/wave-cutover-points-reconcile.sql`

Cutover-only. **Not** part of nightly transform. Operator runs manually after `sync_active = false`.

Prerequisites (enforce in comments at top):
- Merchant `points_expiry_mode` is `ttl` or `fixed_frequency` (not `none`)
- Points frozen in old CRM; NewCRM not writing points yet
- `migration_merchant_status.sync_active = false` for this merchant
- Supabase functions deployed: `fn_ttl_points_repair_build_manifest`, `fn_ttl_points_repair_apply_step1/2/3` (migration `20260902100000_ttl_points_historical_repair.sql` on `wkevmsedchftztoolkmi`)

Script body (merchant-scoped via `migration.scope_merchant` GUC or a documented `merchant_uuid` param):

```sql
-- 1) Build manifest (classify + hold gate)
SELECT fn_ttl_points_repair_build_manifest('<merchant_uuid>'::uuid);

-- 2) Dry-run steps 1 → 2 → 3 (p_dry_run := true); inspect summary

-- 3) Live apply in batches until each step returns 0:
--    fn_ttl_points_repair_apply_step1(run_id, 500, false)
--    fn_ttl_points_repair_apply_step2(run_id, 500, false)
--    fn_ttl_points_repair_apply_step3(run_id, 200, false)  -- wallet deduction lives here

-- 4) Verify: wallet = sum(deductible_balance) per user except unresolved holds
```

Reference implementation: `supabase-crm/bug-reports/20260902-points-historical-repair/apply-track-a-kovet.sql` and `Plan.md`.

Do **not** call `fn_hh_repair_*` (Her Hyness-only).

### 2. New doc: `docs/POINTS_CUTOVER.md` (or follow existing runbook location)

Five-step cutover procedure:

1. Freeze points in old CRM (no `GIVEN` / `REDEEMED`). NewCRM must not write points.
2. Run one final daily sync.
3. `UPDATE migration_merchant_status SET sync_active = false WHERE merchant_uuid = '<uuid>';`
4. Run `wave-cutover-points-reconcile.sql` (steps 1–3 above). Product must sign off `users_wallet_down` / `total_wallet_down_pts` from the manifest before live apply.
5. Go live for points in NewCRM. **Never** set `sync_active` back to true.

Going live before step 4 → Jorakay-style holds (`later_newcrm`, `mongo_sync_gap`). Reconciling before step 2 → next sync overwrites.

Link to full runbook: `supabase-crm/bug-reports/20260902-points-historical-repair/Plan.md` (hold gate, Track B for held users).

### 3. Header comments on existing waves

**`wave-4a-points-old.sql`** — add at top:
- Copies Mongo lots faithfully; `wallet ≠ sum(lots)` after 4a+4f is **expected** for TTL merchants during dual-run.
- Do **not** zero `deductible_balance` for `expiry_date < today` here (Her Hyness mistake).
- Reconciliation: `docs/POINTS_CUTOVER.md` → `wave-cutover-points-reconcile.sql`.

**`wave-4f-wallet-balances.sql`** — add at top:
- Wallet = `pointBalance` (what customer saw in old CRM), not `sum(lots)`.
- Cutover reconcile adjusts lots and burns inactive expiry from wallet; see `docs/POINTS_CUTOVER.md`.

**`finalize-run.ts`** — comment on `sync_active = true`: starts dual-run mirror; turned off manually at points cutover (step 3 of `POINTS_CUTOVER.md`); not re-enabled after reconcile.

### 4. Audit (read-only first, then fix if found)

Search `src/migration/sql/` and `src/migration/steps/` for anything that:
- Sets `deductible_balance = 0` based only on `expiry_date < today` (HH remigrate pattern)
- Forces `points_balance = sum(deductible_balance)`
- Runs reconcile logic inside the nightly transform loop

Report findings. Remove HH-style zeroing if present.

### 5. Optional: daily-sync guard

If the nightly runner can target a merchant with `sync_active = false`, add a skip + log when `sync_active = false` OR when `ttl_points_repair_run.status = 'complete'` exists for that merchant — prevents accidental re-sync after cutover.

## Out of scope for this repo

- Deploying `fn_ttl_points_repair_*` (lives in `supabase-crm` migrations — already on prod for Jorakay)
- Gating `currency-expiry-daily` on `sync_active` (Supabase / Render — separate ticket; prevents double-burn during dual-run)
- Track B hold resolution SQL (operator runbook in `supabase-crm`)

## Acceptance

- [ ] `wave-cutover-points-reconcile.sql` exists and documents step 3 wallet burns
- [ ] `docs/POINTS_CUTOVER.md` exists with the 5-step procedure
- [ ] 4a / 4f / finalize-run comments added
- [ ] No HH-style lot zeroing in loader SQL
- [ ] Daily sync cannot silently re-run on a cutover-complete merchant (if runner supports it)

Commit in this repo only. Do not push unless I say so.
