# Purchase Import System

Bulk CSV import of **historical purchases** and line items into the purchase ledger — grouped by transaction number, validated, then written through the purchase chokepoint with async earn side effects.

Owner surfaces: ops / integration (batch + Inngest event); worker `inngest-bulk-import-purchase-serve` (no loyalty-admin purchase-import UI in repo as of 2026-09-17)

## Concept

Purchase import backfills or migrates **completed purchase history** from a spreadsheet-shaped file. Each CSV row is one **line item**; rows that share the same merchant transaction number are folded into one **purchase header** with many lines. The platform tracks the job as an **import batch** (shared bulk-import batch store with `import_type` purchases).

**Flat CSV row** — One line item plus repeated header fields (`transaction_number`, dates, member key, amounts). The worker groups rows before insert.

**Purchase header** — A single commercial transaction (`transaction_number` unique per merchant) with totals, status, earn flags, and optional store reference.

**Line item** — SKU, quantities, unit price, and line total nested under its header.

**Member match** — Each header needs a platform `user_id`, or a `user_phone` (E.164) resolved to `user_accounts` for the merchant before insert.

**Product match** — Each line uses **`sku_code`** (not raw SKU UUID in the live worker); codes must exist in `product_sku_master`.

**Chunked execute** — After validation, purchases are inserted in fixed-size chunks (50 headers per step). Each chunk is one atomic chokepoint call; a failure mid-file can leave earlier chunks committed.

**Downstream earn** — Successful inserts use the same chokepoint path as live purchases: outbox → Inngest routers → currency / tier / mission processing when `earn_currency` and `processing_method` allow.

## Rules

- **Insert-only** — Import never updates an existing purchase; duplicate `transaction_number` for the merchant fails the chunk (and rolls back that chunk only).
- **Grouping** — All rows with the same `transaction_number` must agree on header fields taken from the first row seen; line fields vary per row.
- **Member validation** — After phone resolution, every header must have a `user_id` that exists on `user_accounts` for the merchant; otherwise the batch fails before any insert step.
- **SKU validation** — Unknown `sku_code` or unknown `store_code` (when provided) fails during grouping/resolution, before insert.
- **Batch status model** — `pending` → `processing` → `completed` | `failed`. There is no separate `validation_failed` status (unlike customer import).
- **Per-chunk atomicity** — `bulk_insert_purchases_with_items` delegates to **`chokepoint_post_purchase_event`** (`created`) for the chunk; one failed chunk does not roll back prior successful chunks in the same batch.
- **Idempotency** — Inngest function uses idempotency key `event.data.batch_id` (24h window). Retired duplicate listener `inngest-bulk-import-serve` was removed (see `docs/CRITICAL_BUG_FIXES.md`).
- **`processing_method`** — Default `queue` (async earn via outbox). Use `skip` for history with no earn; avoid `direct` on large loads (blocks on currency).
- **`earn_currency`** — Default true. CSV string `false` / `FALSE` disables earn for that header. Pair with `record_type` / `processing_method` for refunds or non-qualifying history.
- **`record_type`** — Default `credit` (normal purchase). `debit` for imported refunds when ops intentionally backfill returns.
- **`api_source`** — Always set to `bulk_import` on insert; completed headers get `completed_by_source` `system_bulk_import` when status is `completed`.
- **Event payload** — Production path expects parsed row objects on the Inngest event (`csv_data` array). Very large files may hit Inngest payload limits (see Known gaps).

Example: A file with 120 distinct transaction numbers runs as three insert steps (50 + 50 + 20). If step 3 fails on a duplicate `transaction_number`, steps 1–2 remain in `purchase_ledger`; batch status becomes `failed` with `error_message` from the failing step.

## Journeys

### Admin journey

| Surface | Owning repo | Trigger |
| --- | --- | --- |
| Purchase import UI | loyalty-admin | **Not shipped** — no route or BFF found for `import/bulk-purchases` |
| Customer import wizard | loyalty-admin | **Out of scope** — uses `import/bulk-customers` via `admin-user-import-kickoff` (does not handle purchases) |
| Batch worker | Supabase Edge | `inngest-bulk-import-purchase-serve` → Inngest app `crm-bulk-import-purchases`, function `bulk-import-purchases`, event `import/bulk-purchases` |
| Ops / integration | caller + Inngest | Create `bulk_import_batches` (`import_type` `purchases`, `pending`) → send `import/bulk-purchases` with `batch_id`, `merchant_id`, `csv_data` |

| Setting / knob | Effect on behaviour |
| --- | --- |
| `processing_method` `queue` (default) | Earn and tier/mission fan-out via chokepoint outbox (async) |
| `processing_method` `skip` | Ledger rows without currency pipeline |
| `earn_currency` false | Header stored; no currency award for that purchase |
| `record_type` `debit` | Refund-shaped header; use with ops care on earn reversal |
| `user_phone` vs `user_id` | Phone resolved to member UUID before validation; both empty → batch fails validation |
| `store_code` | Optional; resolved to `store_master.id`; invalid code fails before insert |

1. **Prepare CSV** — Flat rows: required `transaction_number`, `transaction_date`, `final_amount`, `sku_code`, `quantity` (or `quantity_primary`), `unit_price`, `line_total`; member via `user_id` or `user_phone`. Optional header/line discounts, tax, status, payment_status, `store_code`, `quantity_secondary`, `external_ref`, `notes`.
2. **Create batch** — Insert into `bulk_import_batches` with `import_type` `purchases`, `status` `pending`, file metadata and `total_rows` as needed.
3. **Start job** — POST Inngest event `import/bulk-purchases` with `batch_id`, `merchant_id`, and full `csv_data` row array (parsed JSON, lowercase headers if preprocessed client-side).
4. **Monitor** — Poll batch row: `processing` updates `metadata` (`processed_chunks`, `total_chunks`, `imported_purchases`, `imported_items`); terminal `completed` or `failed` with `error_message`.
5. **Reconcile** — Compare `imported_purchases` / `imported_items` to expectations; spot-check `purchase_ledger` by `transaction_number` and earn lag (batch `completed` before wallet updates).

### Member journey

None — back-office / migration only. Members see new history and balances after chokepoint downstream processing (typically seconds after each chunk commit).

## System

### Data model

- **`bulk_import_batches`** — Shared batch header (customer, currency, redemption, purchase). Purchase jobs set `import_type = 'purchases'`. Uses `status`, timestamps, `total_rows`, `imported_purchases`, `imported_items`, `error_message`, `metadata` (chunk progress), `batch_name`, `file_name`, `merchant_id`. Columns such as `match_on`, `import_mode`, `validation_errors` are primary on other import types; purchase path does not populate `validation_failed`.
- **`purchase_ledger`** — Header target; `transaction_number` unique per merchant; `batch_id` column exists for linkage but bulk chokepoint path may not set it on all rows — reconcile by `transaction_number` / import time if needed.
- **`purchase_items_ledger`** — Line items; `sku_id` FK from resolved `sku_code`.
- **`user_accounts`** — Member resolution (`user_id` or `tel` match).
- **`product_sku_master`** — `sku_code` → `id` lookup.
- **`store_master`** — Optional `store_code` → `id` per merchant.

### Functions

- **`bulk_insert_purchases_with_items`** — Normalizes JSON purchase array (nested `items`) and calls **`chokepoint_post_purchase_event`** (`created`, merchant, `{ rows: … }`). Returns `success`, `imported_purchases`, `imported_items`, `error_message`. Sole DB entry for import writes.
- **`chokepoint_post_purchase_event`** — Inserts headers/lines; emits purchase chokepoint events per **Purchase_Transaction.md**.
- **`fn_chokepoint_emit_event`** — Outbox rows for `crm.events.purchase` / `crm.events.purchase_item` when not suppressed.

Customer-import RPCs (`bff_admin_*`, `bulk_upsert_customers_from_import`) and **`admin-user-import-kickoff`** do not route purchase batches (kickoff only maps `customers` and `event_registrations`).

### Flows

**Async path (production)**

```
Insert bulk_import_batches (import_type purchases, pending)
  → Inngest import/bulk-purchases { batch_id, merchant_id, csv_data }
  → Edge inngest-bulk-import-purchase-serve
       (idempotency batch_id, timeout 30m, retries 1, CHUNK_SIZE 50)
      → status processing
      → resolve sku_code + store_code to UUIDs
      → group-by-transaction (flat rows → headers + items[])
      → resolve user_phone → user_id
      → validate all user_ids for merchant
      → for each chunk: bulk_insert_purchases_with_items
      → metadata progress per chunk
      → status completed (or failed on thrown error; prior chunks may persist)
```

**Downstream (per committed chunk)**

```
chokepoint_post_purchase_event (created)
  → chokepoint_event_outbox
  → OutboxPublisher → inngest-event-router-serve
  → currency / tier / mission routers (when earn_currency + processing_method allow)
```

**Retired / incorrect in older docs**

- Render service `crm-bulk-import` with `POST /api/import/purchases` and multipart upload — not present in local repos or Render registry; treat as legacy narrative.
- Single-step “atomic entire file” insert — replaced by 50-purchase chunks (deployed worker v73+).
- CSV column `sku_id` (UUID) as primary — live worker expects **`sku_code`**.
- Shared Inngest app `crm-bulk-import-system` for purchases — purchases use **`crm-bulk-import-purchases`** only.
- Function id `bulk-import-purchases-v2` in ops notes — deployed id is **`bulk-import-purchases`**.

### External services

- **Inngest** — Event `import/bulk-purchases`; serve path `/functions/v1/inngest-bulk-import-purchase-serve` (`verify_jwt` false; Inngest signing).
- **Supabase Edge** — `inngest-bulk-import-purchase-serve` (active).

### Known gaps

- **Admin UI** — No loyalty-admin page to create purchase batches or upload CSV; ops must insert batch + emit Inngest event (or build internal tooling).
- **Kickoff edge** — `admin-user-import-kickoff` does not support `import_type` purchases; do not assume parity with customer import.
- **Cross-chunk rollback** — No automatic compensating delete if chunk *N* fails after earlier chunks succeeded; ops must repair or re-run with dedup awareness.
- **Event payload size** — Full `csv_data` on the event; validate large migrations against Inngest limits; file-in-Storage reference pattern not implemented.
- **`batch_id` on ledger** — Column exists; bulk chokepoint payload may not stamp it — use batch metadata + `transaction_number` for audit unless a later migration wires it.
- **Historical duplicate edge** — `inngest-bulk-import-serve` deleted after double-fire incident; if auditing old batches, check ledger duplicates around fix date in `docs/CRITICAL_BUG_FIXES.md`.

### CSV contract (reference)

Flat file: one row per line item; repeat header columns per row sharing `transaction_number`.

| Column | Required | Notes |
| --- | --- | --- |
| `transaction_number` | Yes | Groups rows; unique per merchant |
| `transaction_date` | Yes | ISO8601 timestamp |
| `final_amount` | Yes | Header total (also drives `total_amount`) |
| `sku_code` | Yes | Resolved to `product_sku_master` |
| `quantity` or `quantity_primary` | Yes | Supports decimals |
| `unit_price` | Yes | |
| `line_total` | Yes | |
| `user_id` | Yes* | *Or `user_phone` (E.164) resolvable to member |
| `user_phone` | Alt | Used when `user_id` empty |
| `store_code` | No | Resolved to `store_master` |
| `discount_amount`, `tax_amount` | No | Header; default 0 |
| `item_discount_amount`, `item_tax_amount` | No | Line; default 0 |
| `quantity_secondary` | No | Line |
| `status`, `payment_status` | No | Default `completed` / `paid` |
| `record_type` | No | Default `credit` |
| `processing_method` | No | Default `queue` |
| `earn_currency` | No | Default true; string `false` disables |
| `transaction_source` | No | Default `admin` |
| `external_ref`, `notes` | No | |

Sample (two lines, one transaction):

```csv
transaction_number,transaction_date,user_id,final_amount,sku_code,quantity,unit_price,line_total,store_code
TXN001,2024-01-15T10:00:00Z,<user-uuid>,350.00,COFFEE-01,2,120.00,240.00,STORE001
TXN001,2024-01-15T10:00:00Z,<user-uuid>,350.00,TEA-01,1,110.00,110.00,STORE001
```

### RPC contract (reference)

```
bulk_insert_purchases_with_items(
  p_purchases jsonb,  -- array of { transaction_number, transaction_date, user_id, items: [...], ... }
  p_merchant_id uuid
) → success, imported_purchases, imported_items, error_message
```

### Comparison with customer import

| Aspect | Customer import | Purchase import |
| --- | --- | --- |
| Operation | Upsert members | Insert purchases + lines only |
| Inngest event | `import/bulk-customers` | `import/bulk-purchases` |
| Worker app | `crm-bulk-import-system` | `crm-bulk-import-purchases` |
| Validation status | `validation_failed` possible | Fails batch to `failed` (no separate status) |
| Primary RPC | Staging + `bulk_upsert_customers_from_import` / chunks | `bulk_insert_purchases_with_items` |
| Downstream | Optional postprocess flags | Purchase chokepoint → earn/tier/mission |
| Admin UI | loyalty-admin customer import | None in repo |

## Related

- **Purchase_Transaction.md** — Ledger model, chokepoint events, completion sources, earn path.
- **Customer_Import_System.md** — Shared `bulk_import_batches` table; different `import_type` and kickoff.
- **Bulk_Import_Currency.md** — Wallet bulk import (not purchase history).
- **Redemption_Import_System.md** — Separate bulk redemption pipeline.
- **docs/CRITICAL_BUG_FIXES.md** — Idempotency, chunking, retired duplicate purchase import edge.
