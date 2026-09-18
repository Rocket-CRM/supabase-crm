# Customer CSV Export

Async export of filtered member rows to CSV. Reuses `bulk_import_batches` with `import_type = 'users_export'`.

## Flow

1. **Admin FE** — export wizard calls `bff_admin_start_user_export(p_batch_name, p_field_keys, p_filters)` → inserts batch (`status = pending`) and enqueues Inngest event `export/users-csv`.
2. **Inngest** — `admin-user-export-csv` edge function (`crm-user-export` app) runs `export-users-csv`:
   - **init** — guard `pending`, set `processing`, `total_rows` via `fn_user_export_count`
   - **chunk-N** — `process_user_export_chunk(batch, offset, 1000)` → upload part to Storage `exports/<merchant>/<batch>/parts/N.csv`, bump `processed_count`. Skipped when `total_rows = 0`.
   - **finalize** — concat uploaded parts + UTF-8 BOM header (human labels from `fn_user_export_field_labels`), upload final CSV, 7-day signed URL → `metadata.download_url`, `status = completed`. Zero-row jobs write a header-only CSV (no part download). Missing Storage parts (400/404 / empty message) are skipped. `onFailure` marks the batch `failed`.
3. **Admin FE** — polls `bff_admin_get_user_import_progress(p_batch_id)` every 3s; shows Download when `metadata.download_url` is set. Page title uses `batch_name` from the batch row.

## Central tracking (`/imports` hub, 2026-07-05)

Export batches are listable next to imports via `bff_admin_list_user_imports(p_type text DEFAULT 'users')` — `'users'` (default, imports only, legacy behavior), `'users_export'`, or `'all'`; invalid values → `INVALID_TYPE`. Each row now includes `import_type` so the FE can badge Import vs Export and route to the export-aware detail variant. `bff_admin_get_user_import_progress` works unchanged for export batches (no `import_type` restriction; returns `batch_name` + `import_type` + `metadata.download_url`); import-only fields (`row_status_counts`, `error_sample`) come back empty. Cancel/rollback/rows/errors are import-only concepts — do not offer them on export batches.

## Batch row contract (`bulk_import_batches`)

| Field | Role |
|---|---|
| `import_type` | `users_export` |
| `field_selection.field_keys` | Selected export columns |
| `metadata.filters` | AND-combined filter payload (see below) |
| `metadata.download_url` | 7-day signed URL when ready |
| `total_rows` / `processed_count` | Progress bar |
| `status` | `pending` → `processing` → `completed` \| `failed` |

## Filters (`metadata.filters`)

Keys omitted when empty; all present keys are AND-combined:

- `user_type` — `buyer` \| `seller`
- `persona_ids` — `uuid[]`
- `tier_ids` — `uuid[]`
- `is_active` — boolean
- `has_wallet_balance` — boolean (points balance > 0)
- `created_from` / `created_to` — `YYYY-MM-DD` (inclusive date range on `user_accounts.created_at`)

Soft-deleted users (`deleted_at IS NOT NULL`) are excluded.

## Source mode (`metadata.source`, 2026-07-05)

Optional server-resolved user-set restriction, AND-combined with `metadata.filters`. Callers pass a small descriptor via `bff_admin_start_user_export(p_source jsonb DEFAULT NULL)` — never user-ID lists. Compiled into SQL by `fn_user_export_source_sql(p_merchant_id, p_source, p_snapshot_at)`; consumed by both `fn_user_export_count` and `process_user_export_chunk`.

| `type` | Keys | User set |
|---|---|---|
| `audience` | `audience_id` | `amp_audience_member` where `entered_at <= snapshot_at AND (exited_at IS NULL OR exited_at > snapshot_at)`; merchant-scoped via `amp_audience_master` |
| `workflow` | `workflow_id` | Distinct `workflow_log.user_id` for the workflow, `created_at <= snapshot_at` |
| `workflow_node` | `workflow_id`, `node_id` | Distinct users with `event_type IN ('node_executed','action_executed')` on the node, `created_at <= snapshot_at` (matches node-stats `unique_passed`) |
| `condition` | `groups[]`, `groups_operator` | Compiled per group via `fn_amp_compile_condition_group`, combined INTERSECT (`and`) / UNION (`or`); evaluated live at export time — point-in-time drift vs the preview count is accepted v1 behavior |

`metadata.snapshot_at` is stamped `now()` by the BFF when a source is present; it time-bounds the audience/workflow sources so OFFSET/LIMIT chunking stays consistent while workflows keep running. The BFF validates tenancy (audience/workflow belongs to merchant; node belongs to workflow) and rejects unknown types (`INVALID_SOURCE` / `SOURCE_NOT_FOUND`). Permission stays `user.export` for all sources. No source → identical behavior to plain filtered export.

## Field keys (v1)

Same catalog as import: `bff_admin_get_importable_fields` groups — `user_accounts_*`, `user_address_*` (latest address by `created_at`), `user_wallet_points_balance`, tier lock fields, `user_profile_*`, `form_<CODE>_*` (latest completed submission per user).

CSV headers use **field labels** (not raw keys).

## Functions

| Function | Purpose |
|---|---|
| `bff_admin_start_user_export` | Permission `user.export`; insert batch; `fn_emit_inngest_event('export/users-csv', …)`; optional `p_source` (see Source mode) |
| `fn_user_export_source_sql` | Compiles `metadata.source` into an AND-clause against `ua` (audience / workflow / workflow_node / condition) |
| `fn_emit_inngest_event` | pg_net POST to `https://inn.gs/e/<vault inngest_event_key>` |
| `fn_user_export_count` | Filtered row count for `total_rows` |
| `process_user_export_chunk` | Paginated row fetch (`ORDER BY ua.id`, OFFSET/LIMIT) |
| `fn_user_export_field_labels` | Header label map for selected keys |

## Edge function

| Slug | Inngest app | Function | Event |
|---|---|---|---|
| `admin-user-export-csv` | `crm-user-export` | `export-users-csv` | `export/users-csv` |

`verify_jwt: false` — Inngest signing key auth (same pattern as `inngest-bulk-import-customers-serve`).

## Storage

Private bucket `exports`. Final path: `<merchant_id>/<batch_id>/<file_name>`.

## Ops — Inngest trigger from DB

Vault secret **`inngest_event_key`** must exist (same value as Supabase edge env `INNGEST_EVENT_KEY`). Without it, `fn_emit_inngest_event` logs a warning and returns NULL; batches stay `pending` until re-kicked.

Re-kick a stuck batch:

```sql
SELECT fn_emit_inngest_event(
  'export/users-csv',
  jsonb_build_object('batch_id', '<uuid>', 'merchant_id', '<merchant_uuid>')
);
```

Register/sync the Inngest app against `https://<project>.supabase.co/functions/v1/admin-user-export-csv` after first deploy.

## Phase 5 (later)

`bff_admin_get_exportable_fields` superset catalog + FE picker — account/lifecycle, resolved tier/persona names, multi-currency balances, tags, consent, referral, aggregates.
