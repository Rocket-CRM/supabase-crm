# Syngenta Events

Field-event operations for the Syngenta deployment: one on-the-ground gathering with its own SKU list, attendee register, event-scoped orders, and optional bulk registration import. Not the generic promo engine in `Event_Promotion.md`.

Owner surfaces: loyalty-admin (Sales Events, imports, front line), member web app (event registration / survey QR), legacy on-device sales APIs

## Concept

A **field event** is a scheduled gathering (location, planned attendance, org tags) owned by a salesperson and optionally staffed by **coordinators**. The event carries a human **event code**, links to an optional **registration form**, and moves through an **open/close lifecycle** with optional geo stamps when sales opens or closes the day on site.

**Registration ledger** rows capture who registered or attended (walk-in, pre-register, form, or import). Attendee identity is stored as free text (name, phone, member id string); historical rows may not match a live loyalty account.

**Event product catalog** is a per-event list of SKUs with optional price overrides on top of master product prices, plus optional one-off custom lines without a master SKU.

**Participating retailers** are an optional allowlist of store locations used to narrow the retailer picker when staff create orders at the event. Empty allowlist means “any merchant store” in the UI.

**Event orders** are manual purchase transactions tagged to the event. Line items can be partially completed at create time or updated later; when the parent purchase completes, normal purchase earn rules run.

**Team role** is derived from email lists on the event (owner vs coordinator), not from a separate membership table. Platform superadmin bypasses team checks.

**Registration import** (admin) bulk-loads ledger rows from CSV via the shared user-import pipeline (validate → stage → Inngest chunks), keyed on phone match by default.

Distinction: **Event promotions** (`event_promo_*`) are a separate rules engine; Syngenta may use both field-event ops and promos, but this doc covers field events only.

## Rules

### Lifecycle (admin list)

| UI label | Condition |
| --- | --- |
| **Pending** | Not closed-done (see below) |
| **Closed / Done** | `opened` is not true **and** `closed_at` is set |

Open/close actions stamp `opened`, `opened_at`, `closed_at`, actor fields, and optional lat/lng JSON on the event row (browser geolocation best-effort on admin; legacy API accepts explicit coordinates).

### Team access

| Caller role | How resolved |
| --- | --- |
| **owner** | Admin JWT email (case-insensitive) ∈ event `owner_email[]` |
| **coordinator** | Email ∈ `coordinator_email[]` |
| **superadmin** | Platform superadmin flag on admin user |
| **none** | Everyone else |

| Operation | Required role |
| --- | --- |
| List/read team, products, orders, stores, attendee search | owner ∨ coordinator ∨ superadmin |
| Upsert products, upsert store allowlist | owner ∨ coordinator ∨ superadmin |
| Invite/remove coordinators | owner ∨ superadmin only |
| Owner invite as coordinator | Rejected (`already_owner`) |
| Remove coordinator | Does not remove owner |

Event-scoped BFFs return `FORBIDDEN` for non-team callers since 2026-05-14. `admin_get_my_events(p_include_all=true)` can list all merchant events for debugging but does not grant team-scoped drill-in.

### Catalog and pricing

- Effective unit price for an event line = event override when set, else master SKU price; custom lines (no master SKU) require an explicit event price.
- Product list upsert is full-list replace (insert/update/delete by row id).

### Store allowlist

- Empty allowlist → admin UI shows all merchant stores in the order retailer picker.
- Non-empty → admin UI must restrict picker to listed stores.
- Create-order API does **not** re-validate store against allowlist; any merchant store id is accepted server-side.

### Attendees and orders

- Create-order customer search only returns registration rows whose `member_id` text resolves to a non-deleted `user_accounts` row for the merchant (legacy non-UUID ids are excluded).
- Query minimum two characters; capped result count server-side.
- Orders are created with transaction source **event** and source id = event uuid; optional per-line `quantity_completed` / `status` at create; parent completes when all lines terminal → earn queue fires.
- Admin line completion override uses **absolute** completed quantities; blocked when parent already completed (use refund flow) or terminal.

### Registration import

- Validate CSV with `match_on: ['tel']` by default; duplicate phone keys in file → `DUPLICATE_MATCH_KEY` with row references.
- `import_mode: 'ongoing'` on start; processing via chunked worker (same Inngest app as customer bulk import).
- Template CSV requires single header row (machine keys); event must be selected and should have linked form/survey for field mapping where applicable.

### Legacy public APIs

- On-device / legacy clients may still call unauthenticated-style event open/close and booking writers by **event code** (merchant-scoped). Admin flows prefer JWT + BFFs.

## Journeys

### Admin journey

| Page / surface | Repo | Primary RPCs |
| --- | --- | --- |
| Sales Events (home list) | loyalty-admin | `admin_get_my_events` |
| Event detail — Manage / Orders / Products / Coordinators / Retailers | loyalty-admin | `get_event_with_stats`, `syngenta_event_action`, `bff_list_event_*`, `bff_upsert_event_*`, `bff_search_event_attendees`, `api_create_manual_purchase_order`, `bff_admin_set_event_order_item_completion` |
| Imports — New event registration import | loyalty-admin | `bff_admin_get_event_import_template_csv`, `bff_admin_validate_event_import_csv`, `bff_admin_start_event_registration_import`, shared user-import stage/run/progress |
| Front line — Register grower / rice survey | loyalty-admin | Member create/profile BFFs; bookings may write ledger via legacy `syngenta_event_booking` or forms |
| Event promos (separate menu) | loyalty-admin | `event_promo_*` BFFs — see `Event_Promotion.md` |

| Knob | Effect |
| --- | --- |
| Owner / coordinator emails on event | Who passes `fn_event_caller_role` for scoped tabs |
| Event product list | SKUs, overrides, sort, active flag for order lines |
| Store allowlist | Retailer picker scope on create order (FE only) |
| Open / close on Manage tab | Lifecycle + geo stamps |
| Linked `form_id` | Survey QR on overview; import field map |
| Registration import batch | Bulk ledger rows matched on tel |

1. **Sales Events** — Staff sees Pending vs Closed/Done filters; opens an event they own or coordinate.
2. **Manage** — Reviews stats/QR links; opens or closes the event (geo optional); registration QR points members to event registration page; survey QR when form linked.
3. **Products** — Builds event catalog (master picks + overrides); team-gated.
4. **Retailers** — Optional allowlist replace; team-gated.
5. **Coordinators** — Owner searches admins and invites/removes coordinators; coordinators cannot manage team.
6. **Orders** — Searches attendees with resolved accounts; creates manual PO against event catalog and retailer; tracks completion or uses admin line override until parent completes and earn runs.
7. **Imports** (ops with `user.create`) — Select event, download template, validate/upload CSV, monitor batch progress (not listed on imports hub until list RPC supports `event_registrations` type — open batch by id).

Frontline sales role lands on Sales Events with sidebar hidden; floating menu also exposes Register Grower and Rice Survey (`Admin_Panel.md`).

### Member journey

| Step | What the member sees |
| --- | --- |
| 1 | Scans event **registration QR** (or follows link with event code) → member web **event registration** flow |
| 2 | Optionally completes linked **survey form** from separate QR |
| 3 | Staff may register or book attendance on site (admin / legacy API) |
| 4 | When staff completes an event order tied to the member account, points/tickets follow normal purchase completion rules — no dedicated “my events” browser in core CRM |

Errors: unresolved account on staff order search simply omits legacy ledger rows; member-facing registration errors follow form/auth rules in `Signup_Login.md` / `Forms.md`.

## System

### Data model

**`syngenta_events_master`** — Event entity: merchant scope, `event_code`, name, schedule, owner/coordinator display names and **email arrays** (team source of truth), location labels + Thailand geo ids, planned attendance, BU/activity tags, lifecycle (`opened`, timestamps, actors), open/close geo JSON, `employee_code`, optional `form_id` → `form_templates`, `zip_code`, audit timestamps. Trigger: `set_updated_at_syngenta_events_master`.

**`syngenta_event_registration_ledger`** — Attendee rows: merchant, `event_id`, `event_code`, text `member_id` / name / tel, registered/attended flags and timestamps, `source`, `custom_data`, optional `form_submission_id`.

**`event_product_config`** — Per-event catalog lines: optional `sku_id` → `product_sku_master`, denormalized codes/names, optional override `price`, `is_active`, `sort_order`. Trigger: `set_updated_at`.

**`event_store_allowlist`** — `(event_id, store_id)` participating retailers; optional `added_by_admin_user_id`; cascade delete with event. Unique per pair. Metadata for FE scoping only.

**`v_syngenta_event_registrations`** — Read view over registration ledger for reporting joins.

**Legacy staging (import/history only):** `syngenta_bookings`, `syngenta_products`, `syngenta_no_tel_users` — not on live admin read path.

**Purchase linkage:** Event orders live in `purchase_ledger` / `purchase_items_ledger` with `transaction_source = 'event'` and `transaction_source_id = event.id`.

### Auth and roles

**`fn_event_caller_role(p_event_id)`** → `owner | coordinator | superadmin | none`: resolve `auth.uid()` to merchant `admin_users`, superadmin bypass, then case-insensitive email ∈ owner array, else coordinator array.

All event BFFs listed below consult this helper except where noted.

### Functions

**Listing and detail**

- `admin_get_my_events(p_include_all?)` — Events where caller email matches owner or coordinator arrays; optional include-all for admin visibility; rows include `my_role`, lifecycle, registration/attendance aggregates, form linkage.
- `get_event_with_stats(p_event_id?, p_event_code?)` — Event row + stats for admin detail header (used by Sales Events detail).
- `bff_get_event_details(p_event_code, p_language?)` — Single event by code; **merchant scope only — no team gate** (see Known gaps).

**Lifecycle and ledger (legacy + admin Manage tab)**

- `syngenta_event_action(p_event_code, p_action, lat?, lng?, p_action_by?)` — Open/close with geo.
- `syngenta_event_booking(...)` — Insert/update registration ledger row by event code.

**Products**

- `bff_list_event_products(p_event_id)` — Effective price `COALESCE(event, master)`; team gate.
- `bff_upsert_event_products(p_event_id, p_products jsonb)` — Full-list upsert; team gate.
- `bff_delete_event_product(p_product_id)` — Remove one config row; team gate.

**Attendees**

- `bff_search_event_attendees(p_event_id, p_query?, p_limit?)` — Ledger ⨝ `user_accounts` for order picker; team gate.

**Orders**

- `bff_list_event_orders`, `bff_get_event_order_stats`, `bff_get_event_order_details` — Event-scoped purchase reads; team gate; details include per-line completion fields.
- `bff_admin_set_event_order_item_completion(p_transaction_number, p_line_items)` — Absolute line completion override; team gate; chokepoint `item_completion_set`; rolls parent to completed when all lines terminal.
- **`api_create_manual_purchase_order`** — Creates event PO (`p_transaction_source = 'event'`, `p_transaction_source_id`); optional line completion at create; does not validate store allowlist.

**Team**

- `bff_list_event_team`, `bff_search_admin_users_for_event` (owner-only search), `bff_invite_event_coordinator`, `bff_remove_event_coordinator`.

**Retailers**

- `bff_list_event_stores`, `bff_search_admin_stores`, `bff_upsert_event_stores` — Full-list allowlist replace; team gate (coordinator manage since 2026-07-15).

**Registration import**

- `bff_admin_get_event_import_fields`, `bff_admin_get_event_import_template_csv`
- `bff_admin_validate_event_import_csv(p_event_id, p_csv, p_match_on?)`
- `bff_admin_start_event_registration_import(...)` — Creates batch; stages via shared user-import BFFs
- `fn_process_event_registration_import_row`, `process_event_registration_import_chunk(p_batch_id, p_chunk_size?)`
- Deprecated DB-only (do not call from FE): `bff_admin_kickoff_event_registration_import`, `bff_admin_resume_event_registration_import`

**Migration / ops**

- `fn_migration_validate_syngenta()` — Data migration checks.

### Flows

**Open/close (admin)** — Manage tab → `syngenta_event_action` with browser geo → updates master lifecycle columns.

**Registration capture** — Member QR → loyalty-user event registration page; or form submission linked on ledger row; or legacy `syngenta_event_booking`; or bulk import row processor writing ledger.

**Create order** — Orders tab → attendee search BFF → manual PO API with event source, event catalog lines, seller admin id, store id (allowlist enforced in FE only) → pending or completed parent depending on line completion → completion updates via admin BFF or initial create payload → parent `completed` triggers purchase earn pipeline (`Purchase_Transaction.md` / chokepoint).

**Bulk registration import** — Wizard validate → start batch → stage rows (`bff_admin_stage_user_import_rows`) → run (`bff_admin_run_user_import`) → edge `admin-user-import-kickoff` → Inngest `inngest-bulk-import-customers-serve` event `import/bulk-event-registrations` → `process_event_registration_import_chunk` loops until batch done.

### External services

- **Inngest** — `inngest-bulk-import-customers-serve` processes event registration chunks (shared worker with customer import).
- **Edge** — `admin-user-import-kickoff` emits bulk import events after staging.
- **Member web app** — Hosted pages `event-registration` and `survey` linked from admin QR (merchant subdomain).

### Known gaps

- **`bff_get_event_details`** has no team gate — only merchant scope; admin detail uses `get_event_with_stats` instead.
- **Store allowlist** is not enforced on `api_create_manual_purchase_order`.
- **Promos tab component** exists under choose-events in loyalty-admin but is not mounted on Event detail; promos are configured via separate Event Promos admin (`Event_Promotion.md`).
- **Imports hub list** may not show event registration batches until list RPC supports `import_type = event_registrations`; batch detail by id works.
- **Legacy ledger `member_id` text** — rows without resolvable `user_accounts` cannot be selected for new orders.

## Related

- **Event_Promotion.md** — Promo engine (`event_promo_*`), optional alongside field events.
- **Order_Booking.md** / **Purchase_Transaction.md** — Manual PO API, line completion, earn on complete.
- **Customer_Import_System.md** — Shared staging, kickoff, and Inngest worker patterns for registration import.
- **Store_Attribute_Classification.md** — `store_master` for retailer search and allowlist.
- **Forms.md** — `form_id` on event, survey capture, import field maps.
- **Admin_Panel.md** — Frontline sales role, default landing on Sales Events.
