# Customer Import

> Supplements `Customer_Import_System.md` (architecture / CSV / Inngest). This file holds address + acquisition_source addenda only.

## User address on import

Bulk customer import (`bulk_upsert_customers_from_import`) and event registration import share the same address upsert path.

### Storage convention (matches signup / `bff_save_user_profile`)

| Column | Meaning | Example |
|--------|---------|---------|
| `city` | Province **code** | `40` |
| `district` | District **code** | `4019` |
| `subdistrict` | Subdistrict **code** | `401905` |
| `province_code`, `district_code`, `subdistrict_code` | Same codes (mirrored) | |
| `state` | Unused for Thai geo (NULL) | |

Never persist Thai geo **names** in `user_address` text columns.

### Functions

- **`fn_resolve_user_address_for_import(p_row jsonb)`** — Reads explicit codes or names from import row keys; calls `fn_resolve_th_address_codes`; validates against `address_th_*`. Returns `{ ok, has_geo, province_code, district_code, subdistrict_code }`. All-or-nothing: if any supplied geo level fails to resolve, `ok = false`.
- **`fn_upsert_user_address_from_import(p_user_id, p_merchant_id, p_row)`** — On `ok`: writes codes to `city`/`district`/`subdistrict` and `*_code`, clears `state`. On unresolved geo: clears geo columns, keeps `addressline_*` / `postcode`. Lines-only: updates lines/postcode without touching geo.
- **`bulk_upsert_customers_from_import`** — Delegates address writes to `fn_upsert_user_address_from_import`.

### Backfill (2026-06-16)

Historical rows backfilled in phases: full-code sync (A), name→code resolve (B), clear unresolvable geo (C), partial-code sync (A2).

## Event registration import — acquisition source

When event registration import creates or updates a user via `bulk_upsert_customers_from_import`, `user_accounts.acquisition_source` is set to the batch **event code** (`field_selection.event_code`).

- **`process_event_registration_import_chunk`** — stamps each upsert row with `acquisition_source = event_code`; passes `default_acquisition_source` in import options.
- **`fn_process_event_registration_import_row`** — same for the single-row path.
- **`bulk_upsert_customers_from_import`** — reads `acquisition_source` / `user_accounts_acquisition_source` from the row, or falls back to `p_options.default_acquisition_source`. On create, value flows through `chokepoint_post_user_event`. On update, sets `acquisition_source` only when currently NULL (chokepoint rule).

Does not overwrite an existing non-null `acquisition_source` on matched users.
