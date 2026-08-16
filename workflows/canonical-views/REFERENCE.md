# Canonical Views — Maintenance REFERENCE

Executable contract for Rocket CRM’s commercial Canonical Views: the pricing sheet and the features summary. Read this before drafting, refreshing, or running a sales Cursor thread against these views.

**Repo:** `Rocket-CRM/supabase-crm`  
**Live catalog:** Supabase `wkevmsedchftztoolkmi` · `internal_product_*`  
**Upstream contract:** `workflows/product-feature-catalog/REFERENCE.md`  
**Baseline docs (EN):** `docs/canonical-views/`  
**Baseline docs (TH):** `docs/canonical-views/th/`  
**Sales runs:** `workflows/canonical-views/runs/<customer>-<yyyymm>/`

---

## 1. Purpose

Two derived commercial lenses on the Product Feature Catalog:

| View | File (EN) | File (TH) | Grain | Job |
|---|---|---|---|---|
| Commercial pricing sheet | `docs/canonical-views/COMMERCIAL_PRICING_SHEET.md` | `docs/canonical-views/th/COMMERCIAL_PRICING_SHEET.md` | **Billable unit** (one sellable / chargeable line) | Quote-shaped summary — not exhaustive |
| Features summary | `docs/canonical-views/FEATURES_SUMMARY.md` | `docs/canonical-views/th/FEATURES_SUMMARY.md` | **Feature group** (active catalog features, one shorthand sales line; see omit list) | RFP / competitor coverage |

Neither is product source of truth. Both are **written** (non-deterministic) from the catalog — not a SQL flatten, not a name-concatenation. HTML/PDF is the only deterministic step.

**Required reading before any view copy:** `Writing Principles/CORE_WRITING_PRINCIPLES.md` §6–8, then `Writing Principles/CANONICAL_VIEW_COPY_PRINCIPLES.md`. Do not load proposal scaffolds. Catalog name/summary craft is a different file (`SALES_FEATURE_COPY_PRINCIPLES.md`).

Out of scope: deal THB amounts in baselines; Rocket Deck web proposal builder as the sales path; writing catalog identity from these views.

**List prices** live in `workflows/canonical-views/list-prices.json` (member scale × `billable_unit_key`). Not on catalog rows, not in `internal_pricing_blocks.base_price_thb`. Fill a run copy with `npm run fill-prices -- --input … --output … --scale 100000 --lang en`. Baselines stay `—`.

### Locales

- Maintain **dual baselines** (EN + TH). Same `billable_unit_key` / `feature_group_key` structure so the HTML exporter is locale-agnostic.
- **Features summary TH** is a localize of the EN features-summary **lines** (same keys, shorthand). Do not rebuild TH by dumping `name_th` + `summary_th`. Module and feature-group **display titles** use `English (Thai)` — English key name first, Thai gloss in parentheses (e.g. `Signup & login (สมัครและเข้าสู่ระบบ)`). Keep `feature_group_key` unchanged.
- **Pricing sheet TH** is curated Thai for the same billable units as EN (labels + sparse bullets). Follow Writing Principles localize-not-translate; keep market-standard English terms (OTP, Tier, API, Shopify, …). After an English sales-copy rewrite, **do not ship TH until a localize pass** — translating the old concatenated-name bullets is not localization.
- **Thai vocabulary is canonical.** Any TH pass must use `Writing Principles/THAILAND_CONTEXT.md` §2 (earn = `สะสมคะแนน`, tier ladder ≠ `บันได`, per seat = `ต่อผู้ใช้งาน`, …) and §4 for heading/gloss rules. Do not re-derive terms per pass.
- A sales run picks **one language** in `brief.md` and copies from the matching baseline folder. Do not mix EN/TH content in one run unless the human explicitly asks for a bilingual pack.

---

## 2. Source-of-truth contract

### Precedence (hard)

1. **Catalog** (`internal_product_*`) — feature identity, hierarchy, status, `commercial_nature`, packages.
2. **Requirements / CRM Knowledge** — behavior evidence.
3. **Canonical Views** — curated commercial presentation only.
4. **Sales run snapshot** — one customer’s photocopy; may diverge freely.
5. Conflict with catalog **stops** a baseline refresh for the affected section; report it. Views never write the catalog in reverse.

### Layer roles

| Layer | Role | Sales may edit? |
|---|---|---|
| Catalog | Product truth | No (catalog / product threads only) |
| Canonical View baselines | Standard sheet (prices blank) | No — product/automation only |
| Run snapshot | Deal sheet (prices + structure) | Yes — Cursor sales thread |
| HTML / PDF | Render of a baseline or a run | Generated; do not hand-edit PDF |

---

## 3. The two views

### 3.1 Commercial pricing sheet

- **Sections** = catalog **modules** (one H2 / one visual block). Never one section per billable unit.
- **Rows** = split by **plan grouping** (Core / Advanced) **and/or fee model** (member band, per month, per campaign-month, per receipt, addon). H3 in the markdown is a row, not a section.
- **Bullets** = `**Keyword**` (bold, normal capitalization) then a sales shorthand description on the same line. Journey-first order on Loyalty Core. Sparse = fewer complete sentences, **not** catalog `name`s joined with commas or semicolons.
- **Notes / PS** (unit definitions, allowances, packaging) are **not** feature bullets. Write a whole-line italic `*…*` after the bullets. The HTML exporter renders `<em>` — no leading `·`, no bold keyword. Use for “what is a campaign unit”, SMS included quota, “this price covers 10 workflows”, Shopify lead-in.
- **Columns** (Merz / Rocket Deck contract): **Feature | Unit | Price**.
- Baseline **Price** is always `—`. **Unit** is the billing period (`Per month`, `Per receipt`, `Per seat / month`, `Per campaign unit / month`) — never the member-scale band. Scale only selects the amount in `list-prices.json`. Packaging (10 active workflows) and allowances (`{{sms_included}}`) live in bullets.
- **Omit from both views** (catalog stays): `loyalty.currency.tickets`, `loyalty.event_promo.engine`. Store attributes fold into earn-rate copy — no standalone view line. **Fold into Admin portal and reports** (features summary): `platform.governance.pdpa_consent`, `platform.governance.translation`, `loyalty.frontline.customer_360` (Member 360 as a key area). **Omit from the pricing sheet:** `customer_service_phone` (phone numbers).
- HTML meta-bar: product `ROCKET CRM`; RHS doc label `PRICING SHEET`.

**Hard rules for bullets (regression from the 2026-08-12 sheet):**

1. Load CORE §6–8 and `CANONICAL_VIEW_COPY_PRINCIPLES.md` **before** writing or refreshing any bullet.
2. Cluster catalog rows by buyer question at **program-area** altitude, then write `**Keyword** description`. Never concatenate `name` fields. Loyalty Core order = member journey, then admin + Front Line, then reports; backend last.
3. Typed lists stay one kind: earn **methods** (purchase sync, marketplace, QR/code, receipt upload, manual adjust) — not the Earn **page**, not Open API, not Receipt AI.
4. Do not bundle unrelated **program areas** (rewards + burn rate; earn rates + tickets; store directory + Front Line). **Do** fold platform plumbing into the parent area: PDPA and languages belong in **Admin portal**, not their own Core lines (right altitude — see `CANONICAL_VIEW_COPY_PRINCIPLES.md` §4). Phone numbers are omitted from the pricing sheet (catalog stays).
5. Config objects are not copy (`store master`, `maintain mode`, `tier windows`, `burn rate` as a bare term). Explain the program (**Member tiers** with upgrade/maintenance conditions; **Burn** as points-to-discount at checkout).
6. Prove coverage where the buyer needs it (**Reports** 30+ covering …; **Open API** members, purchases, points, redemptions, assets — not only earn-from-own-system).
7. Respect commercial grain: Core earn methods (including receipt upload) on the Core **row**; Receipt AI and Open API are Loyalty **rows** (different fee model), not extra modules. Shopify is its own module. **Front Line** is Core (store-staff lookup and assisted actions), one line below admin. Member 360 is an admin area, not the Front Line title.
8. Member-facing UI configuration is **Member app UI CMS**, not “layout” only.
9. Marketing Automation is one module with Workflows and AI as **rows** (plan grouping). Customer Service is one module with Software, AI Customer Service Agent, and Phone numbers as **rows**. Do not title a CS row “Advanced.” Omit stored value until it is GA.

Worked rewrites: `CANONICAL_VIEW_COPY_PRINCIPLES.md` §5.

### 3.2 Features summary

- **Sections** = same modules (one H2 / one ModuleBlock when exported).
- **Rows** = catalog feature groups (`feature_group_key` stays in the heading).
- **Bullets** = **every** active non-deprecated feature in that group — **not** sparse, **not** a catalog photocopy.
  - Format per feature:
    ```markdown
    - **Sales-facing name**
      One shorthand sales sentence (not the catalog summary reprinted).
    ```
  - **Write** the line from the catalog row (+ narrative only if the catalog summary is too thin). Do not run `build-features-summary-md.mjs` as the published voice — that script is a coverage inventory only.
- Same Merz table chrome when rendered; one table per module; Capabilities column holds the shorthand list.
- Pricing sheet stays sparse (clustered); features summary is exhaustive coverage at shorthand grain.
- HTML meta-bar RHS label: `FEATURES SUMMARY` (EN) / `สรุปฟีเจอร์` (TH). Never one ModuleBlock per feature group.

---

## 4. Default billable units (pricing sheet)

Stable `billable_unit_key` values. Changing keys or adding units needs product approval (same bar as `commercial_nature` changes).

**Section grain:** each pricing-sheet **section** is a catalog **module** (H2). Each **row** is a billable unit split by **plan grouping** (Core / Advanced) and/or **fee model**. `commercial_nature` does **not** create a section. The HTML exporter renders one ModuleBlock per H2, with one table row per H3.

### Loyalty

| `billable_unit_key` | Label | Maps from | Default unit |
|---|---|---|---|
| `loyalty_core` | Loyalty Core | Loyalty `commercial_nature = core` (incl. receipt upload, lifecycle, Front Line actions, promo codes, customer import) | Per month |
| `loyalty_advanced` | Loyalty Advanced (additional to Core) | Loyalty `advanced` (not broken out below); additional to Core | Per month |
| `loyalty_campaigns` | Campaigns | Loyalty `consumption` + `campaign_month` — one unit = one campaign type enabled that month | Per campaign unit / month |
| `loyalty_receipt_auto_approve` | Receipt AI / OCR auto-approve | `loyalty.earn.receipt_advanced` (`consumption` / `receipt`) | Per receipt |
| `loyalty_open_api` | Open API | `loyalty.integrations.open_api` (+ `loyalty.earn.openapi` as one of its calls) (`addon`) | Per month |
| `loyalty_sms` | SMS | Free at list; `{{sms_included}}` quota in the bullet; overage 0.25 THB/SMS | Per month |

### Shopify

| `billable_unit_key` | Label | Maps from | Default unit |
|---|---|---|---|
| `loyalty_shopify` | Shopify loyalty plugin | `loyalty.storefront.*` plus Shopify order-earn / member-matching capabilities (catalog rows to match — see product notes) | per month |

Shopify is presented as its own product (a loyalty plugin), not two bullets under Loyalty. Catalog taxonomy may still parent the group under Loyalty until a fourth public module is approved.

### Marketing Automation

| `billable_unit_key` | Label | Maps from | Default unit |
|---|---|---|---|
| `marketing_automation_core` | Workflows | MA `core` (incl. LINE Flex); 10-active-workflow allowance in the bullet | Per month |
| `marketing_automation_advanced` | AI | MA `advanced` | Per month |

One **module / section**. Two **rows** (plan grouping). Do not emit two H2s.

### Customer Service

| `billable_unit_key` | Label | Maps from | Default unit |
|---|---|---|---|
| `customer_service_core` | Customer Service Software | CS `core` (incl. voice) | Per seat / month |
| `customer_service_ai` | AI Customer Service Agent | CS `advanced` | Per resolved case |

One **module / section**. Two **rows** (Software vs AI Agent). Phone numbers are omitted from the pricing sheet (catalog stays). Do **not** title a row “Customer Service Advanced.” Retired keys: `loyalty_stored_value`, `customer_service_phone` (sheet only).

**Bundling rule:** Inside a module, add a row when **plan grouping** differs (Core vs Advanced) **or** the **fee model** differs (member band, monthly, campaign-month, per receipt, addon). Consumption and addon lines are rows in their module — not extra sections — except Shopify, which is its own module. Stored value is a Loyalty capability — omit from the sheet while `status != ga`.

---

## 5. File formats (baselines)

### Pricing sheet block (per module)

H2 = module (section). Each H3 is one table **row** (plan grouping and/or fee model), with its bullets under that row.

```markdown
## <Module>

### <Row label> (`<billable_unit_key>`)

| Feature | Unit | Price |
| --- | --- | --- |
| <Row label> | <unit placeholder> | — |

- **Keyword** description

*Note or PS — unit definition, allowance, packaging. Italic, not a feature bullet.*
```

### Checklist block (per feature group under its module)

H2 = module (section). Each H3 is one table **row** (feature group), with its bullets under that row. The HTML exporter renders **one ModuleBlock per H2**, with one table row per H3 — same section grain as the pricing sheet.

```markdown
## <Module>

### <Group name> (`<feature_group_key>`)

| Feature group | Capabilities |
| --- | --- |
| <Group name> | (see bullets) |

- **<feature name>**
  <one shorthand sales sentence>
```
Voice: **sales shorthand** per `Writing Principles/CANONICAL_VIEW_COPY_PRINCIPLES.md` (load with CORE §6–8 before drafting). Pricing bullets are `**Keyword** description` in journey order. Features-summary lines are one rewritten sentence per feature — not catalog `name`+`summary` verbatim, not proposal prose. No package slogans (“included in Pro”). Status `planned` / `beta` may be noted after the name.

---

## 6. Sales Cursor thread (run snapshot)

Sales does **not** use a web builder. Flow = one interactive Cursor thread + a run folder (same idea as proposal-generator).

### Run folder

`workflows/canonical-views/runs/<customer>-<yyyymm>/`

```
brief.md                 # Language: en|th; include/exclude; price guidance
pricing-sheet.md         # snapshot (start as copy of matching-locale baseline)
features-summary.md      # snapshot (optional for this deal)
export/                  # generated HTML (then Print → PDF)
```

Copy from `runs/_template/`. Then copy baselines by language:

| `brief.md` Language | Pricing baseline | Features baseline |
|---|---|---|
| `en` (default) | `docs/canonical-views/COMMERCIAL_PRICING_SHEET.md` | `docs/canonical-views/FEATURES_SUMMARY.md` |
| `th` | `docs/canonical-views/th/COMMERCIAL_PRICING_SHEET.md` | `docs/canonical-views/th/FEATURES_SUMMARY.md` |

Example ask: *“Download pricing sheet and features summary in Thai.”* → set `Language: th`, copy both TH baselines into the run, export HTML, open → Print → PDF.

### Behind-the-scenes edits

| Chat ask | Agent does |
|---|---|
| Remove a row / section | Delete / omit that block in the **run** files only |
| Expand a section | Add detail bullets (or split) in the **run** MD only; re-export HTML |
| Add a row | Insert a deal-local block in the run (catalog-backed or freeform) |
| Split a row | Replace one billable / features-summary block with N blocks in the run |
| Fill prices | `npm run fill-prices -- --input <run>/pricing-sheet.md --output <run>/pricing-sheet.md --scale <band> --lang en\|th` then re-export |
| Export PDF | Render run → Merz-layout HTML → browser Print → PDF (see §8) |
| Regenerate after feedback | Edit run MD → re-run exporter → new HTML (do not hand-edit HTML) |

**Never** write run edits back into baselines or the catalog unless the human explicitly starts a product/catalog change.

Open runs are **not** overwritten by weekly baseline refresh.

### Resume

A fresh thread pointed at the same run folder continues from the customized snapshot.

---

## 7. Baseline maintenance (product / automation)

Same family as catalog + Product Narrative — **written**, not a SQL flatten.

### When to refresh

- After catalog changes that affect `commercial_nature`, groups, feature names/summaries, or the active set.
- As a step in the weekly catalog Automation (after narrative sync), only for **affected** modules/units.

### Run order (baseline refresh)

1. Read this REFERENCE + `Writing Principles/CANONICAL_VIEW_COPY_PRINCIPLES.md` + CORE §6–8. Catalog REFERENCE only for identity/keys — do not paste catalog summaries.
2. Inspect live catalog (modules, groups, features, `commercial_nature`, names/summaries). Optionally open matching Product Narrative sections if a catalog summary is too thin to write a shorthand line.
3. Diff against current baseline billable units / features-summary groups (keys present/missing). The JSON dump script may help as a **coverage inventory**; it must not overwrite copy.
4. **Rewrite** affected EN pricing bullets (cluster by buyer question) and affected EN features-summary lines (one shorthand sentence per feature). Mirror structure into TH when keys change; localize TH copy in a separate pass — do not dump `name_th`/`summary_th`.
5. Keep Price as `—`. Do not invent THB. Do not touch `runs/`.
6. Run `CANONICAL_VIEW_COPY_PRINCIPLES.md` §7 on every new or changed line. A comma-joined catalog-name list is not done. A reprinted catalog summary is not done.
7. Report: units/groups added/removed/renamed, features-summary coverage vs live keys, conflicts, catalog names that should be fixed upstream, Thai still-stale flag.

### Conflict stop

If a baseline claim cannot be traced to an active catalog feature (or approved billable-unit map), stop that section and ask.

---

## 8. Export (HTML → PDF)

Visual + structure contract matches Rocket Deck Merz pricing (`/Users/rangwan/rocket-deck/src/slides/merz-pricing.tsx`):

- A4 canvas (1080×1527), cream `--slide-surface`, left/top rails, meta bar (date · product · ROCKET)
- Plus Jakarta Sans; typ-heading / typ-caption tokens from `globals.css`
- **One ModuleBlock per module (H2)** for both exports — caption is the module name
  - Pricing: Feature/Unit/Price/Qty/Total table has **one row per billable unit** (plan grouping and/or fee model); Qty defaults to 12 months; Total = Price × 12
  - Features summary: Feature group/Capabilities table has **one row per feature group** (not one ModuleBlock per group)
- Feature column left-aligned (`th` must not center); `·` include lines under Feature name in that row
- Footnotes and headers follow `--lang` (`en` | `th`). Thai pricing title/doc-label: `ใบสรุปราคา`; Thai body font: Sarabun via Google Fonts. Do not emit the blank-baseline internal note on customer exports.
| Stage | Owner |
|---|---|
| Content | Baseline or run markdown |
| HTML | Deterministic script (no LLM) |
| PDF | Browser **Print → Save as PDF** from the HTML (v1); Chromium script later if needed |

### Exporter (deterministic)

```bash
# From repo root — EN baselines
cd workflows/canonical-views && npm run export:all

# TH baselines
cd workflows/canonical-views && npm run export:all:th

# Or any MD path (sales run — language already in the MD content)
node workflows/canonical-views/scripts/md-to-pricing-html.mjs \
  --input workflows/canonical-views/runs/<customer>-<yyyymm>/pricing-sheet.md \
  --output workflows/canonical-views/runs/<customer>-<yyyymm>/export/pricing-sheet.html \
  --mode pricing \
  --title "Acme — Pricing" \
  --doc-label "PRICING SHEET"
```

| Script | `workflows/canonical-views/scripts/md-to-pricing-html.mjs` |
| npm (EN) | `export:pricing` / `export:features` / `export:all` |
| npm (TH) | `export:pricing:th` / `export:features:th` / `export:all:th` |
| Baseline HTML out (EN) | `docs/canonical-views/export/*.html` |
| Baseline HTML out (TH) | `docs/canonical-views/export/th/*.html` |

Sales Cursor thread: after editing the run MD, run the script on that run’s file, then open the HTML and print to PDF. Do not hand-edit the HTML for content changes — edit MD and re-export.

---

## 9. Quality checklist

- [ ] Baseline prices are all `—`
- [ ] Pricing sheet **sections** match live public modules; **rows** match §4 keys (plan grouping and/or fee model) in **both** EN and TH
- [ ] Features summary groups match live `feature_group_key`s for active modules (EN + TH)
- [ ] Pricing sheet bullets are `**Keyword** description` (bold, not all caps); notes/PS are italic `*…*` lines, not feature bullets; Core in journey order including receipt upload on earn methods; PDPA/languages folded into admin; Front Line under admin (not titled Customer 360); reports name Members / Member 360 / Redemptions / Transactions / Campaigns; Open API is a Loyalty **row** (integration product, not earn-only); Shopify is its own module; MA and CS are one section each with rows by plan grouping / fee model; no stored-value row; no catalog-name concatenation; `CANONICAL_VIEW_COPY` §5 would pass
- [ ] Features summary includes every active **GA** feature as one rewritten shorthand line **except** the omit/fold list (tickets, event promo; PDPA / languages / Customer 360 fold into Admin portal and reports); not catalog summary verbatim; no eng jargon. `planned` / not-launched rows are omitted or marked planned, not sold as GA.
- [ ] List prices are only in `list-prices.json`; baselines stay `—`; `fill-prices` is for run copies.
- [ ] TH views are a localize of EN view lines (not a dump of `name_th`/`summary_th`); module/group display titles use `English (Thai)`
- [ ] Sales threads only mutate `runs/<customer>-…/` and copy the baseline matching `brief.md` Language
- [ ] No reverse writes from views → catalog

---

## 10. Publish to rocket-sales

After a baseline refresh, copy views + `list-prices.json` + export scripts into the sales plugin snapshot:

```bash
node workflows/canonical-views/scripts/publish-sales-commercial.mjs
```

Then push `rocket-agent-plugins`. Sales replace their local plugin folder. Do not copy `PRODUCT_NARRATIVE.md` (Knowledge `get_section`).

## 11. Related paths

| Path | Role |
|---|---|
| `workflows/canonical-views/list-prices.json` | Scale × billable-unit list prices (not a DB table) |
| `Writing Principles/CANONICAL_VIEW_COPY_PRINCIPLES.md` | Sales shorthand for the catalog → view jump |
| `Writing Principles/SALES_FEATURE_COPY_PRINCIPLES.md` | Catalog names/summaries (different grain) |
| `workflows/product-feature-catalog/REFERENCE.md` | Catalog + narrative + automation |
| `docs/PRODUCT_NARRATIVE.md` | Derived sales narrative (different grain) |
| `docs/canonical-views/COMMERCIAL_PRICING_SHEET.md` | Pricing baseline (EN) |
| `docs/canonical-views/FEATURES_SUMMARY.md` | Features summary baseline (EN) |
| `docs/canonical-views/th/COMMERCIAL_PRICING_SHEET.md` | Pricing baseline (TH) |
| `docs/canonical-views/th/FEATURES_SUMMARY.md` | Features summary baseline (TH) |
| `docs/canonical-views/export/` · `export/th/` | Generated baseline HTML |
| `workflows/canonical-views/runs/_template/` | Sales run scaffold |
| `/Users/rangwan/rocket-deck/src/slides/merz-pricing.tsx` | Visual reference for table chrome |
