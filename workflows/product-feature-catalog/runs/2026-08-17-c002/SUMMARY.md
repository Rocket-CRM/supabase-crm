# Catalog weekly run — 2026-08-17 — `d1f5a8c3-6e2b-4a91-9d44-20260817c002`

## Environment / evidence constraints

- CRM Knowledge MCP (`search_docs` / `get_section`) was **not** available on this Automation.
- Supabase MCP (`execute_sql`) was **not** available. Live inventory used anon REST on `v_internal_product_feature_catalog` (95 rows) + readable `internal_product_catalog_change_log`.
- `last_verified_at` / full row snapshots are **not** on the projection view; overdue detection used change-log reconstruction + null-as-overdue for features never verified in logged snapshots.
- Catalog write policy: **reviewable SQL only** (`catalog-updates.sql`). Do not apply without human approval.
- Prior same-day live run `c9a4e2b1-7d3f-4c18-8e55-20260817c001` (01:06Z) already added `loyalty.campaign.leaderboard` in the DB.

## Inspect

- `requirements/CHANGELOG.md`: not present in repo.
- Requirement path churn (45d): registry Asset docs only (`REGISTRY_SUPABASE.md` Asset / member+admin BFFs) — **no new sellable Asset row** (Open API summary already includes manage assets).
- Active public modules in live catalog: `loyalty`, `shopify`, `marketing_automation`, `customer_service` (4 — matches REFERENCE §5; automation hard-law text saying “three” is stale vs REFERENCE).

## Classify

| feature_key | change | notes |
|---|---|---|
| 15 currency/tier/mission/referral/reward/signup/persona/store/purchase features | update (verify) | Copy unchanged; refresh `source_refs` + `last_verified_at` from local requirements |
| `loyalty.integrations.open_api` | update | Repair broken Open API doc path → REGISTRY Asset / API Key; verify assets claim |
| `customer_service.chat_voice.voice` | update | Repair missing `CS_Voice.md` → `docs/cs_voice_architecture.md` |
| `platform.governance.admin_shell` | update | Repair missing `Admin_Panel.md` → REGISTRY Admin Panel; **do not** bump `last_verified_at` (claims not fully re-litigated) |
| `loyalty.campaign.leaderboard` | conflict / stop | See Conflicts |
| 8 other broken-`source_refs` features | conflict / stop | Missing requirement paths; left unchanged |
| Asset as new feature | no_change / skip | Covered by Open API; no dedicated product requirement doc |
| Remaining never-verified rows | skipped | No CRM Knowledge; deferred |

## Conflicts (stopped — no SQL mutation)

| feature_key | reason | action |
|---|---|---|
| `loyalty.campaign.leaderboard` | `source_refs` cite non-existent `requirements/Leaderboard.md`; sales claims (e.g. Participate tap / top spenders) not evidenced by REGISTRY Campaign listing alone; narrative section not added | left unchanged; needs dedicated Leaderboard requirement doc before verify/narrative sync |
| `loyalty.analytics.reports` | cites missing `docs/LOYALTY_REPORTS_MARKETING_BRIEF.md` + `requirements/Analytics.md` | left unchanged |
| `loyalty.frontline.customer_360` | cites missing Frontline / Activity_Attribution docs | left unchanged |
| `loyalty.frontline.assisted_actions` | cites missing Frontline / feature-docs/rewards | left unchanged |
| `loyalty.lifecycle.anniversary` | cites missing `docs/AMP_LIFECYCLE_AUTOMATION.md` | left unchanged |
| `loyalty.lifecycle.tier_change` | cites missing `docs/AMP_LIFECYCLE_AUTOMATION.md` | left unchanged |
| `loyalty.persona.targeted_broadcast` | cites missing `requirements/AMP - Rule Based.md` | left unchanged |
| `marketing_automation.workflows.line_flex` | cites missing `requirements/AMP - Rule Based.md` | left unchanged |
| `loyalty.campaign.checkin` | no `requirements/Checkin.md`; REGISTRY Checkin alone too thin for daily/weekly rhythm claim | deferred (not in SQL) |

## Narrative

- Sections updated: **none** (no non-conflicted copy/hierarchy changes; leaderboard sync blocked by conflict).
- Known gaps (reported, not rewritten this run): no `## Shopify` module section; Campaigns intro still lists five mechanics (leaderboard not narrated while conflicted); sparse `<!-- feature_key -->` anchors.

## Canonical Views handoff

- No commercial identity changes in this SQL (no `commercial_nature` / package / active-set edits). **No** sales-pack Canonical Views refresh required for this run.

## Validation (pre-apply)

- Hierarchy / four modules: pass (live view)
- Thai completeness on active ga/beta (view): pass
- `commercial_nature` present; consumption units set: pass (view)
- Broken `source_refs` paths: **fail** until SQL applied for repaired rows + human resolves remaining conflicts
- Narrative anchors vs leaderboard: **fail** (intentional stop)
