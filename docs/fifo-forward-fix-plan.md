# FIFO Lot Tracking — Wallet Drift and Expiry Plan

**Scope:** Prevent new wallet ↔ lot drift, make nightly expiry fault-tolerant, and record mismatches for later repair. Historical reconciliation and pre-cutover expiry backfill remain separate work.

## Accepted decisions

These replace the earlier “strict failure for everyone” and “one transaction for the whole merchant” choices.

1. **Expiry mismatch policy:** If expiring lots exceed the wallet, leave that member unchanged, write one open row to `wallet_reconciliation_issue`, and continue. Never clamp 540 to 326.
2. **Normal-burn policy:** Historical `wallet > allocatable lots` may spend. Allocate as many lots as exist. Permit an unallocated remainder only when it does not exceed the pre-existing shortfall and the shortfall does not grow. Clean members stay strict because their shortfall is zero.
3. **Orchestration:** Render Cron Job `currency-expiry-daily` (repo `Rocket-CRM/crm-event-processors`, same one-shot pattern as `tier-daily-batch`) repeatedly calls one bounded PostgreSQL RPC. Not an Edge Function, and not inside the always-on `crm-event-processors` worker.
4. **Batch size:** 1,000 wallet groups per transaction, one worker. Tune from staging measurements.
5. **Catch-up:** `expiry_date >= cutover_date AND expiry_date <= run_date`, oldest first. Default cutover is **2026-08-31** (FIFO forward-fix night). Pre-cutover backlog stays excluded. Late runs keep the lot’s original expiry date.
6. **Timezone:** `Asia/Bangkok`. Cron schedule remains `0 19 * * *` UTC (02:00 ICT).
7. **Issue table:** Exception/audit state only. One open row per member/currency/type/date. No queue consumer.

## Intended invariants

- `deductible_balance` is the remaining usable amount on an earn lot.
- `expired_amount` records only points actually removed by expiry.
- A non-expiry burn reduces the wallet and matching earn lots atomically.
- Points lots are fungible within `(user_id, merchant_id, currency)`.
- Ticket lots are fungible only within `(user_id, merchant_id, currency, target_entity_id)`.
- Expiry mutates selected earn lots directly, then posts one wallet audit burn that does not run FIFO again.
- `chokepoint_post_wallet_transaction` remains the only canonical wallet writer.
- Render only orchestrates; it does not write wallet rows.

## Target flow

```text
Render currency-expiry-daily
  → loop process_currency_expiry_batch(run_date, cutover_date, 1000)
      → lock up to 1,000 wallet groups (FOR UPDATE SKIP LOCKED)
      → valid (due <= wallet): zero lots, post expiry burn, commit
      → mismatch (due > wallet): unchanged, upsert issue, commit
      → until has_more = false

chokepoint_post_wallet_transaction (non-expiry burn)
  → lock wallet and validate balance
  → measure pre-existing shortfall
  → allocate matching earn lots
  → allow unallocated remainder only if shortfall does not increase
  → update wallet, insert burn, emit event
```

## Objects

| Object | Role |
|---|---|
| `wallet_reconciliation_issue` | Durable mismatch log |
| `util.fn_allocate_fifo_burn` | Internal lot allocator; returns unallocated remainder |
| `util.fn_allocatable_lot_balance` | Internal live-lot sum |
| `util.fn_upsert_wallet_reconciliation_issue` | Internal issue upsert |
| `process_currency_expiry_batch` | One bounded batch transaction |
| `process_expiry_if_needed` | Procedure: loop+commit until done (pg_cron bridge until Render is verified) |
| `currency-expiry-daily` | Render Cron Job orchestrator |

## Out of scope

- Repairing queued historical cases (including Her Hyness) under a business policy.
- Processing lots with `expiry_date < 2026-08-31`.
- Reconstructing missed expiry audit history.
- Unrelated wallet-versus-ledger-net discrepancies.

## Success criteria

- [ ] Valid members expire even when another member is mismatched.
- [ ] Mismatched members are unchanged and appear once in `wallet_reconciliation_issue`.
- [ ] Clean-data burns allocate FIFO lots atomically.
- [ ] Wallet-greater-than-lot burns succeed without increasing shortfall.
- [ ] Ticket burns isolate by `target_entity_id`.
- [ ] Expiry burns do not re-run FIFO.
- [ ] Post-cutover missed dates catch up on the next run.
- [ ] pg_cron is retired after the Render job is verified.
