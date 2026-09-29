# Catalog weekly run — 2026-09-17 — `d6e2a91b-4c70-4f18-9e33-20260917c001`

## Environment / evidence constraints

- CRM Knowledge MCP (`search_docs` / `get_section`) was **not** attached to this Automation. Evidence used `doc_knowledge_chunks` via anon REST (same corpus) plus scoped committed `requirements/**` reads.
- Supabase MCP (`execute_sql`) was **not** available. Live inventory used anon REST on `v_internal_product_feature_catalog` (95 rows) + readable `internal_product_catalog_change_log` (latest live mutation still **2026-08-20**).
- Projection view lacks `last_verified_at` / `source_refs`. Overdue detection used change-log reconstruction + requirement-path churn since verify.
- Catalog write policy: **reviewable SQL only** (`catalog-updates.sql`). Do not apply without human approval.
- Prior reviewable runs `2026-08-17-c002`, `2026-08-31-c001`, `2026-09-07-c001`, and `2026-09-14-c001` remain **unapplied** in live change_log — this run re-carries their evidence-backed verify/repair set under the new `run_id`.
- Knowledge index still contains paths not in this git tree (e.g. `Frontline_Admin_Actions.md`, `Leaderboard.md`, `Checkin.md`, `Shopify.md`). Treated as stale orphans — not enough to clear prior conflicts.

## Inspect

- `requirements/INDEX_DOMAIN.md` / `CHANGELOG.md`: not present in repo.
- Requirement churn since last weekly automation (2026-09-14T02:03Z):
  - `requirements/Authentication.md` + `requirements/Signup_Login.md` (2026-09-14) — shared `issueMemberSession` issuer; JWT Generation says **30-day** access token; Token Expiry + Signup_Login JWT Structure still say **24 hours**. Sellable login methods unchanged.
  - Shopify `shopify_customer_id` on member JWT (2026-09-15) — **no** requirement path change; implementation for existing points-to-discount / matching.
- Still material / still unapplied from prior runs:
  - `requirements/Forms.md` (2026-08-25) — optional survey header `banner_url` (Knowledge: `Custom Fields System > Table Structure`)
  - `requirements/Reward.md` / `Referral.md` path churn — eng attach / outbox; no new sellable row
- Registry-only earlier churn (loyalty cache, LINE webhook, analytics CSV, receipt params, CS Web Push, Customer 360 wallet lots) — **no new sellable rows**.
- Tier perk master still has **no** `tier_perk_*` in committed `Tier.md` — **conflict / do not add**.
- Active public modules in live catalog: `loyalty`, `shopify`, `marketing_automation`, `customer_service` (4 — matches REFERENCE §5).
- `docs/PRODUCT_NARRATIVE.md` is indexed in `doc_knowledge_chunks` — violates REFERENCE “narrative not in Knowledge”; reported only (index job is out of scope).

## Classify

| feature_key | change | notes |
|---|---|---|
| `loyalty.forms.surveys` | update (+ localize_th) | Banner + completion rewards; refresh Thai; source_refs + `last_verified_at` |
| `loyalty.forms.profile_fields` | update (verify) | Forms.md re-checked; copy unchanged |
| `loyalty.forms.custom_fields` | update (verify) | Forms.md re-checked; copy unchanged |
| `loyalty.forms.signup_form` | update (verify) | Forms.md + Signup_Login; copy unchanged |
| `platform.signup.login_methods` | update (verify) | issueMemberSession evidence; **copy unchanged**; TTL claim conflict-stopped |
| `loyalty.campaign.referral` | update (verify) | Referral.md Core + Notifications outbox; copy unchanged |
| `loyalty.reward.catalog` (+ eligibility, dynamic_pricing, promo_codes, groups_limits, flash, admin_push_claim) | update (verify) | Reward.md path churn; copy unchanged |
| 11 currency/tier/mission/signup/persona/store/purchase/openapi/voice features | update (verify / repair) | Re-issue evidence-backed provenance from unapplied prior runs |
| `platform.governance.admin_shell` | update (repair only) | Point source_refs at REGISTRY Admin Panel; **do not** bump `last_verified_at` |
| `loyalty.storefront.shopify_*` / `member_matching` | no_change | JWT `shopify_customer_id` is implementation of existing GA burn/matching |
| `loyalty.frontline.customer_360` | conflict / stop | Wallet lots registry churn; broken Frontline source_refs |
| `loyalty.campaign.leaderboard` | conflict / stop | See Conflicts |
| Broken-`source_refs` / missing-doc features | conflict / stop | See Conflicts |
| Tier perk master (no feature_key) | conflict / stop | Eng shipped without Tier.md evidence for `tier_perk_*` |
| Member access-token TTL (narrative / reqs) | conflict / stop | 30d vs 24h inside Authentication/Signup_Login — do not patch narrative |

## Conflicts (stopped — no SQL mutation for the claim / row)

| feature_key | reason | action |
|---|---|---|
| `platform.signup.login_methods` (TTL claim only) | Knowledge + committed docs disagree: `Authentication.md` JWT Generation = 30-day access token; `Authentication.md` Token Expiry and `Signup_Login.md` JWT Structure = 24 hours. Narrative still says 24 hours. | Row verify only; **narrative 24h left unchanged** |
| `loyalty.frontline.customer_360` | Live `source_refs` cite Frontline docs not in this git tree; 2026-09-13 wallet-lots work is REGISTRY-only | left unchanged; no narrative section |
| `loyalty.campaign.leaderboard` | `source_refs` cite `requirements/Leaderboard.md` not in this git tree | left unchanged; no narrative section |
| `loyalty.analytics.reports` | cites missing `docs/LOYALTY_REPORTS_MARKETING_BRIEF.md` + `requirements/Analytics.md` | left unchanged |
| `loyalty.frontline.assisted_actions` | cites missing Frontline docs | left unchanged |
| `loyalty.lifecycle.anniversary` | cites missing `docs/AMP_LIFECYCLE_AUTOMATION.md` | left unchanged |
| `loyalty.lifecycle.tier_change` | cites missing `docs/AMP_LIFECYCLE_AUTOMATION.md` | left unchanged |
| `loyalty.persona.targeted_broadcast` | cites missing `requirements/AMP - Rule Based.md` | left unchanged |
| `marketing_automation.workflows.line_flex` | cites missing `requirements/AMP - Rule Based.md` | left unchanged |
| `loyalty.campaign.checkin` | no committed `requirements/Checkin.md`; Knowledge orphan too stale to refresh daily/weekly rhythm claim | deferred |
| *(no key)* tier perk master | `tier_perk_master` landed without Tier.md documenting reusable perk master + ladder inheritance | do not add feature; wait for doc closeout |

## Narrative

- Sections updated: **Survey forms** (five-block section + `<!-- feature_key: loyalty.forms.surveys -->`); light Forms umbrella pointer to Survey forms / banner.
- Authentication & Signup **not** migrated / not TTL-patched (conflict).
- Shopify storefront narrative **not** added (no catalog identity change).
- Known gaps (reported, not rewritten): no `## Shopify` module section; sparse `<!-- feature_key -->` anchors elsewhere; leaderboard / Customer 360 still blocked.

## Canonical Views handoff

- Catalog SQL changes **sales copy** for `loyalty.forms.surveys` (summary/includes/Thai) but **not** `commercial_nature`, package membership, or active-set. Optional Canonical Views refresh in `rocket-agent-plugins/plugins/rocket-sales/commercial/` per that pack’s `REFERENCE.md` §7 if the features-summary sheet still uses the thin prior survey line — **not written in this repo**. Prices stay blank; do not touch `sales-run/`.

## Validation (pre-apply)

- Hierarchy / four modules: pass (live view)
- Thai completeness on active ga/beta (view): pass; surveys Thai refreshed in SQL
- `commercial_nature` present; consumption units set: pass (view)
- Broken `source_refs` paths: **fail** until SQL applied for repaired rows + human resolves remaining conflicts
- Narrative surveys anchor: pass (added this run)
- Narrative not indexed into Knowledge: **fail** (live `doc_knowledge_chunks` includes `docs/PRODUCT_NARRATIVE.md`)
