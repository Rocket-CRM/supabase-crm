# Feature Guide: Translation System

## 1. Overview

The Translation System provides multi-language support across the entire loyalty platform. It handles two distinct categories of text: dynamic content tied to specific entities (reward names, form field labels, persona names) and static UI text (page headers, button labels, error messages). Together, they let merchants operate loyalty programs in up to four languages — English, Thai, Japanese, and Chinese — with each merchant choosing their own default.

When a member opens the app, the system resolves their preferred language from a cookie, falls back to the browser's Accept-Language header, and ultimately defaults to Thai. All translated text loads in a single API call at app initialization. If a translation is missing for the requested language, a fallback chain kicks in: try the merchant's default language, then English, then the raw base value. This means members never see blank fields — they always get the best available text.

For merchants expanding into new markets, the admin dashboard provides a dedicated Translation page where staff can browse every translatable entity, edit translations in a 4-column grid (one per language), and use AI-assisted translation to fill gaps. Entity translations are also managed inline within entity forms (e.g., reward settings). The entire system is backed by Redis caching with domain-isolated databases, keeping response times under 100ms.

## 2. Key Concepts

**Entity Translation** — A translated value for a specific database record's field. Stored in the `translations` table, keyed by `entity_type` + `entity_id` + `field_name` + `language_code`. Example: the reward "Coffee Mug" has an entity translation for Thai: `name` = "แก้วกาแฟ".

**UI Translation** — A translated string for static interface text not tied to any entity. Stored in the `ui_translations` table (member-facing) or `ui_translation_admin` table (admin dashboard), keyed by `page_key` + `field_key` + `language_code`. Example: the rewards page header `header_page_title` = "รายการของรางวัล" in Thai.

**Fallback Chain** — The resolution order when a translation is missing: requested language → merchant default language → English → raw base value. Applied both server-side (in DB functions) and client-side (in the `useTranslation` hook).

**Supported Languages** — Four language codes: `en` (English), `th` (Thai), `ja` (Japanese), `zh` (Chinese).

**Default Language** — The merchant's primary language, set in `merchant_languages` with `is_default = true`. Master table content (e.g., `reward_master.name`) is assumed to be in this language. One default per merchant.

**Language Code** — Two-letter identifier (`en`, `th`, `ja`, `zh`) used throughout as the key for translations.

**Entity Type** — The category of translatable content. Current types: `reward`, `reward_category`, `form_field`, `form_field_option`, `form_field_group`, `user_field_config`, `persona`, `consent_version`, `communication_topic`, `tier`.

**Page Key** — Groups static UI translations by screen. Examples: `signup_form`, `rewards`, `profile`, `history`, `navigation`, `utility`, `redemption_status`.

**Field Key** — Identifies a specific UI string within a page. Uses section prefixes: `header_`, `list_`, `details_`, `filter_`, `popup_`, `button_`, `text_`, `error_`, `status_`.

**Merchant Override** — A UI translation scoped to a specific merchant (non-null `merchant_id`), which takes priority over the global version (null `merchant_id`). Example: Syngenta overrides the signup page title with their brand name.

**Language Cookie** — Browser cookie `loyalty_language` set when a member explicitly switches language. Persists for 1 year. Takes highest priority in language resolution.

**Translation Grid** — The admin UI component showing translatable fields as rows and languages as columns (EN, TH, ZH, JA). All cells are editable. Located in the right panel of the Translation Manager.

**AI Translate** — Admin feature that auto-fills missing translations using AI. Triggered by the "AI Translate" button in the Translation Grid toolbar. Sends current rows to `/api/translation/ai-translate` and receives suggested translations.

## 3. Configuration Reference

### Merchant Language Setup (`merchant_languages` table)

| Setting | What it controls | Example | Default |
|---|---|---|---|
| language_code | Which language is available | `th` | Required |
| language_name | Display name shown to members | "ไทย" | Required |
| is_default | Whether this is the merchant's primary language | true | false |
| is_active | Whether members can select this language | true | true |
| display_order | Sort order in language picker | 1 | 0 |

### Entity Translation Fields

| Entity Type | Source Table | Translatable Fields |
|---|---|---|
| `reward` | `reward_master` | name, description_headline, description_body, description_tc, description_slip |
| `reward_category` | `reward_category` | name |
| `form_field` | `form_fields` | label, placeholder, help_text |
| `form_field_option` | `form_field_options` | option_label |
| `form_field_group` | `form_field_groups` | group_name |
| `user_field_config` | `user_field_config` | label, placeholder, help_text |
| `persona` | `persona_master` | persona_name, group_name |
| `consent_version` | `consent_versions` | title, preview, content |
| `communication_topic` | `communication_topics` | topic_name |
| `tier` | `tier_master` | tier_name |

### Cache TTLs

| Cache Domain | TTL | Redis Database |
|---|---|---|
| Rewards catalog | 5 minutes | supabase-rewards-cache |
| User profile template | 5 minutes | supabase-user-profile-cache |
| UI translations (member) | 1 hour | supabase-ui-translations |
| Merchant config | 30 minutes | crm-merchant-config-cache |

## 4. Admin Journey

**Repo:** `Rocket-CRM/loyalty-admin`

**Route map:**

| Page Name | Current Route | BFF / Data Source |
|---|---|---|
| Translation Manager | `/translation` | `translation_api(p_action, p_params)` |
| Global Settings | `/merchant-global-settings` | `bff_get_merchant_global_settings()` |

### 4a. Manage Entity Translations

1. Open **Translation Manager** — 3-panel layout: category nav (left), entity list (center), translation grid (right)
2. Left panel shows entity type groups (sections like "Content", "Forms", etc.) — select an entity type (e.g., "Rewards")
3. Center panel loads all entities of that type — select a specific entity (e.g., "Coffee Mug")
4. Right panel shows the translation grid: rows = translatable fields, columns = EN, TH, ZH, JA
5. Edit any cell to add or change a translation. Edited rows show an "Edited" badge. Header shows "Unsaved changes" badge.
6. Optionally click **"AI Translate"** to auto-fill empty translations using AI — fills all language columns based on the English reference
7. Click **"Save"** to persist all changes. Toast confirms "Translations saved".

### 4b. Configure Merchant Languages

1. Open **Global Settings** — language configuration is part of the merchant setup
2. Enable/disable languages, set default language, configure display order
3. Save changes — clears merchant config cache

### 4c. Manage Static UI Translations

Static UI translations (button labels, page headers, error messages) are managed directly in the database, not through the Translation Manager UI. Admin dashboard text lives in `ui_translation_admin`; member-facing text lives in `ui_translations`.

Current member-facing page keys with translation coverage:

| Page Key | Field Count | Coverage |
|---|---|---|
| `signup_form` | 27 | Auth, OTP, consent, navigation, errors |
| `rewards` | 26 | Catalog headers, detail view, popups, filters |
| `redemption_status` | 5 | Status labels (used, redeemed, expired, cancelled, pending) |
| `profile` | ~15 | Profile header, settings menu, drawers |
| `navigation` | ~5 | Bottom nav labels |
| `utility` | ~10 | Shared buttons (Save, Cancel, Edit) |
| `history` | ~8 | History drawer filters and labels |
| `missions` | ~5 | Mission page elements |
| `benefits` | ~5 | Tier info drawer |

### 4d. Common Admin Mistakes

- Forgetting to add translations for a new language after enabling it → members see fallback text
- Changing the default language without clearing caches → stale data for up to 30 minutes
- Adding UI translations to `ui_translations` when the target is the admin dashboard (should use `ui_translation_admin`)
- Editing entity master table content without updating translations → languages drift apart
- Adding a new UI page without creating translations for all 4 languages → partial page rendering

## 5. Member Experience

**Repo:** `Rocket-CRM/loyalty-user`

**Route map:**

| Page / Component | Current Route | Data Source |
|---|---|---|
| Profile page | `/profile` | `get_user_summary()`, `api_get_merchant_languages()` |
| Change Language drawer | Bottom-sheet on `/profile` | `POST /api/language` (cookie), `router.refresh()` |
| Any page with translations | All routes | `get_ui_translations(p_page_key, p_language)` loaded at app init |

### 5a. Language Resolution on Load

1. Member opens the app — server-side layout runs language resolution
2. Checks `loyalty_language` cookie → if set and supported by merchant, use it
3. Else parses `Accept-Language` header → first match against merchant's supported languages
4. Else defaults to `"th"`
5. Fetches all UI translations for resolved language in one call (`p_page_key = null`)
6. Translations stored in React context via `MerchantProvider`, accessible via `useTranslation(pageKey)` hook

### 5b. Switch Language

1. Member navigates to **Profile** → taps **"Change Language"** in settings menu
2. **Change Language drawer** opens — radio list of merchant's available languages (language names from `merchant_languages`)
3. Member selects a language, taps **"Save"**
4. App sends `POST /api/language` → sets `loyalty_language` cookie (1-year expiry)
5. `router.refresh()` triggers server re-render → new language resolved from cookie → fresh translations fetched → entire app re-renders with new language

### 5c. How Translated Content Appears

1. Static UI text (headers, buttons, labels) — resolved from `useTranslation(pageKey)` hook
2. Entity content (reward names, form labels) — resolved server-side by each API's `p_language` parameter, with fallback chain applied in the DB function
3. If a translation is missing: DB returns fallback (merchant default → English), then `useTranslation` returns field key as last resort

## 6. Perspectives

### 6a. For Customer Success / Support

**Top questions:**

| Question | Answer |
|---|---|
| "Member sees English text on a Thai app" | Translation missing for that field in Thai — falls back to merchant default, then English. Add the missing translation via Translation Manager. |
| "Language changed but text didn't update" | Redis cache may be stale. UI translations cache is 1 hour, rewards 5 minutes. Clear cache or wait for expiry. Member can also hard-refresh the app. |
| "Member can't find language option" | Language must be enabled in `merchant_languages` with `is_active = true`. Check Global Settings. |
| "Some text is translated, some isn't" | Entity translations and UI translations are independent. An entity may be translated while the surrounding UI buttons are not, or vice versa. |
| "Admin dashboard shows wrong language" | Admin uses a separate translation table (`ui_translation_admin`). Check that translations exist there. |

### 6b. For Marketing

**Value proposition:** Multi-language support lets merchants serve customers in their preferred language across all touchpoints — from signup forms through rewards catalog to redemption slips. A Thai merchant expanding to Japan can launch Japanese-language support without rebuilding anything: enable the language, add translations, and members see the app in Japanese.

**Key selling points:**
- **4-language support** — English, Thai, Japanese, Chinese out of the box
- **AI-assisted translation** — admin staff can auto-translate content, then review and refine
- **Per-merchant default** — Thai-first and English-first merchants coexist on the same platform
- **Automatic fallback** — members never see blank fields; the system always surfaces the best available text
- **Single-load architecture** — all translations load once at app init, no per-page loading delays

### 6c. For Testers

**Config → expected behavior:**

| Config | Expected Behavior |
|---|---|
| Member requests `ja`, translation exists | Japanese text displayed |
| Member requests `ja`, no Japanese translation, merchant default is `th` | Thai text displayed (fallback) |
| Member requests `ja`, no Japanese, no Thai | English text displayed (final fallback) |
| `merchant_languages` has `ja` with `is_active = false` | Japanese not shown in Change Language drawer |
| UI translation has merchant-specific override | Override takes priority over global translation |
| Entity saved with new name, cache not expired | Old name shown until cache expires (5 min for rewards) |
| Cache cleared via invalidation function | Next request rebuilds cache with fresh data |

**Business rules as assertions:**

- ASSERT: Language resolution order is cookie → Accept-Language → `"th"` default
- ASSERT: Fallback chain is requested → merchant default → English → base value
- ASSERT: `get_ui_translations(null, lang)` returns all page keys in one response
- ASSERT: Language cookie `loyalty_language` persists for 1 year
- ASSERT: `router.refresh()` after language switch triggers full server re-render with new translations
- ASSERT: AI Translate fills empty cells without overwriting existing translations
- ASSERT: Save on Translation Manager only persists rows with changes
- ASSERT: Merchant override (non-null `merchant_id`) takes priority over global (null `merchant_id`) in UI translations
- ASSERT: Each Redis cache domain is isolated — flushing UI translations cache does not affect rewards cache

**Error states to test:**

- Request unsupported language code (e.g., `fr`) → should fall back to merchant default
- `useTranslation` with nonexistent page key → returns field key strings as-is
- `useTranslation` with nonexistent field key → returns the raw field key (e.g., `"header_page_title"`) or provided fallback string
- AI Translate endpoint fails → error toast, existing translations preserved
- Save with no changes → Save button disabled (not clickable)

**Cross-feature test scenarios:**

- Switch language to Japanese → rewards catalog shows Japanese names (entity translation) + Japanese UI labels (UI translation)
- Create new reward → open Translation Manager → new reward appears in entity list → add translations → verify in member app
- Change merchant default language → clear caches → verify fallback chain uses new default
- Wallet and earn modules use local i18n dictionaries (legacy) — not affected by DB translation changes
- Signup flow in Thai → all form field labels, error messages, consent text, and buttons appear in Thai
- Redemption slip displays translated reward name, status label, and action buttons in member's language

## 7. Business Rules

**Rule:** Master table content is labeled with the merchant's default language, not hardcoded as English.
**Example:** A Thai-first merchant's `reward_master.name` = "แก้วกาแฟ" is cached under `th`, not `en`. English is stored in the `translations` table.

**Rule:** All languages are stored in a single cache key per entity/domain. Language extraction happens at request time via JSONB operations.
**Example:** One Redis key holds `{"en": {...}, "th": {...}, "ja": {...}}`. Requesting Thai extracts only the `th` object.

**Rule:** Cache invalidation triggers automatically on table changes (via DB triggers), but stale reads are possible within the TTL window.
**Example:** Admin edits a reward name → trigger fires → rewards cache invalidated → next member request rebuilds. But a member who loaded 1 minute ago still sees old data until their cache entry expires.

**Rule:** UI translations are public endpoints (no auth required) because they serve login and signup pages.
**Example:** `get_ui_translations` is callable by anonymous users to render the signup form in the member's language.

**Rule:** Admin and member UI translations are stored in separate tables with separate API functions.
**Example:** Admin dashboard uses `ui_translation_admin` + `get_admin_ui_translations()`. Member app uses `ui_translations` + `get_ui_translations()`.

**Rule:** The `translation_api` BFF function handles all admin translation operations through a single endpoint with action routing (`get_menu`, `get_entities`, `get_form`, `save`).
**Example:** Admin selects "Rewards" in nav → `translation_api(action='get_entities', params={entity_type: 'reward'})` returns the list.

**Rule:** Entity translations are keyed by the composite of `entity_type` + `entity_id` + `field_name` + `language_code`. This combination is unique-constrained — one translation per field per language per entity.
**Example:** Reward "Coffee Mug" (`id: abc123`) can have exactly one Thai translation for `name`. Inserting a second one violates the unique constraint — use upsert.

**Rule:** The member app loads all UI translations once at app initialization (server-side in the root layout), not per-page. Language switching triggers a full server re-render that re-fetches all translations.
**Example:** Switching from Thai to English calls `get_ui_translations(null, 'en')` → receives all pages → entire app re-renders.

**Rule:** Legacy local i18n dictionaries exist for wallet and earn modules (`wallet-i18n.ts`, `earn-i18n.ts`). These operate independently of the centralized DB-backed system and will be migrated in the future.
**Example:** Wallet drawer translations come from a hardcoded TypeScript dictionary, not from `get_ui_translations`.

## 8. Related Features

| Feature | Connection to Translation |
|---|---|
| Rewards | Reward name, headline, body, T&C, and slip are translatable entity fields. Catalog API accepts `p_language`. See `Reward.md`. |
| Forms | Form field labels, placeholders, help text, and option labels are translatable. Profile template API accepts `p_language`. See `Forms.md`. |
| Tag & Persona | Persona names and group names are translatable. See `Tag_and_Persona.md`. |
| Tier | Tier names are translatable entity fields. See `Tier.md`. |
| Consent | Consent version title, preview, and content are translatable. See PDPA/consent docs. |
| Currency | Communication topic names are translatable. See `Currency.md`. |
