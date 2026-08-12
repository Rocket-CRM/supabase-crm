# Product Feature Catalog — Maintenance REFERENCE

Executable contract for keeping the Rocket CX product catalog, Product Narrative, and weekly reconcile Automation aligned. Read this file before any catalog write or narrative sync.

**Repo:** `Rocket-CRM/supabase-crm`  
**Live DB:** Supabase project `wkevmsedchftztoolkmi` only  
**Related paths:** `docs/PRODUCT_NARRATIVE.md` (derived), `requirements/**/*.md` (behavior evidence), CRM Knowledge MCP (indexed requirements chunks)

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
| `name` | Yes | Buyer-facing label; may change |
| `summary` | Yes | One or two plain sentences: actor → behavior → outcome |
| `includes` | Yes (array) | Clarifiers/examples only when they prevent misunderstanding; else `[]` |
| `status` | Yes | `ga` \| `beta` \| `planned` \| `deprecated` (DB check) |
| `feature_group_id` | Yes | Exactly one group |
| `sort_order` | Yes | Ordering within group |
| `is_active` | Yes | Soft visibility; prefer `status = deprecated` over hard delete |
| `source_refs` | Yes (after provenance migration) | jsonb array of evidence pointers (see §8) |
| `last_verified_at` | Yes (after provenance migration) | timestamptz of last evidence-backed verify |
| `feature_registry_key` | Optional | Link to eng entitlement registry when known |
| `pricing_catalog_slug` | Optional | External pricing slug when known |

### Keys

- Module keys: `loyalty`, `marketing_automation`, `customer_service` (exactly three **active public** modules).
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

## 5. Three-module taxonomy

Exactly three active public modules.

### Loyalty (`loyalty`)

Public journey (narrative / module summary only): acquisition → engagement → campaigns → analysis → activation.

Capability groups (target shape):

| Group theme | Intent |
|---|---|
| Foundation and acquisition | Signup/login, profile completion, website signup, PDPA, languages, member layout (folded from App foundation; keep stable keys) |
| Points and earn channels | Currency, earn rates (basic/advanced), multipliers, earn channels |
| Rewards and burn | Catalog redeem, eligibility, pricing, promo codes, burn-to-discount |
| Tiers | Ladder, upgrade/maintain, windows, per-tier benefits |
| Campaigns | Missions, referral, check-in, spin, lucky draw (stay inside Loyalty) |
| Lifecycle automations | Rename away from “Lifecycle outcomes”; signup/birthday/anniversary/tier-change automations |
| Customer profile and Customer 360 | Forms/profile fields, Front Line / Customer 360 |
| Segmentation and RFM | Tags/personas/user types, RFM, funnel stages |
| Analytics and reports | Report inventory — state **30+ reports** in sales summary / narrative |
| Admin, data operations, and integrations | Admin permissions, import/export, Open API, storefront integrations, store network, stored value, event promo |

Required corrections vs prior catalog:

- Fold App foundation rows into Loyalty; preserve stable feature keys.
- Keep Campaigns inside Loyalty (not a fourth module).
- Rename Lifecycle outcomes → lifecycle automation language.
- Advanced earn rates: different rates by channel (and related dimensions already sold).
- Multipliers: double points for selected products/categories.
- Include Customer 360, segmentation/RFM, and reporting categories.

### Marketing Automation (`marketing_automation`)

Rename from historical `amp` module key when reworking (preserve package links via migration/seed transaction; document key change in audit log).

Three primary groups:

1. **Deterministic multi-step workflow automation** — condition on customer data; execute messages plus loyalty actions.
2. **AI decisioning agents** — receive goals, allowed actions, outcomes, and constraints; review customer context; choose ACT, WAIT, or SKIP.
3. **AI analysis and recommendations** — analysis/recommendation surfaces distinct from decisioning execution.

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

---

## 6. Feature Catalog Writing Guide

- Exactly three levels: Module → Feature group → Feature.
- A row represents a distinct end-user capability that can be recognized, compared, or sold.
- Package membership never creates the taxonomy.
- Preserve stable keys; labels and group placement may change.
- **Summary:** one or two plain sentences describing actor → behavior → outcome.
- **`includes`:** only a clarifier/example that materially prevents misunderstanding.
- Split basic/advanced when they are distinct comparable capabilities.
- Use `ga`, `beta`, `planned`, or `deprecated`; stale copy is a verification condition, not product status.
- No implementation jargon, generic superlatives, unsupported numbers, or invented package placement.

Additional craft rules:

- Prefer concrete nouns over platform slang (`points`, `receipt upload`, not “engagement engine”).
- Thai/English brand examples belong in `includes` only when they clarify mechanism.
- If evidence is thin, keep summary conservative and mark verification overdue rather than inventing detail.

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

### Verification freshness

Treat a feature as **overdue** when:

- `last_verified_at` is null, or
- older than the Automation’s freshness window (default **30 days**), or
- a touching `requirements/**` path changed since `last_verified_at`.

---

## 9. Transactional maintenance procedure

### Manual or Automation run order

1. **Inspect** recent requirement changes plus catalog rows overdue for verification.
2. **Gather** targeted CRM Knowledge evidence; scoped requirement reads only when needed.
3. **Classify** each candidate: `add` | `update` | `move` | `deprecate` | `no_change`.
4. **Update** the Supabase catalog and audit log **transactionally** (single SQL transaction / migration apply).
5. **Synchronize** only affected Product Narrative sections.
6. **Validate** hierarchy, statuses, packages, source references, narrative anchors, and proposal references.
7. **Report** changed/skipped/conflicting rows and the narrative Git diff.

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

- [ ] Exactly three active public modules: Loyalty, Marketing Automation, Customer Service
- [ ] Every active feature has one group, stable key, clear summary, valid status, source reference, and verification time
- [ ] Package assignments are structured and evidence-backed
- [ ] Loyalty contains lifecycle automations, customer intelligence, analytics, and configurable-program distinctions (basic vs advanced earn, multipliers, etc.)
- [ ] Marketing Automation cleanly separates workflows, AI decisioning, and AI analysis
- [ ] Customer Service cleanly separates non-AI operations, AI service/AOP actions, and supervisor scoring
- [ ] Product Narrative maps to canonical feature keys and contains no unsupported status/package claims
- [ ] Product Narrative is not indexed into CRM Knowledge
- [ ] Proposal workflow resolves the renamed narrative path
- [ ] Automation / run logs all direct catalog changes and produces reviewable narrative diffs

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
