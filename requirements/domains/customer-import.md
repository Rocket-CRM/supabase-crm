# Customer Import / Export

> Per-domain reference. Read ONLY when working on this domain. For the keyword → file map, see `_index.md`.

**Keywords:** customer import, user import, bulk import, bulk upload, migration, csv import, csv export, user_import_staging, bulk_import_batches, bulk_upsert_customers_from_import, process_user_import_chunk, allow_bulk_import, skip_cdc, skip_side_effects, app.skip_side_effects, app.import_batch_id, ongoing import, migration mode, field selection, user_io_schemas, two-row header

**Source:** Lives entirely in this file (no standalone source doc).

## What this is

Asynchronous bulk customer import + CSV export for both ongoing operational use and one-off migrations from external CRMs. Generalises across `user_accounts`, `user_address`, `user_wallet` (target balance), `user_accounts.tier_id`, USER_PROFILE custom fields, **and** any other form whose `form_templates.allow_bulk_import = true`.

Architecture: CSV upload (loyalty-admin → `bff_admin_stage_user_import_rows`) → `user_import_staging` → kickoff Edge `admin-user-import-kickoff` emits `import/bulk-customers` → Inngest app `crm-bulk-import-system` on `inngest-bulk-import-customers-serve` calls `process_user_import_chunk` repeatedly (default 250 rows/chunk) through `bulk_upsert_customers_from_import`. Progress on `bulk_import_batches`. Export is separate: `bff_admin_start_user_export` → Inngest app `crm-user-export` on Edge `admin-user-export-csv` (`export/users-csv`).

## Two import modes

| Mode | Use | CDC | Trigger side-effects | Per-row tier_progress | Initial tier_change_ledger | Mission enqueue |
|---|---|---|---|---|---|---|
| `ongoing` | Day-to-day merchant uploads | published | fire normally | created by trigger | created by trigger | enqueued |
| `migration` | Bulk migration from another CRM (10k–1M+ rows) | suppressed (`skip_cdc=true`) | suppressed via `app.skip_side_effects=true` | **skipped during write**, optionally backfilled in batch | **skipped entirely** unless explicitly opted in | suppressed; optional batch backfill |

## CSV contract (the format export and re-import share)

### Two-row header

| Row | Purpose | Read by importer? |
|---|---|---|
| Row 1 | Machine keys (`user_accounts_firstname`, `user_profile_company_name`, `form_DEALER_SURVEY_company_size`, …) | Yes — this **is** the field mapping |
| Row 2 | Human labels ("First name", "Company name", …) | Skipped (importer drops any row whose first cell does not match `^(user_accounts|user_address|user_wallet|user_profile|form)_`) |

### Column-key prefixes

| Prefix | Destination |
|---|---|
| `user_accounts_<col>` | `user_accounts` table |
| `user_address_<col>` | `user_address` table (keyed `(user_id, merchant_id)`) |
| `user_wallet_points_balance` | wallet target balance (idempotent via `fn_import_wallet_balance`) |
| `user_profile_<field_key>` | USER_PROFILE form custom field — **alias kept for backward compatibility** |
| `form_<form_code>_<field_key>` | Any form whose `form_templates.code = <form_code>`, `status='published'`, `allow_bulk_import=true` |

### Address fields — name vs code

`user_address` stores province, district, and subdistrict as **both** a free-text name (`state`, `district`, `subdistrict`) AND a numeric code (`province_code`, `district_code`, `subdistrict_code`) sourced from the Thai address master tables `address_th_province` / `address_th_district` / `address_th_subdistrict`. Both are surfaced in the importable-fields picker:

| Key | Stored in | Notes |
|---|---|---|
| `user_address_state` | `state` | Province name in TH or EN. Stored verbatim |
| `user_address_province_code` | `province_code` | 2-digit `address_th_province.id` (e.g. `10` = Bangkok). Wins over name when both supplied |
| `user_address_district` | `district` | District name in TH or EN. Stored verbatim |
| `user_address_district_code` | `district_code` | 4-digit `address_th_district.id` (e.g. `1016`). Wins over name when both supplied |
| `user_address_subdistrict` | `subdistrict` | Subdistrict name in TH or EN. Stored verbatim |
| `user_address_subdistrict_code` | `subdistrict_code` | 6-digit `address_th_subdistrict.id` (e.g. `101601`). Wins over name when both supplied |

**Best-effort name → code resolution:** when only a name is supplied (no code), the importer looks the code up in the master tables (case-insensitive on EN, exact on TH). District lookup is scoped to the resolved province when available; subdistrict lookup is scoped to the resolved district. If no match is found, the name is still stored and the corresponding `*_code` column is left NULL — the row is **not** rejected. This means CSVs from systems that only carry names continue to work; CSVs that already carry codes (recommended) are passed through verbatim.

### Cell encoding

| Field type | Storage column | CSV cell |
|---|---|---|
| `text`, `free_text`, `email`, `phone`, `tel`, `normal`, `number`, `date`, `rating`, `select`, `single_select`, `external_code` | `text_value` | Plain string. Date = `DD-MM-YYYY` |
| `multi-select` (or any array field) | `array_value` (`text[]`) | Pipe-delimited — `gym\|yoga\|running`. If a value contains `\|`, JSON-encode the whole cell — `["a\|b","c"]` |
| Object / `object_schema` | `object_value` (`jsonb`) | JSON-encoded — `{"size":"L"}` |
| Boolean | (column-dependent) | `true` / `false` / `1` / `0` / `yes` / `no` (case-insensitive) |
| UUID | (column-dependent) | Standard UUID format |
| Null sentinel | n/a | empty cell **or** literal `-` |

The importer accepts both `option_value` and `option_label` for select / multi-select fields and resolves to `option_value` for storage. Exports write `option_label` for human readability.

## Match keys (dedup)

`bulk_import_batches.match_on text[]` controls which user-identifying columns are tried in priority order. Default: `ARRAY['tel']`. Whitelisted: `tel`, `line_id`, `email`, `external_user_id`, `member_code`, `mongo_id`. Migration mode typically picks `external_user_id` or `member_code` — whatever the source system used as a stable ID.

A row must populate at least one configured match key, otherwise it stages with `row_status='invalid'` and `row_errors` includes `NO_MATCH_KEY` (message names the expected CSV column).

`bff_admin_start_user_import` validates `match_on` against `field_selection` at batch-creation time: every key in `match_on` must have a matching column (`user_accounts_<key>` or bare `<key>`) in the field selection. Mismatch returns `MATCH_KEY_NOT_IN_TEMPLATE` with the missing keys and the expected CSV column names — the batch is **not** created. Empty `match_on` returns `NO_MATCH_KEY_CONFIGURED`. This stops the silent fail-at-stage-time pattern where a CSV without the match-key column would invalidate every row.

## Tables

### `bulk_import_batches` (extended)

Existing generic batches table; this feature adds:

| Column | Type | Purpose |
|---|---|---|
| `import_mode` | text (`ongoing` \| `migration`) | Drives `skip_cdc` and `app.skip_side_effects` GUC |
| `match_on` | text[] | Dedup-key priority order |
| `field_selection` | jsonb | Snapshot of the chosen field schema for this import (or export) |
| `chunk_size` | int default 250 | Rows per Inngest chunk call |
| `last_processed_row_num` | bigint | Resumability cursor into `user_import_staging` |
| `failed_count` | int | Per-batch failed-row count |
| `skipped_count` | int | Per-batch skipped-row count |
| `file_url` | text | Storage URL of the uploaded CSV (for re-download) |

`import_type='users'` for imports, `import_type='users_export'` for exports.

### `user_import_staging`

| Column | Type | Notes |
|---|---|---|
| `row_num` | bigserial PK | global row number |
| `batch_id` | uuid FK `bulk_import_batches(id) ON DELETE CASCADE` | |
| `merchant_id` | uuid FK | RLS isolation |
| `csv_row_num` | int | 1-based row number from CSV (excluding header rows) |
| `row_data` | jsonb | The CSV row keyed by machine keys |
| `row_status` | text | `pending` \| `valid` \| `invalid` \| `processing` \| `imported` \| `updated` \| `skipped` \| `failed` |
| `row_errors` | jsonb | Per-row validation/processing errors |
| `matched_user_id` | uuid | Populated after upsert |
| `processed_at` | timestamptz | |
| `created_at` | timestamptz | |

Indexed on `(batch_id, row_status, row_num)` for chunked draining and on `(merchant_id)`. RLS: `merchant_isolation`.

### `user_io_schemas`

Saved field-selection presets (used by both import wizard "Save template" and export wizard "Use template"). `(merchant_id, lower(name))` is unique. RLS: `merchant_isolation`.

### `form_templates.allow_bulk_import boolean default false`

Per-form opt-in. `USER_PROFILE` is auto-set to `true` for existing rows (its primary purpose is to be filled in). Other forms must be explicitly enabled by the merchant in the Forms admin UI before they appear in the import field-picker.

## Functions

| Function | Caller | Auth | Purpose |
|---|---|---|---|
| `bff_admin_get_importable_fields()` | Admin field picker | `user.read` (implicit via SECURITY DEFINER + RLS) | Returns `{default_fields, address_fields, wallet_fields, forms[]}` for the picker UI. Forms list includes only published forms with `allow_bulk_import=true` (USER_PROFILE always included) |
| `bff_admin_get_user_import_template_csv(p_field_keys text[])` | Admin "Download template" | merchant context | Returns `{csv}` — a CSV string with two-row header (machine keys + labels) for the selected fields |
| `bff_admin_save_import_schema(p_id, p_name, p_description, p_field_selection)` | Admin save preset | `user.create` | Upsert a saved schema |
| `bff_admin_list_import_schemas()` | Admin load preset | merchant context | Lists merchant's schemas |
| `bff_admin_delete_import_schema(p_id)` | Admin | `user.delete` | Deletes a schema |
| `bff_admin_start_user_import(p_batch_name, p_file_name, p_import_mode, p_match_on, p_field_selection, p_metadata, p_chunk_size, p_file_url)` | loyalty-admin wizard after CSV parse | `user.create` | Creates a `bulk_import_batches` row (status `validating`, `import_type='users'`); returns `batch_id` |
| `bff_admin_stage_user_import_rows(p_batch_id, p_rows jsonb)` | loyalty-admin (FE chunks of 500) | `user.create` | Inserts rows into `user_import_staging`, runs format validation per row, sets `row_status='valid'` or `'invalid'` with `row_errors` populated |
| `bff_admin_run_user_import(p_batch_id)` | FE "Start import" CTA | `user.create` | Flips status from `validating` → `pending`. The Inngest worker is event-triggered separately (FE / edge function emits `import/bulk-customers` event with `{batch_id, postprocess_options}`) |
| `bff_admin_get_user_import_progress(p_batch_id)` | FE poll (every 2s while active) | `user.read` | Returns `{status, total_rows, processed_count, imported_users, failed_count, started_at, completed_at, metadata, error_sample, row_status_counts}` |
| `bff_admin_list_user_imports(p_limit, p_offset, p_status, p_mode, p_from, p_to)` | FE history page | `user.read` | Paginated `bulk_import_batches WHERE import_type='users'` |
| `bff_admin_cancel_user_import(p_batch_id)` | FE cancel | `user.create` | Flips status to `cancelled`; Inngest worker exits at next chunk boundary |
| `bff_admin_rollback_user_import(p_batch_id)` | FE rollback (migration only) | `user.delete` | Deletes `user_accounts` rows that this batch inserted (cascades clean wallet, form_submissions, etc.). Does NOT undo updates to existing users |
| `bff_admin_run_user_import_postprocess(p_batch_id, p_options jsonb)` | FE post-migration step | `user.create` | Runs opt-in backfills: `tier_progress`, `fn_auto_assign_on_persona`, mission re-eval enqueue |
| `bff_admin_start_user_export(p_batch_name, p_field_keys, p_filters)` | FE export wizard | `user.export` | Creates an export batch (`import_type='users_export'`) for the Inngest worker to stream to Storage |
| `bulk_upsert_customers_from_import(p_rows jsonb, p_merchant_id, p_create_wallet_ledger_entry, p_batch_id, p_max_errors, p_options jsonb)` | Internal — called by `process_user_import_chunk` | merchant context | Two-pass: validates entire chunk first; only commits if zero errors. `p_options` carries `match_on`, `skip_side_effects` (sets the GUC for this transaction), `skip_cdc` (sets row column), `default_form_code` (default `USER_PROFILE`) |
| `process_user_import_chunk(p_batch_id, p_chunk_size)` | Internal — called by Inngest worker | merchant context | Drains the next chunk of `valid` rows from staging using `FOR UPDATE SKIP LOCKED`, calls `bulk_upsert_customers_from_import`, updates per-row + per-batch progress. Idempotent. |
| `process_user_import_postprocess(p_batch_id, p_options)` | Internal | merchant context | Runs the migration backfills |
| `fn_import_wallet_balance(p_user_id, p_merchant_id, p_target_balance, p_batch_id)` | Existing — called from inside the upsert | n/a | Idempotent target balance: earns up or burn-adjusts to match |

## Trigger guards (migration safety)

When `current_setting('app.skip_side_effects', true) = 'true'` (set by `bulk_upsert_customers_from_import` for migration-mode chunks), the following triggers early-return:

| Trigger | Without guard fires | Skipped during migration |
|---|---|---|
| `assign_entry_tier_on_signup` | overwrites `NEW.tier_id` with merchant entry tier | **Bug-fix:** now only assigns when `NEW.tier_id IS NULL`, irrespective of GUC. Migration-imported tier IDs are preserved |
| `after_user_signup_tier_setup` | inserts `tier_progress` + `tier_change_ledger` per user | yes |
| `trigger_auto_assign_on_persona_change` | `fn_auto_assign_on_persona` + `process_tier_event` | yes |
| `queue_mission_evaluation_batch` | enqueues mission_evaluation_queue rows | yes |
| `trigger_mission_evaluation_realtime` | synchronous mission re-eval per wallet write | yes |
| `fn_sync_user_type_from_persona` | overwrites `NEW.user_type` from persona group | yes — imported `user_type` wins |

Migration mode also writes `skip_cdc=true` on every row inserted/updated in the four CDC-published tables (`user_accounts`, `wallet_ledger`, `form_submissions`, `tier_change_ledger`), so the logical-replication publisher does not emit per-row events.

`app.import_batch_id` is also set as a session GUC for downstream traceability if any future trigger or function wants to know "this write came from a bulk import, batch X".

## Post-migration backfills (opt-in via `bff_admin_run_user_import_postprocess`)

```
{
  "backfill_tier_progress": true,    // recommended ON; single bulk INSERT, very cheap
  "grant_persona_benefits": false,   // calls fn_auto_assign_on_persona per user
  "enqueue_mission_eval":   false    // queues one mission eval per migrated user (NOT per wallet event)
}
```

## Error codes

Errors surface in `bulk_import_batches.validation_errors[]` (sample, capped at 100) and in `user_import_staging.row_errors[]` (per row). Shape: `{row, error_code, field_key?, scope?, message}`.

| Code | Where | Meaning |
|---|---|---|
| `NO_MATCH_KEY_CONFIGURED` | start | `match_on` was empty or NULL — at least one match key is required |
| `MATCH_KEY_NOT_IN_TEMPLATE` | start | `match_on` contains a key whose column (`user_accounts_<key>` or bare `<key>`) is not in `field_selection`. Returns `data.missing_match_keys`, `data.field_selection`, `data.match_on` for the FE to surface |
| `NO_MATCH_KEY` | stage / upsert | Row didn't supply any value for the configured `match_on` keys |
| `INVALID_TEL` | stage / upsert | Phone present but not in `+CC...` format |
| `INVALID_USER_TYPE` | upsert | `user_accounts_user_type` not in (`buyer`, `seller`) |
| `INVALID_UUID` | stage / upsert | persona_id / tier_id is not a UUID |
| `INVALID_DATE` | stage / upsert | birth_date not `DD-MM-YYYY` |
| `INVALID_POINTS` | stage / upsert | points balance non-integer or negative |
| `FORM_NOT_IMPORTABLE` | upsert | `form_<code>_*` references a form that's not published or `allow_bulk_import=false` for the merchant |
| `PROCESSING_ERROR` | upsert | Caught exception during the row's commit pass; `message` carries `SQLERRM` |

## Permissions

Existing `user` resource (no new permission resource):

| Action | Required for |
|---|---|
| `user.create` | Start an import, stage rows, run, cancel, save schemas, run postprocess |
| `user.read` | List imports, poll progress |
| `user.export` | Start an export |
| `user.delete` | Delete a saved schema, rollback a migration batch |

## Business rules

- **Two-pass validation** — `bulk_upsert_customers_from_import` validates the entire chunk first; if any row in the chunk has a validation error, no rows in that chunk are committed. (Per-row format validation also already happened earlier at stage-in time via `bff_admin_stage_user_import_rows`.)
- **Idempotent points** — `fn_import_wallet_balance` sets the target balance via earn or burn-adjustment based on diff against current balance. Re-running an import with the same value is a no-op for the wallet.
- **Idempotent batch ID** — Inngest function uses `idempotency: "event.data.batch_id"`, so re-emitting the event won't double-process. Within a chunk, `FOR UPDATE SKIP LOCKED` lets multiple worker instances coexist.
- **Default field upsert** — `user_accounts`, `user_address`, `user_wallet`, `tier_id`. Each import row that matches an existing user via the configured `match_on` priority **updates** that user (per-column `COALESCE(EXCLUDED, existing)` so empty cells never null-out existing data); rows with no match **insert** a new user. Exactly one `user_address` row exists per `(user_id, merchant_id)` and is upserted in place. Wallet balance is set idempotently to the target via `fn_import_wallet_balance`.
- **Form submission semantics — every import run creates a fresh submission.** For each (form, user) pair where the row carries data, the import always **inserts** a new `form_submissions` row with `source='bulk_import'`, `status='completed'`, `submitted_at=NOW()`, `source_id=batch_id`, and `submission_number='IMPORT-<batch_id>-<csv_row>'`. `form_responses` for that submission are inserted fresh — never updated. Re-imports therefore preserve full history (one submission per import per user×form), which the Forms admin UI surfaces ordered by `created_at DESC`. The earlier "one bulk submission per user×form" unique index has been dropped (`idx_form_submissions_form_user_bulk_uniq`) and replaced by a non-unique chronological index. For `USER_PROFILE`, the import still flips `user_accounts.is_signup_form_complete=true` whenever any field is written.
- **`USER_PROFILE` is always importable**, regardless of `allow_bulk_import`. Other forms require explicit per-merchant opt-in.
- **Rollback is migration-only and insert-only** — `bff_admin_rollback_user_import` deletes `user_accounts` rows the batch inserted (cascades to wallet/forms). Updates to pre-existing users are not reversible automatically.
- **Survey reward triggers** — bulk-imported `form_submissions` carry `source='bulk_import'`; downstream reward/AMP logic should treat `bulk_import` as exempt from triggering rewards. (Today's mission eval triggers respect the GUC; survey reward worker should also check `source` if it doesn't already.)
- **CDC publication** is suppressed only in migration mode. Ongoing-mode imports publish events normally.

## Out of scope

- `auth.users` shadow account creation (imported users can't log in until they sign up themselves; `user_accounts.auth_user_id` is set to the user's own id as a placeholder, matching existing convention).
- **Province / district / subdistrict cross-validation:** the importer best-effort-resolves codes from names but does NOT enforce that the supplied province / district / subdistrict codes are internally consistent (e.g. that the supplied subdistrict_code actually rolls up to the supplied district_code). Inconsistent triplets are stored verbatim. A future enhancement may add cross-validation behind a flag.
- PDPA consent capture (bulk import bypasses signup-form consent).
- Diff preview before commit ("this user's tier will go from Silver→Gold").
- Selective CDC (cannot suppress CDC for some tables in a batch but publish for others).

---
