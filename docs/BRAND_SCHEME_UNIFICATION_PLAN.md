# Brand Scheme Unification — Implementation Plan

Status: approved design, ready to implement · Date: 2026-09-23 · Supabase project: `wkevmsedchftztoolkmi`

## 1. Goal

One brand setting per merchant — the **brand scheme** — drives every customer-facing surface: Shopify widget, Shopify landing page, Shopify loyalty hub, standalone member app (loyalty-user / LIFF), admin history icons, email fallback, BigCommerce embed.

Today the same row (`merchant_display_settings`) stores brand data twice:

- `shopify_brand_scheme` (jsonb) → Shopify surfaces only.
- Flat columns `primary_color`, `secondary_color`, `border_radius_cards|buttons|inputs|modals|button_small` → member app and a few BFFs.

The only link is `admin_upsert_shopify_brand_scheme` copying `tokens.primary` into `primary_color`. Nothing writes `secondary_color` or the radius columns. `logo` has no admin writer.

End state:

- Column `brand_scheme` (renamed) is the single source for colors and radii.
- `merchant_display_settings.logo` stays a column and is the single source for the logo.
- Flat color/radius columns are dropped.
- Every consumer keeps its current output contract (keys and formats) — values are now derived from the scheme.
- One admin pop-up edits it, with a `surface` mode.

## 2. Decisions (locked — do not reinterpret)

| # | Decision |
|---|---|
| D1 | Rename column `shopify_brand_scheme` → `brand_scheme`. Rename every function whose subject is the brand scheme itself (drop `shopify_`). Functions whose subject is a Shopify surface (landing, hub, widget) keep their names. |
| D2 | Scheme `_schema_version` → `2.3.0`. Add `tokens.accent` (hex) and `cards.radius_px` (int). All v2.2.0 keys stay exactly as they are (canonical list: `loyalty-admin/src/components/brand-scheme/types.ts`). |
| D3 | Two radii: `buttons.radius_px` (range widened **0–100**, was 0–40) and new `cards.radius_px` (range **0–40**). No other radius tokens. |
| D4 | Logo stays in `merchant_display_settings.logo` (text URL). It is **not** stored in the scheme JSON. It is edited in the same pop-up and saved by the same RPC via `p_assets`. |
| D5 | Defaults for merchants who have never saved (single set, `fn_brand_scheme_default`): all v2.2.0 defaults unchanged (`tokens.primary` `#1C1C1C`, `buttons.radius_px` `8`), plus `tokens.accent` `#666666`, `cards.radius_px` `12`. |
| D6 | Migration rule: every merchant's migrated scheme equals **what their primary surface shows today**. Primary surface = Shopify if the merchant has an active Shopify install (see D7), otherwise the member app. |
| D7 | "Is Shopify merchant" = `EXISTS (SELECT 1 FROM merchant_credentials WHERE merchant_id = m.id AND service_name = 'shopify_app' AND is_active)`. Do **not** use `merchant_code ILIKE '%.myshopify.com'`. (Verify the `merchant_id` column name on `merchant_credentials` before writing SQL.) |
| D8 | Accepted visible change: Shopify merchants who also use the member app get member-app pop-up radius = their current Shopify button radius (usually 8, was 12). Only two member-app pop-ups use this value. No other visible change is allowed. |
| D9 | Pop-up `surface` prop is set by the **entry point**, not by merchant identity: Shopify-surface pages always pass `shopify`; the General settings card and the Display settings hub pass the current admin surface (`getAdminSurface()` → `shopify` when embedded, else `standalone`). |
| D10 | Theme import: button radius ← Horizon `button_border_radius_primary` (0–100), else Dawn `buttons_radius` (0–40), else **keep existing value**. Card radius ← `card_corner_radius` (both Dawn and Horizon; clamp 0–40), else **keep existing value**. Never map `badge_corner_radius`. Never fall back to a hardcoded 8. Import never touches `tokens.accent` or `logo`. |
| D11 | API payload key `brand_scheme` (widget / landing / hub) is a deployed contract — unchanged. New keys are additive. |
| D12 | Member app (`loyalty-user`) and `loyalty-cache-api`: **no code change**. `get_display_settings_fast` keeps every output key and format. |

## 3. Scheme shape v2.3.0

```jsonc
{
  "_schema_version": "2.3.0",
  "source":  { /* unchanged v2.2.0 keys */ },
  "tokens":  {
    "primary": "#RRGGBB",            // unchanged
    "background": "...", "dark_surface": "...", "foreground_heading": "...", "foreground": "...", // unchanged
    "accent": "#RRGGBB"              // NEW — member app secondary color
  },
  "buttons": {
    /* unchanged v2.2.0 keys (primary.bg/text, secondary.text, borders) */
    "radius_px": 0-100               // range widened
  },
  "cards": {                          // NEW
    "radius_px": 0-40
  }
}
```

Validation (`fn_validate_brand_scheme`): accepts `_schema_version` in `2.3.0, 2.2.0, 2.1.0, 2.0.0, 1.0.0`; `tokens.accent` must be `#RRGGBB` or `#RGB` (case-insensitive) or null (null → default); `cards.radius_px` integer 0–40; `buttons.radius_px` integer 0–100. Merge (`fn_brand_scheme_merge`) always outputs `_schema_version = '2.3.0'` and the full shape with defaults filled.

## 4. Data blast radius (live counts 2026-09-23 — recompute in Phase 0 with D7)

| Population | Count | Current source of truth | Migration action |
|---|---|---|---|
| All merchants (`merchant_master`) | 186 | — | Every merchant ends with a `merchant_display_settings` row and a v2.3.0 `brand_scheme`. |
| Row + scheme | 52 | Scheme (Shopify surfaces), flat (member app) | UPDATE scheme per §5 rules. `tokens.primary` already equals `primary_color` in all 52 (0 mismatches). |
| Row, no scheme | 35 | Flat columns (member app); scheme defaults + `primary_color` overlay (Shopify surfaces) | UPDATE: build scheme per §5 rules. |
| No row | 99 | RPC fallbacks (`#000000`, `#666666`, `12px`) for member app; scheme defaults for Shopify surfaces | INSERT row `(merchant_id, brand_scheme)` per §5 rules. Other columns take table defaults — verified safe: no non-brand key visible to members changes (`select_store`, `scan_mode`, `ui_config`, `old_crm_merchantid` fall back to the same values; points fields stay NULL). |
| `secondary_color` set | 13 (all custom, none `#ed773a`) | Flat | Copied to `tokens.accent`. |
| `logo` set | 8 | Column | No change. |
| Radius split | 49 rows with scheme button radius 8 vs flat card radius 12 | — | Resolved by D6/D8 per merchant type. |

Out of scope data (leave untouched): `merchant_notification_appearance.primary_color/logo_url`, spin wheel `display_config` colors, widget `config.header.brand_mark`, `background_image`.

## 5. Migration algorithm (per merchant `m`)

Compute **before** any function is replaced (use the old functions to capture today's rendering):

```
is_shopify     := D7
row            := merchant_display_settings where merchant_id = m.id (may be NULL)
current_scheme := fn_shopify_merchant_brand_scheme_merged(m.id)      -- if no row: fn_shopify_brand_scheme_merge(NULL, NULL)
member_primary := COALESCE(row.primary_color, '#000000')
member_accent  := COALESCE(row.secondary_color, '#666666')
member_cards   := int(regexp_replace(COALESCE(row.border_radius_cards, '12px'), 'px$', ''))   -- all 87 rows are 'Npx'; clamp 0–40
```

New scheme = `current_scheme` with:

| Key | Shopify merchant | Non-Shopify merchant |
|---|---|---|
| `tokens.primary` | `current_scheme.tokens.primary` | `member_primary` |
| `tokens.accent` | `member_accent` | `member_accent` |
| `buttons.radius_px` | `current_scheme.buttons.radius_px` (unchanged) | `current_scheme.buttons.radius_px` (unchanged) |
| `cards.radius_px` | `current_scheme.buttons.radius_px` (= what landing cards show today) | `member_cards` |
| all other keys | unchanged from `current_scheme` | unchanged from `current_scheme` |
| `_schema_version` | `2.3.0` | `2.3.0` |

Write: UPDATE if row exists, else INSERT `(merchant_id, brand_scheme)`. The backfill fires the existing cache-purge triggers for every merchant — expected, one-time.

## 6. Database changes

### 6.1 Rename map

| Old | New | Notes |
|---|---|---|
| column `shopify_brand_scheme` | `brand_scheme` | `ALTER TABLE … RENAME COLUMN` |
| `fn_shopify_brand_scheme_default()` | `fn_brand_scheme_default()` | v2.3.0 defaults (D5) |
| `fn_shopify_brand_scheme_merge(p_scheme jsonb, p_primary_color text)` | `fn_brand_scheme_merge(p_scheme jsonb)` | No primary overlay param. Preserves `tokens.accent`, `cards`. Legacy key mapping (`brand`→`primary`, `text`/`heading`→`foreground`) kept. |
| `fn_validate_shopify_brand_scheme(p_scheme jsonb)` | `fn_validate_brand_scheme(p_scheme jsonb)` | Returns errors array as today |
| `fn_shopify_merchant_brand_scheme_merged(p_merchant_id uuid)` | `fn_brand_scheme_merged(p_merchant_id uuid)` | `fn_brand_scheme_merge(row.brand_scheme)`; no row → defaults |
| `fn_shopify_brand_scheme_null_if_placeholder(p_value text)` | `fn_brand_scheme_null_if_placeholder(p_value text)` | |
| `fn_shopify_brand_scheme_source_to_imported_from(p_source jsonb)` | `fn_brand_scheme_source_to_imported_from(p_source jsonb)` | |
| `admin_get_shopify_brand_scheme()` | `admin_get_brand_scheme()` | Old name kept as wrapper until Phase 5 |
| `admin_upsert_shopify_brand_scheme(p_scheme jsonb)` | `admin_upsert_brand_scheme(p_scheme jsonb, p_assets jsonb DEFAULT '{}')` | Old name kept as wrapper: calls new with `'{}'` |

Old helper names (non-admin) are dropped in Migration A after every caller is recreated against the new names.

### 6.2 `admin_get_brand_scheme()`

Returns `fn_response_success('OK', …, { scheme: fn_brand_scheme_merged(v_merchant_id), logo: row.logo, updated_at })`. Wrapper `admin_get_shopify_brand_scheme()` returns the same envelope (extra `logo` key is additive).

### 6.3 `admin_upsert_brand_scheme(p_scheme jsonb, p_assets jsonb DEFAULT '{}')`

1. `v_merchant_id := get_current_merchant_id()`; NULL → error.
2. `v_stored := fn_brand_scheme_merged(v_merchant_id)`.
3. **Preserve absent new keys** (protects values while an older admin build is still deployed): if `p_scheme->'tokens'` has no key `accent` → set it from `v_stored`; if `p_scheme` has no key `cards` → set from `v_stored`. Absent key = preserve; explicit JSON null = default.
4. `v_errors := fn_validate_brand_scheme(fn_brand_scheme_merge(p_scheme))`; non-empty → `fn_response_error('Invalid scheme', …, 'VALIDATION_ERROR', { errors })` (same envelope as today).
5. Upsert row `brand_scheme := fn_brand_scheme_merge(p_scheme)`.
   - **Migration A only:** also `primary_color := merged.tokens.primary` (flat readers still live). Removed in Migration B.
6. If `p_assets ? 'logo'`: `logo := p_assets->>'logo'` (JSON null clears). Value must be NULL or a text starting with `https://`; otherwise VALIDATION_ERROR. If key absent, logo untouched.
7. Keep today's landing cache invalidation call.
8. Return `admin_get_brand_scheme()`.

### 6.4 Functions to recreate (28 live objects reference the columns)

**Group 1 — scheme helpers and admin RPCs:** everything in §6.1.

**Group 2 — recreate for column rename only; no behavior change:**
`admin_get_shopify_landing_page_settings()`, `admin_upsert_shopify_landing_page_settings(p_config jsonb)`, `api_get_shopify_landing_page_cached(p_merchant_code text, p_language text)`, `fn_compose_shopify_hub(p_merchant_id uuid, p_user_id uuid, p_language text)`, `fn_shopify_landing_page_theme_layout(<uuid arg — read live identity args>)`, `fn_validate_shopify_landing_page_config(p_config jsonb)` — replace calls to old helper names with new names; replace column references `shopify_brand_scheme` → `brand_scheme`. For `fn_validate_shopify_landing_page_config`: its `secondary_color` reference — if it reads the MDS column, switch to `tokens.accent` in Migration B; if it is a key inside landing config JSON, leave it.

**Group 3 — switch flat readers to the scheme (Migration B). Output keys/formats unchanged:**

| Function | Change |
|---|---|
| `get_display_settings_fast(p_merchant_code text) RETURNS json` | `primary_color` ← `tokens.primary`; `secondary_color` ← `tokens.accent`; `border_radius_cards` ← `cards.radius_px || 'px'`; `border_radius_buttons` ← `buttons.radius_px || 'px'`; `border_radius_inputs` ← constant `'8px'`; `border_radius_modals` ← constant `'16px'`; `border_button_radius_small` ← constant `'6px'`. Scheme via `fn_brand_scheme_merged(merchant_id)` (defaults when no row / unknown code: resolve defaults via `fn_brand_scheme_default()`). All non-brand keys unchanged. |
| `get_display_settings_batch(p_merchant_codes text[])` | `primary_color`, `secondary_color` from merged scheme. Note: today returns NULL for no-row merchants; after migration every merchant has a row. |
| `get_merchant_display_settings(p_merchant_code text)` | Same mapping as `get_display_settings_fast` for its brand keys. |
| `fn_resolve_widget_merchant_display(p_merchant_id uuid)` | `primary_color` ← `scheme.tokens.primary`; `scheme` ← `fn_brand_scheme_merged`. Output shape `{ primary_color, points, tiers, earn_rate, scheme }` unchanged. |
| `admin_get_widget_settings(p_widget_type text)`, `api_get_widget_settings(p_widget_type text, p_merchant_code text)` | Via resolver; payload `{ ok, config, brand_scheme, resolved }` unchanged. |
| `bff_get_campaign_history`, `bff_get_currency_history`, `bff_get_purchase_history`, `bff_get_reward_history`, `bff_get_tier_history`, `bff_get_upload_receipt_history`, `bff_get_user_history_menu` | `v_primary_color := fn_brand_scheme_merged(v_merchant_id)->'tokens'->>'primary'` — resolve once per call, not per row. |
| `bff_get_notification_settings()` | Fallback primary ← scheme `tokens.primary`; fallback logo ← `logo` column (unchanged). |
| `api_bigcommerce_get_merchant_config(p_merchant_code text)` | `themeColor` ← scheme `tokens.primary`. Key name unchanged. |

### 6.5 Triggers, RLS, indexes

No change. `trg_cache_purge_merchant_display_settings` (`bootstrap,earn_channels,widget,shopify_landing`), `merchant_display_settings_invalidate_shopify_landing_cache`, `update_merchant_display_settings_updated_at` are row-level and keep working after the rename. No views, MVs, generated columns, or check constraints reference these columns.

## 7. Cache

No structural change and no key version bump — the scheme lives on the same row, and additive payload keys are safe.

| Cache | Key | TTL | Invalidation | Action |
|---|---|---|---|---|
| Postgres `extensions.ui_cache` widget | `merchant:{id}:widget:v2:{widget_type}` | 300s | MDS triggers | None |
| Postgres landing | `merchant:{id}:shopify_landing_page:v2:{lang}:published` | 300s | MDS triggers | None |
| Render Redis bootstrap (`loyalty-cache-api`) | `lc:{merchant}:bootstrap:{language}` | 600s | `trigger_cache_purge('bootstrap,…')` | None |
| loyalty-user Next Data Cache | tags `lc:all`, `m:{code}`, `m:{code}:bootstrap` | `revalidate: 300` | TTL only | None — up to 5 min lag after save is accepted |
| Admin `revalidatePath` (`brand-scheme/actions.ts`) | paths | — | on save | **Add** `/merchant-global-settings` and `/display-settings` |

The Migration A backfill purges caches for all merchants once. Run outside peak hours.

## 8. Frontend changes

### 8.1 loyalty-admin (`~/Documents/rocket/loyalty-admin`)

| File | Change |
|---|---|
| `src/components/brand-scheme/types.ts` | `BrandSchemeTokens.accent: string`; new `BrandSchemeCards { radius_px: number }`; `BrandScheme.cards: BrandSchemeCards`. |
| `src/components/brand-scheme/scheme-defaults.ts` | `SCHEME_SCHEMA_VERSION = "2.3.0"`; `defaultBrandScheme` adds `tokens.accent: "#666666"`, `cards: { radius_px: 12 }`; `normalizeBrandScheme` keeps `tokens.accent` and `cards` (today it rebuilds and drops unknown keys), clamps `buttons.radius_px` 0–100 and `cards.radius_px` 0–40. |
| `src/components/brand-scheme/actions.ts` | `fetchBrandScheme` → `admin_get_brand_scheme` (returns `{ scheme, logo, updated_at }`); `saveBrandScheme(scheme, assets?: { logo?: string \| null })` → `admin_upsert_brand_scheme(p_scheme, p_assets)`; add revalidate paths (§7). |
| `src/lib/shopify/theme-import/parse-theme-import.ts` (`buildButtons`, line ~174) | Button radius: `button_border_radius_primary` (0–100) → else `buttons_radius` (0–40) → else `null`. Add card radius: `card_corner_radius` (clamp 0–40) → else `null`. Remove the hardcoded `8` fallback. |
| `src/components/brand-scheme/theme-import/map-import-to-scheme.ts` (`themeImportApplyToBrandScheme`) | `null` from the parser = keep the current scheme value. Apply `cards.radius_px`. Never write `tokens.accent`. |
| `src/components/brand-scheme/brand-scheme-modal.tsx` | New required prop `surface: "shopify" \| "standalone"`. Field matrix §8.2. Save always submits the **full** loaded scheme with edits applied — hidden fields pass through unchanged. Logo field saves via `assets.logo`. |
| `src/components/brand-scheme/brand-scheme-provider.tsx` | `openModal({ surface })`; pass through to modal. |
| `src/components/brand-scheme/brand-scheme-card.tsx` | Summary shows primary swatch, logo thumbnail (if set), and accent swatch when `surface = standalone`. Accept `surface` prop. |
| `src/app/(admin)/display-settings/display-settings-hub.tsx` (~line 108, 159–161) | Remove the Shopify-only gate on the brand card and `BrandSchemeProvider`; pass `surface = getAdminSurface()`. |
| `src/app/(admin)/merchant-global-settings/general-settings-form.tsx` (Display settings section, ~356–391) | Add a second card under "Customer-facing appearance": title **Brand**, description "Logo, colors, and corner radius used across your loyalty app and storefront.", `BrandSchemeCard` summary, button **Edit brand** → opens modal with `surface = getAdminSurface()`. Shown on both surfaces. Mount `BrandSchemeProvider` here. |
| Shopify-surface entry points: `appearance-tab.tsx` (shopify-widget), `shopify-landing-page-editor.tsx`, `hub-images-editor.tsx`, `onboarding/steps/brand-match.tsx` | Pass `surface = "shopify"`. Onboarding inline form must round-trip `tokens.accent` and `cards` (use `normalizeBrandScheme`). |
| `src/types/database.ts` | Regenerate Supabase types after Migration A. |

Unchanged: Front Line print (reads `logo` directly), widget/landing editors (already derive primary from scheme), email appearance card.

### 8.2 Pop-up field matrix

| Field | Label | `shopify` | `standalone` |
|---|---|---|---|
| `tokens.primary` | Primary color | ✓ | ✓ |
| `tokens.accent` | Secondary color | — | ✓ |
| `logo` | Logo (help: "Shown in your loyalty app, printed slips, and emails.") | ✓ | ✓ |
| `cards.radius_px` | Card corner radius (px) — help "Rounding for cards and pop-ups." | ✓ | ✓ |
| `buttons.radius_px` | Button corner radius (px) — help "Rounding for buttons." (replaces today's "Corner radius" copy) | ✓ | — |
| `tokens.background`, `dark_surface`, `foreground_heading`, `foreground` | as today | ✓ | — |
| Button colors / borders | as today | ✓ | — |
| Theme import / source / reset | as today | ✓ | — |
| Preview | Widget / Landing / Hub tabs as today | ✓ | — |
| Preview | Static member-app preview: header on primary color with logo, one card using card radius, one secondary-color chip | — | ✓ |

Logo upload: reuse `ImageUploader` + `STANDARD_IMAGE_ACCEPT` exactly as `email-appearance-card.tsx` does, bucket `images`, following that component's path-prefix convention with segment `brand`. Logo does not change the widget header brand mark (widget JSON, stays in the widget Appearance tab).

### 8.3 rewarding-shopify

| File | Change |
|---|---|
| `widget-builder/src/landing/theme.js` (lines ~503–505) | `--rl-btn-radius` ← `buttons.radius_px` (unchanged); `--rl-card-radius` ← `cards?.radius_px ?? buttons.radius_px`. |
| `extensions/shared/brandSchemeStyle.ts` | Update types: add optional `tokens.accent`, `cards.radius_px`; fix stale `tokens.brand` doc. No behavior change. |

Deploy: `npm run deploy` (`shopify app deploy --config shopify.app.toml`). No visual change expected because Migration A sets Shopify merchants' `cards.radius_px` = their `buttons.radius_px`. Widget panel cards (`home.css`, 24px) stay hardcoded — out of scope.

### 8.4 loyalty-user, loyalty-cache-api

No change (D12). Do not touch `app-providers.tsx` defaults.

## 9. Edge function

`supabase/functions/inngest-event-router-serve/lib/notification-email.ts` (~107–129): the `merchant_display_settings` select changes from `logo, primary_color` to `logo, brand_scheme`; fallback primary = `brand_scheme?.tokens?.primary`. Fallback chain otherwise unchanged (appearance → display → `#111111`).

Deploy via MCP: `get_edge_function` for the live bundle → edit → `deploy_edge_function` with the full file set → confirm version and keep `verify_jwt` identical to the pre-deploy value (`list_edge_functions` before and after).

## 10. Phases and order

| Phase | What | Gate to next |
|---|---|---|
| **0 — Preflight (read-only)** | (a) Recompute §4 counts with D7. (b) Create snapshot table `tmp_brand_unification_snapshot` holding, per merchant: `get_display_settings_fast(code)` output, `api_get_widget_settings('<each active widget_type>', code)` `brand_scheme` + `resolved.primary_color`, and landing cached theme. (c) List Shopify merchants affected by D8 (flat `border_radius_cards` ≠ scheme `buttons.radius_px`) — informational. (d) Grep all clones + `supabase/functions` for `shopify_brand_scheme`, `admin_get_shopify_brand_scheme`, `admin_upsert_shopify_brand_scheme`, `fn_shopify_brand_scheme`, and MDS `primary_color|secondary_color|border_radius_`; confirm the list matches §6.4/§8/§9. Anything extra → stop and add it to this plan. | User approval to run Migration A |
| **1 — Migration A** (one transaction) | Capture §5 inputs into a temp table using old functions → rename column → create new helpers + admin RPCs + wrappers → recreate Groups 1–2 → drop old helper names → write backfill. Flat readers (Group 3) still read flat columns; upsert still syncs `primary_color`. | Verification V1 passes |
| **2 — Migration B** | Switch Group 3 readers to scheme; remove `primary_color` sync from upsert. Deploy Edge change (§9). | V2 passes |
| **3 — loyalty-admin** | §8.1 + §8.2. Push `main` only when asked. | Manual acceptance §11 (admin items) |
| **4 — rewarding-shopify** | §8.3; `shopify app deploy`. | Landing visual check on 2 Shopify merchants |
| **5 — Migration C** (destructive — needs explicit "approved") | Preconditions: Phases 2–4 live; `pg_proc` body search returns 0 references to old names and to the flat columns; Edge grep clean. Copy `merchant_id, primary_color, secondary_color, border_radius_cards, border_radius_buttons, border_radius_inputs, border_radius_modals, border_radius_button_small` into `merchant_display_settings_brand_backup` (plus `backed_up_at`). Drop wrappers `admin_get_shopify_brand_scheme`, `admin_upsert_shopify_brand_scheme`. Drop the 7 flat columns. Drop `tmp_brand_unification_snapshot`. | — |
| **6 — Docs closeout** | Per `06-product-doc-closeout`: `requirements/Display_Settings.md`, `requirements/domains/display-settings.md`, `docs/WIDGET_SETTINGS_FE_SPEC.md`, function registry, changelog. | — |

Backup table `merchant_display_settings_brand_backup` is dropped 30 days after Phase 5.

## 11. Verification

**V1 (after Migration A)** — for every merchant, compare the new scheme against the Phase 0 snapshot:

- `brand_scheme.tokens.primary` = Shopify: snapshot widget `brand_scheme.tokens.primary`; non-Shopify: snapshot `get_display_settings_fast.primary_color`.
- `tokens.accent` = snapshot `secondary_color`.
- `buttons.radius_px` = snapshot widget `brand_scheme.buttons.radius_px`.
- `cards.radius_px` = Shopify: snapshot `buttons.radius_px`; non-Shopify: snapshot `border_radius_cards` parsed.
- Every merchant has exactly one row with `_schema_version = '2.3.0'`.
- `get_display_settings_fast` output identical to snapshot except `border_button_radius_small` for newly inserted rows (column default `8px` vs fallback `6px`; no consumer).
Any other difference → stop, do not run Migration B.

**V2 (after Migration B)** — for every merchant, recompute the snapshot outputs and diff:

- `get_display_settings_fast`: allowed diffs only (1) `border_radius_inputs/modals/button_small` now constants, (2) `border_radius_buttons` for merchants whose flat value ≠ scheme value, (3) `border_radius_cards` for D8 Shopify merchants.
- Widget `brand_scheme`: identical except added `tokens.accent`, `cards`, `_schema_version`. `resolved.primary_color` identical.
- Landing cached theme: identical except additive keys.

**Manual acceptance:**

1. Standalone merchant → General settings → Brand → Edit brand: only standalone fields shown. Change primary, secondary, card radius, logo → save → member app header color, accent, pop-up radius, logo update within 5 min.
2. Same merchant → Display settings hub → brand card opens the same pop-up and mode.
3. Standalone merchant → `/display-settings/shopify-widget` → pop-up opens in `shopify` mode (full fields); saving there does not clear accent or logo.
4. Shopify merchant → landing editor → Edit scheme: `shopify` mode; change card radius → landing cards change, buttons don't; change button radius → buttons change, cards don't.
5. Theme import on a Horizon store: button radius = `button_border_radius_primary`, card radius = `card_corner_radius`; on a theme missing either key, the existing value is kept.
6. Save from an **old** admin build (between Migration A and Phase 3 deploy) keeps `tokens.accent` and `cards.radius_px`.
7. Logo appears on Front Line print slip and in email fallback when the email appearance logo is empty.

## 12. Out of scope

Font (hardcoded GraphikThai); `background_image`; wiring member-app buttons to `buttons.radius_px` (buttons use fixed per-size radii); widget panel card radius (`home.css` 24px); `merchant_notification_appearance` override semantics; spin wheel palettes; signup component `ThemeConfig`; BigCommerce contract changes; hiding the Shopify widget page for standalone merchants; removing member-app FE fallbacks.
