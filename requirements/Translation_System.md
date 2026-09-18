# Translation System

Merchant-scoped **dynamic entity copy** (rewards, forms, display blocks, earn channels, …), **member-facing static UI strings** (page keys), and **admin dashboard copy** — with per-merchant default language, shared fallback rules, and isolated Redis caches.

Owner surfaces: loyalty-admin (language config + admin UI copy), loyalty-user (member UI + API language params), Open API getters, rewarding-shopify (same member resolution paths as loyalty-user for embedded storefront)

## Concept

The platform separates **what merchants configure in their primary language** (columns on master tables) from **overrides for other locales** (rows in a shared translation store). Members and APIs always request a **target language**; the backend resolves each field through a fixed fallback chain.

**Dynamic translation** — Optional per-field overrides tied to a concrete program object (a reward, tier, form field, display block, earn channel, etc.). Non-default languages live in the translation store; the merchant’s **default language** is always sourced from the entity’s master row at cache-build time.

**Member UI translation** — Global or merchant-specific strings keyed by **page** and **field** (titles, buttons, errors, redemption status labels). Loaded in bulk for the member app; no auth required.

**Admin UI translation** — A parallel static store and API for loyalty-admin chrome only (headers, section titles, grid columns, shared action buttons). Must not be mixed with member UI keys.

**Merchant languages** — Which of the four platform locales are active for a merchant, which one is default, and display order. Drives fallback and which language labels master-table content.

**Cache bundles** — Heavy read paths (rewards catalog, profile template, display blocks, earn channels) embed a `translations` object with all active languages in Redis so the client can switch language without a round trip when the bundle is already loaded.

**Supported locales** — English (`en`), Thai (`th`), Japanese (`ja`), Chinese (`zh`). Extending the set requires merchant language rows plus seed rows for static UI in all four codes.

## Rules

- **Fallback chain (dynamic fields)** — For each field: requested language → merchant default language → base column on the master row (never hardcoded to English).
- **Fallback chain (member static UI)** — Requested language → merchant-specific row for `(page_key, field_key)` if present → global row (`merchant_id` null) → English row for the same key.
- **Default language invariant** — Exactly one `merchant_languages` row per merchant has `is_default = true` among active languages; master-table text is treated as that language in caches and getters.
- **Write chokepoint (dynamic)** — All admin/API writes of entity overrides go through `save_entity_translations`; direct inserts are for migrations/seeds only.
- **Static UI separation** — Member pages use `ui_translations` + `get_ui_translations`; admin pages use `ui_translation_admin` + `get_admin_ui_translations`. Cross-wiring keys between tables is invalid.
- **Cache invalidation** — Inserts/updates/deletes on `translations` fire domain triggers (rewards, display blocks, earn channels, etc.); `ui_translations` / `ui_translation_admin` changes invalidate UI translation Redis keys; `merchant_languages` / merchant config changes invalidate merchant-config cache.
- **Public member UI API** — `get_ui_translations` is callable without member auth (signup/login surfaces).
- **Admin UI API** — `get_admin_ui_translations` requires admin JWT; parameter order is language first, then optional page key (opposite of the member UI RPC).
- **Export** — `export_translations_for_language` returns dynamic rows for a merchant/language (optional entity-type filter) for bulk edit or external TMS handoff.

*Example (dynamic)* — Merchant default `th`, member requests `ja`, reward name has no Japanese row: response uses Thai name from the `th` bundle, then the `name` column if still missing.

## Journeys

### Admin journey

| Knob | Effect |
| --- | --- |
| Active languages | Which locales appear for members and in translation matrices |
| Default language | Which master-column language is embedded as the default bundle key |
| Display order | Language picker ordering in admin/member where shown |
| Entity override saves | Per-field values for non-default languages on program objects |
| Static admin keys | Dashboard labels via `ui_translation_admin` seeds/overrides |
| Gap / statistics RPCs | Coverage reporting per entity type and language |

| Page | Owning repo | BFF / RPC |
| --- | --- | --- |
| Global Settings (languages) | loyalty-admin | `bff_get_general_config`, `bff_upsert_merchant_languages`, `merchant_languages` table read |
| Feature editors (rewards, tiers, forms, display blocks, earn channels, …) | loyalty-admin | Entity-specific BFFs; dynamic overrides via `get_translation_form_data` / `save_entity_translations` when wired |
| All admin chrome | loyalty-admin | `get_admin_ui_translations` via `useAdminTranslations` |
| Translation ops (export/gaps) | (no dedicated route in loyalty-admin) | `export_translations_for_language`, `get_translation_gaps`, `get_translation_statistics`, `translation_api` |

1. Open **Global Settings** and enable one or more of en/th/ja/zh; set exactly one default.
2. Author program content in the default language inside each feature editor (reward name, form label, block title, etc.).
3. Add other locales via translation tooling or `save_entity_translations` (per entity type/id); use export when bulk-updating.
4. Admin UI strings resolve automatically from `get_admin_ui_translations` per admin language preference (with in-code fallbacks if a key is missing).

### Member journey

| Page | Owning repo | BFF / RPC |
| --- | --- | --- |
| App shell / language | loyalty-user | Merchant config languages; `get_ui_translations` (all pages) on init |
| Signup / login | loyalty-user | `signup_form` page keys |
| Rewards / wallet | loyalty-user | `rewards`, `redemption_status` keys + `api_get_rewards_full_cached(p_language)` |
| Profile / surveys | loyalty-user | `bff_get_user_profile_template(p_language, …)` |
| Display-driven home / store | loyalty-user | `bff_get_display_blocks_cached(p_language)` with `fn_build_display_config_with_translations` |
| Seller purchase (event) | loyalty-user | `seller_purchase` page keys + local error-message map fallback |

1. App loads merchant languages and default; fetches full member UI translation map for the selected language (merchant overrides applied inside RPC).
2. Member switches language → client re-reads from cached multi-language bundles where APIs embed `translations`, or re-fetches UI map / calls APIs with new `p_language`.
3. If a string is missing, user sees fallback per Rules (never a blank key in production UI — loyalty-user/admin hooks supply hardcoded fallbacks for admin; member pages expect DB seeds).

### Shopify

Storefront and embedded loyalty surfaces use the **same** member translation RPCs and display-block translation merge as the native member app; there is no separate Shopify translation table. Landing/widget copy that lives in display settings follows `Display_Settings.md` (block-level dynamic translations + widget settings). Admin chrome on embedded routes still uses `ui_translation_admin`.

## System

### Data model

| Table | Role |
| --- | --- |
| `translations` | Dynamic overrides: `merchant_id`, `entity_type`, `entity_id`, `field_name`, `language_code`, `translated_value`. Unique on `(entity_type, entity_id, field_name, language_code)`. |
| `ui_translations` | Member static copy: `page_key`, `field_key`, `language_code`, `translated_value`, optional `category`; `merchant_id` null = global, else merchant override. |
| `ui_translation_admin` | Admin static copy: same shape as member UI table; never served to loyalty-user. |
| `merchant_languages` | Per-merchant locale config: `language_code`, `language_name`, `is_default`, `is_active`, `display_order`. |

**Configurable dynamic entity types** (from `get_entity_type_config()` / `get_translation_entity_types()`): `reward`, `reward_category`, `tier`, `mission`, `earn_channel`, `leaderboard`, `persona`, `tag`, `consent_version`, `communication_topic`, `form`, `form_field`, `form_field_group`, `display_settings`, `user_field_config`. Legacy rows may still use types such as `form_field_option` even when not listed in the config catalog.

**Member UI page keys (seeded)** — `signup_form`, `rewards`, `redemption_status`, plus additional keys used in app code (e.g. `seller_purchase`). **Admin UI page keys** — one key per major admin surface (`reward_settings`, `display_settings`, `tier_settings`, `utility`, `utilities`, …); see seeds in `ui_translation_admin`.

**Member static field_key conventions** — Prefixes: `header_`, `list_`, `details_`, `filter_`, `popup_`; generic keys `page_title`, `button_*`. **Admin static conventions** — `header_{page_key}`, `section_header_*`, `button_*`, `grid_*`, `tab_*`, `popup_header_*`, categories `page_header`, `section_header`, `button`, etc.

### Functions

| Function | Role |
| --- | --- |
| `save_entity_translations` | Admin write chokepoint for dynamic overrides (json payload per language/field). |
| `get_translation_form_data` | Loads base fields + existing overrides for one entity instance. |
| `get_translation_entities` / `get_translation_entity_types` | Lists entities or grouped type catalog for translation UI. |
| `get_translation_gaps` / `get_translation_statistics` | Coverage reporting. |
| `export_translations_for_language` | Bulk export for a merchant/language. |
| `translation_api` | Action router (admin auth); defers to same operations as discrete RPCs. |
| `fn_get_translation_entity_type` | Normalizes entity type string for storage. |
| `get_translation_cache_keys_to_invalidate` | Computes Redis keys after translation writes. |
| `get_ui_translations` / `get_ui_translations_structured` | Member static UI (optional `p_merchant_code` for overrides). |
| `get_admin_ui_translations` | Admin static UI (`p_language_code`, optional `p_page_key`). |
| `api_get_merchant_languages` / `bff_upsert_merchant_languages` | Read/write merchant language config. |
| `get_reward_translations` | Helper to assemble reward translation jsonb for caches. |
| `fn_build_display_config_with_translations` / `fn_extract_display_block_translations` | Merge display block config with dynamic translations at read time. |
| `api_get_rewards_full_cached`, `bff_get_user_profile_template`, `api_mark_redemption_used`, `bff_get_display_blocks_cached`, `bff_get_earn_channels` | Primary member/API surfaces accepting `p_language` and applying fallback extraction. |

**Triggers** — `translations` → `translations_cache_invalidation`, display-block and earn-channel invalidation triggers; `ui_translations` → `ui_translations_cache_invalidation`.

### Flows

**Dynamic read (cached catalog pattern)** — On cache miss, builder loads master row, sets merchant-default language bucket from columns, merges other languages from `translations`, stores multi-language json under feature-specific Redis keys (rewards, user profile template, etc.). On request, extractor picks `p_language` with fallback chain.

**Dynamic read (display blocks)** — Cached block payload includes translatable config fields; `fn_build_display_config_with_translations` applies language + default language when serving `bff_get_display_blocks_cached` / `api_get_display_blocks_cached`.

**Member static UI** — `get_ui_translations` checks Redis (`ui:{page_key}:lang:{language}` or all-pages key), on miss queries `ui_translations` with merchant override precedence, stores with ~1h TTL.

**Merchant config** — Default language and enabled locales read from `merchant_languages` (and merchant config cache ~30m TTL) so getters do not assume English.

**Admin static UI** — loyalty-admin `useAdminTranslations` loads `get_admin_ui_translations` once per language (in-memory cache per session), with bundled TypeScript fallbacks for missing keys.

### External services

| Service | Role |
| --- | --- |
| Upstash Redis `supabase-rewards-cache` | Rewards catalog all-languages bundle (~5m TTL). |
| Upstash Redis `supabase-user-profile-cache` | Profile template / form persona consent bundle (~5m TTL). |
| Upstash Redis `crm-merchant-config-cache` | Merchant settings including default language (~30m TTL). |
| Upstash Redis `supabase-ui-translations` | Member `ui_translations` cache (~1h TTL). |
| Edge `futurepark_ui_translation` | FuturePark-specific UI translation surface (see `FuturePark.md`). |

Isolated Redis databases prevent a UI translation flush from evicting rewards catalog entries.

### Known gaps

- **Dedicated translation hub** — RPCs (`get_translation_gaps`, `get_translation_form_data`, `translation_api`) exist; loyalty-admin has no standalone “Translation” navigation wired to them (overrides are edited inside feature screens or via SQL/export).
- **Catalog vs data** — `form_field_option` (and similar) may appear in `translations` rows but not in `get_entity_type_config()` until registered.
- **Coverage counts** — Historical row counts in old docs drift quickly; use `get_translation_statistics` live.
- **Performance numbers** — Sub-100ms targets depend on Redis region and cache hit; treat as order-of-magnitude, not SLAs.

### Extending the system

**New dynamic type** — Register in entity type config, ensure feature BFF/cache builder embeds `translations` json, add invalidation trigger if new cache domain.

**New member page keys** — Insert four language rows into `ui_translations` (global `merchant_id` null unless merchant-specific copy); use naming conventions; invalidate UI cache.

**New admin page** — Insert into `ui_translation_admin`; bind keys in loyalty-admin via `useAdminTranslations({ pageKey })`.

## Related

- **Display_Settings.md** — Block-level translatable config and Shopify landing/widget copy.
- **Reward.md** — Reward field matrix and catalog cache.
- **Forms.md** — Profile vs survey forms; `bff_get_user_profile_template` language param.
- **Consent.md** — `consent_version` entity translations.
- **Earn_Channel.md** — `earn_channel` entity type and channel list cache invalidation.
- **Tier.md** — `tier` name translations.
- **FuturePark.md** — `futurepark_ui_translation` edge.
