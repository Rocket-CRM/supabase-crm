# Display Settings

Server-driven layout and chrome for where members see the loyalty program: the native member app (homepage and other pages), headless online store blocks, Shopify storefront touchpoints (landing page, widget panel, customer-account hub), and merchant branding (points label, symbols, widget theme).

Owner surfaces: loyalty-admin, loyalty-user, rewarding-shopify (theme + customer-account UI extensions), Edge `shopify-extension-api` / `shopify-proxy`

## Concept

Display settings answer **what shoppers see** and **how it is packaged** on each channel. Program truth (points, tiers, rewards, referrals, earn rates) always comes from CRM composition at read time — not from hand-typed catalog labels in Shopify metafields.

**Block template** — Global shape catalogue (`block_type` + `block_style` + default JSON). Not per-merchant.

**Placement** — One row per merchant, page, and sort order: which template variant is used and how `config` overrides defaults. Member-app pages use enums such as `homepage`; Shopify loyalty landing uses `shopify_loyalty_landing` with `shopify_landing_*` block types.

**Enrichment** — At read time, UUID picks in `group_*` items resolve to live reward/mission/tier/persona names and images; profile-card ticket rows get balances overlaid after cache. Landing sections on Shopify merge earn/spend/VIP/referral tiles from program truth.

**Persona scope** — Placements may target all personas, specific persona UUIDs, and/or `guest` for anonymous homepage variants.

**Merchant display settings** — Points unit label and symbol used across widgets and read-only in the landing CMS (`merchant_display_settings`).

**Shopify brand scheme (v2.1)** — Stored on `merchant_display_settings.shopify_brand_scheme` (`_schema_version: 2.1.0`): four required tokens (`primary`, `background`, `dark_surface`, `text`), optional primary/secondary button colours, and `radius_px`. Token names follow Shopify Horizon's colour-scheme roles so theme import is a field copy: `primary` ← scheme `primary`, `background` ← `background`, `text` ← `foreground`, `buttons.primary.bg/text` ← `primary_button_background/text`, `buttons.secondary.text` ← `secondary_button_text`, `radius_px` ← theme `buttons_radius`. `dark_surface` has no Horizon role — it is the background of the theme's darkest scheme. Themes without a `primary` role (Dawn family, `color_palette` model) take the primary button fill, else text; field presence decides, never colour values. `primary` paints the launcher, the widget header default, links, icon tints and the default primary-button fill; `background` is the widget panel body. 2.0 rows carried the same value as `tokens.brand`; merge accepts it and rewrites to `primary`. SQL merge/validate persists **chosen** colours only; derived colours (section mode, muted/body/heading/link, borders, shadows, button fill/hover, hero card contrast) are computed in the **rewarding-shopify** bundle at render. Admin edits the raw scheme; previews iframe the same bundle.

**Widget settings** — Per–`widget_type` JSON (theme, header, earn-channel chrome). `shopify` drives the storefront panel; `shopify_hub` holds Loyalty Hub hero / redeem modal / product fallback images.

**Shopify touchpoint** — A merchant-facing surface (landing page, Loyalty Hub, points on product, order banners, wishlist, widget drawer). Each touchpoint has Rocket admin (configure + install walkthrough) and Shopify packaging (theme app extension vs customer-account UI extension). See Journeys › Shopify.

**On-site content hub** — Shopify-embedded admin route that groups touchpoint setup, publish state for landing, and deep links into Shopify’s theme/checkout editors.

## Rules

- Empty `config` on a placement falls back to the matching template’s default JSON shape.
- `group_*.items[].entity` must be `""` or a canonical UUID; labels raise validation error on save (`22P02`).
- `group_*` with `active: false` is omitted from enrichment output entirely.
- Non-UUID `entity` values at read time: logged, item returned unchanged (enrichment never aborts the page).
- Only `rewards`, `missions`, `tiers`, `personas` as `group_*.object` trigger entity enrichment; other objects pass through.
- Profile-card `ticket` fields require a merchant-owned `ticket_type_id` at save; runtime balance overlay runs on every member read (not cached).
- Cache TTL ~5 minutes for member-app display blocks; any write to placements or display translations invalidates all cache keys for that merchant.
- Enrichment failure on a single block returns raw `config` plus `enrichment_error`; sibling blocks still render.
- **Shopify landing** — Publish transitions `merchant_shopify_landing_page_settings.publish_status` to `published`; storefront reads composed payload via app proxy + theme extension. Entitlement **`display.shopify_landing_page`** (Essential+) required; customer-account surfaces and wishlist are on all plans including Free.
- **Shopify brand scheme** — Optional button hex `#1C1C1C` is stored as `null` (Derived). Landing section `surface.swatch` is `background | dark_surface | primary | custom` (`primary` uses `tokens.primary`; legacy `brand`/`extra` normalize to `primary` on read). `merchant_display_settings.primary_color` is synced from `tokens.primary` on every scheme save; upsert invalidates landing and widget caches. Landing enrichment does not attach `style_tokens`; cached/admin landing payloads expose top-level `brand_scheme` (merged raw) and slim `theme` (`section_padding_px`, import meta only).
- **Shopify hub / banners** — View models are composed server-side (`fn_compose_shopify_hub`, widget settings cache). Checkout **points estimate** is not shipped (extension directory excluded from production app manifest).

## Journeys

### Admin journey

| Knob | Effect |
| --- | --- |
| Block type / style | Chooses template shape and admin form fields |
| Order | Sort within page |
| Active | Row included in member payload when true |
| Persona IDs | Restricts placement to listed personas / `guest` |
| `group_*` items + `object` | Picks entities enriched at read time |
| Link type / page | In-app route, external URL, drawer, or outbound handoff |
| Translations | Per-field languages merged on cached read |
| Widget theme / points label | Panel chrome and earn estimate copy on Shopify |
| Hub image slots | Hero, redeem modal, product fallback for Loyalty Hub |
| Landing theme / SEO / CTA defaults | Page shell; sections still use `display_settings` rows |

| Page | Owning repo | BFF / RPC |
| --- | --- | --- |
| Display Settings hub | loyalty-admin | Card visibility from surface + plan |
| Member app homepage / pages | loyalty-admin | `admin_get_display_blocks`, batch create/update/delete |
| Block picker metadata | loyalty-admin | `get_display_settings_menu()` |
| Points label (global) | loyalty-admin | `admin_upsert_merchant_points_display` → `merchant_display_settings` |
| Shopify brand colours | loyalty-admin | `admin_get_shopify_brand_scheme` / `admin_upsert_shopify_brand_scheme` → `{ scheme, updated_at }` |
| Online store display | loyalty-admin | Same block pipeline, `page` for headless `/store` |
| Shopify widget panel | loyalty-admin | `admin_get_widget_settings` / `admin_upsert_widget_settings` (`shopify`) |
| Shopify Loyalty Hub images | loyalty-admin | `admin_get_widget_settings` / `admin_upsert_widget_settings` (`shopify_hub`) |
| Shopify landing CMS | loyalty-admin | `admin_get_shopify_landing_page_settings`, section batch + publish RPCs |
| On-site content hub + setup | loyalty-admin | Walkthrough pages; CTAs open Shopify editors via deep links |

**Member app (native admin)**

1. Open **Display Settings** → **Member app** (core card) for homepage or other `display_page_type` pages.
2. Add, reorder, or deactivate blocks; pick style; configure groups, links, and persona scope.
3. Save → rows in `display_settings`; triggers drop display-block cache for the merchant.
4. Preview uses admin read path (enriched, not cached).

**Shopify merchant admin**

1. Open **On-site content** (`/on-site-content`, Shopify embedded only) — touchpoint hub with landing status, widget panel link, and embedded-content setup cards.
2. **Landing** — Overview at `/on-site-content/landing-page` (publish state, URL hint); **Edit** opens full-screen CMS at `/display-settings/shopify-landing-page` (sections, brand scheme modal, SEO, publish).
   - **Onboarding brand step** (`/onboarding`, step 4) — theme import auto-opens on first visit and is the primary action. The import picker lists each theme colour scheme with its `primary` swatch + hex first, then small background and primary-button swatches. After import the step shows Primary (editable), Background, Text and Primary button (read-only; "Primary (default)" when the button fill is derived) and a "Text on primary" white/black toggle (`buttons.primary.text`). Full editing stays in the brand scheme modal (**Select**).
3. **Widget panel** — `/display-settings/shopify-widget` (theme, header, points tab, earn-channel tab).
4. **Loyalty Hub images** — `/display-settings/shopify-loyalty-hub` (image slots for hub composer).
5. Each embedded touchpoint (**Loyalty Hub**, **points balance**, **points after purchase**, **wishlist**, **points on product**) — `/on-site-content/<surface>` setup page with preview + numbered steps; primary CTA opens Shopify checkout/theme editor (published checkout profile + app id via `editor-deep-links.ts`).
6. **Display Settings** hub (Shopify surface) also links landing, widget, hub images, and online store cards without replacing the on-site content walkthroughs.

### Member journey

| Surface | Owning repo | BFF / RPC |
| --- | --- | --- |
| Authenticated app pages | loyalty-user | `bff_get_display_blocks_cached` |
| Public / code-based merchant | loyalty-user | `api_get_display_blocks_cached` |
| Headless online store | loyalty-user | Display blocks for store pages + chrome tabs |

1. App requests blocks for `page` (+ language).
2. Server resolves persona (`guest` when logged out on public path).
3. Cache hit → optional profile/ticket overlay; miss → enrich then cache.
4. FE renders ordered blocks; link clicks follow `link_type` / handoff edges.

### Shopify

Shopper-facing touchpoints (packaging in **rewarding-shopify**; gateways in Edge). Admin routes verified in loyalty-admin.

| Touchpoint | Shopify packaging | Rocket configure | Rocket install walkthrough |
| --- | --- | --- | --- |
| Loyalty landing page | Theme extension `shopify_landing_*` sections | CMS `/display-settings/shopify-landing-page`; overview `/on-site-content/landing-page` | Theme: add page / app blocks |
| Loyalty Hub | UI extension `loyalty-hub` (`loyalty-account`) | Hub images `/display-settings/shopify-loyalty-hub`; setup `/on-site-content/loyalty-hub` | Checkout & accounts editor |
| Points on product | Theme block `points-on-product` | Setup `/on-site-content/points-on-product` | Theme product template |
| Customer account points banner | UI extension `loyalty-points-balance` | Setup `/on-site-content/points-balance` | Accounts editor, order index |
| Points after purchase | UI extension `loyalty-points-earned` (`loyalty-checkout`) | Setup `/on-site-content/points-earned` | Thank-you / order status |
| Wishlist | Theme `wishlist-heart` + UI `loyalty-wishlist` | Setup `/on-site-content/wishlist` | Theme + accounts editor |
| Widget panel | Theme + `widget.js` launcher | `/display-settings/shopify-widget` | Theme (launcher on hub: coming soon) |

**Shopper flow (summary)**

1. **Landing** — Public `api_get_shopify_landing_page_cached` (cache key `:v2:`); payload includes `brand_scheme` + slim `theme`; sections enriched without `style_tokens`; member overlay when logged in; CTAs open widget, login, or custom URL.
2. **Loyalty Hub** — Session token → `shopify-extension-api` `/hub`; redeem POST `/hub/redeem` with status poll; referrals and spend tiles from composer.
3. **Points on product** — Anonymous `api_get_widget_settings_cached('shopify', shop)`; earn estimate from `resolved.earn_rate`.
4. **Points balance banner** — Extension `GET /balance` (member JWT); `{points}` / `{points_name}` in merchant message.
5. **Points after purchase** — `GET /order-points?order_id=`; guest-safe `{ status: 'guest' }`.
6. **Wishlist** — Theme/proxy HMAC path vs account UI `GET/POST /wishlist` (no app proxy from UI extension sandbox). Headless `/store/wishlist` uses Supabase JWT — see **System › Shopify** below (`wishlist_item`, `bff_user_*` / `fn_shopify_wishlist_*`).

Extension collections: `loyalty-account` → hub, balance, wishlist; `loyalty-checkout` → **points-earned only** (not balance banner).

## System

### Data model

| Table | Role |
| --- | --- |
| `display_block_template` | Global catalogue of block shapes (`block_type`, `block_style`, default `config`) |
| `display_settings` | Per-merchant placements: `page`, `order`, `active_status`, `persona_ids`, `config` |
| `merchant_display_settings` | Points unit label, symbol type/icon/image, `shopify_brand_scheme` (v2), `primary_color` (synced from scheme brand) |
| `merchant_widget_settings` | Per `widget_type` (`shopify`, `shopify_hub`, …) JSON config + `active_status` |
| `merchant_shopify_landing_page_settings` | Landing page SEO, CTA defaults, `publish_status`; per-merchant `config.theme` holds padding + import flags (not colour palette) |
| `widget_config_template` | Default shapes for widget types (validation / merge) |

**`display_block_template`** — `block_type` enum includes member blocks (`banner`, `profile_card`, `tier_progress`, …) and Shopify landing section types (`shopify_landing_hero`, `shopify_landing_how_it_works`, `shopify_landing_ways_to_earn`, `shopify_landing_ways_to_spend`, `shopify_landing_referrals`, `shopify_landing_vip`, `shopify_landing_faq`). `block_style` is free text (e.g. `style_1`, `grid`, `carousel`).

**`display_settings`** — `page` enum includes `homepage`, `rewards_page`, `profile_page`, `shopify_loyalty_landing`. NULL `config` → fall back to matching template row.

### Config shape (member blocks)

```jsonc
{
  "group_1": { "items": [ /* item objects */ ] },
  "group_2": {
    "active": false,
    "object": "rewards",
    "items": [
      {
        "entity": "<uuid>",
        "image": "",
        "order": 0,
        "custom_image": false
      }
    ]
  }
}
```

Only `group_*` keys are scanned by enrichment/validation. Other top-level keys are block-specific (`alignment`, `show_text`, `block_header_text`, `show_my_qr`, …).

**Profile card (`profile_card`)** — `group_1.items[*]` with `data_type`:

| `data_type` | Runtime overlay (user-facing RPCs only) |
| --- | --- |
| `points_balance`, `tier`, `name`, `persona`, `qr_code`, `amount_to_next_tier` | Member FE / summary RPCs |
| `ticket` | Requires `ticket_type_id` at save; `fn_overlay_profile_card_user_values` adds `value`, `ticket_type_name`, `ticket_code` after cache (every read; guest → `0`) |

**`group_*.object` enrichment**

| `object` | Source | Enriched fields |
| --- | --- | --- |
| `rewards` | `reward_master` | `entity_name`, `entity_image`, `entity_description`, `fallback_points` |
| `missions` | `mission` | name, image, description |
| `tiers` | `tier_master` | name, icon |
| `personas` | `persona_master` | name, image |

**`entity` invariant** — `""` or UUID; `trigger_validate_display_settings_config` raises `22P02` on labels.

### Functions

**Read path (member app blocks)**

| Function | Role |
| --- | --- |
| `api_get_display_blocks_cached` | Public FE; cached; enriches; persona `guest` when unauth |
| `bff_get_display_blocks_cached` | Authenticated FE; cached; adds `ui_config` |
| `admin_get_display_blocks` | Admin; not cached; active + inactive |
| `bff_get_display_settings` | Raw rows + translations (no enrichment) |
| `fn_enrich_display_config` | Group enrichment; never raises |
| `fn_build_display_config_with_translations` | Enrichment + `display_block_item` translations |
| `fn_overlay_profile_card_user_values` | Post-cache ticket balances |
| `fn_derive_display_block_ui_config` | Admin `link_type_options` / `page_options` when block has links |
| `fn_get_display_link_destinations` | Canonical link catalog |
| `get_display_settings_menu` | Admin picker `{ blocks, link_types, pages }` |
| `get_entity_options_by_type` | Admin entity picker by type (`reward`, `mission`, `tier`, `persona`, products, stores, `ticket_type`, …) |
| `admin_create_display_block` / `admin_update_display_block` / `admin_delete_display_block` / `admin_batch_update_display_blocks` | Placement CRUD |
| `fn_invalidate_display_blocks_cache` | Merchant-wide cache bust (settings + translation triggers) |

**Widget + merchant display**

| Function | Role |
| --- | --- |
| `admin_get_widget_settings` / `admin_upsert_widget_settings` / `admin_reset_widget_settings` | Widget JSON per `widget_type` |
| `bff_get_widget_settings` / `api_get_widget_settings_cached` | Member/storefront reads; widget cache key `:v2:`; payload includes `brand_scheme` (raw merged) |
| `admin_upsert_merchant_points_display` | Points label + symbol on `merchant_display_settings` |
| `admin_get_shopify_brand_scheme` / `admin_upsert_shopify_brand_scheme` | Read/write v2.1 scheme; response `{ scheme, updated_at }` only; upsert syncs `primary_color` from `tokens.primary` |
| `fn_shopify_brand_scheme_default` / `fn_shopify_brand_scheme_merge` / `fn_validate_shopify_brand_scheme` | v2.1 shape (`tokens.primary`), merge (incl. v1 `heading` → `text`, v2.0 `brand` → `primary`), validation |
| `fn_shopify_landing_page_theme_layout` | Slim landing `theme` JSON (padding + import meta) |
| `fn_resolve_widget_merchant_display` | Points/tiers/earn + raw merged `scheme` (no `scheme_resolved`) |

**Shopify landing**

| Function | Role |
| --- | --- |
| `admin_get_shopify_landing_page_settings` / `admin_upsert_shopify_landing_page_settings` | Page shell + theme |
| `admin_publish_shopify_landing_page` / `admin_unpublish_shopify_landing_page` | Publish state |
| `admin_batch_update_shopify_landing_sections` | Section rows on `display_settings` |
| `admin_enrich_shopify_landing_preview_sections` | Admin preview enrichment |
| `api_get_shopify_landing_page_cached` | Storefront cached payload (`brand_scheme`, slim `theme`, `theme_resolved` points/primary only) |
| `fn_enrich_shopify_landing_sections` / `fn_overlay_shopify_landing_member_state` | Program tiles + member overlay |
| `fn_invalidate_shopify_landing_page_cache` | Landing cache bust |

**Shopify Loyalty Hub (composer)**

| Function | Role |
| --- | --- |
| `bff_user_get_shopify_hub` | Authenticated hub view model |
| `fn_compose_shopify_hub` / `fn_compose_shopify_hub_unbranded` | Guest/member composition |
| `fn_shopify_hub_apply_images` / `fn_shopify_hub_resolve_image` | Hub image slots from `shopify_hub` widget settings |

### Flows

**Member-app block load** — Request `page` + language → resolve merchant + persona → cache key `merchant:<uuid>:display_blocks:<page>:persona:<id|guest>:all_languages` (TTL 300s) → on miss: filter active placements, enrich each block, cache → overlay profile/ticket values → return ordered blocks. Per-block enrichment wrapped in exception handler: failure → raw `config` + `enrichment_error`.

**Link destinations** — Stored config uses `link_type` + `page` (+ `url` when external or `online_store` + `store_specific`). Catalog kinds: `page` (member routes), `drawer` (bottom sheets including `drawer_my-qr`), `online_store` (headless `/store…`). `handoff` uses Integration Hub `integration_key` from `bff_list_outbound_handoffs`, not the global pages list; member click → Edge `start-outbound-handoff`.

**Landing publish** — Admin saves sections + page settings → publish RPC sets `published` → storefront theme/bootstrap loads composed JSON/HTML via app proxy; earn/spend/VIP/referral section content from enrichment, not manual `group_*` catalogs.

### External services

| Service | Role |
| --- | --- |
| Edge **`shopify-extension-api`** | Customer-account UI extensions: verifies Shopify session token, resolves merchant, mints member JWT; routes `/hub`, `/balance`, `/order-points`, `/hub/activity`, `/hub/redeem`, `/wishlist` |
| Edge **`shopify-proxy`** | Theme app proxy HMAC + `logged_in_customer_id` + cookies (wishlist theme blocks) |
| **rewarding-shopify** | `extensions/loyalty-widget` (landing sections, points-on-product, wishlist heart); `loyalty-hub`, `loyalty-points-balance`, `loyalty-points-earned`, `loyalty-wishlist`; collection manifests `loyalty-account`, `loyalty-checkout` |
| **widget-builder** | Built assets for landing + widget panel |

`shopify-extension-api`: CORS `*`; JWT verified inside handler (`verify_jwt = false` on deploy).

### Known gaps

- Checkout **points estimate** UI extension deferred (Shopify Plus complexity; `loyalty-checkout-ext` not in production `extension_directories`).
- Widget **launcher** on Loyalty Hub marked coming soon in on-site content hub.
- Registry grep may lag newly shipped `admin_*_shopify_landing_*` / hub composer RPCs — verify live `pg_proc` when wiring new touchpoints.

### Shopify (System)

**Identity**

| Surface | Auth | Gateway |
| --- | --- | --- |
| UI extensions | Shopify session token | `shopify-extension-api` |
| Theme / app proxy | HMAC + customer id + cookies | `shopify-proxy` |
| Product points block | None | `api_get_widget_settings_cached` |

**`shopify-extension-api` routes (representative)**

| Method | Path | Member required | Backend |
| --- | --- | --- | --- |
| GET | `/hub` | No (guest composer) | `bff_user_get_shopify_hub` / `fn_compose_shopify_hub` |
| GET | `/balance` | Yes | Hub subset + affordable reward flag |
| GET | `/order-points` | No (guest-safe) | `bff_user_get_order_points` |
| GET | `/hub/activity` | Yes | History pages |
| POST | `/hub/redeem` | Yes | Redemptions + status poll |
| GET/POST | `/wishlist` | Yes | Wishlist get / toggle |

**Admin route index (on-site + display)**

| Route | Purpose |
| --- | --- |
| `/on-site-content` | Touchpoint hub |
| `/on-site-content/landing-page` | Landing overview |
| `/on-site-content/loyalty-hub` | Hub install walkthrough |
| `/on-site-content/points-balance` | Order list banner setup |
| `/on-site-content/points-earned` | After-purchase setup |
| `/on-site-content/points-on-product` | Product block setup |
| `/on-site-content/wishlist` | Wishlist setup |
| `/display-settings/shopify-landing-page` | Landing CMS |
| `/display-settings/shopify-widget` | Widget panel |
| `/display-settings/shopify-loyalty-hub` | Hub image slots |

**Config split (Shopify)**

| Concern | Store |
| --- | --- |
| Brand scheme v2, points name, symbol | `merchant_display_settings` (`shopify_brand_scheme`, `primary_color`) |
| Hub hero / redeem modal / product fallback images | `merchant_widget_settings` (`shopify_hub`) |
| Landing theme, SEO, CTA defaults | `merchant_shopify_landing_page_settings` |
| Landing section order/content | `display_settings` where `page = shopify_loyalty_landing` |
| Widget panel chrome | `merchant_widget_settings` (`shopify`) |

Platform plumbing (OAuth, app proxy paths, entitlements, deploy manifest): **Shopify.md**. Authoritative cross-touchpoint narrative: **requirements/reference/SHOPIFY_REFERRALS_ONSITE_INTEGRATIONS.md** Part 2.

## Related

- **Shopify.md** — OAuth, embedded auth, webhooks, billing sync, marketplace order path, `rewarding-shopify` packaging (not touchpoint CMS detail).
- **requirements/reference/SHOPIFY_REFERRALS_ONSITE_INTEGRATIONS.md** — Part 2 touchpoint catalog and engineering reference (sync with `~/Downloads/SHOPIFY_REFERRALS_ONSITE_INTEGRATIONS.md` when newer).
- **Tier.md** — `tier_progress` block and landing VIP enrichment.
- **Reward.md** / **Mission.md** — Featured entity sources for `group_*` picks.
- **Platform_Plan_Feature_Registry.md** — Landing entitlement and embedded gating keys.
- **Translation** — `display_block_item` entity translations on cached reads.
