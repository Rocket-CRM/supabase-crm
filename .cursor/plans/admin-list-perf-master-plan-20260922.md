# Admin list performance — master plan (2026-09-22)

Source thread: "reward list page on admin loads very slowly" → audit all admin list pages.
Status audited at 22:10 (UTC+8) against live DB + working trees. Use this file as the
single checklist; tick items here as they land.

## Root cause (settled)

`bff_list_rewards` returns every reward for the merchant and LEFT JOINs a GROUP BY over the
merchant's whole `reward_redemptions_ledger` (1.5–1.8 M rows on big merchants) to attach
redeemed/used counts. Mean 2.5 s, max 10 s. UI shows 25 rows. The same RPC was reused as a
generic "give me rewards" call in 6 other places, so they all paid the ledger scan.

Fix shape (approved by user):
- Server-paginated reward list, no ledger join → `bff_list_rewards_paged`.
- Redeemed / Used / Not used move to the reward **detail** header as pills → `bff_get_reward_redemption_stats`.
- Reward pickers become lazy + fuzzy search (same pattern as the earn-rules pickers).
- Other admin list pages with the same load pattern get the same treatment.

## Repos / branches

| Repo | Path | Branch | State |
|---|---|---|---|
| Admin FE | `~/Documents/rocket/loyalty-admin` | `main` | 18 modified + 4 new files, **uncommitted** |
| Backend | `~/Documents/rocket/supabase-crm` | `feat/expiry-reminder-render-cron` | 2 migration files **untracked**, both **applied live** |
| Supabase | project `wkevmsedchftztoolkmi` | — | new RPCs + indexes live |

Rules for the executing thread: edit only the owning clone; commit per repo; **do not push**
unless the user says so; no new schema/RPC changes without "approved".

---

## A. DONE — live in DB (applied via MCP, migration files written, not committed)

### A1. `supabase/migrations/20260922210000_reward_list_paged_and_redemption_stats.sql` ✅ live
- `idx_reward_master_name_trgm` (gin, pg_trgm) on `reward_master.name`.
- `fn_reward_admin_list_base(...)` — shared predicate (merchant, ids, kind, status, categories, visibility, fuzzy query).
- `bff_list_rewards_paged(p_query, p_kind all|catalog|campaign, p_status all|active|inactive, p_category_ids, p_visibility, p_ids, p_page, p_page_size≤100, p_with_summary)` → `{items, total, page, page_size, summary}`. Summary = merchant-wide counts from `reward_master` only.
- `bff_get_reward_redemption_stats(p_reward_id)` → `{redeemed_qty, used_qty, not_used_qty}` for one reward (indexed ledger read).
- `bff_list_rewards` (old) left untouched — no admin caller remains.
- Grants: authenticated + service_role; anon revoked.

### A2. `supabase/migrations/20260922220000_event_promos_list_perf.sql` ✅ live, ✅ equivalence verified
- `idx_event_promo_merchant`, `idx_event_promo_rule_promo`.
- `bff_list_event_promos` rewritten: `applicable_events_count` computed once as a (promo, event) set instead of a correlated 3×EXISTS per promo. 2635 ms → 162 ms on Syngenta.
- Output shape unchanged. Verified 46/46 promos: applicable/rule/mapping/claim counts and mappings all identical to old logic (the earlier md5 mismatch was array element ordering only). **No FE change needed.**

---

## B. DONE — FE code written in `loyalty-admin` (uncommitted, tsc clean, NOT visually verified)

### B1. Data layer
- `src/lib/api/reward-list.ts` — rewritten around `bff_list_rewards_paged`:
  `fetchRewardListPage`, `searchRewardOptions`, `fetchActiveRewardCount`, `fetchRewardPreview` (now paged), `fetchRewardRedemptionStats`. Old `fetchRewardList` (full list) **removed**.
- `src/lib/api/reward-list-types.ts` — `RewardListItem` drops `redeemed_qty/used_qty/not_used_qty`, adds `reward_code`, `assign_promocode`, `image_url`, `created_at`; new `RewardListSummary`, `RewardListPageResult`, `RewardRedemptionStats`.
- `src/app/(admin)/reward-list/actions.ts` — removed the `fetchRewardList` re-export.

### B2. Reward list page (server-paginated) — `/reward-list`
- `src/app/(admin)/reward-list/lib/list-query.ts` (new) — URL ↔ query state (`tab`, `q`, `status`, `category`, `page`), `REWARD_LIST_PAGE_SIZE = 25`.
- `src/app/(admin)/reward-list/page.tsx` — reads `searchParams`, fetches one page + summary; groups tab fetched **only** when `tab=groups`; Shopify surface passes `visibility=['user','campaign']` to SQL instead of filtering client-side.
- `src/app/(admin)/reward-list/reward-list-page.tsx`, `reward-list.tsx` — consume `initialQuery` / `initialPage`; pagination/filter/search now navigate via URL.

### B3. Reward detail: stats pills
- `src/app/(admin)/reward-settings/[id]/reward-redemption-stats-pills.tsx` (new) — Redeemed / Used / Not used badges, loaded after mount.
- `src/app/(admin)/reward-settings/[id]/reward-settings-form.tsx` — pills mounted in `Page primaryAction` (edit mode, non-Shopify); active-reward quota check now uses `fetchActiveRewardCount("catalog")` instead of fetching the full list.

### B4. Shared lazy/fuzzy picker primitives
- `src/components/reward/use-reward-search.ts` (new) — debounced server search + "load more", backed by `bff_list_rewards_paged`.
- `src/components/reward/reward-search-combo.tsx` (new) — `AsyncSearchCombo` wrapper for rewards.
- `src/components/patterns/async-search-combo/async-search-combo.tsx` — added `preloadOnFocus` + request sequencing (stale-response guard).

### B5. Call sites migrated off `bff_list_rewards`
| Call site | File | Pattern now | Lazy + fuzzy? |
|---|---|---|---|
| Home dashboard count | `src/app/(admin)/home-stats.ts` | `p_page_size:1, p_with_summary:true` → `summary.active_total` | n/a (count) |
| Redeem rules preview | `src/lib/api/reward-list.ts::fetchRewardPreview` (page unchanged) | paged, 5 items | n/a (preview) |
| Reward settings quota | `reward-settings-form.tsx` | `fetchActiveRewardCount` | n/a (count) |
| Content Library button action | `content-library/[id]/components/button-action-editor.tsx`, `content-library/data.ts`, `types.ts` | `RewardSearchCombo` | ✅ |
| Front Line push reward (member tab) | `front-line/[userId]/push-reward/push-reward-tab.tsx`, `push-reward-card.tsx` | `useRewardSearch` | ✅ |
| Front Line push reward (list page) | `front-line/push-reward/push-reward-list-page.tsx` | `useRewardSearch` | ✅ |
| Reward group settings picker | `reward-group-settings/[id]/reward-group-settings-form.tsx` | `useRewardSearch` | ✅ |
| Campaign reward pickers (referral, lifecycle) | `src/lib/api/campaign-reward-options.ts::listCampaignRewardOptions` | paged, `kind:campaign status:active`, first 100 | ⚠️ partial — see C2 |
| AMP condition builder | `src/components/patterns/amp-condition-builder/actions.ts` | paged, `status:all`, first 100 | ⚠️ partial — see C3 |

---

## C. NOT DONE — in scope of what was approved

### C1. Visual QA + commit (do first)
- [ ] `cd ~/Documents/rocket/loyalty-admin && npm run dev`; walk `/reward-list` (standalone + Shopify surface): search, status filter, category filter, page 2, `tab=campaign`, `tab=groups`, `tab=categories`; deep-link with query string; confirm no full-list call in network tab.
- [ ] Reward detail (`/reward-settings/<id>`): pills show correct Redeemed / Used / Not used for a reward with known ledger rows; skeleton then values; hidden on create + Shopify.
- [ ] Each picker in B5: opens with first page on focus, fuzzy search narrows, "load more" appends, pre-selected value hydrates its label.
- [ ] Home dashboard reward count unchanged vs before.
- [ ] Redeem rules preview shows 5 cards + total.
- [ ] Commit `loyalty-admin` (one commit, e.g. `perf(rewards): server-paginate reward list, lazy reward pickers, detail stats pills`).
- [ ] Commit the two migration files in `supabase-crm` (they are already applied; commit is for the record). Note: current branch is `feat/expiry-reminder-render-cron` — decide whether to commit there or switch to `main` first.

### C2. Campaign reward pickers → true lazy + fuzzy (user asked for it)
- Files: `lifecycle-automations/lifecycle-automation-form.tsx` (lines ~219, ~451), `referral-settings/referral-outcome-cards.tsx` (~182).
- Today: one paged call for first 100 active campaign rewards, no search input. `listCampaignRewardOptions` already accepts `{query, limit}`.
- To do: replace the static `Select` with `RewardSearchCombo` (or `useRewardSearch({kind:'campaign', status:'active'})`), hydrate selected id via `p_ids`.
- Judgment: campaign rewards are per-slot and few; acceptable to keep as-is if the user prefers. Confirm before spending effort.

### C3. AMP condition builder reward options → lazy + fuzzy
- File: `src/components/patterns/amp-condition-builder/actions.ts::fetchAmpEntityOptions` (first 100, `status:'all'`).
- The builder loads all entity option lists (missions, tags, check-ins, rewards) in one server action; rewards is the only one that could exceed 100. To do: switch the reward field to an async combo (same primitive as C2). Lower priority than C2.

### C4. Product-doc closeout (rule `06-product-doc-closeout`, once per thread)
- [ ] `supabase-crm/requirements/Reward.md` — note server pagination, new RPCs, stats moved to detail header; changelog entry.
- [ ] Registry entry for `bff_list_rewards_paged`, `bff_get_reward_redemption_stats`, and the `bff_list_event_promos` rewrite (follow whatever the earn-rules closeout `fc8f855` did today for format).

---

## D. NOT DONE — secondary audit findings (from the same thread, not yet approved to build)

| # | Page / RPC | Finding | Proposed fix | Status |
|---|---|---|---|---|
| D1 | `/referral-settings` | `listReferralLedger({limit:50})` runs on every load even when the ledger tab isn't open (`referral-settings/page.tsx` L15–19) | Gate on `searchParams.tab === 'ledger'`, else pass empty and load client-side on tab switch | not started |
| D2 | Feature-gated routes | Server fetch completes before `FeatureRouteGate` rejects; off-plan merchants pay the fetch | Check entitlement in the server component before the `Promise.all` on expensive pages (reward-list, earn-rules, event-promos) | not started |
| D3 | `bff_admin_get_team` | 285 ms mean × 1.4 k calls; per-member store-scoping check | Low priority — only matters if teams grow; batch the store lookup | deferred (judgment: skip) |
| D4 | pg_stat outliers | `admin_search_members`, `get_entity_history`, `list_receipt_uploads`, `admin_get_consent_config` show high max latency | Not investigated; likely outliers / already paginated. Re-check `pg_stat_statements` after a week of the new code | not started |
| D5 | `/earn-rules` ~10 RPCs per visit | **Done in a parallel thread today** (`loyalty-admin` 36dba80…054eb50, `supabase-crm` e8c7b51 + `earn_rules_uncovered_perf`) | — | done elsewhere |

---

## E. Execution order for the follow-up thread

1. **C1** — run dev, visually verify B2–B5, fix anything broken, commit both repos. This is the only step that must happen before anyone else pulls `main`.
2. **C4** — doc closeout (10 min).
3. **C2** — campaign pickers lazy+fuzzy (ask user first; may be skipped).
4. **D1** — referral-settings ledger gating (small, self-contained, FE only).
5. **C3**, **D2** — only if the user wants to continue.
6. **D4** — revisit `pg_stat_statements` later; no code now.

## F. Verification SQL (paste-ready, read-only)

```sql
-- RPC timings after rollout (expect bff_list_rewards_paged ≪ 100 ms, bff_list_rewards calls → 0 growth)
select (regexp_match(query, '"public"\."(bff_[a-z_]+)"'))[1] as fn, calls,
       round(mean_exec_time) as mean_ms, round(max_exec_time) as max_ms
from pg_stat_statements
where query ilike '%bff_list_rewards%' or query ilike '%bff_get_reward_redemption_stats%'
   or query ilike '%bff_list_event_promos%'
order by mean_exec_time desc;
```
