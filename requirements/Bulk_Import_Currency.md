# Bulk Import Currency

Additive CSV import of points and tickets into member wallets through validated batches and chunked async execution — not customer profile import.

Owner surfaces: Inngest worker (`inngest-bulk-import-currency-serve`); loyalty-admin ops UI (planned — `loyalty.ops.bulk_currency_import` in product catalog; no import route in repo as of 2026-09-17)

## Concept

Bulk import currency loads **wallet adjustments** for many members from a spreadsheet-shaped file. Each row identifies a member, a currency kind (points or tickets), and a signed adjustment intent (earn or burn). The platform treats the file as one **import batch**: validate the whole file before writing anything, then apply rows in fixed-size chunks so large migrations do not hit statement timeouts or edge time limits.

**Import batch** — A tracked job with row counts, status, validation errors, and progress metadata. Currency batches use the shared bulk-import batch store with a currency-specific type discriminator.

**CSV row** — One member adjustment: match key (phone or internal member id), currency kind, positive amount, optional component and transaction kind, optional ticket type for tickets, optional reason text.

**Validate-only pass** — Reads every row and runs the same checks as execution, but writes no ledger rows. Any row-level validation error fails the entire batch (no partial apply after validation failure).

**Execute pass** — Writes each valid row through the wallet **chokepoint** (locked balance update + ledger insert). Runs in chunks; chunk-level RPC failures abort the job; individual row failures inside a chunk are skipped and reported without aborting the chunk.

**Per-row dedup** — Each executed row gets a stable dedup key derived from batch id and global row index so Inngest retries do not double-post the same row, while multiple rows for the same member in one file remain allowed.

**Migration mode (`skip_emit`)** — Optional flag on the async job that suppresses chokepoint **outbox** emission (tier, mission, AMP, notification routers). Ledger rows still land; FIFO burn allocation and selected ledger triggers still run. Used for historical balance loads where downstream automation should not fire.

**Member match** — Rows resolve members by E.164 phone (`+…`) or by platform user UUID. Customer-import match fields (email, LINE, external id, member code) are not used on this path.

## Rules

- **Additive balance semantics** — Every row adds to or subtracts from the current balance via the chokepoint; import never replaces a wallet total. Burns use `transaction_type` burn with a positive amount; insufficient balance on burn → row skipped in execute pass, reported in errors, chunk continues.
- **Validation gate** — If any row fails validation in phase 1 → batch status `validation_failed`, `validation_errors` populated, no ledger writes for that batch.
- **Validation vs execute strictness** — Validation is all-or-nothing for the file. Execute tolerates per-row skips (dedup hit, burn insufficient balance, mid-run member missing) and still completes the batch when chunks finish unless the RPC throws.
- **Dedup** — With a batch id, dedup key pattern `bulk_{batch_id}_row_{global_index}`. Duplicate key on retry → row skipped (unique index on ledger dedup key). Without batch id, dedup keys are null and idempotency is weaker (not the normal admin path).
- **`skip_emit`** — When true on the Inngest event → RPC passes skip flag into chokepoint metadata → outbox emit skipped. Mission evaluation remains Inngest-driven from outbox when emit is on; wallet ledger triggers such as Shopify store-credit enqueue still run when applicable.
- **Row field rules** — `currency_type` is `points` or `tickets`. `amount` is a positive integer. Points rows must not carry `ticket_type_id`; ticket rows must. `component` defaults to adjustment (`base` | `bonus` | `adjustment`). `transaction_type` defaults to earn. Phone must be E.164 when used.
- **Batch status model** — `pending` → `processing` → terminal: `completed` | `validation_failed` | `failed`. Progress fields update in batch `metadata` during chunk loop (`processed_rows`, `succeeded_rows`, `skipped_rows`, `total_error_count`, `skip_emit`). Terminal `completed` may still list execute-pass errors (capped in metadata).
- **Error cap** — RPC returns up to `p_max_errors` (default 100) detailed errors per call; additional failures increment counts only.

Example: A file with 250 rows and `skip_emit: true` validates in one RPC call, then executes as three 100-row chunks (offsets 0, 100, 200). Row 42 fails burn for insufficient points → skipped, batch still `completed` with row 42 in execute error list.

## Journeys

### Admin journey

| Surface | Owning repo | Trigger / RPC |
| --- | --- | --- |
| Bulk currency import UI | loyalty-admin | (planned) — not shipped; product key `loyalty.ops.bulk_currency_import` |
| Ops / integration trigger | caller + Inngest | Insert batch (`import_type` currency, `pending`) → send `import/bulk-currency` with `batch_id`, `merchant_id`, `csv_data`, optional `skip_emit` |
| Batch worker | Supabase Edge | `inngest-bulk-import-currency-serve` → `bulk_import_currency` validate then chunked execute |
| Customer import wizard | loyalty-admin | **Out of scope** — see Customer_Import_System (profile upsert, not wallet rows) |

| Setting / knob | Effect on behaviour |
| --- | --- |
| `skip_emit: true` on Inngest event | Suppresses tier/mission/AMP/notification outbox for all rows in the batch |
| `skip_emit` false or omitted | Normal chokepoint outbox → routers (same as manual admin adjust when emit enabled) |
| Batch without `batch_id` on RPC | Weak dedup; avoid for production loads |
| CSV row `transaction_type` burn | Subtracts via chokepoint; row skipped if balance insufficient |
| CSV row `component` | Maps to wallet component bucket on ledger (base / bonus / adjustment) |

1. **Prepare CSV** — Columns align to row field rules (member key, currency type, amount, optional component, transaction type, ticket type id, reason). Member keys must exist in `user_accounts` for the merchant.
2. **Create batch record** — Insert into shared bulk import batches with `import_type` currency, status `pending`, file metadata and row count as needed for ops tracking.
3. **Start job** — Emit Inngest event `import/bulk-currency` with parsed row array in `csv_data`. Set `skip_emit` for migration loads that must not fan out automation.
4. **Monitor** — While `processing`, read batch `metadata` for chunk progress. On `validation_failed`, fix CSV using `validation_errors`. On `failed`, read `error_message` (worker/RPC exception). On `completed`, reconcile `processed_count`, `total_amount`, and optional `execute_errors` in metadata against expectations.
5. **Reconcile** — Spot-check `wallet_ledger` for batch `source_id` = batch id and dedup keys `bulk_{batch}_row_{n}`.

### Member journey

| Surface | Owning repo | BFF / RPC |
| --- | --- | --- |
| Wallet balance & history | loyalty-user (and admin Customer 360) | Standard wallet read paths; no import-specific screen |

1. Member does not participate in the import flow — no upload or consent step on member apps.
2. After execute pass, balance reflects new ledger rows (points/tickets components per row).
3. If `skip_emit` was false, member may receive normal earn/burn notifications and downstream effects (tier re-eval, missions, etc.) as for any wallet movement.
4. If `skip_emit` was true, balance and ledger history update without those automated side effects.

## System

### Data model

- **`bulk_import_batches`** — Shared batch header for customer, purchase, redemption, and currency imports. Currency jobs set `import_type = 'currency'`. Status, timestamps, `validation_errors`, `processed_count`, `total_amount`, `skipped_count`, `metadata` (chunk progress, `skip_emit`, execute error sample), `error_message` on worker failure. Columns such as `match_on`, `import_mode`, purchase counters are used by other import types; currency jobs rely primarily on status + metadata + counts above.
- **`wallet_ledger`** — Immutable movement rows written only via **`chokepoint_post_wallet_transaction`**. Batch id becomes ledger `source_id` when provided. Dedup key from trigger/helper using per-row bulk pattern when batch id present.
- **`user_accounts`** — Member resolution target for `tel` or `user_id` on each CSV row.

### Functions

- **`bulk_import_currency`** — Sole writer entry for this feature: validates or executes JSON row arrays with merchant id, optional batch id, validate-only flag, skip-emit flag, row offset for chunking, max error cap. Returns success/valid flags, counts, amounts, and error arrays. Each executed row calls **`chokepoint_post_wallet_transaction`** (wallet lock, signed amount, ledger insert, conditional outbox).
- **`chokepoint_post_wallet_transaction`** — Canonical wallet writer; import must not bypass it.
- **`fn_chokepoint_emit_event`** — Outbox writer; skipped when `_skip_emit` set in chokepoint metadata from import.

Customer-import helpers **`fn_bulk_import_match_user_id`** / **`fn_bulk_import_validate_member_code`** belong to Customer_Import_System, not this path.

### Flows

**Async path (production)**

```
Batch insert (import_type currency, pending)
  → Inngest import/bulk-currency { batch_id, merchant_id, csv_data, skip_emit? }
  → Edge inngest-bulk-import-currency-serve (Inngest app crm-bulk-import-currency, fn bulk-import-currency,
     idempotency batch_id, timeout 30m, retries 1, chunk size 100)
      → status processing
      → bulk_import_currency(p_validate_only := true) on full row set
      → if invalid: validation_failed + validation_errors, stop
      → for each chunk: bulk_import_currency(p_row_offset := chunkIndex * 100, p_skip_emit)
      → metadata progress per chunk
      → status completed (or failed on thrown error)
```

No Kafka on this path. Currency side effects when emit is on follow **chokepoint_event_outbox** → OutboxPublisher → **`inngest-event-router-serve`** → domain routers (e.g. **`inngest-currency-serve`**, mission routers) — same architecture as **`Currency.md`**.

**Sync path** — None for full files; RPC may be invoked directly for small tests but large files expect the Inngest worker.

### External services

- **Inngest** — Event `import/bulk-currency`; function registered on edge serve path `/functions/v1/inngest-bulk-import-currency-serve`.
- **Supabase Edge** — `inngest-bulk-import-currency-serve` (deployed; verify_jwt false — Inngest signing only).

### Known gaps

- **Admin UI** — No loyalty-admin page or BFF found that creates currency batches or sends the Inngest event; ops/integration must trigger manually until UI ships.
- **Event payload size** — Full `csv_data` is embedded in the Inngest event; validate ~10k-row files against Inngest size limits; if over limit, move CSV to Storage and pass a reference (not implemented).
- **Scale testing** — Chunked worker path verified in production fixes; largest cited single-path run 1,071 rows; 10k-row chunked run not yet recorded in ops notes.
- **Historical fix (2026-07-08)** — Prior worker bug skipped chunk loop and left batches stuck in `processing` with ledgers written; RPC v2 added validate-only, skip_emit, row offset, and per-row dedup keys. Reconcile stuck batches via ledger counts if needed.

### RPC contract (reference)

```
bulk_import_currency(
  p_rows jsonb,
  p_merchant_id uuid,
  p_batch_id uuid DEFAULT NULL,
  p_max_errors integer DEFAULT 100,
  p_validate_only boolean DEFAULT false,
  p_skip_emit boolean DEFAULT false,
  p_row_offset integer DEFAULT 0
) → success, valid, processed_count, skipped_count, total_amount,
  error_message, errors, total_error_count
```

Row JSON fields: `tel` (E.164) or `user_id` (uuid); `currency_type` (`points`|`tickets`); `amount` (positive int); optional `component`, `transaction_type`, `ticket_type_id`, `reason`.

## Related

- **Customer_Import_System.md** — Member profile upsert import; shares `bulk_import_batches` but different `import_type`, RPCs, and Inngest event.
- **Currency.md** — Wallet semantics, chokepoint, expiry, and outbox → Inngest award path for non-import writes.
- **Redemption_Import_System.md** — Separate bulk import for redemptions (`bulk_import_redemptions_chunk`).
- **Purchase_Import_System.md** — Purchase ledger import (`import_type` purchases).
