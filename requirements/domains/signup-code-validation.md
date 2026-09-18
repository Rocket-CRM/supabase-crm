# Signup Code Validation

> Per-domain reference. Read ONLY when working on this domain. For the keyword → file map, see `_index.md`.

**Keywords:** signup code, external code, dealer code, corporate code, tax id, code claim, validate code, signup_codes, signup_code_claims, fn_consume_signup_code, bff_validate_signup_code, bff_upload_signup_codes, bff_list_signup_codes, bff_delete_signup_codes, external_code field type, persona-scoped signup, max_consumers, target_user_column

**Source:** Lives entirely in `requirements/Signup_Login.md` (sections 6–7) and this file. No standalone source doc.

## What this is

Persona-scoped, pre-uploaded code validation during signup. Admin uploads a CSV of valid codes per `external_code` field (e.g. dealer codes for dealer persona, company tax IDs for corporate persona). User entering signup form for that persona must enter and validate one of those codes; on profile save the code is atomically consumed and (optionally) denormalized into a typed column on `user_accounts`.

## Naming model (read this first)

The "pool" concept is **not a separate table**. A pool is the set of `signup_codes` rows attached to one `user_field_config` row of `field_type='external_code'`:

```
persona  ──(persona_ids[])──▶  user_field_config (= the pool)  ──(field_config_id)──▶  signup_codes  ──(code_id)──▶  signup_code_claims
```

So:

- "The pool" = a `user_field_config` row.
- "The codes in the pool" = `signup_codes` rows whose `field_config_id` points to that field.
- "Claim of one code by one user" = a `signup_code_claims` row.

Frontend should treat one `external_code` field as one pool. To list pools for an admin: `SELECT id, field_label, config FROM user_field_config WHERE merchant_id=$1 AND field_type='external_code'`.

## Tables

### `signup_codes`

| Column                     | Type                 | Notes                                                                              |
| -------------------------- | -------------------- | ---------------------------------------------------------------------------------- |
| `id`                       | uuid PK              | `gen_random_uuid()`                                                                |
| `merchant_id`              | uuid NOT NULL        | FK `merchant_master`, RLS isolation                                                |
| `field_config_id`          | uuid NOT NULL        | FK `user_field_config(id)` — must point to a row with `field_type='external_code'` |
| `code`                     | text NOT NULL        | Unique per `(field_config_id, code)`                                               |
| `metadata`                 | jsonb DEFAULT `'{}'` | Preview info shown after Validate **plus** prefill values that auto-fill the user's profile form. See "Metadata shape" below. |
| `max_consumers`            | int DEFAULT 1        | How many distinct users can claim this code (1 for one-time-use, N for shared)     |
| `consumed_count`           | int DEFAULT 0        | Atomic counter, capped via CHECK `consumed_count <= max_consumers`                 |
| `is_active`                | boolean DEFAULT true | Admin-controlled enable/disable                                                    |
| `created_at`, `updated_at` | timestamptz          | Standard, `trigger_set_updated_at`                                                 |

Indexes: `(merchant_id)`, `(field_config_id)`, `(field_config_id, code) WHERE is_active`. RLS: `merchant_isolation`.

### `signup_code_claims`

| Column        | Type                        | Notes                                                  |
| ------------- | --------------------------- | ------------------------------------------------------ |
| `id`          | uuid PK                     |                                                        |
| `merchant_id` | uuid NOT NULL               | RLS isolation                                          |
| `code_id`     | uuid NOT NULL               | FK `signup_codes(id)` — points to one code, not a pool |
| `user_id`     | uuid NOT NULL               | FK `user_accounts(id)`                                 |
| `claimed_at`  | timestamptz DEFAULT `now()` |                                                        |

Unique on `(code_id, user_id)` to block double-claim by same user. Indexes: `(merchant_id)`, `(user_id)`, `(code_id)`. RLS: `merchant_isolation`.

## Field config (extends existing `user_field_config`)

Admin sets `field_type = 'external_code'` on a `user_field_config` row. Per-field config goes in the existing `config jsonb` column:

```json
{
  "external_code": {
    "pool_label": "Dealer codes 2026",
    "max_consumers": 1,
    "target_user_column": "external_user_id",
    "prefill_schema": {
      "default": ["firstname", "external_user_id", "id_card"],
      "custom":  ["company_name", "department"]
    }
  }
}
```

| Key                  | Notes                                                                                                                                                                                                                                                                                                                                                                                          |
| -------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `pool_label`         | Admin-facing label shown above the code list. UI-only — not used by any RPC.                                                                                                                                                                                                                                                                                                                   |
| `max_consumers`      | Default cap when uploading new codes (per-code value can override). `1` = single-use codes, `N>1` = shareable codes, very large = effectively unlimited.                                                                                                                                                                                                                                       |
| `target_user_column` | If set, the consumed code is written to this column on `user_accounts`. Whitelisted: `external_user_id`, `member_code`, `id_card`. Other values are ignored.                                                                                                                                                                                                                                  |
| `prefill_schema`     | **Schema-on-pool.** Two arrays of `field_key`s declaring which default fields and which `USER_PROFILE` custom fields each code in this pool may prefill. Set via `bff_set_signup_code_prefill_schema`. Defaults to `{ default: [], custom: [] }` (no prefill allowed). Codes whose `metadata.prefill` includes any key not in this schema are rejected at upload with `KEY_NOT_IN_POOL_SCHEMA`. |

Persona scoping uses the existing `user_field_config.persona_ids[]` array — same as every other persona-scoped field. To give different personas different rules (e.g. corporate code with `max_consumers=50` vs dealer code with `max_consumers=1`), create separate `user_field_config` rows scoped to the respective `persona_ids[]`. There is no `(persona, pool)` cross table — different rules ⇒ different field configs.

`prefill_schema` keys are validated once at schema-set time against the pool's persona scope. After that, every code uploaded into the pool is guaranteed to target persona-compatible fields. Admin can pick from any default field (`user_field_config`, excluding other `external_code` fields and the pool itself) or any custom field on the merchant's `USER_PROFILE` form template, as long as `visible_to_user=true`, the field is not deleted/inactive, and persona scopes overlap.

## Metadata shape (preview + prefill)

`signup_codes.metadata` carries two distinct kinds of data per code, both optional:

```json
{
  "preview": {
    "company_name": "Acme Corp",
    "tier_label": "Gold dealer"
  },
  "prefill": {
    "default": {
      "firstname": "Acme",
      "external_user_id": "ACME-00123",
      "id_card": "1234567890123"
    },
    "custom": {
      "company_name": "Acme Corp",
      "department": "Sales"
    }
  }
}
```

| Block             | Purpose                                                                                                                                                                                                                                                                                                                                |
| ----------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `preview`         | Free-form jsonb shown on the FE after Validate succeeds (e.g. confirm the code belongs to "Acme Corp"). Not schema-validated. Returned as `data.preview_metadata`.                                                                                                                                                                     |
| `prefill.default` | Map of `user_field_config.field_key` → value. Keys must be in `pool.config.external_code.prefill_schema.default[]`. Upload rejects any key not in the schema. The FE seeds these into the corresponding default-field inputs after a successful Validate.                                                                              |
| `prefill.custom`  | Map of `form_fields.field_key` → value, scoped to the merchant's `USER_PROFILE` template. Keys must be in `pool.config.external_code.prefill_schema.custom[]`. Upload rejects any key not in the schema. The FE seeds these into custom-field inputs.                                                                                  |

**Why split `default` vs `custom`:** the same `field_key` can theoretically exist in both pools; the split makes the destination unambiguous and matches how `bff_save_user_profile` already routes default vs custom values.

**Schema-on-pool, not on each code.** The set of keys a code may prefill is declared once on the parent pool (`user_field_config.config.external_code.prefill_schema`) via `bff_set_signup_code_prefill_schema`, with persona/visibility/existence checks done at that step. Codes inherit a guaranteed-valid schema. The CSV import template, the Add-code form's input list, and the export template are all derived from this schema via `bff_get_signup_code_prefillable_fields`.

**FE auto-fill, not silent overwrite:** the FE seeds the form inputs from `data.prefill` after Validate; the user can review and override before Submit. `fn_consume_signup_code` does not re-stamp these values — submitted form values flow through `bff_save_user_profile` like any other user-entered values. The only column the consume path writes is the optional `target_user_column` (the consumed code itself, not metadata).

**Validation strictness:**

- **Schema-set time** (`bff_set_signup_code_prefill_schema`) — strict, hard-reject. All keys must exist, be `visible_to_user=true`, not deleted/inactive, and persona-overlap the pool. Returns `data.rejected[]` with per-key error codes if any key fails; entire schema is left unchanged.
- **Upload time** (`bff_upload_signup_codes`) — strict, hard-reject. Each code's prefill keys must be a subset of the pool's `prefill_schema`. Codes with off-schema keys are skipped with `KEY_NOT_IN_POOL_SCHEMA` in `data.errors[]`.
- **Validate time** (`bff_validate_signup_code`) — tolerant. If a field has been deleted/renamed/hidden between upload and signup, the offending key is silently dropped from `data.prefill` so user signup is never blocked by a stale code. Admin can detect drift by re-reading `bff_get_signup_code_prefillable_fields` for the pool.

## Functions

| Function                                                                                                                                          | Caller                                       | Auth                                               | Purpose                                                                                                                                                                                                                                                  |
| ------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------- | -------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `bff_validate_signup_code(p_field_key text, p_code text, p_selected_persona_id uuid DEFAULT NULL)`                                                | End-user (FE Validate button)                | `get_current_merchant_id()`, optional `auth.uid()` | Read-only validation. Returns `{valid, preview_metadata, prefill: {default, custom}, already_claimed, remaining_seats}` or structured error. `prefill.*` blocks contain only keys that still resolve against `user_field_config` / `USER_PROFILE.form_fields` for the merchant; deleted/renamed keys are silently dropped. Idempotent for already-claimed codes. |
| `fn_consume_signup_code(p_user_id uuid, p_field_config_id uuid, p_code text)`                                                                     | Internal (called by `bff_save_user_profile`) | `SECURITY DEFINER`                                 | Atomic consumption: persona check → race-safe `UPDATE ... WHERE consumed_count < max_consumers RETURNING ...` → insert claim → optional `target_user_column` write. Does **not** apply `metadata.prefill` — the FE seeded those values into the form payload, which `bff_save_user_profile` writes through its normal default/custom routing. Raises `SIGNUP_CODE:<code>:<msg>` on failure (rolls back caller's txn). |
| `bff_save_user_profile` (extended)                                                                                                                | End-user FE final submit                     | `auth.uid()`                                       | After `user_accounts` upsert, calls `fn_consume_signup_code` for each submitted `external_code` field. Catches `raise_exception` with `SIGNUP_CODE:` prefix and returns structured error. Whole txn rolls back on failure.                               |
| `bff_upload_signup_codes(p_field_config_id uuid, p_codes jsonb)`                                                                                  | Admin panel — used for both bulk import AND single Add/Edit (1-item array) | `check_admin_permission('form', 'create')`  | Bulk upsert. `p_codes = [{code, metadata?, max_consumers?, is_active?}]`. Each code's `metadata.prefill.{default,custom}` keys must be a subset of the pool's `prefill_schema`. Idempotent on `(field_config_id, code)`. Returns `{created, updated, skipped, errors}` where `errors` is a per-row, per-field array (`{row, code, error_code, scope, field_key, message}`). Rows with any prefill error are skipped (not partially saved). On re-upload, `max_consumers` is set to `GREATEST(new_value, consumed_count)` for safety. |
| `bff_list_signup_codes(p_field_config_id uuid, p_status text DEFAULT 'all', p_search text DEFAULT NULL, p_limit int DEFAULT 50, p_offset int DEFAULT 0)` | Admin panel                                  | `check_admin_permission('form', 'read')`    | Paginated list with claim status. `p_status` ∈ `all`, `available`, `consumed`, `inactive`. Returns each row (full `metadata` jsonb included, so admin UI can render preview + prefill blocks) plus `remaining_seats` and `last_claimed_at`. |
| `bff_delete_signup_codes(p_code_ids uuid[], p_hard_delete boolean DEFAULT false)`                                                                 | Admin panel                                  | `check_admin_permission('form', 'delete')`  | Soft delete (`is_active=false`) by default. Hard delete only allowed for `consumed_count = 0`; consumed codes are forced soft-delete. Returns `{soft_deleted, hard_deleted, blocked}`.                                                                   |
| `bff_set_signup_code_prefill_schema(p_field_config_id uuid, p_schema jsonb)`                                                                      | Admin "Configure pool" page                  | `check_admin_permission('form', 'edit')`    | Sets the pool's `config.external_code.prefill_schema`. `p_schema = { default: text[], custom: text[] }` of `field_key`s. Validates every key against `user_field_config` (default) / `form_fields` joined to `USER_PROFILE` template (custom): existence, persona overlap with the pool, `visible_to_user=true`, not deleted/inactive, not the pool itself, not another `external_code` field. On any rejection, the entire write is aborted and `data.rejected[]` lists per-key error codes. On success, returns `data.accepted = { default: [...], custom: [...] }`. |
| `bff_get_signup_code_prefillable_fields(p_field_config_id uuid)`                                                                                  | Admin pool-config + add-code + import + export-template flows | `check_admin_permission('form', 'read')`    | Returns `{pool, available, selected}`. `available.{default,custom}` lists all eligible fields the admin could put in the schema (full metadata: `field_key`, `field_label`, `field_type`, `is_required`, `persona_ids`, `options`, `help_text`, `placeholder`). `selected.{default,custom}` is the currently-configured schema with the same per-field metadata, in schema order — FE uses this to render Add/Edit form inputs and to generate CSV import/export templates. |

### Persona enforcement

Persona scoping is enforced in **two places**:

1. `bff_validate_signup_code` — checks the caller's effective persona (`p_selected_persona_id` or saved `user_accounts.persona_id`) against `user_field_config.persona_ids[]`. Returns `PERSONA_MISMATCH` on miss.
2. `fn_consume_signup_code` — re-checks the same condition at consume time, against `user_accounts.persona_id` for the user being saved. Raises `SIGNUP_CODE:PERSONA_MISMATCH:...`. This means a crafted save payload that bypasses the FE Validate step still cannot consume a code from a field outside the user's persona.

If a field has empty/null `persona_ids[]`, both checks are skipped — the field is universal.

## Error codes

### Validate / save path

`bff_validate_signup_code` and `bff_save_user_profile` both surface these in `data.error_code`:

| Code               | Meaning                                                              | Surfaced by validate? | Surfaced by save? |
| ------------------ | -------------------------------------------------------------------- | --------------------- | ----------------- |
| `EMPTY_CODE`       | User entered blank                                                   | Yes                   | No (would not enter consume path) |
| `FIELD_NOT_FOUND`  | No `external_code` field with that key for current merchant          | Yes                   | Yes               |
| `PERSONA_MISMATCH` | User's effective persona is not in `persona_ids[]` for that field    | Yes                   | Yes               |
| `INVALID_CODE`     | Code not in `signup_codes`                                           | Yes                   | Yes               |
| `CODE_INACTIVE`    | Code exists but `is_active=false`                                    | Yes                   | Yes               |
| `CODE_EXHAUSTED`   | `consumed_count >= max_consumers` and current user hasn't claimed it | Yes                   | Yes               |
| `NO_MERCHANT`      | No merchant context resolved                                         | Yes                   | n/a               |

### Schema-set path (`bff_set_signup_code_prefill_schema`)

On any rejected key, the entire write is aborted with `success=false`, `data.error_code = 'SCHEMA_INVALID'`, and `data.rejected[]` containing `{scope, field_key, error_code, message}`:

| Code                       | Scope             | Meaning                                                                                                                                                  |
| -------------------------- | ----------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `INVALID_PREFILL_KEY`      | `default`/`custom`| `field_key` does not exist in `user_field_config` (default) or in this merchant's `USER_PROFILE` template (custom)                                       |
| `PREFILL_FIELD_HIDDEN`     | `default`/`custom`| Field exists but `active_status=false` / `deleted_at IS NOT NULL` / `visible_to_user=false` — user wouldn't see the prefilled input                       |
| `PREFILL_PERSONA_MISMATCH` | `default`/`custom`| Pool has explicit `persona_ids[]`, the chosen field has explicit `persona_ids[]`, and the two arrays do not overlap                                       |
| `SELF_REFERENCE`           | `default`         | Admin tried to add the pool's own `external_code` field to its own prefill schema                                                                        |
| `UNSUPPORTED_FIELD_TYPE`   | `default`         | Admin tried to prefill another `external_code` field — codes consume their own field's seat, not another field's                                         |

Pool-level rejections also return `error_code` ∈ `FIELD_NOT_FOUND`, `WRONG_FIELD_TYPE`, `INVALID_SCHEMA_SHAPE` (when `p_schema` is not `{default: array, custom: array}`).

### Upload path (per-row, in `data.errors[]`)

`bff_upload_signup_codes` returns a `data.errors` array of `{row, code, error_code, scope, field_key, message}` objects. The row is skipped (counted in `data.skipped`) if any error fires for it.

| Code                       | Scope             | Meaning                                                                                                          |
| -------------------------- | ----------------- | ---------------------------------------------------------------------------------------------------------------- |
| `EMPTY_CODE`               | `null`            | Row's `code` is missing/blank                                                                                    |
| `KEY_NOT_IN_POOL_SCHEMA`   | `default`/`custom`| Code's `metadata.prefill.<scope>` contains a `field_key` that is not in the pool's `prefill_schema.<scope>[]`. Admin must add it via `bff_set_signup_code_prefill_schema` first. |

## Auth flow integration

**No changes to `bff-auth-complete`, `next_step`, or `form_step`.** The `external_code` field rides inside the existing `default_field` form step, after persona is selected. `bff-auth-complete` already returns persona-filtered `missing_data.default_fields_config` via `bff_get_user_profile_template`, which passes through `field_type='external_code'` and the `config` jsonb. The FE renders a Validate button when `field_type === 'external_code'` and gates Submit on validation success; the save-side re-validates and re-checks persona atomically as a race-safe fallback.

## Business rules

- **One code per row.** `signup_codes` holds one row per individual code. The "pool" is the field config that owns those rows, not a separate table.
- **Single-use vs shareable per code.** `max_consumers = 1` means single-use; `max_consumers > 1` means shareable up to that many distinct users. `config.external_code.max_consumers` on the field is just the upload default; per-row values can override.
- **Per-user uniqueness.** Same user cannot claim same code twice (unique on `(code_id, user_id)` in `signup_code_claims`).
- **Atomic consumption.** All consumption goes through `fn_consume_signup_code` which uses race-safe `UPDATE ... WHERE consumed_count < max_consumers RETURNING ...`.
- **Rollback on failure.** If consumption fails inside `bff_save_user_profile`, the entire profile save (including `user_accounts` insert for new users) rolls back.
- **Persona enforced on both validate and consume paths.** The save path cannot be bypassed by skipping the FE Validate.
- **Denormalization is opt-in.** Only the three whitelisted columns (`external_user_id`, `member_code`, `id_card`) accept the consumed code; any other `target_user_column` value is silently ignored to prevent SQL injection.
- **Persona scoping is on the field, not on the code.** Codes inherit persona scope from their `field_config_id`. Different personas with different rules ⇒ different field_config rows.
- **Validate is idempotent.** Already-claimed codes return `success=true, already_claimed=true` so users can re-validate without surprise.
- **Prefill is admin-authored, FE-applied.** `metadata.prefill.{default,custom}` is validated strictly at upload (rows with off-schema keys are skipped) and filtered tolerantly at validate (deleted/renamed keys are dropped from the response). The save path does not re-stamp prefill values; it writes whatever the user submitted via `bff_save_user_profile`.
- **Schema lives on the pool, values live on the codes.** The set of prefillable `field_key`s is declared once on the pool via `bff_set_signup_code_prefill_schema` and validated at that step. Codes inherit the schema; their `metadata.prefill` is just data. CSV import templates, manual-add form inputs, and export templates are all derived from `bff_get_signup_code_prefillable_fields` so admin always sees a fixed, deterministic shape per pool.
- **Field-key validation reuses the merchant's live config.** Default-field keys resolve against `user_field_config` (merchant-scoped); custom-field keys resolve against `form_fields` joined to `form_templates.code='USER_PROFILE'`. No new lookup tables.

---
