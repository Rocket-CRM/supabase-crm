# Display Settings

> Per-domain reference. Read ONLY when working on this domain. For the keyword → file map, see `_index.md`.

**Keywords:** display_settings, display_block_template, display_blocks, homepage, block_type, block_style, profile_card, banner, banner_hero, navigation, bottom_menu, announcement, group_1, group_2, object (group), entity (item), persona_ids, enrichment, display_page_type, display_block_type, merchant_widget_settings, widget_config_template, widget_type, shopify_widget

**Source:** `Display_Settings.md`

**Tables:**
- `display_settings` (per-merchant placements, `config` jsonb)
- `display_block_template` (global catalogue of `(block_type, block_style)` shapes)
- `merchant_display_settings` (per-merchant brand theme — `primary_color`, `secondary_color`, `logo`, `border_radius_*`, `ui_config`, plus the merchant-level points display: `points_unit_label`, `points_symbol_type`, `points_symbol_icon`, `points_symbol_image_url`). Single source of truth for primary color + points label/symbol used by widget, LIFF, and admin views.
- `merchant_widget_settings` (per-merchant widget surface config; one row per `(merchant_id, widget_type)`; `config` jsonb — does NOT store primary_color or points)
- `widget_config_template` (global catalogue of widget surfaces with `config_default` jsonb; mirrors `display_block_template`)

**Supabase Functions:**

| Function | Type | Purpose |
|---|---|---|
| `api_get_display_blocks_cached(p_page, p_language, p_merchant_code)` | API | Public FE page load (merchant_code param); cached, fail-soft per block |
| `bff_get_display_blocks_cached(p_page, p_language)` | BFF | Authenticated FE page load; cached, includes `ui_config`, fail-soft per block |
| `admin_get_display_blocks(p_page)` | BFF | Admin editor list — active + inactive, with `persona_ids` merged and `ui_config`, fail-soft per block |
| `bff_get_display_settings(p_page, p_language_code)` | BFF | Raw rows + translations; does not enrich |
| `fn_enrich_display_config(p_config)` | Backend | Entity lookups for `group_*.items[*].entity`; skips inactive groups; skips non-UUID entity with `RAISE NOTICE` (never raises) |
| `fn_build_display_config_with_translations(...)` | Backend | Enrichment + per-language translation overlay |
| `fn_derive_display_block_ui_config(...)` | Backend | Computed UI hints |
| `fn_transform_images_to_arrays(...)` | Backend | Legacy scalar→array image normalisation |
| `fn_invalidate_display_blocks_cache(p_merchant_id)` | Backend | Purge all cache keys for a merchant |
| `get_display_settings_menu()` | Backend | Catalogue of templates + styles for the admin editor |
| `get_entity_options_by_type(p_entity_type)` | Backend | `{id, name}[]` picker source. Accepts `reward`, `mission`, `tier`, `persona`, `product_*`, `store`, `store_attribute_set` |
| `trigger_validate_display_settings_config` | Trigger | BEFORE INSERT/UPDATE on `display_settings`; rejects non-UUID `entity` with SQLSTATE 22P02 naming the offending path |

**Key Business Rules:**
- `config.group_*.items[*].entity` must be "" or a UUID. Labels like `"reward"` are rejected by trigger.
- `object` on a group is one of `rewards | missions | tiers | personas` (or ""); only these produce entity enrichment.
- `active: false` on a group short-circuits enrichment for that group.
- Row-level `active_status = false` hides a block from the user-facing RPCs but not the admin RPC.
- `persona_ids` is a `text[]` accepting UUIDs and/or the literal string `'guest'` for unauthenticated viewers; empty/NULL means all personas.
- Cache key includes `merchant_id`, page, persona, and all-languages; TTL 300s; invalidated by AFTER triggers on `display_settings` and `translations`.

---

## Widget Display Settings (sub-domain)

Sub-menu under *Display Settings* in admin sidebar (alongside Brand Theme, Tier Display). Powers customer-facing widget surfaces — Shopify widget v1, BigCommerce/Web Widget future.

**Single source of truth for merchant-level display values is `merchant_display_settings`:**
- `primary_color` — used everywhere theme color is applied
- `points_unit_label` — merchant's chosen name for their points unit ("Coins", "Stars", "แต้ม"). Used by widget AND LIFF mobile app AND admin views
- `points_symbol_type` / `points_symbol_icon` / `points_symbol_image_url` — symbol next to point counts

Widget config only stores widget-specific layout (`theme.mode`, header background, brand mark, coins layout). It does NOT duplicate `primary_color` or `point.*`. The widget read RPCs surface those merchant-level values in a `resolved` block.

Mirrors brand-theme pattern: in-place edits, no versioning, **no per-language translation overlay** (matches `merchant_display_settings`). If translation is later required, the canonical path is to register `merchant_widget_settings` as an `entity_type` in `translation_api` (the existing `/translation` admin), not to build per-page editors.

### Tables

| Table | Shape | Notes |
|---|---|---|
| `merchant_widget_settings` | `(id uuid, merchant_id uuid FK→merchant_master, widget_type text, config jsonb, active_status bool, created_at, updated_at)` | UNIQUE `(merchant_id, widget_type)` — one row per surface per merchant. RLS: isolation by `request.jwt.claims.merchant_id` + permissive `SELECT` for anon (storefront via `api_*`). |
| `widget_config_template` | `(id uuid, widget_type text UNIQUE, config_default jsonb, schema_version text, storage_bucket text, storage_path_template text, created_at, updated_at)` | Catalogue of widget surfaces. Seeded with `widget_type='shopify'`, `storage_bucket='images'` (same as main display settings), `storage_path_template='widget/{merchant_id}/'`. RLS: permissive read. |

### `config` JSONB shape (Shopify v1, schema_version `1.0.0`)

- `theme.mode` ∈ `{light, dark}` (primary_color is NOT here — read from `merchant_display_settings.primary_color`)
- `header.background.type` ∈ `{solid, gradient, image}` with sub-objects `solid.color`, `gradient.{from,to,angle}`, `image.{items[],carousel}`
- `header.background.image.items[]` — 1..10 entries, each `{id, url, alt, order, size_kb≤1024}`; alt required
- `header.background.image.carousel` — `{autoplay bool, interval_ms 1000..30000, transition fade|slide}`
- `header.coins_layout` ∈ `{default, overlay, below}`
- `header.brand_mark` — `{type text|image|none, text 1..40, image_url, position left|center|right}`
- `_schema_version` — `'1.0.0'`

**`point` is NOT stored in widget config.** Points unit name + symbol are merchant-level (used by widget AND LIFF AND admin views), so they live on `merchant_display_settings.points_*` and are surfaced to the widget via the `resolved` block. `fn_validate_widget_config` rejects any payload containing a `point` key with a `DEPRECATED` error.

**No per-language translation.** The merchants stored config is the single source of truth. If a merchant needs to localize `header.brand_mark.text` or image alts in the future, register `merchant_widget_settings` as an `entity_type` in `get_translation_entity_types()` and let `translation_api` / the `/translation` admin page handle it — do not add a parallel overlay here.

### Functions

| Function | Type | Purpose |
|---|---|---|
| `get_widget_settings_menu()` | Backend | Catalogue of available widget surfaces with per-widget `storage` hint — feeds admin surface picker. Mirrors `get_display_settings_menu`. |
| `fn_resolve_widget_storage(p_widget_type, p_merchant_id)` | Backend | Returns resolved storage upload target `{bucket, path_prefix, public, max_file_size_kb, allowed_mime_types}` for FE upload widgets. Substitutes `{merchant_id}`, `{merchant_code}`, `{widget_type}` tokens. |
| `admin_get_widget_settings(p_widget_type)` | BFF | Admin editor load: returns merchant row (or template default if none) + `resolved` block (primary_color + points display) from `merchant_display_settings` + resolved `storage` target. |
| `admin_upsert_widget_settings(p_widget_type, p_config, p_active_status)` | BFF | In-place upsert keyed on `(merchant_id, widget_type)`. Pre-validates via `fn_validate_widget_config` — returns structured error array on failure. |
| `admin_reset_widget_settings(p_widget_type)` | BFF | Resets row to `widget_config_template.config_default`. |
| `admin_upsert_merchant_points_display(p_label, p_symbol_type, p_symbol_icon, p_symbol_image_url)` | BFF | Targeted write for `merchant_display_settings.points_unit_label`/`points_symbol_*`. Validates icon list (12 keys) + cross-field rule (image type requires non-empty url). Single source of truth for the merchant's points unit name + symbol used by widget, LIFF, admin views. |
| `bff_get_widget_settings(p_widget_type)` | BFF | Authenticated read. Cached 300s in `extensions.ui_cache`. Resolves primary_color, points display, and storage target. No language param. |
| `api_get_widget_settings_cached(p_widget_type, p_merchant_code)` | API | Anon storefront read for widget JS. Cached 300s. Fail-soft — returns template defaults on any error. No language param. |
| `fn_validate_widget_config(p_widget_type, p_config)` | Backend | Returns `{ok bool, errors[]:{path,code,message}}`. Used by trigger and admin pre-save. Rejects deprecated `point` block. |
| `fn_widget_config_with_defaults(p_widget_type, p_config)` | Backend | Shallow-merges saved config over `config_default`. |
| `fn_resolve_widget_merchant_display(p_merchant_id)` | Backend | Returns `{primary_color, points:{unit_label, symbol_type, symbol_icon, symbol_image_url}}` from `merchant_display_settings`. Single helper used by all 3 widget read RPCs to keep the `resolved` block consistent. |
| `fn_invalidate_widget_settings_cache(p_merchant_id, p_widget_type)` | Backend | Purges `merchant:{id}:widget:{type}` cache key via `extensions.ui_cache_del`. |
| `trigger_validate_widget_settings_config` | Trigger | BEFORE INSERT/UPDATE on `merchant_widget_settings`; raises SQLSTATE 22P02 with offending JSON path on validation failure. |
| `trigger_invalidate_widget_settings_cache_on_change` | Trigger | AFTER INSERT/UPDATE/DELETE on `merchant_widget_settings`. |
| `trigger_invalidate_widget_cache_on_merchant_display_change` | Trigger | AFTER INSERT/UPDATE/DELETE on `merchant_display_settings`. Purges all widget cache keys for that merchant — ensures `primary_color` and `points_*` changes propagate within seconds. |

### Key Business Rules

- **Single source of truth for primary color and points display**: widget reads `merchant_display_settings.primary_color`, `points_unit_label`, `points_symbol_*` via the `resolved` block; never store these in `merchant_widget_settings.config`. Same values are used by LIFF mobile app and admin history pages — change once, applies everywhere.
- **Tier list / coin balance / earn-redeem CTAs / greeting text** are NOT stored here. Widget runtime fetches them from Loyalty › Tier, Loyalty › Currency, Loyalty › Rules, and Member Display / Translation respectively.
- `active_status = false` hides the widget from the public `api_*` RPC but still loads in `admin_*`/`bff_*`.
- `merchant_id` in `merchant_widget_settings` cascades on merchant delete; `translations` rows for that entity must be cleaned up explicitly (no FK cascade — same as other entity_types).
- Cache key: `merchant:{merchant_id}:widget:{widget_type}`. TTL 300s. Invalidated by AFTER trigger on `merchant_widget_settings`.
- Image upload size enforced server-side at ≤1024 KB (1 MB) per item; 1..10 items per carousel.
- Carousel transitions: `fade` and `slide` only. `interval_ms` ∈ [1000, 30000].
- **FE never hardcodes the storage bucket.** All read RPCs return a `storage` block with `{bucket, path_prefix, public, max_file_size_kb, allowed_mime_types}`. Default is the public `images` bucket (same as `merchant_display_settings`) under `widget/{merchant_id}/`.

---
