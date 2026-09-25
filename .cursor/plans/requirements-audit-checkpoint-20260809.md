# Requirements corpus audit — checkpoint / execution plan

**Date:** 2026-08-09  
**Workspace:** `~/Documents/rocket/supabase-crm`  
**Supabase project:** `wkevmsedchftztoolkmi`  
**Mode:** Read-only by default. Propose edits; apply only when user explicitly approves a batch.  
**Out of scope for this program:** building Knowledge MCP / embeddings / daily reindex.

---

## Task

Prepare `requirements/**/*.md` as the **only** product-canonical corpus for a future Knowledge MCP (chunk/index that tree). Audit accuracy, coverage, legacy, structure/writing, and always-on update workflow; apply approved doc fixes in batches.

---

## Status (this thread)

### Done

- **Phase A — Inventory:** 194 markdown files under `requirements/`. Grouped: product top-level, `domains/` slugs, `feature-docs/`, `archive/`, `architecture/`, meta/registries, AMP cluster, CS cluster, integrations, client-custom (Yuanta/Syngenta).
- **Phase B — Coverage matrix:** Feature → doc → status (solid / thin / missing / wrong home / split). Live schema spot-check confirmed key tables (checkin*, package_*, persona_entitlement, store_credit_promo, earn_channel*, consent*, display_*, cards/card_types, shopify_*, purchase_receipt_upload*, futurepark_redemptions, order_ledger_mkp).
- **Scoped decisions captured (not yet applied):**
  - **Open API:** Promote `docs/Rocket Loyalty Open API Documentation.md` (bodies, curl, examples) → `requirements/Open_API.md`; keep `docs/openapi/openapi.yaml` as machine contract; thin-pointer `PLATFORM_API_REFERENCE.md`.
  - **Analytics:** Document **edge `analytics-query` → BigQuery** (`rocket-prod-analytics.serving_loyalty` named reports). There are **no** Postgres RPCs that call BQ. Seed: `docs/BQ_PARTITION_AND_CLUSTERING.md` + `.cursor/deploy/analytics-query/reports/registry.ts`. Separate from AMP/CS/Metabase analytics.
  - **Marketplace:** Consolidate Shopee/Lazada/TikTok onto `Marketplace.md`; keep `Shopify.md` separate; keep `Multi_Channel_Product_Reference.md` as companion; archive Kafka-era `MARKETPLACE_SETUP.md`; stub/rewrite `Ecommerce_Marketplace_Integration.md`.

### Not done

- Phase C accuracy audit (evidence-backed stale claims)
- Phase D full apply (legacy delete/archive/rewrite) — **recommendations below; not executed**
- Phase E structure/writing restructure queue apply
- Phase F always-on update workflow rule text apply
- Any mass rewrites or new large docs

### Freshness caveat

Many top-level files show mtime `2026-08-09` from bulk touch — **mtime ≠ content freshness**. Prefer CHANGELOG bullets, in-doc “Last Updated”, and live MCP vs claims.

---

## Frame (for every new-thread turn)

Product truth write home: `requirements/**/*.md` only.  
Live BE truth: Supabase MCP — docs lose when they conflict.  
Registries/indexes: grep only (`domains/_index.md`, `REGISTRY_SUPABASE.md`, `REGISTRY_RENDER.md`, `CHANGELOG.md`).  
Writing standards: `Writing Principles/CORE_WRITING_PRINCIPLES.md`, `00-core.mdc` Output Style, `13-feature-guide-writing.mdc` for feature-guides only.  
Target product-doc shape: **Concept → Feature & journey overview → System design**.  
Exclude forcing that template onto registries/changelogs/pure pointers.

---

## Phase A — Inventory (reference)

| Group | ~Count | Role |
|---|---:|---|
| Product top-level | ~85 | Canonical product/system docs |
| `domains/` slugs | 42 | Retiring; residual rules |
| `feature-docs/` | 26 | Audience guides; INDEX vs folder disagree |
| `archive/` | 21 | Retired drafts |
| `architecture/` | 3 | Cross-cutting eng patterns |
| Meta / registries | ~10 | Ops indexes — not product template |
| AMP / CS / integration / client | remainder | Module & custom |

**Domain map gap:** `_index.md` omits Shopify, FuturePark, Receipt Upload, Earn Channel, Store Credit, Package, Persona Entitlement, Order Booking, Consent, Platform Plan, Central Outcome, Check-in, Open API, Analytics (BQ), etc. — even when docs exist.

---

## Phase B — Coverage matrix (execute from this)

Status key: **solid** / **thin** / **missing** / **wrong home** / **split**

| Feature | Primary doc | Status | Action |
|---|---|---|---|
| Tier | `Tier.md` (+ `Tier_Simplification.md`) | solid / split | Keep Tier; archive Simplification after pointer |
| Reward | `Reward.md` + feature-docs | solid / structure risk | Accuracy + restructure opener |
| Currency / wallet | `Currency.md` | solid / structure risk | Accuracy + move seller section after concept |
| Purchase | `Purchase_Transaction.md` | solid | Accuracy sample |
| Marketplace Shopee/Lazada/TikTok | `Marketplace.md` | thin / live | Expand; absorb Ecommerce |
| Shopify | `Shopify.md` | solid / wrong routing | Domain-map row |
| BigCommerce | pointed at Ecommerce… | wrong home | Thin home after marketplace consolidate |
| Receipt upload (generic) | `Receipt_Upload_Earning.md` | solid / wrong routing | Domain-map |
| FuturePark | `FuturePark.md` | solid / wrong routing | Domain-map; keep stubs |
| Earn channels | Earn_Channel* (3–4) | split | Consolidate |
| Missions | `Mission.md` | solid | Accuracy |
| Spin wheel | `Spin_Wheel.md` | solid | Accuracy light |
| **Check-in** | feature-docs only | **missing** | Create `Checkin.md` |
| Forms / Signup / Consent | Forms, Signup_Login, Consent | solid / Consent wrong routing | Domain-map Consent |
| Display settings | `Display_Settings.md` | thin / schema-first | Restructure + accuracy |
| Auth / Admin / Notifications | respective docs | solid–thin | Accuracy light |
| AMP workflows / rules / AI / conditions | multiple | split | Keep contract; clarify ownership |
| Central outcome / chokepoints | Central_Outcome…, architecture/event-chokepoints | solid / wrong routing | Domain-map outcome |
| Packages / Persona entitlements / Store credit | Package, Persona_Entitlement, Store_Credit | solid–thin / wrong routing | Domain-map |
| Stored-value cards | feature-docs + live `cards` | **missing product** | Create or merge decision |
| Order booking / Asset / Referral / Activity | respective | solid–thin | Domain-map + accuracy |
| RFM / Funnel / Campaign grouping | thin | thin | Expand or accept thin |
| Tag & Persona / Store classification / Translation | aging | aging | Accuracy |
| Import/export systems | several | solid / split | Keep; stub Customer_Import addendum OK |
| Platform plan registry | Platform_Plan… | solid / wrong routing | Domain-map |
| **Open API** | `docs/…` only | **missing in requirements** | Promote → `Open_API.md` |
| **Analytics (BQ)** | `docs/BQ_…` + edge only | **missing** | Create `Analytics.md` |
| Mass lucky draw | Knowledge slug only | unknown | Confirm product status before doc |
| CS suite | many `CS_*.md` | thin / aging / duplicate | Accuracy + merge plan |
| Custom webhooks / Multi-channel SKU / Syngenta | respective | thin–solid | Leave scope clear |

### Missing docs to create (approve before writing)

1. **`requirements/Checkin.md`** — concept, admin/member journeys, `checkin` / `checkin_outcomes` / `checkin_ledger`, `process_checkin`, reverse, earn-channel coupling.
2. **`requirements/Open_API.md`** — promote from `docs/Rocket Loyalty Open API Documentation.md` (+ concept opener; link yaml).
3. **`requirements/Analytics.md`** — `analytics-query` → BQ serving layer; report catalog; auth; distinguish AMP/CS/Metabase.
4. **`requirements/Stored_Value_Cards.md`** *or* merge into Store Credit/Currency after product decision.
5. **Domain-map rows only** for existing homes listed above (Batch 0).
6. Optional later: Mass Lucky Draw; CS chatbot/IVR if live.

---

## Phase C — Accuracy fix queue (prioritized; not yet run)

For each: grep doc claims → verify via Supabase MCP (+ FE hubs only as pointers) → record `stale claim | evidence | proposed fix`. Prefer surgical updates.

| Priority | Doc | Focus claims |
|---:|---|---|
| 1 | `Tier.md` | maintain windows, pending upgrades, chokepoint/Inngest path |
| 2 | `Reward.md` | variants, groups, Inngest redemption, Shopify discount |
| 3 | `Currency.md` | chokepoint_post_wallet, expiry, ticket types, store credit hooks |
| 4 | `Purchase_Transaction.md` | dual ledger, earn triggers, marketplace claim landing |
| 5 | `Receipt_Upload_Earning.md` + `FuturePark.md` | OCR tables, prompts, approval, settlement |
| 6 | `Shopify.md` | OAuth, webhooks, store credit issue, plan sync |
| 7 | `Marketplace.md` (after expand) | ingest mode Inngest, credentials, backfill |
| 8 | `AMP_Workflows.md` + `AMP - Rule Based.md` + `AMP_Condition_Contract.md` | audiences, Inngest amp-serve, condition JSON |
| 9 | `Mission.md` | post-Confluent progress, due reset cron |
| 10 | `Forms.md` + `Signup_Login.md` + `Consent.md` | field systems, next_step, consent ledger |
| 11 | `Display_Settings.md` | enrich, blocks, cache invalidation |
| 12 | CS: Conversations, Channels, Procedures, Feature_Spec | deployed vs aspirational |
| 13 | Next wave | Referral, Activity_*, Notifications, Import systems, Tag_and_Persona, Store_Attribute, Translation, Package, Persona_Entitlement, Store_Credit, Asset, Order_Booking, Platform_Plan, Central_Outcome |

---

## Phase D — Legacy / remove / rewrite / merge (recommendations)

| Item | Recommend | Notes |
|---|---|---|
| `MARKETPLACE_SETUP.md` | **Archive** → `requirements/archive/` | Kafka/Confluent path retired |
| `Ecommerce_Marketplace_Integration.md` | **Rewrite → stub** pointing to `Marketplace.md` (+ BigCommerce note) | Still claims Kafka/Redis; Shopify already points here as “platform-generic” — update that link |
| `Marketplace.md` | **Expand / rewrite** as Shopee/Lazada/TikTok canonical | Absorb still-true concept/journey from Ecommerce; keep live Inngest ops |
| `Shopify.md` | **Keep** | Separate product |
| `Multi_Channel_Product_Reference.md` | **Keep** companion | Link from Shopify + Marketplace |
| `feature-docs/marketplace-integration.md` | **Update or archive** after product settle | Still tells Kafka story; INDEX policy |
| `FuturePark_OCR_*` / `FuturePark_Receipt_*` stubs | **Keep** short pointers | Already correct |
| `Tier_Simplification.md` | **Archive** after Tier.md owns end-state pointer | Migration memoir |
| `INDEX_FUNCTION.md` | **Quarantine/delete** | Deprecated by `06-update-docs`; replaced by REGISTRY_SUPABASE |
| `domains/*.md` slug files | **Continue retire/merge** | Per `_index.md` Phase 6 |
| `feature-docs/*` vs INDEX “Archived” | **Reconcile** | INDEX says archived; many files still in `feature-docs/` — move or fix INDEX |
| `archive/feature-docs-draft/*` | **Leave; exclude from Knowledge** | |
| Earn Channel set (`Earn_Channel.md`, `_Canonical`, `_FE_Guide`, `Earn_from_Code.md`) | **Consolidate** | One canonical + FE appendix + earn-from-code as mechanic subsection or sibling with clear ownership |
| `agent-context-architecture.md` vs `AGENT_CONTEXT_ARCHITECTURE.md` | **Dedupe** | Meta |
| `CS_Feature_Spec.md` vs modular `CS_*.md` | **Merge or mark umbrella** | Spec-dump vs modules |
| `amp_analysis.md` | **Archive or slim** | Analysis dump |
| `AMP - Cache Layer.md` | Review → archive if obsolete | Apr-19 |
| `Custom_Reward_Scripts.md` | Keep if still used; else archive | Feb-01 |
| `Loyalty_Signup_Component.md` | FE component guide — keep or move under Signup | |
| `Spin_Wheel_CS_Config_TH.md` | Client config — keep client-scoped | |
| `Yuanta/**` | Client — keep; exclude or tag for Knowledge | |
| `CURSOR_RULES_PRINCIPLES.md` | Meta — not product corpus | |
| Duplicate Kafka narratives in feature-docs | Align to live Inngest/chokepoint | |

**Knowledge index include (suggested):** product top-level + architecture that defines product contracts; exclude `archive/`, registries optional as metadata, `INDEX_FUNCTION`, client one-offs unless tagged, pure stubs.

---

## Phase E — Structure / writing fix queue

Rubric: concept → journey → system design; pyramid; MECE; plain language before tables.

| Priority | Doc | Issue | Restructure note |
|---:|---|---|---|
| 1 | `Reward.md` | Opens on store-stock schema | Move Store Stock after Core Concepts; lead with Executive Summary / concept |
| 2 | `Currency.md` | Seller Perspective before Exec Summary | Relocate seller section under earning variants |
| 3 | `Display_Settings.md` | Tables-first | Add Concept + Admin/Member journey before Tables |
| 4 | `CS_Feature_Spec.md` / `CS_AI_System.md` | Schema/spec openings | Concept + journey before schema; or mark as schema appendix |
| 5 | `Asset.md`, `RFM_Scoring.md`, `Syngenta_Events.md` | Tables-first shorts | Add 5–10 line concept + journey |
| 6 | `Marketplace.md` (when expanding) | Ops-first (OK if short) | Add concept + member claim journey before ingest steps |
| 7 | Good exemplars to copy | `Mission.md`, `Consent.md`, `Package.md`, `Persona_Entitlement.md`, `Receipt_Upload_Earning.md` | |

---

## Phase F — Always-on update workflow (draft; apply only when approved)

### Definition of done

A behavior-affecting change is **incomplete** until:

1. Authoritative `requirements/<Domain>.md` updated (or new doc + `_index.md` row),
2. `REGISTRY_RENDER.md` updated if edge/cron/queue/Render changed,
3. `REGISTRY_SUPABASE.md` regenerated if schema/RPC names changed (`registry-regenerate` skill),
4. One-line `CHANGELOG.md` append (existing protocol in `06-update-docs.mdc`).

### Routing

- Grep `requirements/domains/_index.md` for keywords → authoritative doc.
- Hubs (Shopify/FuturePark ops) **point into** requirements; never become product SoT.

### Suggested rule changes (propose text in execution thread; don’t apply until approved)

- Extend `.cursor/rules/06-update-docs.mdc`:
  - Explicit checklist: Concept/Journey/System-design sections touched when behavior changes.
  - Mandatory `_index.md` row for new domains (already partially there).
  - Open API / Analytics / Marketplace / Shopify / FuturePark / Receipt / Earn Channel named in the change→doc table.
  - “Wrong home” ban: do not document Shopify product in Ecommerce/Marketplace docs.
- Optional hook: before task close, if git diff touches `supabase/functions` or migration-like paths, remind domain doc update (proposal only).
- Manual escape hatch before Knowledge reindex: operator runs doc audit diff / CHANGELOG since last index — mention only; do not build indexer here.

---

## Recommended execution batches (new thread)

Apply only with explicit user approval per batch.

### Batch 0 — Routing only (smallest)

Update `requirements/domains/_index.md` Domain Map + keywords for:

Shopify, FuturePark, Receipt_Upload_Earning, Earn_Channel (canonical), Store_Credit, Package, Persona_Entitlement, Order_Booking, Consent, Platform_Plan_Feature_Registry, Central_Outcome_Dispatcher, Checkin (after Batch 2 or placeholder), Open_API (after Batch 1), Analytics (after Batch 1).

### Batch 1 — Create / promote (approved decisions)

1. Promote Open API → `requirements/Open_API.md`; pointer from `docs/openapi/*`.
2. Create `requirements/Analytics.md` from `analytics-query` + `docs/BQ_PARTITION_AND_CLUSTERING.md`.
3. Marketplace consolidate: expand `Marketplace.md`; stub Ecommerce; archive `MARKETPLACE_SETUP.md`; fix Shopify link that cites Ecommerce as platform-generic home.

### Batch 2 — Checkin product doc

Create `requirements/Checkin.md` from live registry + `feature-docs/checkin.md` + MCP signatures; domain-map row.

### Batch 3 — Earn Channel consolidation

Pick canonical (`Earn_Channel_Canonical.md` or `Earn_Channel.md`); demote others to pointers; domain-map single target.

### Batch 4 — Phase C accuracy wave 1

Tier, Reward, Currency, Purchase, Receipt/FuturePark, Shopify — surgical fixes with evidence list in-chat before apply.

### Batch 5 — Structure wave 1

Reward + Currency opener fixes; Display_Settings concept/journey; CS umbrella decision.

### Batch 6 — Phase F workflow

Draft + apply approved `06-update-docs` (and related) text; reconcile feature-docs INDEX vs folder.

### Batch 7 — Remaining accuracy + legacy sweep

CS, AMP AI, aging Tag/Store/Translation, Stored_Value_Cards decision, INDEX_FUNCTION quarantine, domains slug retirement continuation.

---

## Next exact step (start of new thread)

1. Attach this file.
2. Ask user which batch to execute first (default recommendation: **Batch 0 + Batch 1**).
3. Before any write: re-read this plan §Batch N; verify live claims via Supabase MCP for that batch only.
4. Apply only the approved batch; append CHANGELOG if behavior/doc contract changed; stop and report.

---

## Critical context for the next thread

- Product SoT: `requirements/**/*.md` only; Shopify/FuturePark hubs already point here.
- Open API source to promote: `docs/Rocket Loyalty Open API Documentation.md` (~53KB) + `docs/openapi/openapi.yaml` + `docs/openapi/PLATFORM_API_REFERENCE.md`. Gateway project: `mabioklchbkanhjwgibj` (see `REGISTRY_RENDER.md`).
- Analytics live code: `.cursor/deploy/analytics-query/` — reports in `reports/registry.ts`; auth in `lib/auth.ts`; BQ in `lib/bq.ts`. Dataset `rocket-prod-analytics.serving_loyalty`. Reports: `transactions.purchases[.rows]`, `rewards.redemptions[.rows]`, `members.overview[.rows]`, `currency.points_overview[.rows]`, `currency.points_movement`, `currency.points_snapshot[.rows]`, `overview.loyalty`, `home.metrics`, `health`.
- Marketplace live path: webhook → Inngest `marketplace/order-received` → `inngest-marketplace-serve` → `upsert_marketplace_order` → `claim_marketplace_order` (`Marketplace.md`). Kafka docs are stale.
- Check-in: live tables/RPCs in registry §Checkin; **no** `requirements/Checkin.md` yet; feature guide at `requirements/feature-docs/checkin.md`.
- Do not full-read huge requirement files; grep + scoped Read; extract MCP findings immediately.
- Checkpoint again if the execution thread hits ~10–15 user turns or heavy tool use.
- Do **not** maintain old CRM Knowledge typed blocks as part of this program; do **not** start Knowledge MCP indexing here.

---

## Deliverables checklist (original ask)

| # | Deliverable | Where |
|---|---|---|
| 1 | Executive summary | Status + Frame above |
| 2 | Coverage matrix | Phase B |
| 3 | Missing docs list | Phase B |
| 4 | Legacy list | Phase D |
| 5 | Accuracy fix queue | Phase C |
| 6 | Structure/writing fix queue | Phase E |
| 7 | Always-on workflow proposal | Phase F |
| 8 | Recommended next batches | Batches 0–7 |

---

## Executive health snapshot

| Dimension | Health | One-liner |
|---|---|---|
| Accuracy | Mixed / unverified at scale | Cores exist; Kafka-era and aging CS/Tag/Store docs are risk; Phase C not run |
| Coverage | Gaps | Checkin, Open API, Analytics BQ, stored-value cards, domain-map holes |
| Legacy | High clutter | ~194 files; duplicates, archive drift, deprecated INDEX_FUNCTION |
| Structure | Uneven | Some concept-led; Reward/Currency/Display/CS schema-first |
| Update workflow | Partial | `06-update-docs` exists; needs domain coverage + DoD enforcement |
