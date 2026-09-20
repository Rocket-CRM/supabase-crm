# Display Settings

> Per-domain reference. Read ONLY when working on this domain. For the keyword → file map, see `_index.md`.

**Keywords:** display_settings, display_block_template, display_blocks, homepage, block_type, block_style, profile_card, banner, banner_hero, navigation, bottom_menu, announcement, group_1, group_2, object (group), entity (item), persona_ids, enrichment, display_page_type, display_block_type, merchant_widget_settings, widget_config_template, widget_type, shopify_widget, shopify_brand_scheme, on-site content

**Source:** `Display_Settings.md` (canonical spine — Shopify Horizon scheme, colour ladder, landing CTAs, widget v1.1.0)

**Tables:**
- `display_settings` (per-merchant placements, `config` jsonb)
- `display_block_template` (global catalogue of `(block_type, block_style)` shapes)
- `merchant_display_settings` — points display + `shopify_brand_scheme` (v2.1: `tokens.primary`, `background`, `dark_surface`, `text`, optional buttons, `radius_px`); `primary_color` synced from `tokens.primary` on scheme upsert
- `merchant_widget_settings` (per `(merchant_id, widget_type)`; `config` jsonb — layout/header chrome only, **not** primary colour or points)
- `merchant_shopify_landing_page_settings` — SEO, publish status, slim `config.theme` (padding + import meta; no `cta_defaults`)
- `widget_config_template` (global catalogue of widget surfaces with `config_default` jsonb)

**Shopify on-site colour (summary)** — SQL stores raw brand scheme + widget layout JSON; **rewarding-shopify** `widget-builder` derives landing section colours from the scheme ladder and widget **accents** (hero, launcher, links, progress) from `tokens.primary`; widget page/cards use fixed Figma neutrals. See `Display_Settings.md` §Rules (colour ladder, landing CTAs, brand scheme).

**Supabase Functions:** (member-app + widget + Shopify landing — full list in `Display_Settings.md` §System)

| Function | Type | Purpose |
|---|---|---|
| `api_get_display_blocks_cached` / `bff_get_display_blocks_cached` | API/BFF | Member-app blocks |
| `admin_get_shopify_brand_scheme` / `admin_upsert_shopify_brand_scheme` | BFF | v2.1 scheme read/write; upsert busts landing + widget cache |
| `admin_get_widget_settings` / `admin_upsert_widget_settings` | BFF | Widget JSON per `widget_type` (Shopify panel schema **1.1.0**) |
| `api_get_widget_settings_cached` / `bff_get_widget_settings` | API/BFF | Storefront widget payload incl. raw `brand_scheme` |
| `api_get_shopify_landing_page_cached` | API | Landing payload incl. `brand_scheme`, enriched sections |

---

## Widget Display Settings (sub-domain)

Sub-menu under *Display Settings* in admin sidebar. Powers customer-facing widget surfaces — Shopify widget v1, BigCommerce/Web Widget future.

**Merchant-level (`merchant_display_settings`):**
- `shopify_brand_scheme` v2.1 — Horizon-aligned tokens; theme import is field copy (see canonical doc)
- `primary_color` — synced from `tokens.primary`; used in `resolved.primary_color` for widget/launcher
- `points_unit_label`, `points_symbol_*` — shared with LIFF and admin

**Widget config (`merchant_widget_settings`, Shopify `_schema_version` 1.1.0):**
- Header: `background.type` `solid` | `gradient` | `image`; **solid/gradient colours are not stored** — derived from brand scheme at render; merchant sets gradient **angle** only when `type=gradient`
- `header.brand_mark`, `header.coins_layout`, optional image carousel
- **`theme.mode` deprecated** — storefront derives light/dark from scheme background contrast
- Does **not** store `primary_color`, `point.*`, or header hex endpoints (removed in v1.1.0)

Detail: `docs/WIDGET_SETTINGS_FE_SPEC.md` + `Display_Settings.md` §Rules / §System.

**Cache:** widget key `merchant:{id}:widget:{type}` (~300s); invalidated on widget row change and on `merchant_display_settings` change (scheme/points).

**FE spec:** `docs/WIDGET_SETTINGS_FE_SPEC.md`
