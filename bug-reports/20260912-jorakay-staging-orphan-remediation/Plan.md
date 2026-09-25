# Jorakay staging orphan remediation

## Purpose

During Jorakay cutover, many Old CRM rows were copied into **staging** but never written to New CRM product tables. **`user_wallet` still reflected Old CRM headline balances** while **open earn lots did not include those points**. The Sep **TTL historical repair** closed that gap with **“TTL historical repair wallet-only”** — a single wallet debit **not tied to specific lots or receipts**.

That line fixed the headline number **without establishing truth** (missing earns, receipt history, purchase links, or fair inactive expiry). Support cases (e.g. admin receipts visible in Old CRM but not New CRM, large unexplained debits) follow from that.

**This plan is a separate, one-off ops activity** — not the nightly migration job. **Whole merchant (jorakay)** — no single-member pilot. Goals:

1. **Undo lazy wallet-only repair** for the **classified migration-gap cohort** (everyone on that list in one approved run).
2. **Sub-migrate all orphan staging rows** into **receipt upload + purchase + wallet earn**, with **relations where IDs allow**, **without** triggering live earn/outbox or re-awarding points.
3. **Never increase `user_wallet` when inserting wallet earn rows** — wallet already includes those points; backfill adds **lots and audit trail**, not balance.
4. **Adjust expiry only on newly inserted earn lots** where rules require it. **Do not** re-run Sep merchant-wide TTL historical repair on members who already had it.
5. End with **wallet ≈ sum(open lots)** for almost all members; **explicit tail** for manual investigation.

---

## Execution order (merchant-wide)

1. **Reverse lazy TTL wallet-only** for all **migration-gap** members (Phase 1) — **before** any orphan insert.
2. **Sub-migrate all orphans** (Phase 2).
3. **Expiry on new earn rows only** from that insert batch (Phase 3).
4. **Verify** wallet vs open lots; document tail (Phase 4).

**Pause** `migration_merchant_status.sync_active` for jorakay for the full apply window.

---

## Scope

| In scope | Out of scope |
|----------|----------------|
| Merchant **jorakay** (`7522af2c-a7f6-4ab8-8493-6875a3b19544`) | Re-running full-merchant migration waves |
| **All** staging orphans (receipt upload, purchase, wallet earn) | Re-approving receipts or live purchase/earn APIs |
| Migration-gap **wallet-only reversal** list (classified pre-apply) | Blind reversal of every Sep repair line without classification |
| Batched SQL with row limits (technical), same rules every batch | Schema/RPC changes without separate approval |
| | **Re-running Sep merchant-wide TTL historical repair** |
| | **`api_create_purchase`**, **`chokepoint_post_wallet_transaction`**, outbox earn paths |

---

## Principles (non-negotiable)

### How orphans land (copy existing Jorakay historical shape)

Match **~73k migrated Jorakay purchases** — not **~2.8k live earns** (never write orphans like live chokepoint earns).

| Surface | Insert style |
|---------|----------------|
| **`purchase_ledger`** | Direct SQL. `earn_currency = false`, `skip_cdc = true`, `mongo_id`, `processing_method = skip`, `api_source = migration`. **No** `api_create_purchase`. |
| **`purchase_receipt_upload`** | Direct SQL; `mongo_id`; link to purchase when refs match. |
| **`wallet_ledger` (earn)** | Direct SQL from staging `GIVEN`; `mongo_id`; `skip_cdc = true`; **`user_wallet` not updated**. **No** `chokepoint_post_wallet_transaction`. |

1. **No outbox / no re-award** — verify no new outbox earn for backfilled keys.
2. **Earn backfill never updates `user_wallet`.**
3. **Orphans only** — `NOT EXISTS` on target product table per staging `mongo_id`.
4. **Bundle per slip** — upload + purchase (when staging has it) + earn; link where possible.
5. **Reverse lazy repair first** for migration-gap cohort — Phase 1 before Phase 2.
6. **Expiry = scoped ops on new inserts only** — no second Sep merchant-wide repair.

### Phase 1 reversal — **ledger + wallet**, lazy TTL lines gone

For each user on the migration-gap reversal list, undo **`TTL historical repair wallet-only`** in **one transaction**. **Both** are mandatory:

| Target | Requirement |
|--------|----------------|
| **`user_wallet`** | Increase **`points_balance`** by the total lazy repair burn being reversed (same points as the removed/neutralized ledger debits). |
| **`wallet_ledger`** | **Remove the lazy TTL effect** — the Sep **`TTL historical repair wallet-only`** burn row(s) for that user must **not** remain as a net deduction. Eng chooses **delete those rows** or **offsetting reversal row(s)** that fully neutralize them; either way, history + balance must agree and the lazy line must not stand alone as “correct.” |

**Not acceptable:** credit wallet only; offset ledger only; leave burn rows unchanged while fixing wallet.

**Scope:** only **`TTL historical repair wallet-only`** (and paired repair burns on the approved list) — not other Sep expiry work unless explicitly listed.

---

## Phases

### Phase 0 — Inventory and classification (read-only)

- Orphan counts: staging → missing `purchase_receipt_upload`, `purchase_ledger`, `wallet_ledger` earn.
- **Migration-gap reversal list:** wallet-only repair recipients where orphan staging given (and/or receipt-level evidence) supports undoing lazy line — exclude **legitimate inactive TTL** (no orphans; do not reverse).
- Signed counts + reversal list before any write.

**Gate:** Approved reversal list + orphan row counts.

---

### Phase 1 — Reverse lazy repair (whole migration-gap cohort)

For **every user on the approved list**, before Phase 2:

- **Wallet:** credit `points_balance` by lazy repair amount.
- **Ledger:** delete or fully neutralize **`TTL historical repair wallet-only`** row(s) for that user (see **Phase 1 reversal** above).
- **Do not** change existing **earn lots** in this phase.
- Expect **wallet > lots** until Phase 2–3 complete.

**Gate:** Sum of reversals matches sum of prior wallet-only burns on list; spot-check users.

---

### Phase 2 — Sub-migrate **all** orphans

Merchant-wide, batched for size — **direct SQL**, same rules as Principles:

1. Insert **purchase** from staging bills.
2. Insert **receipt upload**; link upload → purchase when refs align.
3. Insert **wallet earn**; link earn → purchase when order id matches; **`user_wallet` unchanged**.
4. Verify sample: flags match existing historical purchase; no outbox for backfilled keys.

**Gate:** Orphan counts → zero for targeted staging keys.

---

### Phase 3 — Expiry on **new rows only**

Only on earns inserted in Phase 2 (allowlist by `ledger_id` / `mongo_id` batch):

| Old CRM situation | Lot | Wallet |
|-------------------|-----|--------|
| Already expired (member had point activity after earn) | Zero `deductible_balance` on **new** line | No reduction |
| Should have expired (inactive) | Zero **new** line lot | Reduce wallet by same amount |

Targeted SQL or scoped ops helper — **not** Sep merchant-wide TTL repair re-run.

**Gate:** Merchant reconciliation report; tail list for remaining wallet ≠ lots.

---

### Phase 4 — Tail investigation

- Users still off after Phases 1–3 → owned tickets (duplicates, dual-run edge cases, misclassified reversal).
- No second lazy wallet-only sweep.

---

## Verification (after apply window)

- Wallet vs sum(open earn lots) — count mismatches.
- Orphan staging keys — zero remain.
- Reversal: per user, wallet credit = wallet-only burn reversed; ledger shows offsetting history.
- No live-path earns on backfilled `mongo_id`s.

---

## Risks

| Risk | Mitigation |
|------|------------|
| Ledger reversed but wallet not updated (or vice versa) | Single transaction; verify sums |
| Double wallet on earn insert | Never update `user_wallet` in Phase 2 |
| Re-award | Historical purchase flags; no API path |
| Wrong reversal cohort | Phase 0 classification |
| sync_active | Pause for full window |
| Balance spike after Phase 1 | Comms; complete Phase 2–3 promptly |

---

## Success criteria

- All orphans materialized with links where data allows.
- Migration-gap lazy repair reversed (**ledger + wallet**).
- Earn backfill did not touch `user_wallet`.
- Wallet ≈ open lots for ≥ agreed threshold; tail documented.

---

## Open decisions (before apply)

1. **Reversal mechanism** — delete lazy repair `wallet_ledger` row(s) vs offsetting reversal row(s); must be atomic with `user_wallet` credit.
2. **Migration-gap list rules** — threshold to include a user on Phase 1 reversal list.

---

## References (context only)

- `bug-reports/20260902-points-historical-repair/Plan.md`
- Lazy line description: `TTL historical repair wallet-only`
