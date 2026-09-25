# Shopify landing CMS — hero layout, card grids, step markers, earn icons

Implementation plan. Written for an executor who did not attend the design discussion. Follow it literally; where it says "verify", read the file and confirm before editing. Where it says "do not", there is a reason in the *Why* line — do not work around it.

Repos (all under `~/Documents/rocket/`): `rewarding-shopify` (storefront bundle + admin preview iframe), `loyalty-admin` (CMS), `supabase-crm` (migrations + requirements). Supabase project `wkevmsedchftztoolkmi` only. Commit per repo. Do not push unless asked.

---

## 0. Model and invariants

**Model.** Three layers decide how the landing page looks:

| Layer | Storage | Owns |
|---|---|---|
| Brand scheme (global, theme-importable) | `merchant_display_settings.shopify_brand_scheme` | colour tokens, button tokens, radius |
| Page style (global to the landing page) | `merchant_shopify_landing_page_settings.config.theme` | section spacing; **new:** card grid look (`cards`) |
| Section config (per placement) | `display_settings.config` | content, surface swatch, two custom text roles, CTA show/text/style; **new:** layout variant keys |

Rule for placing a setting: **what makes cards look like the same family is global (Page style); what depends on the content of one section is per section; every colour and every pixel value beyond the ones listed below is derived.**

**Invariants — do not violate.**

1. No new tables, no new RPCs beyond `CREATE OR REPLACE` of the functions named here, no new `block_style` rows. *Why:* the config shape already has homes for everything; `block_style` is unused by the landing renderer and adding a second layout axis would be a fork.
2. No per-section colour keys beyond the existing `surface.*`, `text_hex`, `heading_hex`. No per-section pixel spacing keys. *Why:* colours come from the scheme ladder; spacing rhythm is page-wide.
3. Storefront CSS may not contain colour literals (`npm run lint:theme-css` must pass). Every colour is a `--rl-*` variable emitted from `theme.js` / `primitives.jsx`.
4. Admin preview and published storefront render from the same code path (`normalizeLandingDocument` → `LandingPage`). Do not add visual fallbacks that exist only in `loyalty-admin/.../preview/preview-enrichment.ts`.
5. Existing merchants must render identically until they touch a new setting: every new key has a default in `fn_shopify_landing_default_section_config` / `fn_shopify_landing_default_page_config` and the renderer must treat a missing key as that default.
6. Do not restructure files that are not listed. Do not rename existing config keys. Do not "clean up" unrelated CSS.
7. Database changes go through a migration file committed in `supabase-crm/supabase/migrations/` **and** applied with Supabase MCP `apply_migration` after the user says "approved". Author `CREATE OR REPLACE FUNCTION` bodies by first fetching the live body (`select pg_get_functiondef('<fn>'::regproc)`) and editing it — never from memory. Several of these functions are live but not in tracked migrations (see §1.4).

---

## 1. Config contract (the source of truth for every workstream)

### 1.1 Page style — `merchant_shopify_landing_page_settings.config.theme`

```json
{
  "theme": {
    "section_padding_px": 88,
    "cards": {
      "gap_px": 24,
      "border": "none",
      "fill": "raised"
    }
  }
}
```

| Key | Type / allowed | Default | Meaning |
|---|---|---|---|
| `theme.cards.gap_px` | integer, 0–48, step 4 | 24 | gap between cards, rows and columns alike, in every card grid section |
| `theme.cards.border` | `none` \| `line` | `none` | `line` draws a 1px border on each card. When `gap_px = 0` the borders collapse into a single grid of lines (see §4.3). |
| `theme.cards.fill` | `flat` \| `raised` | `raised` | `raised` = card background is the section's level-1 tint (`--rl-card-bg`, today's look). `flat` = transparent card on the section surface. |

Existing behaviour to keep: `fn_shopify_landing_merge_page_config` strips `theme.palette`, `theme.buttons`, and trims `theme.import`. Add `cards` alongside `section_padding_px`; do not touch the strip list.

### 1.2 Hero — `shopify_landing_hero` section config (additions only)

```json
{
  "content_align": "center",
  "side_image_position": "none",
  "side_image_url": ""
}
```

| Key | Allowed | Default | Meaning |
|---|---|---|---|
| `content_align` | `start` \| `center` \| `end` | `center` | Horizontal placement and text alignment of the content block (headline, subtext, CTA, content card). |
| `side_image_position` | `none` \| `start` \| `end` | `none` | `none` = single column (today). `start`/`end` = two columns at ≥768px; the contained image sits on that side, content takes the other. |
| `side_image_url` | string URL or `""` | `""` | The contained "subject" image. Independent from `background.image_url` (the cover backdrop). Both may be set. |

Everything in `background.*` (cover image, tint) and `content_card.*` is **unchanged** and stays independent of these three keys. Key names mirror the referrals section (`layout`, `side_image_url`) — do not invent new spellings.

### 1.3 Card sections — `shopify_landing_ways_to_earn`, `shopify_landing_ways_to_spend`, `shopify_landing_how_it_works`

```json
{
  "tile_layout": "stacked",
  "grid": { "columns_desktop": 3 }
}
```

| Key | Sections | Allowed | Default | Meaning |
|---|---|---|---|---|
| `tile_layout` | earn, spend, how_it_works | `stacked` \| `inline` | `stacked` | `stacked` = icon on top, text centred. `inline` = text left, icon right (today's earn look). |
| `grid.columns_desktop` | earn, spend only | `2` \| `3` \| `4` | `3` | Columns at ≥1024px. Tablet/mobile derived (§4.2). how_it_works always renders 3 (steps are exactly 3) — do not add the key there. |
| `steps_marker` | how_it_works only | `icon` \| `number` | `icon` | `icon` = `steps[].icon_url` or default step icon. `number` = large `01` / `02` / `03` numeral, no icon. Never both. |

`tile_limit` (earn/spend) is unchanged.

### 1.4 Where these keys are enforced (SQL)

Live functions (verified via `pg_proc`) and what to change:

| Function | Args → returns | Change |
|---|---|---|
| `fn_shopify_landing_default_page_config()` | → jsonb | add `theme.cards` defaults (§1.1) |
| `fn_validate_shopify_landing_page_config(p_config jsonb)` | → text (NULL = ok) | validate `theme.cards.*` per §1.1; reject non-integer / out-of-range gap, unknown enum values |
| `fn_shopify_landing_default_section_config(p_block_type text)` | → jsonb | add §1.2 keys to hero CASE; add §1.3 keys to earn / spend / how_it_works CASEs |
| `fn_validate_shopify_landing_section_config(p_block_type text, p_config jsonb)` | → text | add enum checks for §1.2 / §1.3 keys per block type; `side_image_url` string-or-empty |
| `fn_enrich_shopify_landing_sections` | (existing) | only in WS4: replace `'icon_url', NULL` for earn tiles |

Latest in-repo migrations: `20260919140000_shopify_brand_scheme.sql` (page config fns), `20260920040307_shopify_brand_scheme_v2.sql` (enrichment, cached RPCs), `20260920153000_shopify_widget_header_scheme_derived.sql` (section upgrade). **Not in repo, live only:** `fn_validate_shopify_landing_section_config`, `fn_shopify_landing_default_section_config`, `fn_shopify_landing_merge_section_config`, `admin_batch_update_shopify_landing_sections`, `fn_jsonb_deep_merge_landing`. The new migration must contain the full `CREATE OR REPLACE` for every function it changes, fetched live first (Invariant 7).

`display_block_template` rows for `shopify_landing_*` are live with no seed migration. The new migration must `UPDATE display_block_template SET config = config || '<new defaults>'::jsonb WHERE block_type = '<type>' AND block_style = 'default'` for hero, ways_to_earn, ways_to_spend, how_it_works so template fallback matches the function defaults.

Also verify: `admin_get_shopify_landing_page_settings` and `api_get_shopify_landing_page_cached` (both in `20260920040307_shopify_brand_scheme_v2.sql`) expose `theme` to the client. If they project `theme` key-by-key (e.g. only `section_padding_px`), add `cards`. If they pass the merged `theme` object through, nothing to do — say which in the commit message.

---

## 2. Workstreams and order

Do them in this order. Each has a gate; do not start the next before the gate passes.

| # | Workstream | Repos | Gate |
|---|---|---|---|
| WS1 | Shared tile primitive + page-level Cards settings | rewarding-shopify, loyalty-admin, supabase-crm | all three card sections render through one `Tile`; `gap_px` / `border` / `fill` visibly change the page; existing merchants unchanged at defaults |
| WS2 | Hero: `content_align`, contained side image, Auto-colour derivation fix | rewarding-shopify, loyalty-admin, supabase-crm | every combination in §4.1 renders; theme-resolver tests pass |
| WS3 | How it works: `steps_marker`, ring removal, default icons on published path | rewarding-shopify, loyalty-admin, supabase-crm | published page with empty `icon_url` shows a default icon; number mode shows `01/02/03` with no icon |
| WS4 | Earn channel `icon_url` (merchant override → landing, hub, widget) | supabase-crm, loyalty-admin, rewarding-shopify | uploaded icon appears on landing earn tile; hub and widget unchanged when unset |
| WS5 | Docs closeout | supabase-crm | `requirements/Display_Settings.md` updated (§7) |

WS1 to WS3 SQL changes may ship as **one** migration `supabase-crm/supabase/migrations/20260922120000_shopify_landing_layout_and_cards.sql` if executed in one thread; WS4 is a separate migration `20260922130000_earn_channel_icon_url.sql`.

---

## 3. WS1 — shared tile primitive + Cards settings

### 3.1 Storefront (`rewarding-shopify/widget-builder/src/landing/`)

**`components/tiles.jsx`** — add one exported component and refactor the three existing ones onto it.

```jsx
// Tile: the single card used by how-it-works steps, earn tiles, reward tiles.
// props:
//   layout: 'stacked' | 'inline'
//   icon:   { src: string|null, alt: string }   // rendered only when src is truthy and marker is null
//   marker: { text: string } | null              // e.g. { text: '01' } — replaces the icon
//   title:  string
//   description: string|null
//   meta:   ReactNode|null                       // e.g. reward points line; rendered under description
//   className?: string
export function Tile({ layout, icon, marker, title, description, meta, className }) { ... }
```

Markup (exact class names — CSS below depends on them):

```html
<article class="rl-tile rl-tile--stacked|rl-tile--inline {className}">
  <div class="rl-tile__media">
    <!-- one of: -->
    <span class="rl-tile__number">01</span>
    <img class="rl-tile__icon" src="…" alt="…" loading="lazy" />
  </div>
  <div class="rl-tile__body">
    <h3 class="rl-tile__title">…</h3>
    <p class="rl-tile__desc">…</p>          <!-- omit element when description empty -->
    <div class="rl-tile__meta">…</div>       <!-- omit element when meta null -->
  </div>
</article>
```

Refactor:
- `EarnTile` (tiles.jsx) → returns `<Tile layout={layout} icon={{src: iconSrc, alt: tile.title}} title=… description=… />`. Keep `iconSrc = tile.icon_url || tile.image_url` exactly as today (`tiles.jsx:32`).
- `RewardTile` (tiles.jsx) → `<Tile … meta={<span class="rl-tile__points">{pointsLabel}</span>} />`. Keep the existing points formatting code; only move it into `meta`.
- `StepCard` (`components/HowItWorksSection.jsx`) → `<Tile layout=… marker={marker} icon=… title={step.heading} description={step.description} />`. Marker logic is WS3; in WS1 pass `marker={null}` and keep icon behaviour as today (icon may be empty).

**`components/gridSections.jsx`** and **`HowItWorksSection.jsx`** — replace `.rl-step-grid` / `.rl-earn-grid` / `.rl-reward-grid` containers with one grid element:

```jsx
<div
  className="rl-tile-grid"
  style={{ '--rl-grid-cols': colsDesktop, '--rl-grid-cols-tablet': colsTablet }}
>
```

where `colsDesktop = section.config?.grid?.columns_desktop ?? 3` for earn/spend, `3` for how_it_works, and `colsTablet = Math.min(colsDesktop, 2)`. `tile_layout = section.config?.tile_layout ?? 'stacked'` passed to each `Tile`. **Note the default change:** earn tiles were inline today; the product decision is that the default becomes `stacked` for all three. Existing merchants therefore see earn tiles switch to stacked — this is intended and approved; do not "preserve" inline as the earn default.

**`theme.js` → `applyLandingThemeCss(node, document, resolved)`** — after the existing root vars, add:

```js
const cards = document?.theme?.cards || {};
const gap = Number.isFinite(cards.gap_px) ? Math.max(0, Math.min(48, cards.gap_px)) : 24;
node.style.setProperty('--rl-cards-gap', `${gap}px`);
node.classList.toggle('rl-cards--border-line', cards.border === 'line');
node.classList.toggle('rl-cards--collapsed', cards.border === 'line' && gap === 0);
node.classList.toggle('rl-cards--fill-flat', cards.fill === 'flat');
```

Classes go on the same node that carries `--rl-section-pad` (the `.rocket-landing` root). Also set `node.style.setProperty('--rl-card-radius', '12px')` — a derived constant, not a setting.

**`landing.css`** — delete the rules for `.rl-step-grid`, `.rl-step-card`, `.rl-step-card__icon-ring`, `.rl-step-card__index`, `.rl-step-card__body`, `.rl-earn-grid`, `.rl-earn-tile`, `.rl-earn-tile__icon-ring`, `.rl-earn-tile__copy`, `.rl-reward-grid`, `.rl-reward-tile`, `.rl-reward-tile__icon-outer` once nothing references them (grep first). Add:

```css
.rl-tile-grid {
  display: grid;
  grid-template-columns: 1fr;
  gap: var(--rl-cards-gap, 24px);
}
@media (min-width: 768px)  { .rl-tile-grid { grid-template-columns: repeat(var(--rl-grid-cols-tablet, 2), minmax(0, 1fr)); } }
@media (min-width: 1024px) { .rl-tile-grid { grid-template-columns: repeat(var(--rl-grid-cols, 3), minmax(0, 1fr)); } }

.rl-tile {
  display: flex;
  gap: 16px;
  padding: 24px;                              /* derived constant — not a setting */
  border-radius: var(--rl-card-radius, 12px);
  background: var(--rl-card-bg);
  color: var(--rl-card-text);
  border: 0 solid var(--rl-card-border);
  min-width: 0;
}
.rl-tile--stacked { flex-direction: column; align-items: center; text-align: center; }
.rl-tile--inline  { flex-direction: row; align-items: flex-start; text-align: left; }
.rl-tile--inline .rl-tile__body  { order: 0; flex: 1 1 auto; }
.rl-tile--inline .rl-tile__media { order: 1; flex: 0 0 auto; }

.rl-tile__media { display: flex; align-items: center; justify-content: center; width: 48px; height: 48px; }
.rl-tile__icon  { width: 48px; height: 48px; object-fit: contain; display: block; }  /* no ring, no background */
.rl-tile__number { font-size: 40px; line-height: 1; font-weight: 700; color: var(--rl-card-heading); }
.rl-tile__title { margin: 0; color: var(--rl-card-heading); }
.rl-tile__desc  { margin: 4px 0 0; color: var(--rl-card-text); }
.rl-tile__meta  { margin-top: 8px; color: var(--rl-section-link); }

/* Card border: line */
.rl-cards--border-line .rl-tile { border-width: 1px; }

/* Collapsed grid lines when gap is 0: tiles draw right+bottom, grid draws top+left */
.rl-cards--collapsed .rl-tile-grid { border-top: 1px solid var(--rl-card-border); border-left: 1px solid var(--rl-card-border); }
.rl-cards--collapsed .rl-tile { border-width: 0 1px 1px 0; border-radius: 0; }

/* Card fill: flat */
.rl-cards--fill-flat .rl-tile { background: transparent; }
```

`--rl-card-bg`, `--rl-card-border`, `--rl-card-text`, `--rl-card-heading`, `--rl-section-link` already exist (`primitives.jsx:102–133`). If `--rl-card-border` resolves to `transparent` on some surfaces in `resolveSectionTokens`, change it to `fg at 16% alpha` in `theme.js` so `border: line` is visible on every swatch — that is a derivation fix inside the one module, allowed.

Check while here: `.rl-section` padding reads `var(--rl-section-pad-local, var(--rl-section-pad-y))` (`landing.css:46`) and never `--rl-section-pad`, which `applyLandingThemeCss` sets from `theme.section_padding_px`. Verify whether `LandingPage` passes `padding` to `SectionFrame` per section. If `section_padding_px` has no visible effect on the storefront, fix by making `.rl-section` fall back to `var(--rl-section-pad)` before `--rl-section-pad-y`. Report which case it was.

### 3.2 Admin (`loyalty-admin/src/app/(admin)/display-settings/shopify-landing-page/`)

**`types.ts`** — extend:
```ts
export type LandingCardsBorder = "none" | "line";
export type LandingCardsFill = "flat" | "raised";
export interface LandingCardsTheme { gap_px: number; border: LandingCardsBorder; fill: LandingCardsFill; }
// in LandingPageConfig.theme: cards?: LandingCardsTheme
export type LandingTileLayout = "stacked" | "inline";
// in LandingSectionConfig: tile_layout?: LandingTileLayout; grid?: { columns_desktop: 2 | 3 | 4 };
```

**`landing-theme-layout.ts`** — the normalizer for `theme` must fill `cards` with §1.1 defaults when missing and clamp `gap_px` to 0–48 in steps of 4.

**`landing-layout-form.tsx`** (`LandingLayoutForm`, rendered in the Globals pane between `BrandSchemeCard` and `PageSettingsForm`) — rename the card title to **"Page style"** and add, under the existing section-spacing control, a subheading **"Cards"** with three controls:

| Label | Control | Values | Help text |
|---|---|---|---|
| Card spacing | Polaris `RangeSlider` min 0 max 48 step 4, suffix "px" | `theme.cards.gap_px` | "Space between cards in How it works, Ways to earn and Ways to spend. Set to 0 for a grid with no gaps." |
| Card border | Polaris `ChoiceList` (single) | None / Line | "With 0 spacing, borders become grid lines." |
| Card fill | Polaris `ChoiceList` (single) | Raised / Flat | "Raised tints the card against the section. Flat keeps only the section colour." |

Do not add colour pickers here. Do not add per-row/per-column spacing. Save goes through the existing `persistDraft` → `saveLandingPageSettings` → `admin_upsert_shopify_landing_page_settings`; no new action.

**`landing-section-form.tsx`** — for `shopify_landing_ways_to_earn` and `shopify_landing_ways_to_spend` add a new `SectionSettingsGroup` titled **"Layout"** placed directly after "General" and before "Content":

| Label | Control | Key |
|---|---|---|
| Columns on desktop | Polaris `Select` options 2 / 3 / 4 | `grid.columns_desktop` |
| Card layout | Polaris `ChoiceList` single: "Stacked — icon above text", "Inline — text left, icon right" | `tile_layout` |

For `shopify_landing_how_it_works` the same group holds only **Card layout** in WS1 (WS3 adds the marker). Use the existing `patchConfig(patch)` helper; for `grid` write `patchConfig({ grid: { ...(config.grid ?? {}), columns_desktop: n } })`.

**`landing-section-helpers.ts`** — normalizers that fill section defaults must set `tile_layout: "stacked"` and `grid.columns_desktop: 3` when missing for earn/spend, `tile_layout: "stacked"` for how_it_works.

Preview: the editor already posts the full `config` + `sections` to the iframe (`preview-surface.tsx:66–76`, no key whitelist); no change needed. Verify the preview updates live when you move the slider.

### 3.3 SQL (`supabase-crm`)

In the migration (§1.4): `fn_shopify_landing_default_page_config` + `fn_validate_shopify_landing_page_config` for `theme.cards`; `fn_shopify_landing_default_section_config` + `fn_validate_shopify_landing_section_config` for `tile_layout`, `grid.columns_desktop`; `display_block_template` UPDATEs. Validation messages follow the existing style in the function (short English sentence naming the key).

### 3.4 WS1 gate

- `cd rewarding-shopify/widget-builder && npm run lint:theme-css && npm run build` pass.
- `node src/landing/normalize.test.mjs` and `node src/landing/theme-resolver.test.mjs` pass (add a test asserting `tile_layout` / `grid` defaults survive `normalizeLandingDocument`).
- In the admin editor: defaults render the page as before except earn tiles are now stacked; moving Card spacing to 0 + Border "Line" shows a clean single-line grid with no doubled lines; Fill "Flat" removes card tint on every section; Columns 4 shows 4 columns at ≥1024px, 2 at 768–1023, 1 below.
- SQL: `select fn_validate_shopify_landing_page_config('{"theme":{"cards":{"gap_px":50}}}')` returns an error string; with `24` returns NULL.

---

## 4. WS2 — hero layout and Auto-colour derivation

### 4.1 Rendering rules (storefront `components/HeroSection.jsx`, `HeroMemberCard.jsx`, `landing.css`)

Read the three keys with defaults: `contentAlign = config.content_align ?? 'center'`, `sidePos = config.side_image_position ?? 'none'`, `sideUrl = config.side_image_url || ''`. Treat `sidePos !== 'none' && !sideUrl` as `sidePos = 'none'` (no empty column).

Background is untouched: the existing cover image / tint / swatch code stays exactly as it is.

Add classes on `.rl-hero__inner`: `rl-hero__inner--align-start|center|end` and, when a side image renders, `rl-hero__inner--split rl-hero__inner--image-start|end`. Markup with a side image:

```html
<div class="rl-hero__inner rl-hero__inner--split rl-hero__inner--image-end rl-hero__inner--align-start">
  <div class="rl-hero__content"> <!-- existing card / member card goes here unchanged --> </div>
  <div class="rl-hero__side"><img class="rl-hero__side-img" src="…" alt="" loading="lazy" /></div>
</div>
```

CSS:

```css
.rl-hero__inner--align-start  { justify-content: flex-start; }
.rl-hero__inner--align-center { justify-content: center; }
.rl-hero__inner--align-end    { justify-content: flex-end; }
.rl-hero__inner--align-start .rl-hero__card  { text-align: left; }
.rl-hero__inner--align-center .rl-hero__card { text-align: center; }
.rl-hero__inner--align-end .rl-hero__card    { text-align: right; }
.rl-hero__inner--align-start .rl-hero__actions { justify-content: flex-start; }
.rl-hero__inner--align-end .rl-hero__actions   { justify-content: flex-end; }

.rl-hero__inner--split { display: grid; grid-template-columns: 1fr; gap: 32px; align-items: center; }
.rl-hero__side { display: flex; justify-content: center; order: -1; }        /* mobile: image above content */
.rl-hero__side-img { max-width: 100%; max-height: 420px; object-fit: contain; border-radius: var(--rl-card-radius, 12px); display: block; }
@media (min-width: 768px) {
  .rl-hero__inner--split { grid-template-columns: 1fr 1fr; gap: 48px; }
  .rl-hero__inner--image-end .rl-hero__side   { order: 1; }
  .rl-hero__inner--image-start .rl-hero__side { order: -1; }
  .rl-hero__inner--split .rl-hero__content { display: flex; }
  .rl-hero__inner--split.rl-hero__inner--align-start .rl-hero__content  { justify-content: flex-start; }
  .rl-hero__inner--split.rl-hero__inner--align-center .rl-hero__content { justify-content: center; }
  .rl-hero__inner--split.rl-hero__inner--align-end .rl-hero__content    { justify-content: flex-end; }
}
```

Existing `.rl-hero__card` max-width caps stay. The member card (`HeroMemberCard`) sits inside `.rl-hero__content` and must follow the same alignment classes — check it does not hardcode `text-align:center`.

All 3 × 3 combinations are valid; there is no validation coupling between `content_align` and `side_image_position`, nor between either and `background.*`.

### 4.2 Auto-colour derivation fix (`theme.js`)

Problem: with a cover image, `resolveHeroCardContentColors` (`theme.js:318–348`) and the primary-button inversion inside `resolveSectionTokens` both evaluate contrast against `surface.swatch`, not against what is actually behind the text.

Add one pure function and use it in both places:

```js
// Returns the hex colour that is effectively behind the hero content text/buttons.
export function resolveHeroContentBackdrop({ sectionTokens, background, contentCard, cardBgResolved }) {
  const hasImage = Boolean(background?.image_url);
  let base = sectionTokens.background;
  if (hasImage && background?.tint?.enabled) {
    const tintHex = background.tint.color === 'light' ? '#FFFFFF' : '#000000';
    const strength = clamp01((background.tint.strength_pct ?? 40) / 100);
    base = mixHex(base, tintHex, strength);
  } else if (hasImage) {
    base = null;   // unknown: photo with no tint
  }
  if (contentCard?.enabled) {
    const cardBase = base ?? sectionTokens.background;
    const alpha = clamp01((contentCard.bg_opacity_pct ?? 85) / 100);
    return mixHex(cardBase, cardBgResolved, alpha);
  }
  return base ?? sectionTokens.background;
}
```

Use the existing `mixHex` / clamp helpers in `theme.js`; do not add a colour library. Then:

- In `resolveHeroCardContentColors`: Auto heading/body = `readable(tokens.text, backdrop)` where `backdrop = resolveHeroContentBackdrop(...)`. Custom `heading_hex` / `text_hex` still win when set.
- For the hero CTA: recompute `buttonPrimaryBg/Text` using the same inversion rule as `resolveSectionTokens` (contrast `< 3` → `extreme(backdrop)` fill) but against `backdrop` instead of the section background. Do this by factoring the existing button block into `resolveButtonTokens(bg, brandScheme)` and calling it once for the section (unchanged behaviour) and once for the hero content backdrop. Hero uses the second result for its CTA CSS vars only.

No new config keys. Add cases to `theme-resolver.test.mjs`: (a) dark swatch + light tint 60% + no card → text resolves dark; (b) any swatch + card enabled → text readable on blended card colour; (c) primary equal to backdrop → button inverts.

### 4.3 Admin

**`types.ts`**: `content_align?: "start"|"center"|"end"; side_image_position?: "none"|"start"|"end"; side_image_url?: string;` on the hero config.

**`landing-section-form.tsx`** hero branch (`isHero`, lines ~400–428) — new group order:

1. **General** (unchanged)
2. **Layout** (new) — `Content alignment`: Polaris `ChoiceList` Left / Center / Right → `start|center|end`. `Side image`: `ChoiceList` None / Left of text / Right of text → `none|start|end`. When not `none`, show `ImageUploader` (same props as the background uploader at `649–660`, `folder={\`${folder}/hero-side\`}`, `maxFiles={1}`) bound to `side_image_url`, labelled "Side image", help "Shown at its own size beside the text. Use the Background group for a full-width photo."
3. **Text & button** (unchanged)
4. **Background** (unchanged; keep label "Background image")
5. **Content card** (unchanged)
6. **Appearance** (unchanged) — add one line of subdued help text under Text color: "Auto keeps text and buttons readable against the content card or tint. Button colours come from your brand scheme."

Normalizers in `landing-section-helpers.ts` fill the three defaults.

### 4.4 SQL

`fn_shopify_landing_default_section_config` hero CASE: add the three keys. `fn_validate_shopify_landing_section_config` hero branch: enum checks; `side_image_url` must be text (empty allowed). `display_block_template` hero UPDATE.

### 4.5 WS2 gate

- Combinations to check in the editor, each screenshot-verified at 1280 and 390 widths: (center, none), (start, none), (end, none), (start, end) with cover image + tint, (start, end) with flat swatch, (end, start) with cover image no tint + card on. Mobile shows side image above content in every split case.
- Existing merchants (no new keys) render pixel-identical to before, except where the derivation fix changes Auto text on image heroes — list those merchants' hero settings in the PR description.
- Tests in §4.2 pass; `lint:theme-css` passes.

---

## 5. WS3 — How it works: marker, ring removal, default icons

### 5.1 Storefront

**New file `src/landing/step-icons.js`** exporting `DEFAULT_STEP_ICON_URLS = [signupUrl, cartUrl, redeemUrl]` — the three URLs currently used by `fixture/previewPlaceholders.js:21–38` (`stepSignup`, `stepCart`, `stepRedeem`). `previewPlaceholders.js` must import from this file instead of holding its own copy.

**`normalize.js`** — where steps are normalised (`~59–63`): `icon_url = step.icon_url || DEFAULT_STEP_ICON_URLS[index] || DEFAULT_STEP_ICON_URLS[0]`. This makes the **published** page show default icons (today it renders nothing when `icon_url` is empty — a live gap).

**`HowItWorksSection.jsx`** — `marker = config.steps_marker ?? 'icon'`. For each step: `marker === 'number'` → `<Tile marker={{ text: String(index + 1).padStart(2, '0') }} icon={null} … />`; else `<Tile marker={null} icon={{ src: step.icon_url, alt: step.heading }} … />`. Delete the `step.step_label || \`/ 0${index+1}\`` index rendering (`HowItWorksSection.jsx:15`) and any `step_label` reading. The ring is already gone from WS1's `Tile`.

### 5.2 Admin

**`loyalty-admin/.../preview/preview-enrichment.ts`** — remove the step-icon fallbacks (`~27–58`). The iframe now owns them (Invariant 4). Keep any non-visual placeholder text enrichment that lives there.

**`landing-section-form.tsx`** how_it_works "Layout" group (created in WS1) — add above Card layout:

| Label | Control | Key | Effect |
|---|---|---|---|
| Step marker | `ChoiceList` single: "Icon", "Number" | `steps_marker` | When `number`, hide the per-step icon uploaders in the Steps group and show help "Steps show 01, 02, 03 instead of icons." When `icon`, show uploaders with help "Leave empty to use the default icon." |

`types.ts`: `steps_marker?: "icon" | "number"`. Normalizer default `icon`.

### 5.3 SQL

Default + validate `steps_marker` for how_it_works; template UPDATE.

### 5.4 WS3 gate

- A published merchant page (or preview with `steps[].icon_url = ""`) shows the three default icons.
- `number` mode: numerals `01 02 03` in heading colour, no `<img>` in the step tiles, no `/ 01` text anywhere (grep the built `extensions/loyalty-widget/assets/landing.js` for `"/ 0"`).
- `previewPlaceholders.js` and `preview-enrichment.ts` contain no step icon URLs of their own.

---

## 6. WS4 — earn channel icon (merchant override)

Scope: one column, one admin field, wire-through to landing (required), hub and widget (additive, render only when present). Do **not** add a per-tile icon field to the landing section — the earn channel owns its icon so hub, widget and landing agree.

### 6.1 SQL — migration `20260922130000_earn_channel_icon_url.sql`

1. `ALTER TABLE earn_channel ADD COLUMN IF NOT EXISTS icon_url text;`
2. `bff_upsert_single_earn_channel(p_data jsonb, p_language text)` — fetch live body; persist `p_data->>'icon_url'` (NULL when absent/empty). No other behaviour change.
3. `fn_enrich_shopify_landing_sections` (fetch live body from `20260920040307_shopify_brand_scheme_v2.sql` lines 520–531 as reference, then live) — replace `'icon_url', NULL` with `'icon_url', COALESCE(ec.icon_url, reg.default_icon_url)` where `ec` is the merchant `earn_channel` row and `reg` the `earn_channel_registry` row joined the same way the function already resolves titles. If the function builds tiles from a different source that has no registry join, add the join minimally and say so.
4. `fn_compose_shopify_hub_unbranded` — add `'icon_url', COALESCE(ec.icon_url, reg.default_icon_url)` to each earn object. Additive key only.
5. `bff_get_earn_channels` — verify whether it already returns `icon_url`; if not, add it additively. `requirements/Earn_Channel.md` notes `icon_url` was removed from the member contract earlier — re-adding as an optional field is intended; note it in WS5.

### 6.2 Admin (`loyalty-admin/src/app/(admin)/earn-channels/`)

- `EarnChannelRecord` type: `icon_url?: string | null`.
- Channel edit form: `ImageUploader` field labelled **"Icon"**, `maxFiles={1}`, `folder="earn-channels/icons"`, help "Square image, shown on the landing page, loyalty hub and widget. Leave empty for the default." Include in the `p_data` payload built in `[id]/actions.ts` (~147) and `actions.ts` (~327).

### 6.3 Storefront

Landing: no change — `EarnTile` already reads `tile.icon_url` first (`tiles.jsx:32`, `normalize.js:123–136`), and `resolveDefaultEarnTileIconUrl` remains the fallback after registry default. Hub (`extensions/loyalty-hub`) and `WayToEarnView.jsx`: render `icon_url` when present, otherwise exactly what they render today. No layout change.

### 6.4 WS4 gate

- Upload an icon on one earn channel → landing earn tile shows it after cache invalidation; other channels unchanged.
- Hub and widget lists unchanged for channels without `icon_url`.

---

## 7. WS5 — docs closeout (`supabase-crm/requirements/Display_Settings.md`)

Edit, do not rewrite:

- **Rules → Shopify brand scheme / colour ladder bullet:** add "Card grid look is page-level (`theme.cards`: `gap_px` 0–48, `border` none|line, `fill` flat|raised); borders collapse to grid lines at gap 0; card padding, radius, icon box are derived constants."
- **Rules → new bullet "Shopify landing layout keys":** hero `content_align` (start|center|end), `side_image_position` (none|start|end) + `side_image_url` (contained image, independent of `background.image_url`); earn/spend `grid.columns_desktop` (2|3|4, tablet = min(n,2), mobile 1) and `tile_layout` (stacked|inline, default stacked); how_it_works `tile_layout`, `steps_marker` (icon|number), default step icons resolved in the storefront bundle for preview and published alike; no icon ring, no forced step index.
- **Rules → Shopify landing CTAs bullet:** append "Hero Auto text and button contrast resolve against the content card / tint backdrop when a cover image is set."
- **System → Data model:** `merchant_shopify_landing_page_settings` row: "`config.theme` = `section_padding_px` + `cards` + import flags".
- `requirements/Earn_Channel.md`: `earn_channel.icon_url` (merchant override, falls back to `earn_channel_registry.default_icon_url`) feeds landing tiles, hub earn list, and widget earn list.
- Changelog entry per the repo's convention if one exists in `requirements/`.

---

## 8. Admin page — final shape after all workstreams

Globals pane (unchanged order): **Brand** (`BrandSchemeCard`) → **Page style** (`LandingLayoutForm`: Section spacing; Cards: spacing / border / fill) → **Page settings** (SEO).

Section drawer group order (same for every section type so the merchant learns it once):

| Section | Groups in order |
|---|---|
| Hero | General · Layout (content alignment, side image) · Text & button · Background · Content card · Appearance |
| How it works | General · Layout (step marker, card layout) · Content · Steps · Text & button · Appearance |
| Ways to earn / Ways to spend | General · Layout (columns, card layout) · Content · Program tiles · Text & button · Appearance |
| Referrals / VIP / FAQ | unchanged |

Controls are Polaris `ChoiceList`, `Select`, `RangeSlider`, `ImageUploader` only. No thumbnails, no colour pickers, no free-text pixel inputs in the new groups.

---

## 9. What the executor must not do

- Do not add `columns`, `gap`, `padding`, `border`, or any colour to per-section config. Do not add per-section overrides of `theme.cards`.
- Do not add a hero-only button colour, a "button on image" toggle, or an image-luminance analyser.
- Do not keep the icon ring "as an option". Do not keep `/ 01` step indices behind a flag.
- Do not use `block_style` for any of this. Do not create new `display_block_template` rows.
- Do not put default icons or any visual fallback in `loyalty-admin` preview code.
- Do not write SQL function bodies from memory; fetch live with `pg_get_functiondef` first.
- Do not apply migrations before the user says "approved". Do not push.

---

## 10. Verification commands

```bash
# storefront
cd ~/Documents/rocket/rewarding-shopify/widget-builder
npm run lint:theme-css
node src/landing/normalize.test.mjs
node src/landing/theme-resolver.test.mjs
node src/landing/landing-cta.test.mjs
npm run build          # writes extensions/loyalty-widget/assets/landing.js + landing.css

# admin
cd ~/Documents/rocket/loyalty-admin
npm run lint
npx next build         # type check (no dedicated typecheck script)
```

SQL smoke (read-only, via Supabase MCP `execute_sql` on `wkevmsedchftztoolkmi`):

```sql
select fn_validate_shopify_landing_page_config('{"theme":{"cards":{"gap_px":24,"border":"line","fill":"flat"}}}'::jsonb);  -- NULL
select fn_validate_shopify_landing_section_config('shopify_landing_hero',
  fn_shopify_landing_default_section_config('shopify_landing_hero') || '{"content_align":"end","side_image_position":"start","side_image_url":"https://x/y.png"}'::jsonb);  -- NULL
select fn_validate_shopify_landing_section_config('shopify_landing_how_it_works',
  fn_shopify_landing_default_section_config('shopify_landing_how_it_works') || '{"steps_marker":"badge"}'::jsonb);  -- error text
select block_type, config->'tile_layout', config->'grid', config->'steps_marker', config->'content_align'
  from display_block_template where block_type like 'shopify_landing_%';
```
