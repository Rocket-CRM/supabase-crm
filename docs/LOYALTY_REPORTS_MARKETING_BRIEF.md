# Loyalty Reports — Marketing Briefing for Abstracted UI

**Purpose.** Ten admin reports that tell the loyalty program's marketing story. Each report spans one lever (transactions, points, rewards, campaigns, tiers, missions, referrals, vouchers, earn boosts, audiences). Customer-360 / individual profile screens are handled separately and are **out of scope** here.

**How to read this doc.**

- **Why it matters** — the marketing question the report answers.
- **Table** — the row-level list view (fields the admin scans/sorts/filters).
- **Visuals** — 2–4 chart tiles that sit above or beside the table.
- **Filters** — the global filter bar for the page.

All reports share a **date-range picker** and **period-over-period comparison** (vs previous period, vs same period last year). Currency is **points** and **local currency** depending on context. All counts come from `purchase_ledger`, `wallet_ledger`, `reward_redemptions_ledger`, `tier_progress`, and mission/AMP/referral tables described in `requirements/`.

---

## 1. Transactions & Revenue Report

**Why it matters.** Is the program driving incremental spend? Where does it come from?

**Filters.** Channel (`transaction_source`, `api_source`), store, status (`valid` / `refunded` / `pending`), record type (`credit` / `debit`), member tier, persona, tags.

**Visuals.**

- KPI strip: Gross sales, Net sales, Orders, Avg order value, Refund rate, % Sales from members.
- Line chart: Net sales over time, split by channel (online / in-store / Shopify / Lazada / admin).
- Donut: Sales mix by channel and by tier.
- Stacked bar: Top 10 stores or categories by net sales.
- Heatmap: Day-of-week × hour — busiest transaction windows.

**Table — Transactions list.**


| Field               | Source                              |
| ------------------- | ----------------------------------- |
| Transaction ID      | `purchase_ledger.id`                |
| Date / Time         | `created_at`                        |
| Member              | `user_id` → name / tel / tier       |
| Channel             | `transaction_source` + `api_source` |
| Store               | `store_id` → name                   |
| Items (count)       | `purchase_items_ledger` rollup      |
| Gross amount        | `total_amount`                      |
| Discount            | `discount_amount`                   |
| Net amount          | `final_amount`                      |
| Points earned       | `earn_currency`                     |
| Earn factor applied | multiplier label from `earn_factor` |
| Status              | `status` + `record_type`            |
| External ref        | `external_ref` (reconciliation)     |


**Row drill-down.** Line items, earn rules that fired, wallet ledger rows generated, reversal history.

---

## 2. Points Economy & Liability Report

**Why it matters.** Every unredeemed point is a future liability. Marketing needs to see issuance, redemption, expiry and the outstanding balance at a glance.

**Filters.** Period, source type (`purchase`, `campaign`, `referral`, `activity`, `manual`, `mission`, `form`), tier, persona.

**Visuals.**

- KPI strip: Points issued, Points redeemed, Points expired, Net change, **Outstanding liability**, Breakage %.
- Waterfall: Opening balance → issued → redeemed → expired → adjustments → closing.
- Stacked area: Issuance over time by `source_type`.
- Cohort heatmap: Issuance month × % redeemed within 30/60/90/180/365 days.
- Bar: Expiry wall — points expiring in next 7 / 30 / 60 / 90 days.

**Table — Points movement (aggregated).**


| Field                   | Source                                 |
| ----------------------- | -------------------------------------- |
| Period bucket           | day / week / month                     |
| Source type             | `wallet_ledger.source_type`            |
| Issued points           | sum of positive `signed_amount`        |
| Redeemed points         | sum of negative `signed_amount` (burn) |
| Expired points          | rows with expiry processing            |
| Reversed points         | reversal rows                          |
| Unique members affected | count distinct `user_id`               |
| Avg points / member     | calc                                   |


**Secondary table — Expiry watchlist.** Members with ≥ X points expiring in next 30 days, sortable by expiring amount.

---

## 3. Rewards Redemption Report

**Why it matters.** Which rewards pull members in, which ones hoard inventory, and which are costing too many points.

**Filters.** Reward category, visibility (`user` / `admin` / `campaign`), fulfillment status, tier, persona, reward group.

**Visuals.**

- KPI strip: Redemptions, Units redeemed, Points burned, Unique redeemers, Failed attempts, Avg points per redemption.
- Bar (top 20): Redemption count per reward — toggleable to Points burned per reward.
- Line: Redemptions over time by reward category.
- Donut: Redemption mix by fulfillment method (digital / shipping / pickup / printed).
- Funnel: Viewed → Eligible → Attempted → Redeemed → Fulfilled.

**Table — Reward performance.**


| Field                         | Source                                         |
| ----------------------------- | ---------------------------------------------- |
| Reward                        | `reward_master.name` + image                   |
| Category / Tags               | `reward_master`                                |
| Visibility                    | `reward_master.visibility`                     |
| Redemptions                   | `reward_redemptions_ledger` count              |
| Units (qty)                   | sum `qty`                                      |
| Points cost (avg / effective) | avg from `points_calculation`                  |
| Total points burned           | sum `points_deducted`                          |
| Unique redeemers              | distinct `user_id`                             |
| Failure rate                  | failed eligibility / limit / points            |
| Stock remaining               | `reward_master.stock`                          |
| Fulfillment SLA               | avg time to `fulfillment_status = 'fulfilled'` |


**Row drill-down.** Per-reward: redemption trend, demographic breakdown (tier/persona), failure reason breakdown, linked campaign.

---

## 4. Campaign (AMP Workflow) Performance Report

**Why it matters.** Attribution for every automation — did the workflow move points, spend, tier, or retention?

**Filters.** Workflow status (active / paused / draft), trigger type (purchase / wallet / user / schedule), date.

**Visuals.**

- KPI strip: Active workflows, Members enrolled, Actions executed, Points awarded, Messages sent, Estimated attributed revenue.
- Table-embedded sparklines per workflow: enrollments over time.
- Sankey: Workflow step-by-step branch flow (entered → condition A pass → action X, condition A fail → action Y).
- Bar: Action usage mix (`award_points`, `assign_tag`, `assign_persona`, `assign_earn_factor`, `add_to_audience`, messaging).

**Table — Workflow list.**


| Field                | Source                                  |
| -------------------- | --------------------------------------- |
| Workflow name        | `amp_workflow.name`                     |
| Status               | active / paused / draft                 |
| Trigger              | entry condition type                    |
| Enrollments (period) | `amp_workflow_log`                      |
| Completions          | terminal node reached                   |
| Branch win-rate      | % per branch                            |
| Points awarded       | sum from `award_points` nodes           |
| Messages sent        | count                                   |
| Attributed net sales | purchases by enrolled members in window |
| Last run             | `amp_workflow_log.last_executed_at`     |


**Row drill-down.** Node-by-node stats with a mini-canvas preview of the graph.

---

## 5. Tier & Membership Health Report

**Why it matters.** Tier movement is the single biggest indicator of program health and elite-member retention.

**Filters.** Tier, persona, acquisition channel, join cohort (month).

**Visuals.**

- KPI strip: Total members, New members, Active members (period), % at each tier, Avg spend per tier.
- Stacked area: Tier distribution over time.
- Sankey: Tier transitions between period start and period end (upgrades / downgrades / maintained / churned).
- Line: Avg maintenance progress to next tier by segment.
- Bar: Members within 10% / 20% of next-tier threshold (upsell opportunity).

**Table — Tier movement ledger.**


| Field               | Source                                     |
| ------------------- | ------------------------------------------ |
| Date                | `tier_change_ledger.created_at`            |
| Member              | `user_id`                                  |
| From tier → To tier | `previous_tier` / `new_tier`               |
| Reason              | upgrade / maintenance / downgrade / manual |
| Qualifying spend    | tier window sales                          |
| Qualifying orders   | tier window orders                         |
| Next deadline       | `tier_progress.maintain_deadline`          |


**Secondary table — Tier benefit utilization.** Per-tier: avg earn multiplier used, exclusive rewards redeemed, welcome gifts issued.

---

## 6. Missions & Gamification Report

**Why it matters.** Missions are behavioral nudges — completion rate tells you whether the program is actually changing behavior.

**Filters.** Mission type (purchase / wallet earn / form), activation (manual / auto), status, tier, persona.

**Visuals.**

- KPI strip: Active missions, Enrollments, Completion rate, Claim rate, Avg time-to-complete, Points awarded.
- Bar (top 10): Missions by completion rate.
- Funnel: Enrolled → In progress → Completed → Claimed.
- Line: Completions over time, split by mission.
- Heatmap: Condition type × completion rate (purchase vs earn source vs form).

**Table — Mission performance.**


| Field                | Source                               |
| -------------------- | ------------------------------------ |
| Mission              | `mission_master.name`                |
| Type                 | purchase / wallet earn / form        |
| Activation           | manual / auto                        |
| Period               | start / end                          |
| Enrolled             | distinct users in `mission_progress` |
| Completed            | `mission_log_completion`             |
| Completion %         | calc                                 |
| Claimed              | outcomes claimed                     |
| Unclaimed            | completed − claimed                  |
| Avg time to complete | median duration                      |
| Outcome payout       | points / tickets / tag / earn factor |


**Row drill-down.** Condition-level progress distribution, segment that completes fastest.

---

## 7. Referral Program Report

**Why it matters.** Cheapest acquisition channel in the program — needs its own dashboard to prove it.

**Filters.** Period, referrer tier, referee channel.

**Visuals.**

- KPI strip: Unique referrers, Successful referrals, Referral → member conversion, Referral-attributed sales, Referral points awarded, Avg LTV of referred members.
- Funnel: Shared → Clicked → Signed up → First purchase → Repeat purchase.
- Bar: Top 20 referrers by successful referrals.
- Line: Referral signups over time.
- Map / region bar (if geo available).

**Table — Referral ledger.**


| Field                     | Source                                      |
| ------------------------- | ------------------------------------------- |
| Referral ID               | `referral_ledger.id`                        |
| Referrer                  | `referrer_user_id`                          |
| Referee                   | `referee_user_id`                           |
| Shared on                 | share channel                               |
| Status                    | invited / signed-up / qualified / rewarded  |
| Qualifying event          | first purchase / signup / custom            |
| Points awarded (referrer) | from `wallet_ledger source_type='referral'` |
| Points awarded (referee)  | same                                        |
| Referee LTV (30/90/365d)  | purchases rollup                            |


**Secondary table — Top referrers leaderboard.**

---

## 8. Promo Code & Voucher Report

**Why it matters.** Finance wants to know: how much inventory is outstanding, how fast is it moving, and which partners are performing.

**Filters.** Reward, batch, partner / merchant, status (available / assigned / redeemed / expired).

**Visuals.**

- KPI strip: Total codes, Available, Assigned, Redeemed, Expired, Redemption rate.
- Stacked bar: Per-reward code pool — available vs redeemed vs expired.
- Line: Redemption velocity (codes redeemed per day).
- Bar: Top partners / merchants by code volume and redemption %.

**Table — Code batch list.**


| Field              | Source                       |
| ------------------ | ---------------------------- |
| Batch / lot        | `reward_promo_code.batch_id` |
| Reward             | `reward_master.name`         |
| Partner / merchant | `partner_merchant`           |
| Uploaded           | batch created_at             |
| Total codes        | count                        |
| Available          | unassigned                   |
| Assigned           | assigned but not used        |
| Redeemed           | used_at is not null          |
| Expired            | past expiry                  |
| Redemption %       | calc                         |


**Secondary view — Individual code search.** Quick find by code string for CS handoff.

---

## 9. Earn Factor (Boost) Effectiveness Report

**Why it matters.** Bonus-points campaigns are expensive. Marketing needs to prove the multiplier actually caused incremental purchases.

**Filters.** Earn factor, tier, persona, store, category.

**Visuals.**

- KPI strip: Active factors, Members eligible, Transactions boosted, Base points, Bonus points paid, % sales lifted vs control.
- Bar: Each earn factor — bonus points issued vs incremental sales attributed.
- Line: Spend per eligible member — pre / during / post boost window.
- Scatter: Bonus cost (points × value) vs incremental net sales per campaign.

**Table — Earn factor list.**


| Field                | Source                           |
| -------------------- | -------------------------------- |
| Earn factor name     | `earn_factor.name`               |
| Type                 | global / targeted / group        |
| Multiplier / bonus   | definition                       |
| Window               | start → end                      |
| Eligible members     | `mv_earn_factor_users` count     |
| Transactions applied | `purchase_ledger` with factor id |
| Base points issued   | sum                              |
| Bonus points issued  | sum                              |
| Net sales in window  | sum                              |
| Lift vs control      | calc                             |


---

## 10. Audience & Segment Performance Report

**Why it matters.** Personas, tags, and AMP audiences are how marketing targets campaigns — this report shows whether those segments are actually behaving differently.

**Filters.** Segment type (persona / tag / audience), specific segment, date.

**Visuals.**

- KPI strip (per selected segment): Members, Active %, Avg AOV, Avg orders, Points earned, Points redeemed, Reward redemptions, CSAT (if available).
- Comparison bar: Selected segment vs All members for 6 key metrics.
- Line: Segment size over time (joins / exits).
- Matrix: Segments × top rewards redeemed (which segment loves which reward).
- Bubble: Segment size (x) vs avg LTV (y) vs redemption rate (bubble size).

**Table — Segment roster.**


| Field                 | Source                                         |
| --------------------- | ---------------------------------------------- |
| Segment               | persona / tag / audience name                  |
| Type                  | persona / tag / audience                       |
| Members               | count                                          |
| Net change (period)   | new − removed                                  |
| Avg AOV               | calc                                           |
| Avg orders            | calc                                           |
| Total points earned   | calc                                           |
| Total points redeemed | calc                                           |
| Top reward            | top by qty                                     |
| Driving workflow      | AMP workflow that adds to this segment, if any |


**Row drill-down.** Member list with standard columns (for handoff), plus a "Compare to another segment" button.

---

## Shared design notes for the UI team

- **Layout pattern.** Every report = Filter bar → KPI strip → 2–4 charts → Data table → Row drill-down drawer. Keep the pattern consistent across all 10.
- **Charting.** ECharts (already in the project). Prefer small multiples over one crowded chart.
- **Export.** Every table needs CSV / XLSX export and "Save as segment" where relevant.
- **Empty states.** Each report should show a one-sentence marketing definition at the top when no data has loaded yet (useful for first-time users and demo screenshots).
- **Demo mode.** Seed each report with realistic values so slides and stakeholder walkthroughs work without a live merchant.

---

## Visual Style — Follow Shopify Polaris

For these mockups to feel like the real admin product, follow **Shopify Polaris v13** as closely as possible. A reference image of the current admin is attached separately — use it as the visual ground truth when the Polaris spec and the image disagree (the image wins).

**Polaris look & feel in one paragraph.** Clean, neutral, content-forward. White `Page` background, subtle grey app chrome (`--p-color-bg-surface-secondary`), generous whitespace, 4px radius on cards/tables/buttons, soft 1px hairline borders (`--p-color-border`) instead of heavy shadows. Typography is Inter-based: `headingLg` for page titles, `headingMd` for card titles, `bodyMd` for table content, `bodySm` + subdued tone for helper text. Colors are muted; the saturated colors are reserved for status (`Badge` tones: `success`, `info`, `warning`, `critical`, `attention`) and for the single action accent. Primary buttons use Polaris' dark charcoal primary, destructive uses critical red, everything else is plain. No custom drop-shadows, no gradients, no emoji icons — use `@shopify/polaris-icons` only.

**Page scaffolding (apply to every report page).**

- `Page` with `title`, `subtitle`, `primaryAction` (e.g. "Export"), `secondaryActions` (e.g. "Schedule", "Create segment"), and `backAction` if nested.
- `Layout` + `Layout.Section` for vertical stacking, `InlineGrid` / `BlockStack` / `InlineStack` for internal spacing (gap tokens: `200` / `300` / `400`).
- `Card` (with optional `Text` title + `ButtonGroup` in the header) wraps every distinct block — the filter bar is a `Card`, each chart is a `Card`, the table is a `Card`.

**Component primitives to try first.**


| Block                          | Polaris primitives                                                                                                                       |
| ------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------- |
| Filter bar                     | `Filters` (with `ChoiceList`, `RangeSlider`, date pickers via `Popover` + `DatePicker`), or `IndexFilters` when bolted onto `IndexTable` |
| KPI tile                       | `Card` + `BlockStack` + `Text variant="headingLg"` for value + `Text tone="subdued"` for label + small `Badge` for trend                 |
| Data table                     | `IndexTable` for clickable row lists (has selection, sticky header, bulk actions). `DataTable` for dense numeric tables.                 |
| Row drill-down                 | `Modal` (large) or `Sheet` / side-`Drawer` pattern via `Modal` large variant — use whichever the repo already standardises on            |
| Status chips                   | `Badge` with tones                                                                                                                       |
| Links / member names           | `Link` (monochrome) — not blue                                                                                                           |
| Buttons                        | `Button`, `ButtonGroup`; primary only for the single hero action per page                                                                |
| Empty / loading states         | `EmptyState`, `SkeletonBodyText`, `SkeletonDisplayText`, `Spinner`                                                                       |
| Tooltips & help                | `Tooltip`, `Popover`, `HelpText`                                                                                                         |
| Tabs (for report sub-sections) | `Tabs`                                                                                                                                   |
| Pagination                     | `Pagination` (plain, inline below table)                                                                                                 |
| Toast feedback                 | `Frame` + `Toast`                                                                                                                        |


**Extending Polaris.** Use **existing primitives and props wherever they cover the need** — do not restyle them. If a block genuinely isn't covered (e.g. "KPI stat card with sparkline", "Sankey workflow preview", "Segment-vs-all comparison bar"), **propose a new primitive** rather than inlining bespoke JSX. Each new primitive proposal should include:

1. Name (e.g. `StatCard`, `TrendBadge`, `ComparisonBar`, `WorkflowGraphPreview`).
2. Which Polaris primitives it composes (so it still inherits tokens and tone).
3. Props API and default slot behaviour.
4. The report(s) it's used on.

List all proposed new primitives in a **"New primitives needed"** section of the mockup deliverable so the design-system team can review and promote them to the shared library.

**Charts within Polaris.** ECharts renders inside `Card`. Use Polaris color tokens for axes, gridlines, and legend text (`--p-color-text-subdued`, `--p-color-border-subdued`). Use a small Polaris-flavoured categorical palette (charcoal primary + muted secondaries); reserve red strictly for negative / critical trends. No chart titles inside the chart — let the `Card` header own the title.