# Activity Attribution

Unified **activity log** (CDP-style events), **marketing campaign** identifier resolution, and **purchase attribution** ROI — distinct from activity-based earning uploads (`Activity_Based_Earning.md`).

Owner surfaces: loyalty-admin (activity types, campaigns, reports, Customer 360), Open API (`api_log_user_activity`)

## Concept

Activity attribution is the merchant’s **event stream plus marketing math**: every meaningful member touch is logged with typed properties and campaign keys; purchases stay on the purchase ledger but can be **split across campaigns** for ROI using a merchant-wide attribution model.

**Activity type** — Catalog entry (platform-standard or merchant-custom) that defines which property keys are allowed on events of that type.

**Activity property field** — Typed schema row scoped to one activity type; values live in the event’s property bag and can surface in AMP conditions when exposed.

**Attribution field** — Merchant-wide typed key (not tied to one activity type); values live in the event’s attribution bag and power custom campaign identifiers plus AMP acquisition predicates.

**Activity event** — One immutable ledger row per occurrence (page view, link click, campaign touch, custom types). Completed purchases are **not** duplicated here; when purchase-time campaign keys exist, the ingest path may emit a separate **campaign touch** activity instead.

**Marketing campaign** — Named paid/owned program with budget, optional flight dates, channel label, and a set of **external identifiers** (UTM campaign name, voucher code, LINE param, link token, or custom attribution key/value pairs).

**Campaign stamp** — At ingest, at most one campaign is resolved from identifier priority and stored on the event; this is the primary link between touches and campaigns (not a separate join table).

**Attribution model** — Merchant-wide rule (`u_shape`, first touch, last touch, linear) that splits each purchase amount across qualifying campaign touches inside a lookback window.

**Purchase attribution row** — Computed split of revenue for one purchase × one campaign × one model; safe to recompute (delete+insert per purchase).

**Acquisition stamp** — Write-once fields on the member account capturing first-touch UTM dimensions, resolved campaign, and full attribution JSON; not recomputed from historical events at read time.

**ROI view** — Lifetime attributed revenue vs campaign budget plus acquisition-cohort metrics keyed off the acquisition campaign on the member.

Platform-standard activity types are seeded (`page_view`, `link_click`, `campaign_touch`); merchants add custom types and fields in admin.

## Rules

- **Single write chokepoint** — Every activity event is created only through the central log function (Open API wraps the same path). Direct inserts into the activity ledger are out of contract.
- **Type and shape validation** — Unknown or inactive activity type → reject. Property and attribution JSON must match active field definitions (types, required keys, enum membership). Invalid payload → reject before persist.
- **Idempotency** — When an external reference is supplied and already exists for the merchant, the call returns the existing row without duplicating (same reference + merchant).
- **Campaign resolution (at most one)** — Evaluate identifier types in fixed priority; first match wins; no campaign → event still stored with null campaign stamp.
  - Priority: voucher code → LINE param → link token → UTM campaign string → custom attribution field (field key must match an active attribution field definition; value equals configured identifier value).
  - Built-in types read from the attribution JSON by type name. Custom matches require both `key_name` and `key_value` on the identifier row (value-only custom rows are invalid).
  - Duplicate identifier tuples per merchant (type + name + value) are forbidden at upsert.
- **UTM columns** — Dedicated UTM source/medium/campaign/term/content columns on the event are populated from attribution when present; they are not a second resolution path beyond the priority list above for campaign stamp (UTM campaign participates via the `utm_campaign` identifier type).
- **Acquisition immutability** — On first event for a member where acquisition columns are still empty, stamp UTM dimensions, resolved campaign id, attribution JSON, and acquired timestamp. Later events never overwrite acquisition, including backfilled historical activities or imports.
- **Purchases** — Purchase facts and amounts come from the purchase ledger only. Attribution compute considers completed purchases and attributed activities in the lookback window before `transaction_date`.
- **Attribution models** (merchant config, one model for all campaigns on a merchant):
  - `u_shape`: 40% first touch, 40% last touch, remaining 20% split across middle touches; 1 touch = 100%; 2 touches = 50% / 50%.
  - `first_touch`, `last_touch`, `linear`: standard definitions over the same touch set.
  - Lookback length is merchant-configured days ending at purchase time.
- **Recompute safety** — Nightly (and manual) compute deletes prior split rows for each purchase then inserts fresh rows for the active model. Unique key is purchase + campaign + model.
- **ROI and reports** — Lifetime ROI on campaign list uses the reporting view (full budget, not date-prorated). Date-ranged performance reports join computed splits to purchases by transaction date; acquisition revenue KPIs use members acquired in range and their lifetime completed purchase sum. Cross-campaign purchase KPIs count distinct purchases. Report freshness exposes attribution watermark from merchant marketing config.
- **Condition catalog** — Activity ledger is a whitelisted AMP aggregate collection; acquisition dimensions extend the member account collection. Field defs with “expose to conditions” compile to dynamic predicate names (`prop__<type>__<key>`, `attr__<key>`). Typed JSON predicates use the shared AMP JSON clause builder.
- **Report filter passthrough** — Purchase and member drill reports accept additive filters for attributed campaign and acquisition UTM dimensions without changing core report signatures.

## Journeys

### Admin journey

| Page | Owning repo | BFF / RPC |
| --- | --- | --- |
| Activity types | loyalty-admin | `bff_list_activity_types`, `bff_upsert_activity_type`, `bff_upsert_attribution_field` |
| Marketing campaigns (list + edit) | loyalty-admin | `bff_list_mkt_campaigns`, `bff_get_mkt_campaign_details`, `bff_upsert_mkt_campaign`, `bff_get_mkt_campaign_roi`, `bff_get_mkt_config`, `bff_upsert_mkt_config`, `bff_report_mkt_campaigns` (performance panel) |
| Marketing campaign ROI (cross-campaign) | loyalty-admin | `bff_report_mkt_campaigns` |
| Acquisition / lead source | loyalty-admin | `bff_report_acquisition` |
| Activity engagement | loyalty-admin | `bff_report_acquisition` (activity volume sections) |
| Executive overview | loyalty-admin | Composes acquisition, campaign, funnel, RFM BFFs (no new RPC) |
| Customer 360 | loyalty-admin | `bff_admin_get_member_360` |
| Purchase / member reports | loyalty-admin | `bff_report_purchases`*, `bff_report_members`* (*additive filters/columns) |
| RFM settings | loyalty-admin | `bff_list_activity_types` (recency activity type picker) |

| Setting | Effect on behaviour |
| --- | --- |
| Activity type code / name / active | Which events can be logged; code immutable after create |
| Property fields on a type | Allowed keys and types in `properties` for that type |
| Attribution field defs | Custom keys in `attribution`; required for custom campaign identifiers |
| Expose field to conditions | Field appears in AMP builder as dynamic predicate |
| Campaign status / window / budget | Reporting eligibility, ROI vs budget, flight dates |
| Campaign identifiers | Maps external keys to campaign for ingest stamp |
| Attribution model + lookback | How purchase revenue splits across touches |
| RFM recency activity type | Which logged activity type drives recency in RFM (when configured) |

1. Open **Activity types** — create or edit types; add property fields; maintain merchant **attribution fields** used by custom identifiers and AMP.
2. Open **Marketing campaigns** — create campaign, set channel, status, budget, and optional window; add identifiers (built-in UTM/voucher/LINE/link or custom field + value); save.
3. On campaign edit, open **Performance** — pick date range; review ranged KPIs, revenue/touch series, drill to purchases/members/activities; export CSV; jump to Customer 360 from drills.
4. Open **Marketing campaign ROI** report — compare campaigns for a period (KPIs, chart, table, CSV) under the same permission family as campaign admin.
5. Open **Acquisition** report — cohort by UTM dimension or campaign; review activation, time-to-first-purchase, and acquisition revenue sections.
6. Open **Activity** report — volume by activity type and members active in range without a completed purchase.
7. Open **Executive overview** for a CDP snapshot (acquisition, campaigns, funnels, RFM widgets).
8. On **Customer 360**, review acquisition line, RFM badge, funnel stage, attributed campaigns, and **Activity** stream tab (campaign stamp shown on activity rows).
9. Optionally tune **Attribution model** and lookback on campaign settings (merchant marketing config).

Naming: **Marketing campaigns** here are identifier/budget programs — not AMP workflow automations (`AMP_Workflows.md`).

### Member journey

| Surface | Owning repo | BFF / RPC |
| --- | --- | --- |
| (none — ingest only) | integrators / internal loggers | `api_log_user_activity` → central log function |
| Customer 360 (staff view) | loyalty-admin | `bff_admin_get_member_360` |

1. Member generates touchpoints in channels (web, LINE, store, integrations); events arrive via Open API or internal loggers with activity code, optional properties, attribution bag, and optional external reference.
2. Member does not configure attribution in a consumer app surface in-repo; staff see attributed history on Customer 360 when assisting the member.

## System

### Data model

| Table / view | Role |
| --- | --- |
| `activity_type_master` | Catalog: `merchant_id` NULL = platform-standard types; merchant rows = custom. `code` immutable, snake_case, unique per merchant including standards. |
| `activity_field_def` | Typed fields: `scope='activity_property'` + `activity_type_id`, or `scope='attribution'` (no type id). Controls validation and AMP exposure. |
| `activity_ledger` | One row per event: user, type, `occurred_at`, `properties`, dedicated UTM columns, `attribution`, `mkt_campaign_id`, `source`, `external_ref`. Partial indexes on merchant+user/time, type/time, campaign/time. |
| `mkt_campaign` | Campaign master: name, description, channel, `status` (`draft\|active\|paused\|ended`), budget, window. |
| `mkt_campaign_identifier` | Maps `key_type` (`utm_campaign`, `voucher_code`, `line_param`, `link_token`, `custom`) + `key_value` (+ `key_name` when custom) → campaign. Unique per merchant on type + coalesced name + value. |
| `mkt_config` | One row per merchant: `attribution_model`, `attribution_lookback_days`, `attribution_watermark` (compute progress / report freshness). |
| `mkt_purchase_attribution` | Computed splits: purchase, user, campaign, amount, model, touch count, computed_at. Unique `(purchase_id, campaign_id, model)`. |
| `v_mkt_campaign_roi` | Lifetime ROI reporting view (attributed revenue vs budget, acquisition cohort metrics via `user_accounts.acquisition_campaign_id`). |
| `user_accounts` acquisition columns | Write-once: UTM dims, `acquisition_campaign_id`, `acquisition_attribution`, `acquired_at` (plus legacy `acquisition_source`). |

Triggers: `set_updated_at` on activity type, activity field def, marketing campaign, marketing config.

### Functions

| Function | Role |
| --- | --- |
| `fn_log_user_activity` | Ingest chokepoint: validate type/fields, resolve campaign, insert ledger, apply acquisition stamp once. |
| `api_log_user_activity` | API-key merchant resolution wrapper for external integrators. |
| `bff_list_activity_types` / `bff_upsert_activity_type` | Admin catalog read/write including property field children. |
| `bff_upsert_attribution_field` | CRUD merchant attribution field defs. |
| `bff_list_mkt_campaigns` / `bff_get_mkt_campaign_details` / `bff_upsert_mkt_campaign` | Campaign CRUD; identifiers as JSON children with validation (duplicate → `DUPLICATE`; unknown custom field → `INVALID_ATTRIBUTION_FIELD`). |
| `bff_get_mkt_config` / `bff_upsert_mkt_config` | Read/update attribution model and lookback. |
| `bff_get_mkt_campaign_roi` | Single-campaign lifetime ROI from view. |
| `bff_report_mkt_campaigns` | Date-ranged campaign performance and cross-campaign report; filter sections (`kpis`, `series`, `table`, drills). Detail mode when campaign id set. |
| `bff_report_acquisition` | Lead-source / acquisition cohort report plus activity engagement sections (volume by type, active without purchase). |
| `bff_admin_get_member_360` | Adds RFM, acquisition, attributed campaigns, funnel stage, activity stream entries (`event_type='activity'`), activity counts. |
| `bff_report_purchases` / `bff_report_purchases_rows` | Additive campaign/UTM filters and attributed campaign + buyer acquisition columns. |
| `bff_report_members` / `bff_report_members_rows` | Additive acquisition, RFM segment, funnel stage filters/columns. |
| `fn_mkt_compute_purchase_attribution` | Watermark-based batch compute of purchase splits (invoked by cron and manually). |

### Flows

**Ingest (sync)** — Client → `api_log_user_activity` or internal caller → `fn_log_user_activity` → validate against `activity_type_master` + `activity_field_def` → resolve `mkt_campaign_identifier` → insert `activity_ledger` → optionally stamp `user_accounts` acquisition columns.

**Purchase touch** — On purchase with campaign keys, purchase pipeline may log `campaign_touch` (purchase row remains authoritative for revenue).

**Attribution compute (async batch)** — pg_cron job `mkt-attribution-compute` (`0 18 * * *` UTC) → `fn_mkt_compute_purchase_attribution()` → advances watermark → repopulates `mkt_purchase_attribution` for purchases since watermark using touches in lookback.

**Reporting (read)** — Admin BFFs join `mkt_purchase_attribution` to `purchase_ledger` on transaction date; acquisition reports cohort on `acquired_at` (fallback `created_at`); ROI list uses `v_mkt_campaign_roi`.

**AMP** — Condition builder reads exposed field defs; evaluation on activity/acquisition collections via reconcile-capable matchers (see Known gaps for realtime v1).

### External services

- **Open API gateway** — `api_log_user_activity` for partner/event ingestion (`Open_API.md`).
- **pg_cron** — Nightly attribution compute job on Supabase project database.

### Known gaps

- **AMP realtime batch matcher v1** — Does not evaluate activity ledger or extended acquisition predicate fields; hourly reconcile remains source of truth for audience membership tied to those fields.
- **Global attribution job** — pg_cron invokes `fn_mkt_compute_purchase_attribution()` once for all merchants per run (not merchant-sharded); manual invoke used in demos/ops for verification.

## Related

- **Activity_Based_Earning.md** — Admin-approved upload matrix and earn path; separate tables and BFFs from this activity log.
- **Campaign_Activity_Grouping.md** — Operational/report grouping mappings (`campaign_activity`), not marketing identifier ROI.
- **Purchase_Transaction.md** — Purchase ledger facts and amounts used in attribution compute.
- **AMP_Workflows.md** — Audiences and workflows consuming activity/acquisition condition collections.
- **Funnel.md** — Funnel stage on Customer 360 and member report filters.
- **RFM_Scoring.md** — RFM segment on 360 and reports; optional recency activity type from this catalog.
- **Open_API.md** — External activity ingest via API key.
