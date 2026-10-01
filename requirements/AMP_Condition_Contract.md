# AMP Condition Contract (v2)

Contract between the backend condition engine and the shared frontend condition builder (audience builder, workflow builder, agent builder). The backend owns and curates the schema; the frontend renders purely from this contract with no per-collection knowledge.

- **Metadata**: `bff_get_workflow_collections()` — no params, returns the jsonb array documented below.
- **Evaluation**: `fn_evaluate_amp_condition_group(p_user_id uuid, p_merchant_id uuid, p_group jsonb) → boolean` — evaluates ONE group. Group combination (`groups_operator` AND/OR across `groups[]`) stays caller-side, unchanged.
- **Clause builder**: `fn_amp_build_condition_clause(p_collection, p_cond, p_alias, p_default_timezone) → text` — internal helper shared by the simple-condition loop and the aggregate-filter loop. All dynamic SQL uses `%I`/`%L`.

Applied migrations: `amp_condition_evaluator_v2`, `amp_condition_evaluator_v2_1_form_answer_jsonb_array`, `amp_condition_metadata_v2`, `amp_condition_metadata_v2_1_supports_simple`, `amp_condition_metadata_v3_collections_1_6` (2026-07-04).

**Implementation note:** `bff_get_workflow_collections()` merges `bff_get_workflow_collections_v2()` (original 7 collections) with `bff_get_workflow_collections_v3_extensions()` (6 additional collections) and `bff_get_workflow_collections_v4_extensions()` when present. `user_wallet` is inserted at position 2 (immediately after Member Profile). The public RPC name is unchanged.

### Collection catalog (13)

| # | `name` | Label | Simple | Aggregate | Admin question |
|---|---|---|---|---|---|
| 1 | `user_accounts` | Member Profile | ✓ | — | Who is this member? |
| 2 | `user_wallet` | Current Balance | ✓ | — | Do they have ≥ X points/tickets right now? |
| 3 | `wallet_ledger` | Points & Wallet Activity | ✓ | ✓ | Earned/burned points in a period? |
| 4 | `purchase_ledger` | Purchases | ✓ | ✓ | Spent / bought at store / channel? |
| 5 | `purchase_items_ledger` | Purchase Items | — | ✓ (join) | Bought SKU X / quantity / line spend? |
| 6 | `package_assignment` | Package Assignments | ✓ | ✓ | Has package X assigned? |
| 7 | `user_benefit` | User Benefits | ✓ | ✓ | Has benefit of type X? |
| 8 | `form_submissions` | Forms & Surveys | ✓ | ✓ (+ kinds) | Submitted form / answered question? |
| 9 | `mission_log_completion` | Mission Completions | ✓ | ✓ | Completed mission X (N times)? |
| 10 | `reward_redemptions_ledger` | Reward Redemptions | ✓ | ✓ | Redeemed/used reward X? |
| 11 | `user_tags` | Member Tags | ✓ | ✓ | Has tag X? |
| 12 | `tier_change_ledger` | Tier Changes | ✓ | ✓ | Was upgraded/downgraded? |
| 13 | `checkin_ledger` | Check-ins | ✓ | ✓ | Checked in N times / streak day ≥ X? |

## 1. Metadata shape

Top level is a **jsonb array of collections** (unchanged from v1 so the current FE keeps working). All v2 keys are additive.

### Collection keys

| Key | Type | Meaning |
|---|---|---|
| `name` | string | Persisted `collection` value. Physical table name. |
| `label`, `description` | string | Display copy. |
| `supports_simple` | bool | Whether `type:"simple"` groups may target this collection. `false` only for `purchase_items_ledger` (no user column — aggregate-only via join). |
| `supports_aggregate` | bool | Whether `type:"aggregate"` groups may target this collection. |
| `time_field` | string | Column to persist as `time_field` when the admin sets a time window on an aggregate. |
| `aggregates` | array | **The curated aggregate list — the only aggregate configurations the UI may offer.** Each entry: `{aggregate, field, label}`. Persist `aggregate` + `field` verbatim. |
| `aggregate_fields` | array | v1-shaped equivalent kept for the legacy FE. New FE should read `aggregates`. |
| `joinable_to` | object | Present on `purchase_items_ledger` only. Persist verbatim as the group's `join` key for aggregates on this collection. |
| `fields` | array | Curated field list (see below). Every listed field is valid both as a simple condition and as an aggregate filter (subject to `supports_simple`). |
| `condition_kinds` | array | Present on `form_submissions` only. Declares the special condition types (§4). |

### Field keys

| Key | Type | Meaning |
|---|---|---|
| `name` | string | Persisted `field` value. Physical column, except logical fields (below). |
| `label` | string | Display label. |
| `type` | string | v1 vocabulary kept for legacy FE: `string`, `number`, `boolean`, `date`, `timestamp`, `uuid`. |
| `input` | string | **Widget selector**: `text`, `number`, `date`, `boolean` (no value input — operator carries the meaning), `select` (render `options`), `entity_picker` (render picker for `ref`), `none` (no value input; operators like is_empty/is_not_empty only). |
| `operators` | array | **The complete valid operator list for this field.** No generic type→operator map exists; render exactly this list. |
| `options` | array | For `input:"select"`: `{value, label}` pairs. Persist `value`. |
| `ref` | string | For `input:"entity_picker"`: which entity the picker lists (§3). Persist the entity's canonical uuid as `value`. |
| `logical` | bool | Field is not a physical column; the evaluator resolves it (see `resolves`). |
| `resolves` | array | The physical columns a logical field matches against. Informational. |

### Annotated example (one collection)

```jsonc
{
  "name": "purchase_ledger",            // persisted as group.collection
  "label": "Purchases",
  "supports_simple": true,               // may be used in type:"simple" groups
  "supports_aggregate": true,            // may be used in type:"aggregate" groups
  "time_field": "created_at",            // persist as group.time_field when a window is set
  "aggregates": [                        // ONLY these aggregate configs may be offered
    {"aggregate": "count", "field": "id",           "label": "Number of purchases"},
    {"aggregate": "sum",   "field": "final_amount", "label": "Total spend (amount paid)"},
    {"aggregate": "avg",   "field": "final_amount", "label": "Average spend per purchase"},
    {"aggregate": "max",   "field": "final_amount", "label": "Largest single purchase"},
    {"aggregate": "sum",   "field": "total_amount", "label": "Total order value (before discount)"}
  ],
  "fields": [
    {"name": "final_amount", "label": "Amount Paid (after discount)", "type": "number",
     "input": "number",
     "operators": ["equals","not_equals","greater_than","greater_or_equal","less_than","less_or_equal"]},
    {"name": "status", "label": "Status", "type": "string",
     "input": "select",                  // fixed option list; no free text, no contains
     "options": [{"value":"completed","label":"Completed"}, {"value":"refunded","label":"Refunded"} /* … */],
     "operators": ["equals","not_equals","in","not_in"]},
    {"name": "store", "label": "Store", "type": "uuid",
     "input": "entity_picker", "ref": "store",   // FE maps ref "store" → store option source
     "operators": ["equals","not_equals","in","not_in"],
     "logical": true, "resolves": ["store_id","store_code"]}  // evaluator matches either column
  ]
}
```

## 2. Operator vocabulary

Canonical operators the metadata emits (the evaluator additionally accepts legacy spellings `gt/gte/lt/lte/eq`, `greater_than_or_equals`, `less_than_or_equals`, `is_null`, `is_not_null`, `date_anniversary_today` — saved data uses them; never emit them for new conditions):

| Operator | SQL semantics | Notes |
|---|---|---|
| `equals` / `not_equals` | `= / !=` | `not_equals` keeps SQL NULL semantics (NULL field ≠ match) — unchanged from v1. |
| `greater_than`, `greater_or_equal`, `less_than`, `less_or_equal` | `> >= < <=` | Numbers and dates. |
| `contains` | `ILIKE '%v%'` | |
| `not_contains` | `(f IS NULL OR f NOT ILIKE '%v%')` | NULL counts as "does not contain". |
| `starts_with` / `ends_with` | `ILIKE 'v%' / ILIKE '%v'` | |
| `is_empty` / `is_not_empty` | `(f IS NULL OR f::text = '')` / inverse | No value input. |
| `is_true` / `is_false` | `f IS TRUE / f IS FALSE` | Booleans only. No value input. |
| `in` / `not_in` | `IN (…)` / `(f IS NULL OR f NOT IN (…))` | `value` is a JSON array. Empty array: `in`→false, `not_in`→true. |
| `birthday_today`, `anniversary_today` | `fn_amp_lifecycle_date_matches(...)` | Optional condition keys `timezone`, `days_offset`. |
| `between` | **not implemented** | FE drops it; never emit. |

Aggregate **result** comparison operators: `greater_than`, `greater_or_equal`, `less_than`, `less_or_equal`, `equals` (+ legacy spellings). Unknown → `>=` (v1 fallback kept).

Unknown operators in conditions/filters still fall through to `equals` (v1 behavior preserved for old saved data).

## 3. Entity-ref vocabulary

The FE maps each `ref` to an option source (id = canonical uuid, label = name):

| ref | Canonical entity | Suggested option source |
|---|---|---|
| `tier` | `tier_master.id` / `tier_name` | existing tier list endpoint |
| `persona` | `persona_master.id` / `persona_name` | `bff_get_persona_structure` |
| `store` | `store_master.id` / `store_name` | store list endpoint |
| `package` | `package_master.id` / `name` | package list endpoint |
| `product_sku` | `product_sku_master.id` / `name` (+`sku_code`) | SKU search endpoint |
| `form_template` | `form_templates.id` / `name` (status=published) | form template list endpoint |
| `mission` | `mission.id` / `mission_name` | mission list endpoint |
| `reward` | `reward_master.id` / `name` | `bff_list_rewards` |
| `tag` | `tag_master.id` / `tag_name` | tag list endpoint |
| `checkin` | `checkin.id` / `name` | check-in campaign list endpoint |

Form **questions** are not a ref: the `form_answer` kind declares `question_source: {function: "bff_get_amp_form_fields", param: "p_form_id", options_key: "options"}` — call it with the picked form, render `fields[]` as the question list, and use each field's `options` as answer choices for select/multi-select questions.

### Logical de-duplicated fields

Admins pick one entity; the evaluator resolves the historical column duplication:

- `purchase_ledger.store` → matches `store_id = <uuid>` **OR** `store_code = (SELECT store_code FROM store_master WHERE id = <uuid>)`. (1.44M purchase rows carry only `store_code`; matching the id column alone would miss ~38% of rows.)
- `purchase_items_ledger.sku` → same pattern over `sku_id` / `sku_code` via `product_sku_master`.

`not_equals` / `not_in` on logical fields are NULL-safe: rows with no store/SKU at all count as "not that store/SKU" (`NOT COALESCE(match, false)`). A non-uuid value degrades to `equals`→FALSE / `not_equals`→TRUE rather than erroring.

## 4. Persisted condition JSON (per group type)

The caller-side wrapper is unchanged: `{"groups": [...], "groups_operator": "AND"|"OR"}`. Each group below is what `fn_evaluate_amp_condition_group` receives.

### 4.1 `simple` (unchanged shape; new operators allowed)

```json
{
  "type": "simple",
  "collection": "user_accounts",
  "timezone": "Asia/Bangkok",
  "conditions": [
    {"field": "email", "operator": "is_not_empty"},
    {"field": "tier_id", "operator": "in", "value": ["<tier-uuid-1>", "<tier-uuid-2>"]},
    {"field": "birth_date", "operator": "birthday_today", "days_offset": 0}
  ]
}
```

Scoping is automatic: `user_id = p_user_id AND merchant_id = p_merchant_id` (`id = p_user_id` for `user_accounts`). Conditions AND together within a group.

### 4.2 `aggregate` (unchanged shape; filters accept the full operator set incl. logical fields)

```json
{
  "type": "aggregate",
  "collection": "purchase_items_ledger",
  "aggregate": "sum",
  "field": "line_total",
  "operator": "greater_or_equal",
  "value": 50000,
  "time_field": "created_at",
  "time_range": "12 months",
  "join": {"table": "purchase_ledger", "on": {"local": "transaction_id", "foreign": "id"}},
  "filters": [
    {"field": "sku", "operator": "equals", "value": "<product_sku_master uuid>"}
  ]
}
```

`time_range` is any Postgres interval literal. NULL aggregate results coalesce to 0 before comparison (v1 behavior kept).

### 4.3 `form_submission` (new)

```json
{
  "type": "form_submission",
  "form_id": "<form_templates uuid>",
  "operator": "submitted",
  "time_range": "90 days"
}
```

- `operator`: `submitted` | `not_submitted` (`not_submitted` = NOT EXISTS — the negation the simple model cannot express).
- Only `status = 'completed'` submissions count. Time window applies to `COALESCE(submitted_at, created_at)`. `time_range` optional.

### 4.4 `form_answer` (new)

```json
{
  "type": "form_answer",
  "form_id": "<form_templates uuid>",
  "field_id": "<form_fields uuid>",
  "operator": "equals",
  "value": "option_value",
  "time_range": "12 months"
}
```

- EXISTS over `form_submissions (status='completed') JOIN form_responses ON submission_id` filtered to `field_id`.
- Matches `text_value` and, for multi-select answers, elements of `array_value` (jsonb[]; scalar elements extracted as text). Structured object answers (grid/object-schema questions) are not matchable — the UI should only offer answer conditions on scalar question types (`select`, `single_select`, `multi-select`, `text`, `free_text`, `normal`, `number`, `rating`, `tel`, `email`, `date`).
- Operators: `equals`, `not_equals`, `contains`, `not_contains`, `in` (value = JSON array), `greater_than`/`greater_or_equal`/`less_than`/`less_or_equal` (numeric-safe: non-numeric answers never match), `is_empty`, `is_not_empty`.
- **Negation semantics**: `not_equals`/`not_contains` mean "the user answered this question with something else" (EXISTS with inverted predicate) — a user who never answered does NOT match. "Has not submitted at all" is `form_submission`+`not_submitted`.
- `value_type` on saved conditions (`"static"`) is FE bookkeeping; the evaluator ignores it.

### 4.5 `content_engagement` (new 2026-07-06, split-only)

```json
{
  "type": "content_engagement",
  "scope": "node",
  "node_id": "<workflow_node uuid, required when scope=node>",
  "metric": "clicked",
  "operator": "is_true",
  "link_label": "CTA",
  "time_range": "1 month"
}
```

- Branches on engagement with tracked content (`amp_engagement_event` JOIN `amp_tracked_link` ON token). Metrics: `clicked` (EXISTS on `event_type='click'`; operators `is_true`/`is_false`), `page_time` and `scroll_depth` (`MAX(value)` vs threshold; operators `gte|gt|lte|lt|eq|neq` + `value`; no rows = never matches, regardless of operator).
- Scopes: `node` (one message node, requires `node_id`), `workflow` (any message in the workflow), `any` (across all workflows; only scope where `time_range` applies).
- **Enrollment scoping:** `node`/`workflow` count only the current run — the executor injects `_workflow_id` and `_inngest_run_id`, and the evaluator matches `tl.workflow_log_id IN (SELECT id FROM workflow_log WHERE inngest_run_id = <run>)`. Missing runtime context fails closed (false, including for `is_false`).
- `link_label` (optional) narrows to one tracked link when a message has several. Empty string = unset.
- **Split-only**: metadata entry carries `"contexts": ["split"]`; the set-based compiler (`fn_amp_compile_condition_group`) intentionally raises on this type — no audience compile, no entry matching, no count preview. Only `fn_evaluate_amp_condition_group` evaluates it.
- Page metrics require destinations on Rocket-hosted pages that run the engagement beacon; external URLs get `clicked` only.

### 4.6 Example: current balance (simple)

```json
{
  "type": "simple",
  "collection": "user_wallet",
  "conditions": [
    {"field": "points_balance", "operator": "greater_or_equal", "value": "500"}
  ]
}
```

### 4.7 Example: mission completion count (aggregate)

```json
{
  "type": "aggregate",
  "collection": "mission_log_completion",
  "aggregate": "count",
  "field": "id",
  "operator": "greater_or_equal",
  "value": 1,
  "time_field": "completed_at",
  "time_range": "30 days",
  "filters": [
    {"field": "mission_id", "operator": "equals", "value": "<mission uuid>"}
  ]
}
```

### 4.8 Example: tier upgrade (simple)

```json
{
  "type": "simple",
  "collection": "tier_change_ledger",
  "conditions": [
    {"field": "change_type", "operator": "equals", "value": "upgrade"}
  ]
}
```

### 4.9 Example: check-in streak (aggregate)

```json
{
  "type": "aggregate",
  "collection": "checkin_ledger",
  "aggregate": "max",
  "field": "streak_day",
  "operator": "greater_or_equal",
  "value": 7,
  "time_field": "checkin_timestamp",
  "time_range": "90 days",
  "filters": [
    {"field": "checkin_id", "operator": "equals", "value": "<checkin uuid>"}
  ]
}
```

## 5. Judgment calls (curation decisions)

**Fields cut from the metadata** (evaluator still accepts them — nothing saved breaks at evaluation time):

- All raw uuid plumbing: `id`, `user_id`, `merchant_id`, `source_id`, `reference_id`, `seller_id`, `transaction_id`, `auth_user_id` — no picker semantics, pure foot-guns.
- `wallet_ledger`: `balance_before/after`, `deductible_balance`, `component`, `description`, `created_by`, `signed_amount` (as a simple field — kept only as the `sum` "net change" aggregate).
- `purchase_ledger`: `transaction_number`, `external_ref`, `api_source` (duplicates `transaction_source`), `earn_currency`, `record_type`, `processing_method`, `notes`, `created_at` (duplicate of `transaction_date` for admin intent; still the aggregate `time_field`).
- `user_accounts`: `firstname`/`lastname` (kept `fullname`), `id_card` (PII matching), `external_user_id`, `member_code`, `role`, `user_type`, `image`, `is_active`, `mongo_id`.
- `purchase_items_ledger`: `variant_name` (kept `product_name`), `item_type` (no stable domain), `sku_code`/`sku_id` (replaced by logical `sku`).
- `package_assignment` / `user_benefit`: `source_type`/`source_id`, `assigned_by`, `created_by`, `notes`, `metadata`.
- `form_submissions`: `source`, `submission_number`, `ref_userid`, `tel`, `source_id`, `source_id_2` (import plumbing).

**Aggregate combinations disallowed** (were offered in v1): `avg/min/max` on `wallet_ledger` amounts (an "average points transaction" answers no admin question); `min` everywhere (no admin question found); `avg/min/max(unit_price)` on items; `avg` on `signed_amount`. `count` is expressed once per collection with a business label ("Number of purchases") instead of per-field count permutations.

**Option lists**: `payment_status` (paid/pending/refunded), `transaction_type`, `transaction_source`, `gender` (canonical uppercase — legacy lowercase rows exist but new conditions should target canonical), `user_stage` (lead/member) are curated from live value distributions, not full dumps. `package_assignment.status` / `user_benefit.status` expose only `active` (the only observed value). `wallet_ledger.source_type` exposes the full enum except `account_removal`.

**Known saved-data references to fields no longer in the metadata** (flagged, per the backward-compat rule — evaluation is unaffected; the new FE needs a fallback render, e.g. read-only raw display, for these when editing old configs):

- `purchase_items_ledger.sku_code` — 4 saved aggregate filters. Still evaluates; new UI should offer `sku` instead.
- `user_accounts.id equals <uuid>` — 2 saved conditions (test artifacts).
- Fields that never existed but are saved (already broken before v2, unchanged): `user_accounts.birth_month`, `user_accounts.tier_eval_days_remaining`, `purchase_ledger.service_type`, `wallet_ledger.balance`, `wallet_ledger.expiry_days_remaining`.

**New collections (v3) — fields intentionally cut:**

- `mission_log_completion`: `trigger_type`, `trigger_id`, `completion_number`, `global_completion_number`, `progress_used`, `outcomes_distributed` (internal plumbing).
- `reward_redemptions_ledger`: `code`, `promo_code`, `points_deducted`, `points_calculation`, `source_type`/`source_id`, store ids, error fields, `mongo_id`.
- `user_tags`: `source_type`/`source_id` (provenance only).
- `tier_change_ledger`: `change_reason`, `metadata`, `created_by`, `triggered_by_condition_id`.
- `checkin_ledger`: `matched_outcomes` (jsonb blob — not matchable in simple conditions).

**Deferred (not yet in metadata)**: `referral_ledger` (needs inviter/invitee role picker), `campaign_participation` (lower priority — missions/check-ins cover most cases).

- `is_not_null` (saved on `line_id`) previously fell through to `= NULL-text` (always false); now evaluates correctly.
- `in` (saved on `tier_id` with uuid arrays) previously errored (`uuid = '["…"]'` cast failure); now evaluates correctly.
- Non-join aggregates with `filters` previously generated `c.field` without a `c` alias → SQL error; the non-join branch now aliases the table `c`, so these evaluate instead of erroring.

**Deferred (not yet in metadata)**: `referral_ledger` (needs inviter/invitee role picker), `campaign_participation` (lower priority — missions/check-ins cover most cases).

**Known gap (batch matcher)**: `fn_amp_find_matching_users` still has v1 semantics — first group only, old operator set, no form types, no logical fields, no v3 collections. Workflows relying on batch matching won't evaluate new condition types until it is aligned.

**Behavior changes that are deliberate fixes** (previously silently wrong, now correct): (batch audience matcher) still has v1 semantics — first group only, old operator set, no form types, no logical fields. Workflows relying on batch matching won't understand new condition types until it is aligned.

## 6. Security invariants

- All identifiers via `%I`, all values via `%L`; list values are individually `%L`-quoted; interval strings pass through `%L::INTERVAL`.
- Logical-field resolution looks up master tables by uuid (validated by regex before cast) — invalid input degrades to constant TRUE/FALSE, never raw SQL.
- Merchant + user scoping is injected server-side from function args, never from the condition JSON.
