# Earn Channels

Member-facing “ways to earn” cards: taxonomy, platform templates, effective merge with merchant overrides, and admin/consumer BFFs. Functional earning stays in source systems (purchase, missions, referral program, etc.).

Owner surfaces: loyalty-admin, loyalty-user, Shopify Loyalty Hub / landing / widget drawer, Open API (receipt upload attribution)

## Concept

Earn channels are the **display gateway** to earning mechanics. They answer what appears on the Earn page (and Shopify earn tiles), how each card is grouped, and which member UI flow opens when the member taps — not whether points actually accrue. That split matters: a merchant can hide a card while the underlying feature stays on, or show a referral card while the referral **program** is off (invite then fails at apply).

**Channel type** — Section grouping on the earn surface: purchase, campaign, lifecycle, or custom.

**Earn method** — The member interaction contract (stored as `method_type`, returned as `earn_method`). One field drives the entire inner flow (receipt upload, marketplace claim, mission list, referral share, etc.).

**Registry template** — Platform catalog row keyed by stable `channel_code`: default copy, default method, availability rule, and what merchants may customize.

**Source system** — Live proof the merchant has the mechanic: feature flags, Shopify credentials, active missions/check-ins/forms, lifecycle workflows, referral program state (program gate lives in Referral — not on the earn card).

**Effective channel** — Merged view of registry + source facts + merchant override row (if any) + custom/legacy rows. Consumer APIs return only rows where display `active = true`.

**Override row** — Physical `earn_channel` row tied to a registry `channel_code` (or a custom channel). Customizes copy/assets/order/button or hides a default with `active = false`.

**Display vs functional** — Display eligibility = source availability + merchant display override. Functional earning = the source system (purchase pipeline, `fn_process_referral_signup`, mission check-in, etc.).

## Rules

- **`earn_method` is the sole FE routing key** — `channel_type` groups cards only; `channel_code` is backend/ops identity, not UI routing.
- **Effective list** — `fn_get_effective_earn_channels` merges registry templates, source availability, overrides, and custom rows. A registry default can appear **without** a physical `earn_channel` row until the merchant customizes or hides it.
- **Legacy coexistence** — If a merchant already has a legacy physical row with the same `channel_type` + `method_type` as a registry default, the computed default is suppressed so existing displays are not replaced.
- **Consumer visibility** — `bff_get_earn_channels` returns only effective channels with `active = true`, ordered by `display_order`, then name.
- **Admin visibility** — `bff_admin_get_earn_channels` returns all effective rows (active and inactive) plus registry catalog and form `options`.
- **Hide vs delete** — Registry-backed and system/integration rows: delete API **hides** via override `active = false`, not hard delete. Custom/legacy rows: hard delete when allowed.
- **Reset override** — `bff_reset_earn_channel_override` removes a registry override row and object translations for that channel; restores computed platform default. Codes: `RESET`, `ALREADY_DEFAULT`, `NOT_RESETTABLE`, `NOT_FOUND`.
- **Primary write path** — Prefer `bff_upsert_single_earn_channel` (one object). `bff_upsert_earn_channel` remains legacy array sync; it does not delete computed defaults by omission.
- **Copy resolution order** — Object translation → override/custom stored value → static UI default (`ways_to_earn` / `default_<channel_code>_…`) → registry default. Effective translation entity id: override row id when present, else deterministic `fn_earn_channel_effective_id(merchant_id, channel_code)` (stable when override is created).
- **New registry overrides** — Inserts seed `earn_channel.id` via `fn_earn_channel_effective_id` so object translations do not orphan when a computed default becomes physical (~11 pre-fix rows keep random ids but remain internally consistent).
- **Historical attribution** — `purchase_ledger.earning_channel_id` and `purchase_receipt_upload.earning_channel_id` are optional metadata **without FK**; deleting/hiding a channel leaves stale UUIDs on old rows.
- **Referral card (`campaign:referral`)** — Always listed in the effective catalog for CMS/marketing; **program on/off** is `referral_program` / `fn_is_referral_program_active`. Invite and apply require program active; earn-channel Active is not the program switch. See `requirements/Referral.md` and `requirements/reference/SHOPIFY_REFERRALS_ONSITE_INTEGRATIONS.md` Part 1.
- **Receipt upload channel** — Member upload options (`seller_reference`, `receipt_selection`, `receipt_number`, `purchase_date`) live in channel `config`, merged on upsert so they are not wiped. Admin approval entry modes (`line_item_amount`, `line_item_derived`, `total_only`) live in merchant-level `feature_config` (`feature_key = upload_receipt`, group `earn_channel`), not in the channel row.
- **External link / generic card** — `config.mode` ∈ `{ page, url }` plus `value` (route key or URL). Button show/label from `button_action`.
- **Marketplace** — Platform list on `marketplace_platforms`; claim status floors on `merchant_master.marketplace_claim_from_status` — not in channel `config`.
- **Cache** — Member response cached per merchant/language (`fn_invalidate_earn_channels_cache` + triggers on channel, registry, translations, missions, check-ins, forms, workflows, credentials, feature_config, merchant_master).

### Shopify

- **Landing / Hub earn tiles** — Not stored in Shopify metafields. `fn_enrich_shopify_landing_sections` and hub composers merge live effective channels (and referral/rewards/tiers) at read time. Landing block type `ways_to_earn`; widget drawer page `drawer_earn-channels`. See `requirements/Display_Settings.md`, `requirements/Shopify.md`, reference MD Part 2.
- **Shopify store channel** — Registry `shopify_store` (default method `external_link`) available when `merchant_credentials.service_name = 'shopify_app'` is active; often seeded via `shopify_seed_default_earn_channel`.
- **Referral in embedded admin** — Shopify embedded referral settings hide signup tab, program master switch, and **earn-channel banner**; purchase referral tab remains. Earn card on storefront still follows effective-channel rules above.

## Journeys

### Admin journey

| Page | Owning repo | BFF / RPC |
| --- | --- | --- |
| Earn Channels (list) | loyalty-admin | `bff_admin_get_earn_channels` |
| Earn Channel settings (create/edit) | loyalty-admin | `bff_upsert_single_earn_channel`, `bff_delete_earn_channel`, `bff_reset_earn_channel_override` |
| Translations (earn channel entity) | loyalty-admin | `get_translation_entities`, `save_entity_translations` (`entity_type = earn_channel`) |
| Receipts Upload (approval) | loyalty-admin | `bff_approve_receipt_upload`, `bff_get_upload_receipt_config`, `bff_set_upload_receipt_config` |
| Upload receipt feature config | loyalty-admin | `bff_set_upload_receipt_config` (merchant-level entry mode / auto-approve) |

| Setting | Effect on behaviour |
| --- | --- |
| Active (show/hide) | Whether the channel appears on member earn surfaces (`bff_get_earn_channels` filters `active = true`) |
| Display order | Sort among channels within the earn list |
| Channel type + method type | Section grouping and member flow when tapped (identity fields locked on registry-backed rows unless capability allows) |
| Copy / banners / how-to | Card and detail presentation; overridable per registry capabilities |
| Button action + link config | CTA for `external_link` / `generic_card` |
| Marketplace platforms | Which platforms appear on marketplace_code flow |
| Receipt upload config keys | Extra member fields and channel/store picker on upload |
| Reset to default | Drops override row and translations; restores registry-computed display |

1. Open **Earn Channels** — list loads all effective rows with source metadata (`can_hide`, `can_delete`, `can_reset`, `is_computed_default`).
2. Toggle visibility or reorder — saves via single-channel upsert (override row created when needed).
3. Edit copy/assets — same upsert; optional **Translations** for non-default languages on physical override ids.
4. Customize a registry default — upsert with matching `channel_code` (or deterministic computed id); capabilities gate method/button edits.
5. Remove custom channel — delete when `can_delete`; registry default — hide (inactive override) instead of delete.
6. Restore platform default — **Reset** when `can_reset` (registry-backed overrides only).

### Member journey

| Surface | Owning repo | BFF / RPC |
| --- | --- | --- |
| Ways to earn / Earn page | loyalty-user | `bff_get_earn_channels` |
| Per-method flows | loyalty-user | Method-specific APIs (missions, forms, referral invite, receipt upload, marketplace claim, etc.) |
| Shopify Hub earn section | rewarding-shopify + extensions | `bff_user_get_shopify_hub` / `fn_compose_shopify_hub` (enriched channels) |
| Shopify landing `ways_to_earn` | rewarding-shopify theme + proxy | `api_get_shopify_landing_page_cached` + `fn_enrich_shopify_landing_sections` |

1. Member opens Earn — client loads `bff_get_earn_channels` (optional `p_language`, `p_surface` for cache keying).
2. Cards render grouped by `channel_type`; tap uses **`earn_method`** only.
3. **`receipt_upload`** — upload flow; optional seller/receipt fields from channel config; store picker when `receipt_selection` requires it (`bff_list_stores_for_receipt_upload`). See `requirements/Receipt_Upload_Earning.md`.
4. **`marketplace_code`** — platform picker + order claim using `marketplace_platforms`.
5. **`external_link` / `generic_card`** — content + button; `mode=url` opens browser, `mode=page` uses app route map.
6. **`mission` / `form` / `checkin` / `social`** — navigate to respective feature pages (feature APIs own progress).
7. **`referral`** — referral share/apply UI; if program inactive, apply/share errors per Referral rules (card may still show).
8. **`info_card`** — read-only lifecycle messaging; earning triggered elsewhere (workflows).

Routing reference (field usage): card display uses `channel_name`, `headline`, `description`, banners; detail uses how-to fields; `button_show` / `button_label` / flattened config for CTAs. Legacy Thai FE guide content archived at `Earn_Channel_FE_Guide.md` (pointer only).

### Shopify

- **Hub** — Categorized earn/spend/referrals; earn rows from composer + effective channels (same methods as loyalty-user).
- **Landing** — `ways_to_earn` section enriched from effective channels; member overlay when logged in.
- **Widget drawer** — Earn channels tab opens `drawer_earn-channels` when configured in display settings CTA.
- **Points on product** — Uses widget earn rate, not the earn-channel list (separate touchpoint).

## System

### Data model

| Table | Role |
| --- | --- |
| `earn_channel_registry` | Platform templates: `channel_code`, type/subtype, default method/copy/config, `availability_rule`, `capabilities`, sort order |
| `earn_channel` | Merchant overrides, hidden defaults, custom/legacy/system rows; `method_type`, `config`, `button_action`, `marketplace_platforms`, `default_award_scope`, `override_kind`, `source_type` |
| `feature_config` | Proves upload receipt / marketplace / campaign activity availability; hosts **merchant-level** receipt approval entry mode |
| `merchant_credentials` | Shopify app credential proves `shopify_store` template |
| `merchant_display_settings` | Earn page icon (`ui_config.earn_channel_page_icon`) |
| `merchant_master` | `marketplace_claim_from_status` for marketplace channels |
| `ui_translations` | Static defaults for registry channels (`page_key = ways_to_earn`) |
| `translations` | Object translations for override/custom rows (`entity_type = earn_channel`) |
| `purchase_receipt_upload` / `purchase_ledger` | Optional `earning_channel_id` metadata (no FK) |

Registry columns verified live include: `channel_code`, `default_method_type`, `allowed_earn_methods`, `default_award_scope`, `availability_rule`, `capabilities`, `default_button_action`, `default_config`.

### Functions

| Function | Role |
| --- | --- |
| `fn_get_effective_earn_channels(merchant, language, include_admin_metadata?)` | Core merge + COALESCE copy; admin metadata when requested |
| `fn_earn_channel_effective_id(merchant, channel_code)` | Deterministic id for translations/overrides before physical row |
| `fn_invalidate_earn_channels_cache(merchant)` | Drops cached member payloads |
| `bff_get_earn_channels(language?, surface?)` | Member envelope: `page_icon`, `channels[]`, cache flags |
| `bff_admin_get_earn_channels(language?)` | Admin list + `registry[]` + `options` (types, methods, platforms, default_award_scope) |
| `bff_upsert_single_earn_channel(data, language?)` | Primary create/update override or custom row; merges receipt upload config fragments |
| `bff_upsert_earn_channel(data[], language?)` | Legacy batch sync |
| `bff_delete_earn_channel(channel_id, language?)` | Hard delete custom or hide registry default |
| `bff_reset_earn_channel_override(channel_id, language?)` | Drop override + translations |
| `shopify_seed_default_earn_channel(merchant, merchant_code)` | Merchant onboarding default shop/external link row |
| `bff_approve_receipt_upload`, `bff_get_upload_receipt_config`, `bff_set_upload_receipt_config` | Receipt upload approval and merchant-level entry modes (earn channel adjacent) |
| Translation pipeline | `get_entity_type_config`, `get_translation_entities`, `get_translation_form_data`, `save_entity_translations`, `get_translation_cache_keys_to_invalidate` for `earn_channel` |

**Member `channels[]` keys (contract):** `id`, `channel_code`, `channel_type`, `earn_method`, copy/asset fields, `display_order`, button flatteners, `marketplace_platforms`, how-to fields. Removed from contract: `channel_subtype`, `icon_url`.

**Admin `channels[]` metadata:** `override_id`, `registry_id`, `source`, `source_status`, `source_ref`, `is_computed_default`, `can_hide`, `can_delete`, `can_reset`, capability flags (`can_customize_*`).

**Upsert error codes (representative):** `NO_MERCHANT_CONTEXT`, `VALIDATION_ERROR`, `INVALID_CHANNEL_TYPE`, `DUPLICATE_CHANNEL_CODE`, `NOT_FOUND`, `HAS_DEPENDENCIES`, `ERROR`.

### Flows

**Read (member)** — Auth merchant → cache lookup → on miss `fn_get_effective_earn_channels` with translations applied → filter active → sort → return. Triggers on source tables invalidate cache when missions, forms, credentials, etc. change.

**Read (admin)** — Same resolver with admin metadata and full registry catalog for the settings UI.

**Write override** — Upsert validates capabilities → insert/update `earn_channel` with stable id for registry codes → invalidate cache → translation cache keys when copy changes.

**Hide default** — Delete API on computed id writes inactive override (or deletes custom row).

**Earn method values (registry + custom):** `receipt_upload`, `qr_scan`, `marketplace_code`, `external_link`, `account_link`, `mission`, `form`, `checkin`, `social`, `referral`, `info_card`, `generic_card`.

**Registry catalog (channel_code → default method → availability sketch):**

| channel_code | Default method | Availability (summary) |
| --- | --- | --- |
| `shopify_store` | `external_link` | Active Shopify credential |
| `purchase:receipt_upload` | `receipt_upload` | `feature_config` upload_receipt |
| `purchase:marketplace` | `marketplace_code` | `feature_config` marketplace_code |
| `campaign:mission` / `checkin` / `form` / `social` | matching method | Active mission / check-in / published form / campaign.activity |
| `campaign:referral` | `referral` | Always in catalog; program gate separate |
| `lifecycle:*` | `info_card` or `form` | Active earning lifecycle workflow or profile form |
| `custom:generic` | `generic_card` | Manual/custom |

Subtype and manual-only templates (`purchase:online_store`, `purchase:partner_store`, etc.) remain in registry for ops; availability rules may be manual/legacy.

### External services

- **rewarding-shopify** — Landing enrichment, hub composition, extension APIs; does not own channel rows.
- **loyalty-admin / loyalty-user** — Settings and member earn UI consumers of BFFs above.

### Known gaps

- Pre-2026-06-16 registry override rows (~11) may use non-deterministic ids; resolver still consistent; reset/translations should use admin-exposed ids.
- `bff_upsert_earn_channel` batch sync still used by some flows — prefer single upsert for new work.
- Earn-factor **award scope** (`default_award_scope` on channel/registry) is exposed to admin; member routing unchanged — purchase earning rules live under Currency / Purchase Transaction.

### Shopify

- Storefront earn **content** is composed server-side (`fn_enrich_shopify_landing_sections`, hub composer); install/configure paths in `requirements/Display_Settings.md` and reference MD Part 2 §2.2–2.4.
- Checkout points estimate touchpoint deferred (not in extension deploy manifest).

## Related

- **Referral.md** — Program gate, invite/apply, purchase claims; earn channel is CMS card only.
- **Receipt_Upload_Earning.md** — Upload API, approval, store picker, ledger attribution.
- **Earn_from_Code.md** — Code-based earning mechanic (sibling feature, not earn-channel display doc).
- **Display_Settings.md** / **Shopify.md** — Widget drawer earn tab, landing `ways_to_earn`, on-site content hub routes.
- **Currency.md** / **Purchase_Transaction.md** — Functional purchase earning after receipt/marketplace/Shopify order paths.
- **Platform_Plan_Feature_Registry.md** — Feature keys backing availability rules (`earn_channel.*`, campaign.activity).
- **reference/SHOPIFY_REFERRALS_ONSITE_INTEGRATIONS.md** — Part 1 (referral vs program gate), Part 2 (storefront earn surfaces).
