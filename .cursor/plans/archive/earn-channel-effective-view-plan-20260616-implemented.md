# Earn Channel Effective View Restructure Plan

## Goal

Move earn channels from a manually materialized display table to an effective, computed merchant surface:

- `earn_channel_registry` defines the canonical templates and availability rules.
- Source systems determine whether a merchant actually has a channel.
- `earn_channel` preserves merchant overrides, custom channels, and existing display customizations.
- BFF functions keep the same frontend response contract, but read from an effective resolver/view instead of only physical `earn_channel` rows.

This should apply to standalone app channels and Shopify. There should be no noticeable frontend behavior change for members: the member app still receives the same channel fields, in the same general shape, but the backend has a cleaner source of truth.

## Current State

`earn_channel` is currently the source of merchant-visible earn channel rows. It stores copy, banner assets, method type, button config, display order, and active state.

`earn_channel_registry` currently stores a partial template catalog:

- `type`
- `subtype`
- `display_name`
- `ui_component`
- `default_headline`
- `default_description`
- `default_icon_url`
- `default_banner_url`
- `sort_order`
- `allowed_earn_methods`

Current gaps:

- Registry does not contain a stable `channel_code`.
- Registry does not describe availability rules.
- Registry does not distinguish a default selected `method_type` from allowed methods.
- Registry does not define editability or visibility behavior.
- Registry does not identify which source system proves availability.
- `bff_get_earn_channels` reads physical `earn_channel` rows only.
- `bff_admin_get_earn_channels` reads physical rows plus registry/options, but does not return effective computed defaults.
- `bff_upsert_earn_channel` performs full replacement and deletes rows not in the submitted payload.
- Shopify is currently handled as a materialized system row, but the same computed model should apply to Shopify too.

## Target Mental Model

Use three layers:

1. **Registry template**
   Describes what a channel type is and how it should look by default.

2. **Source availability**
   Determines whether this merchant should see that channel.

3. **Merchant override**
   Stores only merchant-specific customization, hiding, ordering, or custom channels.

In short:

```text
effective earn channels =
  registry templates available to merchant
  + source-system facts
  + merchant overrides
  + merchant custom channels
```

## Registry Structure

Extend `earn_channel_registry` so each row is a complete channel template.

Recommended columns:

| Column | Role |
|---|---|
| `id uuid` | Existing primary key |
| `channel_code text` | Stable canonical identity, e.g. `integration:shopify`, `lifecycle:birthday` |
| `type text` | Existing group: `purchase`, `campaign`, `lifecycle`, `custom`, `integration` if needed |
| `subtype text` | Existing subtype: `birthday`, `anniversary`, `marketplace`, etc. |
| `display_name text` | Default channel name |
| `ui_component text` | Rendering component or method-like UI hint |
| `default_method_type text` | One selected default method, e.g. `account_link`, `receipt_upload`, `info_card` |
| `allowed_earn_methods text[]` | Existing list of methods allowed for customization |
| `default_award_scope text` | Default `purchase` or `purchase_item`, where relevant |
| `default_headline text` | Default headline copy |
| `default_description text` | Default description copy |
| `default_howto_description text` | Default how-to copy |
| `default_icon_url text` | Default icon |
| `default_banner_url text` | Default banner |
| `default_button_action jsonb` | Default button shape, label, visibility |
| `default_config jsonb` | Default method/button config |
| `availability_rule jsonb` | Machine-readable rule proving merchant availability |
| `capabilities jsonb` | Edit/hide/delete/customization controls |
| `sort_order integer` | Default display ordering |
| `is_active boolean` | Whether this template is globally available |
| `created_at timestamptz` | Existing timestamp |
| `updated_at timestamptz` | Add for registry maintenance |

Example registry rows:

```json
{
  "channel_code": "integration:shopify",
  "type": "purchase",
  "subtype": "shopify_store",
  "display_name": "Online Store",
  "ui_component": "account_link",
  "default_method_type": "account_link",
  "allowed_earn_methods": ["account_link", "external_link"],
  "availability_rule": {
    "source": "integration",
    "integration": "shopify",
    "condition": "connected"
  },
  "capabilities": {
    "can_hide": true,
    "can_delete": false,
    "can_customize_copy": true,
    "can_customize_assets": true,
    "can_customize_method": false,
    "can_customize_button": true
  }
}
```

```json
{
  "channel_code": "lifecycle:birthday",
  "type": "lifecycle",
  "subtype": "birthday",
  "display_name": "Birthday",
  "ui_component": "info_card",
  "default_method_type": "info_card",
  "allowed_earn_methods": ["info_card"],
  "availability_rule": {
    "source": "workflow",
    "domain": "loyalty",
    "surface": "lifecycle_automation",
    "event": "birthday",
    "requires_active": true
  },
  "capabilities": {
    "can_hide": true,
    "can_delete": false,
    "can_customize_copy": true,
    "can_customize_assets": true,
    "can_customize_method": false,
    "can_customize_button": false
  }
}
```

```json
{
  "channel_code": "purchase:receipt_upload",
  "type": "purchase",
  "subtype": "receipt_upload",
  "display_name": "Upload Receipt",
  "ui_component": "receipt_upload",
  "default_method_type": "receipt_upload",
  "allowed_earn_methods": ["receipt_upload"],
  "availability_rule": {
    "source": "feature_config",
    "feature_group": "earn_channel",
    "feature_key": "upload_receipt",
    "requires_enabled": true
  },
  "capabilities": {
    "can_hide": true,
    "can_delete": false,
    "can_customize_copy": true,
    "can_customize_assets": true,
    "can_customize_method": false,
    "can_customize_button": false
  }
}
```

Registry should contain default values and structure, not live merchant state.

Do not store these in registry:

- Merchant Shopify shop domain.
- Merchant-specific marketplace platform selection.
- Merchant-custom headline, description, banners, or button URL.
- Whether a merchant has birthday points configured.
- The workflow ID that powers birthday points.
- Per-merchant active/hidden state.

Those belong to source systems or the override layer.

## Override Table Behavior

Keep `earn_channel` as the merchant override and custom-channel table.

Meaning of a row after the restructure:

- If `channel_code` matches a registry row, the row is an override for that computed default.
- If `channel_code` is merchant-custom and not a registry code, the row is a custom channel.
- Existing rows remain valid and continue to provide display values.

Required behavior:

- Override copy fields win over registry defaults.
- Override `display_order` wins over registry `sort_order`.
- Override `active = false` hides a computed default.
- Override assets win over default assets.
- Override button config wins only if registry capabilities allow button customization.
- Override method type wins only for channels where capabilities allow method customization.
- System/integration identity should not be edited through merchant overrides.

Recommended new or clarified fields on `earn_channel`:

| Column | Role |
|---|---|
| `channel_code` | Stable identity; already exists |
| `override_kind` | Optional: `default_override`, `custom`, `legacy`, `system_override` |
| `source_type` | Optional: `registry`, `custom`, `legacy`, `integration` |
| `source_ref` | Optional JSONB for migration/debugging, not used as availability source |
| `active` | For default overrides, false means hidden |
| `is_system` | Keep for compatibility during transition, but avoid relying on it as the long-term model |

The table should not be required for default channels to appear.

## Effective Channel Resolver

Introduce an internal resolver function or view:

```text
fn_get_effective_earn_channels(p_merchant_id uuid, p_language text default null)
```

This resolver should return rows in the same field shape currently used by `bff_get_earn_channels`:

- `id`
- `channel_code`
- `channel_type`
- `earn_method`
- `channel_name`
- `headline`
- `description`
- `howto_description`
- `banner_urls`
- `display_order`
- `button_show`
- `button_label`
- `button_config_mode`
- `button_config_value`
- `howto_banners`
- `stores_banner`
- `marketplace_platforms`

It may include admin-only metadata when called by admin BFFs:

- `source`
- `source_status`
- `registry_id`
- `override_id`
- `can_hide`
- `can_delete`
- `can_customize_copy`
- `can_customize_method`
- `is_computed_default`

### ID Strategy

For frontend compatibility, every returned channel should have a stable `id`.

Recommended:

- Existing override/custom row: return `earn_channel.id`.
- Computed default without override: return deterministic UUID derived from `(merchant_id, channel_code)`.

Writes should use `channel_code` as the business identity, even if the read contract still exposes `id`.

## Availability Logic

Availability should be computed per registry row.

### Plan / Feature Config Sources

For registry rows with:

```json
{
  "source": "feature_config",
  "feature_group": "earn_channel",
  "feature_key": "upload_receipt"
}
```

The resolver checks effective merchant entitlement:

- merchant-specific `feature_config` override first, if present
- otherwise plan-level `feature_config` from `merchant_master.plan_id`
- `enabled = true`

Examples:

- `earn_channel.upload_receipt` -> show receipt upload.
- `earn_channel.marketplace_code` -> show marketplace channel.
- `earn_channel.product_code_scan` -> show product code scan.

### Integration Sources

For Shopify:

```json
{
  "source": "integration",
  "integration": "shopify",
  "condition": "connected"
}
```

The resolver checks the canonical Shopify connection/config state for the merchant. The current Shopify materialized row should be migrated into an override row or preserved as an override, not treated as the source of truth.

Shopify should be resolved exactly like other channels:

```text
registry template + Shopify connection state + merchant override
```

### Workflow / Lifecycle Sources

For birthday:

```json
{
  "source": "workflow",
  "surface": "lifecycle_automation",
  "event": "birthday",
  "requires_active": true
}
```

The resolver checks for an active lifecycle workflow/trigger configuration that represents birthday points or birthday lifecycle automation.

Rules to define before implementation:

- Does the workflow need to be active, or merely configured?
- Does it need an `award_currency` action specifically?
- Should message-only birthday automation create an earn channel?

Recommended business rule:

Only show an earn channel when the configured lifecycle automation creates a member-visible earning benefit, such as an `award_currency` action. Message-only automations should not show in earn channels unless Product wants “birthday campaign” to be displayed even without earning.

### Campaign Sources

Campaign-driven channels should resolve from the live source:

- Missions from active mission configuration.
- Referral from active referral configuration.
- Check-in from active check-in configuration.
- Forms from published earning forms.

This should be handled incrementally, starting with the channels currently represented in registry and existing merchants.

## BFF Wiring

### `bff_get_earn_channels`

Keep the response contract unchanged:

```json
{
  "page_icon": "...",
  "channels": [],
  "language": "en",
  "cache_hit": false
}
```

Change only the data source:

- current: `earn_channel` rows where `merchant_id = current merchant and active = true`
- target: `fn_get_effective_earn_channels(current merchant, language)` filtered to visible/active rows

Translation behavior:

- Existing translations are keyed by physical `earn_channel.id`.
- For computed defaults without overrides, use registry default copy first.
- If multilingual registry copy is needed, add registry-level translations or create override rows when merchant translates a computed default.
- Existing merchant translations should continue to apply to override/custom rows.

Cache behavior:

- Keep the same cache key shape initially.
- Invalidate cache when:
  - `earn_channel` override rows change
  - relevant source config changes
  - relevant workflow lifecycle config changes
  - Shopify integration state changes
  - registry template changes

### `bff_admin_get_earn_channels`

Keep existing major fields:

```json
{
  "success": true,
  "channels": [],
  "registry": [],
  "options": {}
}
```

Change `channels` to effective admin channels, not only physical rows.

Add admin metadata in each channel where safe:

- `source`
- `registry_id`
- `override_id`
- `is_computed_default`
- `can_delete`
- `can_hide`
- `can_customize_copy`
- `can_customize_method`

Frontend can ignore these at first, preserving current UI behavior. Later, the admin UI can use them to prevent deleting computed defaults and show “managed by feature/integration” labels.

### `bff_upsert_single_earn_channel`

Use this as the primary admin save path.

Behavior:

- If payload refers to a computed default by `channel_code`, create or update an `earn_channel` override row.
- If payload refers to an existing physical row by `id`, update it as today.
- If payload creates a custom channel, insert a physical `earn_channel` row as today.
- Validate method changes against registry capabilities.
- Do not allow identity changes for computed defaults or integration-managed channels.

### `bff_upsert_earn_channel`

This function currently full-replaces the merchant channel set and deletes anything not submitted.

Target behavior:

- Do not delete computed defaults.
- Do not delete system/integration channels.
- Treat omitted computed defaults as unchanged, not deleted.
- For physical custom channels, full replacement can remain only if the admin UI intentionally owns the entire custom list.

Recommended migration:

1. Deprecate batch full-replace for the new admin UI.
2. Patch it defensively so it never deletes:
   - `is_system = true`
   - registry-backed overrides unless explicitly marked for delete/hide
   - rows with dependencies in purchase or receipt upload ledgers
3. Prefer `bff_upsert_single_earn_channel` for new edit flows.

### `bff_delete_earn_channel`

Target behavior:

- Custom physical channels can be deleted if no dependencies exist.
- Registry-backed computed defaults cannot be deleted.
- Deleting a computed default should become “hide this channel” by writing an override with `active = false`, or the BFF should return a clear `PROTECTED` response and require a hide action.

## Migration Strategy

### Phase 1 — Registry Enrichment

Add missing registry fields:

- `channel_code`
- `default_method_type`
- `default_award_scope`
- `default_howto_description`
- `default_button_action`
- `default_config`
- `availability_rule`
- `capabilities`
- `is_active`
- `updated_at`

Backfill current registry rows with stable `channel_code` values.

Suggested initial codes:

| Type | Subtype | Channel Code |
|---|---|---|
| purchase | 1st_party_online | `purchase:online_store` |
| purchase | 1st_party_offline | `purchase:offline_store` |
| purchase | 3rd_party_online | `purchase:marketplace` |
| purchase | 3rd_party_offline | `purchase:partner_store` |
| purchase | shopify_store | `integration:shopify` |
| lifecycle | birthday | `lifecycle:birthday` |
| lifecycle | anniversary | `lifecycle:anniversary` |
| lifecycle | tier_upgrade | `lifecycle:tier_upgrade` |
| lifecycle | profile_completion | `lifecycle:profile_completion` |
| campaign | mission | `campaign:mission` |
| campaign | checkin | `campaign:checkin` |
| campaign | form | `campaign:form` |
| campaign | referral | `campaign:referral` |
| campaign | social | `campaign:social` |
| custom | custom | `custom:generic` |

### Phase 2 — Preserve Existing Merchant Rows

Classify current `earn_channel` rows:

- If `channel_code` maps cleanly to a registry code, treat as override.
- If Shopify system row exists, map to `integration:shopify`.
- If no registry mapping exists, treat as custom/legacy physical channel.

Do not delete existing rows during migration.

For merchants with custom copy/assets/order, keep those values in `earn_channel` so the effective resolver returns the same display.

### Phase 3 — Effective Resolver

Create the resolver function/view.

Initial resolver can support:

- existing overrides/custom rows
- feature-config-driven channels
- Shopify integration channel
- lifecycle birthday/anniversary channel

Return the same field names expected by `bff_get_earn_channels`.

### Phase 4 — BFF Read Cutover

Update `bff_get_earn_channels` to read the resolver.

Validate:

- Existing merchant with physical rows sees no frontend-visible change.
- Merchant with Shopify sees Shopify channel from registry + integration state + override.
- Merchant with eligible feature but no physical row sees default channel.
- Merchant with hidden override does not see that channel.
- Existing translations still apply to physical override rows.

Update `bff_admin_get_earn_channels` to read effective admin channels, while preserving `registry` and `options`.

### Phase 5 — Write Path Hardening

Update admin write functions:

- `bff_upsert_single_earn_channel` creates overrides for computed defaults.
- `bff_upsert_earn_channel` no longer deletes computed/default/system rows accidentally.
- `bff_delete_earn_channel` hides computed defaults instead of deleting, or returns a protected response.

### Phase 6 — Cache Invalidation

Extend invalidation beyond `earn_channel` changes:

- registry updates
- feature_config updates
- merchant plan changes
- lifecycle workflow changes
- Shopify integration state changes

Start conservatively by invalidating on more events than strictly needed. Tighten later if cache churn becomes a problem.

## Backward Compatibility

Frontend member app should not notice:

- `bff_get_earn_channels` response shape stays the same.
- Existing fields stay populated.
- Existing merchant display copy stays preserved through override rows.
- Existing Shopify merchants still see Shopify.
- Custom merchant-created channels still work.

Admin frontend may receive extra metadata but should not need to consume it immediately.

## Open Product Decisions

Before implementation, confirm:

1. Should a lifecycle channel appear only when it awards points/currency, or whenever the lifecycle automation exists?
2. Should disabled but configured sub-features appear as inactive/admin-only channels, or disappear entirely from member app?
3. Which channels are plan-entitlement-only versus configuration-dependent?
4. Should merchants be allowed to hide plan-provided default channels?
5. Should merchants be allowed to change the method type of default channels, or only copy/assets/order?
6. Should missing registry default copy block visibility, or should display fall back to `display_name` only?

## Recommended First Implementation Slice

Start with a narrow, low-risk slice:

1. Enrich registry for:
   - `integration:shopify`
   - `purchase:marketplace`
   - `purchase:receipt_upload`
   - `lifecycle:birthday`
   - `lifecycle:anniversary`
2. Create effective resolver for these rows only.
3. Cut over `bff_get_earn_channels`.
4. Validate against existing merchants with current physical rows.
5. Cut over `bff_admin_get_earn_channels`.
6. Harden write/delete paths.
7. Expand campaign and custom channel handling.

This reduces risk because the first slice covers the exact pain points: Shopify, plan-enabled earn methods, and lifecycle birthday/anniversary display.
