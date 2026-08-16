# Product Feature Catalog — Maintenance REFERENCE

Executable contract for keeping the Rocket CX product catalog, Product Narrative, and weekly reconcile Automation aligned. Read this file before any catalog write or narrative sync.

**Repo:** `Rocket-CRM/supabase-crm`  
**Live DB:** Supabase project `wkevmsedchftztoolkmi` only  
**Related paths:** `docs/PRODUCT_NARRATIVE.md` (derived), CRM Knowledge MCP (indexed requirements chunks), `requirements/**/*.md` (behavior evidence). Commercial Canonical Views (pricing sheet, features summary, list prices) are authored in `rocket-agent-plugins/plugins/rocket-sales/commercial/` — not this repo.

---

## 1. Purpose and audience

### Purpose

Maintain one coherent product surface for three consumers:

| Consumer | Uses |
|---|---|
| Eng agent | CRM Knowledge + live code/Supabase for how things work |
| Sales agent | Catalog + Product Narrative + CRM Knowledge for what we sell |
| Proposal workflow | Same three inputs; proposals are outputs, never sources |

This workflow owns:

1. Canonical Supabase feature catalog (`internal_product_*`).
2. Derived sales Product Narrative (`docs/PRODUCT_NARRATIVE.md`).
3. Weekly Cursor Automation that reconciles both from requirements evidence.

### Audience

| Reader | What they do here |
|---|---|
| Weekly Automation / eng agent | Diff requirements → classify → update catalog + affected narrative sections |
| Human product owner | Approve REFERENCE changes, review narrative Git diffs, resolve conflicts |
| Proposal / sales writers | Consume catalog + narrative; never edit catalog identity from narrative |

Out of scope: engineering entitlement registry (`feature_config` / plan gating), CRM Knowledge chunking (doc-knowledge reconcile job), writing new requirements docs (documentation closeout).

---

## 2. Source-of-truth contract

### Precedence (hard)

1. **Catalog** controls whether a feature exists, where it belongs, its status, and package inclusion.
2. **Requirements / CRM Knowledge** control how the feature behaves.
3. **Product Narrative** controls customer-facing explanation only.
4. A conflict **stops the affected update** and is reported; narrative never updates the catalog in reverse.

### Layer roles

| Layer | Role | Indexed into CRM Knowledge? |
|---|---|---|
| `requirements/**/*.md` | Product/eng behavior source; updated via documentation closeout | Yes (via doc-knowledge reconcile) |
| CRM Knowledge chunks | Detailed evidence layer derived from requirements | — (is the index) |
| `internal_product_*` | Canonical feature identity, hierarchy, sales summary, examples, status, package inclusion | No |
| `docs/PRODUCT_NARRATIVE.md` | Derived sales copy for proposals and sales-agent answers | **No** — must remain outside Knowledge indexing |

### Architecture note

- Product/engineering work updates `requirements/**/*.md` through documentation closeout.
- The doc-knowledge reconcile job maintains the Knowledge **index**, not the source documents.
- Catalog writes and narrative syncs are reviewable: catalog via audit log; narrative via Git diff.

---

## 3. Catalog schema

### Tables (canonical)

| Table | Purpose |
|---|---|
| `internal_product_module` | Top product area (`module_key`, `name`, `summary`, `sort_order`, `is_active`) |
| `internal_product_feature_group` | Capability cluster under a module (`feature_group_key`, …) |
| `internal_product_feature` | Sellable/comparable capability leaf (`feature_key`, `summary`, `includes`, `status`, …) |
| `internal_product_package` | Commercial package under a module (`package_key`, …) |
| `internal_product_feature_package` | Many-to-many feature ↔ package membership |
| `internal_product_catalog_change_log` | Append-only audit of catalog mutations (see §9 / Deliverable 4) |

### Feature row columns (identity + sales)

| Column | Required | Notes |
|---|---|---|
| `feature_key` | Yes | Stable slug; never rename casually — prefer deprecate + add |
| `name` | Yes | Buyer-facing English label; may change |
| `summary` | Yes | English: one or two plain sentences: actor → behavior → outcome |
| `name_th` | Yes for sellable Thai surfaces | Thai localized name (nullable until localized; see §6.1) |
| `summary_th` | Yes for sellable Thai surfaces | Thai localized summary/description (nullable until localized; see §6.1) |
| `includes` | Yes (array) | Clarifiers/examples only when they prevent misunderstanding; else `[]` |
| `status` | Yes | `ga` \| `beta` \| `planned` \| `deprecated` (DB check) |
| `feature_group_id` | Yes | Exactly one group |
| `sort_order` | Yes | Ordering within group |
| `is_active` | Yes | Soft visibility; prefer `status = deprecated` over hard delete |
| `source_refs` | Yes (after provenance migration) | jsonb array of evidence pointers (see §8) |
| `last_verified_at` | Yes (after provenance migration) | timestamptz of last evidence-backed verify |
| `feature_registry_key` | Optional | Link to eng entitlement registry when known |
| `pricing_catalog_slug` | Optional | External pricing slug when known |
| `commercial_nature` | Yes | How the feature is sold/charged: `core` \| `advanced` \| `addon` \| `consumption` (see §8.1). Orthogonal to package membership. |
| `consumption_unit` | When `commercial_nature = consumption` | Unit of meter: e.g. `campaign_month`, `receipt`. Null for non-consumption rows. |

Projection view `v_internal_product_feature_catalog` also exposes `feature_name_th`, `summary_th`, `commercial_nature`, `consumption_unit` (appended after legacy columns).

English `name` / `summary` remain the edit source of truth. Thai columns are derived localizations — never invent Thai first and reverse-translate into English.

### Keys

- Module keys: `loyalty`, `shopify`, `marketing_automation`, `customer_service` (four **active public** modules).
- Group keys: `<module_prefix>.<group>` (e.g. `loyalty.earn`, `marketing_automation.workflows`).
- Feature keys: `<group_or_module>.<capability>` (existing Loyalty keys like `loyalty.currency.points` stay stable).
- Package keys: structured per module (e.g. `loyalty_core`, `loyalty_advanced`); package membership never creates taxonomy.

### Legacy modules

Former public modules (e.g. `platform` / App foundation) are **folded into Loyalty** for public catalog presentation. Preserve stable feature keys when moving groups; deactivate the old module rather than deleting rows.

---

## 4. Feature row granularity rules

A catalog row is a **distinct end-user capability** that a buyer, salesperson, or proposal can recognize, compare, or sell.

| Do create a row when… | Do not create a row when… |
|---|---|
| A buyer would ask “do you have X?” as its own question | X is only an implementation detail, field, or enum |
| Basic vs advanced are **distinct comparable** capabilities | The difference is only packaging/SKU packaging |
| Splitting prevents false equivalence in proposals | Two labels describe the same journey with different words |
| Status or package membership legitimately differs | The “feature” is only a journey outcome label reused across groups |

Rules:

- Exactly three levels: **Module → Feature group → Feature**. No fourth public level in the sales catalog.
- Package membership never creates or splits taxonomy.
- Preserve stable `feature_key`s; labels and group placement may change.
- Journey language (acquisition → engagement → campaigns → analysis → activation) may appear in module/group **summaries**, not as overlapping feature rows.
- Never delete a formerly valid feature; set `status = deprecated` with evidence in `source_refs` / change log.

---

## 5. Public module taxonomy

Four active public modules: Loyalty, Shopify, Marketing Automation, Customer Service.

### Loyalty (`loyalty`)

Public journey (narrative / module summary only): acquisition → engagement → campaigns → analysis → activation.

Capability groups (target shape):

| Group theme | Intent |
|---|---|
| Foundation and acquisition | Signup/login (incl. custom signup / profile-completion form fields), website signup. Member layout is Member app UI CMS. PDPA and languages sit **inside Admin portal** (stable keys). |
| Points and earn channels | Currency, earn rates (basic/advanced), multipliers, earn channels |
| Rewards and burn | Catalog redeem, eligibility, pricing, promo codes, burn-to-discount |
| Tiers | Ladder, upgrade/maintain, windows, per-tier benefits |
| Campaigns | Missions, referral, check-in, spin, lucky draw (stay inside Loyalty) |
| Lifecycle automations | Rename away from “Lifecycle outcomes”; signup/birthday/anniversary/tier-change automations |
| Customer profile | Forms/profile fields. Surveys stay here. |
| Segmentation and RFM | Tags/personas/user types, RFM, funnel stages |
| Admin portal and reports | Loyalty admin config (reward codes, tier earn rates, space settings, PDPA, languages, roles), Member 360, **30+ reports**. Group sits after the member-journey groups. |
| Front Line | Store-staff lookup and assisted actions — not paired with Customer 360 |
| Admin, data operations, and integrations | Import/export, Open API, store network, stored value, event promo |

Required corrections vs prior catalog:

- Fold App foundation rows into Loyalty; preserve stable feature keys.
- Keep Campaigns inside Loyalty (not a separate module).
- Stored value stays inside Loyalty (not a module) and is **not** a pricing-sheet row until `status = ga`.
- Receipt upload is a Core **earn method** (`commercial_nature = core`). Receipt AI/OCR auto-approve stays `consumption`.
- Rename Lifecycle outcomes → lifecycle automation language.
- Advanced earn rates: different rates by channel (and related dimensions already sold).
- Multipliers: double points for selected products/categories.
- Include Customer 360 as an **admin** area (Member 360), segmentation/RFM, Front Line as its own group, and reporting inside Admin portal and reports.

### Shopify (`shopify`)

Public module: a Shopify **loyalty plugin**. Group key `loyalty.storefront` is preserved (stable keys); the group lives on this module.

Capability: paid-order earn, storefront widget, checkout points-to-discount, member matching.

**Commercial presentation (pricing sheet):** one Shopify section (usually one row — addon / per month).

### Marketing Automation (`marketing_automation`)

Rename from historical `amp` module key when reworking (preserve package links via migration/seed transaction; document key change in audit log).

Three primary groups:

1. **Deterministic multi-step workflow automation** — condition on customer data; execute messages plus loyalty actions.
2. **AI decisioning agents** — receive goals, allowed actions, outcomes, and constraints; review customer context; choose ACT, WAIT, or SKIP.
3. **AI analysis and recommendations** — analysis/recommendation surfaces distinct from decisioning execution.

**Commercial presentation (pricing sheet):** one **Marketing Automation** section; Workflows and AI are **rows** (plan grouping). Catalog groups stay three; `commercial_nature` core vs advanced may still exist for packaging.

### Customer Service (`customer_service`)

Rename from historical `cs` module key when reworking (same audit discipline).

Capability groups:

- Omnichannel inbox and connectivity
- Chat and voice
- Agent productivity, quick replies, and knowledge search
- Routing and chatbot workflows
- Service analytics
- AI service agent
- AOPs, knowledge, and customer actions
- Supervisor AI and quality scoring for human and AI cases

Keep non-AI operations, AI service/AOP actions, and supervisor scoring cleanly separated.

**Commercial presentation (pricing sheet):** one **Customer Service** section. Rows: Customer Service Software (core, incl. voice), AI Customer Service Agent (advanced), Phone numbers (addon fee model). Do not present these as three modules.

---

## 6. Feature Catalog Writing Guide

**Required reading before any `name` / `summary` write:** `Writing Principles/CORE_WRITING_PRINCIPLES.md` §6–8, then `Writing Principles/SALES_FEATURE_COPY_PRINCIPLES.md`. Catalog copy is sales explanation, not a dump of config objects.

Canonical Views are a **separate write** in the sales pack (`rocket-sales/commercial/COPY_PRINCIPLES.md`). They rewrite from these rows; they do not inherit `name` / `summary` verbatim.

- Exactly three levels: Module → Feature group → Feature.
- A row represents a distinct end-user capability that can be recognized, compared, or sold.
- Package membership never creates the taxonomy.
- Preserve stable keys; labels and group placement may change.
- **Name:** a salesperson’s label for the capability the buyer is buying — not the admin-screen or schema name (`Store master`, `Tier ladder`, `Burn rate — merchant default` fail). See `SALES_FEATURE_COPY_PRINCIPLES.md`.
- **Summary:** one or two **sales** sentences: what you can set up / what members get, optional `such as` / `e.g.` with buyer-recognizable examples. Actor → behavior → outcome still holds; the actor is the merchant or the member, not the config object.
- **`includes`:** clarifiers/examples that prevent misunderstanding; put longer example lists here when the summary must stay short.
- Split basic/advanced when they are distinct comparable capabilities.
- Use `ga`, `beta`, `planned`, or `deprecated`; stale copy is a verification condition, not product status.
- No implementation jargon, generic superlatives, unsupported numbers, or invented package placement.
- Commercial nature (`core` / `advanced` / `addon` / `consumption`) never appears inside `summary` — it lives in `commercial_nature` (+ `consumption_unit`).

### 6.0 Summary craft principles (from catalog reviews)

These are hard rules for English `summary` / Thai `summary_th` and for choosing `includes` examples.

1. **Mechanism-true examples only.**  
   Every example must be a real action or object of *that* feature.  
   Wrong: Earn page setup explained with abstract buckets (“purchase, missions, birthday”).  
   Right: concrete member cards/actions (“upload a receipt”, “claim a marketplace order”, “scan a QR”).  
   System taxonomy labels (`channel_type = lifecycle`) belong in requirements, not sales summaries, unless they are the thing being sold.

2. **Group by the buyer’s configure/experience moment.**  
   Place the row where a merchant would look for it when buying or setting up.  
   Example: custom signup / profile-completion form fields belong under **Signup & login**, not under a generic forms catalog that also holds surveys. Surveys / ongoing profile field master stay under profile/forms.

3. **State the product contrast when contrast is the sell.**  
   If two modes exist and buyers confuse them, say the contrast in plain language + 1–2 examples.  
   Example: points are fungible (one interchangeable balance); tickets are non-fungible token types (raffle tickets ≠ parking passes; each type has its own balance).

4. **Easy to digest ≠ incomplete.**  
   Summaries must still cover the real sellable capability (modes, dimensions, contrasts) in plain language a buyer can follow in 1–2 sentences.  
   Cut fluff (liability philosophy, urgency marketing, implementation jargon) — **do not** cut product depth.  
   Wrong: points expiry → “Merchants can set when points expire.”  
   Right: name the modes buyers choose (rolling TTL after earn vs fiscal-period expiry + minimum validity) in everyday words; put extra examples in `includes`.

5. **Name dimensions when you claim “advanced” or “by channel and more”.**  
   Never write “related dimensions” without listing the sellable dimensions and at least one example.  
   For advanced earn rates, dimensions include: earn/purchase channel, store, product (SKU / product / brand / category), member tier, persona.  
   Example: “2× points on Shopee”, “higher rate at flagship stores”, “Gold tier earns 1.5×”, “skincare category earns double”.

6. **Concrete nouns over abstract category names.**  
   Prefer “upload a receipt” / “Gold members” over “purchase channel type” / “tier entity”. Keep market-standard product nouns (Tier, Mission, OCR) when they are the sold concept.  
   **Names follow the same rule:** “Member tiers”, “Points-to-discount at checkout”, “Custom signup form”, “Store / outlet directory” — not “Tier ladder”, “Burn rate — merchant default”, “Profile fields & custom fields”, “Store master”.

7. **Use `includes` for overflow examples.**  
   Summary stays 1–2 sentences of real capability. Extra examples, contrasts, or “not this” clarifiers go in `includes` as short strings.

8. **Don’t invent methods or merge adjacent features.**  
   Don’t describe Mission or Birthday as if they were receipt-style earn *methods* when the row is Earn page visibility; don’t describe lifecycle automation inside Earn page setup. Keep each row’s claim inside its own boundary.

9. **Verify capability before writing.**  
   Before collapsing or shortening a summary, confirm modes/controls against requirements / CRM Knowledge for that feature. A craft note about tone never overrides product scope.

10. **Sales explanation, not config inventory.**  
    `name` and `summary` must pass `SALES_FEATURE_COPY_PRINCIPLES.md`. Do not ship config-object names (`store master`, `maintain mode`, `tier windows`, `burn rate — merchant default`) or semicolon-joined unrelated capabilities. Canonical Views rewrite from these rows — they will not launder a bad catalog name.

Self-check before write (also run `SALES_FEATURE_COPY_PRINCIPLES.md` §4):

1. Would a salesperson say this **name and summary** aloud without then translating it?
2. Are examples actions a member or admin actually performs for this feature?
3. Did I remove real capability while “simplifying,” or only remove fluff?
4. If I said “advanced” / “multiple dimensions” / multiple modes, did I name them?
5. Is the group placement where the buyer would look?
6. Did I check requirements evidence for this row (not just prior catalog copy)?
7. Is the **name** a sold capability, or a config object / screen / schema label?
8. Did I bundle two “do you have X?” answers into one name (tags with profile fields, tickets with earn rates)?

### 6.1 Thai localization (`name_th` / `summary_th`)

**Trigger:** when English `name`/`summary` is added or materially changed, or when a human asks to localize / refresh Thai catalog copy. Do not invent Thai for unverified English rows.

**Authority (read in this order before writing Thai):**

1. `Writing Principles/TRANSLATION_PHILOSOPHY.md` — localize, don’t translate; English-term policy; Thai B2B/SME tone.
2. `Writing Principles/TRANSLATION_PRINCIPLES.md` — proposal/pack craft that still applies to sales catalog labels: meaning-first rewrite, no calques, no `การ <english-verb>`, numerals as Arabic digits.
3. `Writing Principles/SALES_PRESENTATION_SLIDE_PRINCIPLES.md` §6 — keep market-standard product terms in English inside Thai prose.
4. This Feature Catalog Writing Guide (§6) — `name_th` stays punchy; `summary_th` stays actor → behavior → outcome in 1–2 sentences.

**Register:** Thai B2B/SME sales catalog (operator-facing), not government-proposal formal Thai. Still avoid marketing fluff and ChatGPT calques.

**Localize, don’t translate:**

| Wrong | Right |
|---|---|
| Word-for-word English grammar in Thai script | Meaning rewritten so a Thai salesperson would say it in a buyer meeting |
| Forced Thai coinages for SaaS terms | Keep the English term; localize the surrounding explanation |
| Inflating with สามารถ…ได้ / เพื่อที่จะ | Cut filler; keep mechanism short |

**Usually keep in English** (inside Thai labels/summaries when natural):

| Category | Examples |
|---|---|
| Platforms / brands | LINE, Shopify, Shopee, Lazada, TikTok Shop, Rocket |
| Technical | OTP, QR, POS, OCR, API, Open API, SMS, AI, Workflow, Dashboard |
| Product concepts (market-standard) | Tier, Mission, Campaign, Segment, Omnichannel, Customer 360, Front Line, RFM, CSAT, AOP, Watchtower |
| Decision labels | ACT, WAIT, SKIP |
| Metrics / compliance labels | PDPA, KPI (when used as the label) |

Prefer clear Thai when an everyday equivalent is already natural (`คะแนน` for points in body copy, `แลกของรางวัล` for redeem) — but do **not** replace established English product nouns just for purity. First-use gloss is optional (`ระบบสมาชิก (loyalty)`) only when it helps; then stay consistent.

**Never:** `การ activate`, `การ onboard`, `การ scale`. Either a full Thai verb (`การเปิดใช้งาน`) or a clean English noun (`Onboarding`).

**Column mapping:**

| English | Thai |
|---|---|
| `name` | `name_th` — short title; same punch as English |
| `summary` | `summary_th` — mechanism description; same claim scope as English (no new features, numbers, or package claims) |

`includes` stays English unless a future run explicitly localizes it. Modules/groups do not require Thai columns unless product asks later.

**Self-check before write:**

1. Would a Thai colleague say this aloud to a merchant buyer?
2. Any literal metaphors (`ร่ม`, `จุดเจ็บปวด`, `ระบบนิเวศ`, …)? Rewrite.
3. Any awkward Thai replacements for OTP / Tier / Workflow / AI / etc.? Restore English term.
4. Claims match English `summary` (status, numbers like “30+ reports”, package implications)?
5. Title length still title-like; summary still 1–2 sentences?

**Procedure hook:** after English catalog classify/update (§9 step 4), refresh `name_th`/`summary_th` for changed rows in the same transaction when Thai is in scope for the run. Log Thai-only refreshes as `update` on the feature entity with before/after including the Thai fields. Missing Thai on an otherwise complete GA row is a validation warning, not a status change.

---

## 7. Product Narrative Writing Guide

Audience: marketer, salesperson, proposal writer, or buyer asking what a feature does and why it matters.

Path: `docs/PRODUCT_NARRATIVE.md` (renamed from `docs/PRODUCT_FEATURE_CATALOG.md`).

### Document contract

- Derived sales copy, **not** a competing source of truth.
- Feature sections map to canonical `feature_key`s (preserve markdown anchors across rename).
- Not indexed into CRM Knowledge.
- Update only sections affected by changed/overdue catalog rows; never rewrite the full document on every weekly run.
- Narrative changes are reviewable Git diffs before they become proposal fuel.

### Structure

Each module gets a short introduction covering its promise, operating journey, and how its groups work together.

Each feature gets one `###` section mapped to its stable feature key (anchor may use the human name; key mapping lives in a machine-readable comment or index table at the top of the file / per section HTML comment `<!-- feature_key: … -->`).

Required blocks per feature section:

1. **What it enables** — buyer-facing what + why.
2. **How it works** — admin/customer journey in operating order.
3. **What differentiates it** — concrete behavior or flexibility.
4. **Key controls** — customer-relevant choices, not schemas/functions/exhaustive enums.
5. **Example** — optional and only when it materially clarifies the mechanism.

Voice: consultative, specific, outcome-led, proposal-ready. Planned/beta status must be explicit. Every material claim traces to the canonical row or requirement evidence.

Legacy four-block catalog template (Overview / Purpose / User Journey / Configurations & Rules) is **superseded** for new or resynced sections by the five blocks above. When touching a legacy section, migrate that section to the new template; leave untouched sections alone until their catalog row changes.

---

## 8. Evidence, status, and package rules

### Evidence (`source_refs`)

`source_refs` is a jsonb array of objects:

```json
[
  {
    "kind": "requirements",
    "path": "requirements/Tier.md",
    "heading": "Tier maintenance",
    "note": optional
  },
  {
    "kind": "knowledge",
    "path": "requirements/Tier.md",
    "heading": "Tier upgrade",
    "query": "optional search hint"
  }
]
```

Rules:

- At least one `source_refs` entry for every active (`ga`/`beta`/`planned`) feature after provenance lands.
- Prefer CRM Knowledge hits first; scoped requirement reads only when Knowledge is thin or missing.
- Identifiers/paths must come from tool results or known committed paths — never invent.
- `last_verified_at` updates only when evidence was actually re-checked in that run.

### Status

| Status | Meaning |
|---|---|
| `ga` | Generally available and sellable |
| `beta` | Available with known limits; narrative must say beta |
| `planned` | Committed direction; not GA; narrative must say planned |
| `deprecated` | Was valid; keep row; do not sell as current |

Stale narrative or overdue verification ≠ status change.

### Packages

- Packages are commercial bundles under a module.
- Assign features via `internal_product_feature_package` only with evidence (prior package map, pricing/sales confirmation, or explicit product decision).
- Do not invent package placement.
- Folding App foundation into Loyalty may retire `platform_base` as a public package after features are reassigned — log the change; do not silently drop membership.

### 8.1 Commercial nature (pricing tag) — orthogonal to packages

Package membership answers “which SKU bundle lists this feature.”  
`commercial_nature` answers “how this capability is licensed or charged.” They often correlate but are **not** the same column.

| `commercial_nature` | Meaning | Typical pattern |
|---|---|---|
| `core` | Included in the standard / most common license packages | Signup, points balance, basic earn rate, reward catalog, core CS inbox |
| `advanced` | Bundled only when the merchant takes the premium/advanced package — they get the **advanced set as a bundle**, not à la carte | Tickets, advanced earn rates, multipliers, persona-scoped tiers, most advanced Loyalty depth |
| `addon` | Sold / enabled **per feature** (toggle or line item), not only via the advanced bundle | Open API; other true à la carte entitlements |
| `consumption` | Charged by metered units of use | Campaigns (`campaign_month`); receipt AI/OCR auto-approve (`receipt`) |

Rules:

- Every active sellable feature has exactly one `commercial_nature`.
- When `commercial_nature = consumption`, `consumption_unit` is required. Otherwise `consumption_unit` is null.
- Canonical unit keys (extend only with product approval): `campaign_month` (one campaign feature enabled for one calendar month), `receipt` (one receipt processed by AI/OCR auto-approve). Add new unit keys in this REFERENCE before writing rows.
- Do **not** encode price amounts or SKU prices on the feature row — only nature + unit type. Canonical View list prices live in the sales pack (`rocket-agent-plugins/plugins/rocket-sales/commercial/list-prices.json`). Do not add a third price table. `internal_pricing_blocks` remains the proposal/deck SKU pointer only.
- `includes` / `summary` must not invent commercial claims (“included in Pro”) — nature lives in columns.
- Changing `commercial_nature` requires explicit product/pricing owner confirmation (same bar as package reassignment).

Decision guide:

1. Is it metered by usage events or enabled-months? → `consumption` (+ unit).
2. Else, can it be bought/enabled alone without the advanced bundle? → `addon`.
3. Else, is it only in the premium/advanced bundle (and not standard)? → `advanced`.
4. Else → `core`.

### Verification freshness

Treat a feature as **overdue** when:

- `last_verified_at` is null, or
- older than the Automation’s freshness window (default **30 days**), or
- a touching `requirements/**` path changed since `last_verified_at`.

---

## 9. Transactional maintenance procedure

### Manual or Automation run order

1. **Inspect** recent requirement changes plus catalog rows overdue for verification (include rows with null/stale `name_th`/`summary_th` when Thai is in scope).
2. **Gather** targeted CRM Knowledge evidence; scoped requirement reads only when needed.
3. **Classify** each candidate: `add` | `update` | `move` | `deprecate` | `no_change` | `localize_th`.
4. **Update** the Supabase catalog and audit log **transactionally** (single SQL transaction / migration apply). For English changes that need Thai, rewrite `name_th`/`summary_th` per §6.1 in the same transaction.
5. **Synchronize** only affected Product Narrative sections (English narrative; Thai catalog columns are not mirrored into `PRODUCT_NARRATIVE.md` unless a future Thai narrative is requested). When commercial identity or fuel copy changed (`commercial_nature`, groups, active set, names/summaries that views use), **do not rewrite Canonical Views in this repo.** Report a handoff: refresh affected sheets in `rocket-agent-plugins/plugins/rocket-sales/commercial/` per that pack’s `REFERENCE.md`. Prices stay blank; do not touch sales `sales-run/`.
6. **Validate** hierarchy, statuses, packages, source references, narrative anchors, proposal references, and Thai completeness for active sellable rows when Thai is in scope.
7. **Report** changed/skipped/conflicting rows, Thai localize counts, and the narrative Git diff.

### Conflict stop

Stop the affected row (do not apply partial narrative or catalog mutation for that row) when:

- Narrative claims contradict catalog status/package.
- Requirements evidence contradicts an existing GA claim without an explicit deprecate/planned decision.
- Two candidates would share one `feature_key` or collapse distinct sellable capabilities incorrectly.
- Package reassignment lacks evidence.

Report conflicts in the run summary; leave prior catalog state intact for those rows.

### Transaction + audit

Each catalog run:

1. Allocate a `run_id` (uuid).
2. Apply module/group/feature/package mutations inside one transaction.
3. Append one change-log row per entity mutation with: `run_id`, entity key/type, change type, before/after snapshots, `source_refs`, timestamp.
4. Commit only if validation checks pass; otherwise rollback.
5. Never hard-delete formerly valid features.

### Narrative sync discipline

- Map changed `feature_key`s → narrative `###` sections (via anchors / `<!-- feature_key -->`).
- Rewrite only those sections (+ module intros if group set changed).
- Leave unrelated sections untouched.
- Update proposal workflow paths when the narrative file is renamed (`workflows/proposal-generator/REFERENCE.md`, `SCAFFOLDS.md`, and any scaffolds/resources that cite the old path). `workflows/general-proposal` may mention the old path only as a negative “do not use” — retarget that string to `PRODUCT_NARRATIVE.md` so the ban stays accurate.

### Schema evolution (provenance)

Apply once (before first audited weekly run):

1. Add `source_refs jsonb not null default '[]'` and `last_verified_at timestamptz` to `internal_product_feature`.
2. Create append-only `internal_product_catalog_change_log` with columns for run id, entity type/key, change type, before/after jsonb, source_refs, created_at.
3. Backfill `last_verified_at` only when a feature is verified in a run; do not fake timestamps.

---

## 10. Quality checklist and run-summary format

### Pre-flight

- [ ] Working only in `~/Documents/rocket/supabase-crm`
- [ ] No overlapping dirty edits on target files (or intentional exclusive ownership of this run)
- [ ] This REFERENCE read end-to-end
- [ ] Supabase project is `wkevmsedchftztoolkmi`
- [ ] CRM Knowledge MCP available for evidence gather

### Acceptance checklist

- [ ] Four active public modules: Loyalty, Shopify, Marketing Automation, Customer Service
- [ ] Every active feature has one group, stable key, clear summary, valid status, source reference, and verification time
- [ ] When Thai is in scope: every active `ga`/`beta` feature has non-empty `name_th` and `summary_th` that pass §6.1 (localize, English-term policy)
- [ ] Summaries pass §6.0 and `SALES_FEATURE_COPY_PRINCIPLES.md` (sales explanation, salesperson-aloud names, no config-object labels, no unrelated bundles)
- [ ] Every active sellable feature has `commercial_nature`; consumption rows have `consumption_unit` (§8.1)
- [ ] Package assignments are structured and evidence-backed
- [ ] Loyalty contains lifecycle automations, customer intelligence, analytics, and configurable-program distinctions (basic vs advanced earn, multipliers, etc.)
- [ ] Marketing Automation cleanly separates workflows, AI decisioning, and AI analysis
- [ ] Customer Service cleanly separates non-AI operations, AI service/AOP actions, and supervisor scoring
- [ ] Product Narrative maps to canonical feature keys and contains no unsupported status/package claims
- [ ] Product Narrative is not indexed into CRM Knowledge
- [ ] Proposal workflow resolves the renamed narrative path
- [ ] Automation / run logs all direct catalog changes and produces reviewable narrative diffs
- [ ] If commercial identity changed, a Canonical Views **handoff** is reported for `rocket-sales/commercial/` — view files are not written in this repo

### Run-summary format (chat)

```markdown
## Catalog run summary — <date> — run_id `<uuid>`

### Counts
- Changed: N
- Skipped (no_change): N
- Conflicts (stopped): N
- Deprecated: N
- Added: N

### Module / group moves
- …

### Feature changes
| feature_key | change | notes |
|---|---|---|
| … | update | … |

### Conflicts
| feature_key | reason | action taken |
|---|---|---|
| … | … | left unchanged |

### Narrative
- Sections updated: …
- Git diff: `git diff -- docs/PRODUCT_NARRATIVE.md` (summary in prose)

### Validation
- Hierarchy / status / packages / source_refs / anchors: pass|fail
```

### Weekly Automation gate (before first wire)

1. Commit and push this `REFERENCE.md` after explicit user approval.
2. Verify CRM Knowledge and Supabase connections are Automations-eligible and authenticated.
3. Confirm schedule and model with the user.
4. Show the Automation draft table for approval.
5. Open the Automations editor for final save — do not invent a silent schedule.

Automation run order is identical to §9. Automation prompt must say: read committed `workflows/product-feature-catalog/REFERENCE.md` first.

---

## Appendix A — Current baseline (as of REFERENCE authoring)

Snapshot for the first rework thread; not a permanent inventory.

| Module key (live) | Public name | Groups / features (approx) |
|---|---|---|
| `platform` | App foundation | 3 groups / 7 features — **fold into Loyalty** |
| `loyalty` | Loyalty | Many groups / ~60 features — rework group naming + gaps |
| `amp` | AMP / Marketing Automation | Module stub — **seed 3 groups** |
| `cs` | Customer Service | Module stub — **seed CS groups** |

Packages live: `platform_base`, `loyalty_core`, `loyalty_advanced`.

Narrative source file: `docs/PRODUCT_NARRATIVE.md` (renamed from `PRODUCT_FEATURE_CATALOG.md` on 2026-08-12).

Reports claim discipline: use **30+ reports** in Loyalty analytics sales copy (product decision for this catalog).

First rework run_id: `a8f3c2e1-5b4d-4e9a-9c1f-20260812c001`.

Thai localize seed run_id: `b7e4a91c-2d8f-4c3a-a1e0-202608120001` (added `name_th` / `summary_th` on all active features).

Thai re-localize after EN sales rewrite: `e4c8a7b2-1d5f-4a90-9c3e-20260813c002` (63 `name_th`/`summary_th` updates; 2 Shopify rows filled from null).

---

## Appendix B — Proposal path retarget checklist

When renaming the narrative file, update at least:

| Path | Change |
|---|---|
| `workflows/proposal-generator/REFERENCE.md` | `PRODUCT_FEATURE_CATALOG.md` → `PRODUCT_NARRATIVE.md` |
| `workflows/proposal-generator/SCAFFOLDS.md` | Same path + wording (“catalogue” may stay; path must match) |
| `workflows/general-proposal/REFERENCE.md` | Negative citation path |
| `docs/PROJECT_CONTEXT_STRUCTURE.md` | If it still points at the old path |
| `requirements/CHANGELOG.md` | Optional historical mentions — leave unless editing that changelog entry anyway |

Preserve `###` feature anchors used by SCAFFOLDS reading lists.
