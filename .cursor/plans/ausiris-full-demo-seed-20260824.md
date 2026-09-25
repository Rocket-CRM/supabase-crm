# Ausiris full demo seed — execution plan

**For:** a fresh thread that generates data on merchant **Ausiris**.  
**Not for:** `rocket-demo` (`fae172a5-de90-440e-a766-db6a5982cc9b`) and **not** the July 28-member `SEED-AUS` on New CRM (`09b45463-3812-42fb-9c7f-9d43b6fd3eb9`).

**Date:** 2026-08-24. **Demo:** tomorrow. **Approval required** before any writes.

---

## Verdict

**One-shot SQL** against Ausiris: insert masters, then people, then dated ledgers with FKs, then run the platform’s existing recompute RPCs. Copy rocket-demo’s *order of work* only. **Do not** add a generator product, Postgres function family, or cron.

Target merchant already exists and is almost empty: **7 rewards + 3 tiers + 1 test user**. Sales rewards stay. Tiers are already Silver / Gold / Platinum — keep them. Create catalog, stores, personas, 10,000 members over 6 months, linked purchases/wallet/activities/missions, then run RFM / funnel / attribution / AMP reconcile.

---

## Locked merchant

| Field | Value |
|---|---|
| Name | Ausiris |
| `merchant_code` | `ausiris` |
| `merchant_id` | `b7794d29-2df7-47e2-a707-5654fe9f71c4` |
| Created | 2026-08-22 |
| Existing rewards | 7 (keep; fill missing points conditions) |
| Existing tiers | Silver, Gold, Platinum (`user_type=buyer`) |
| Existing members | 1 test user `rk / test rk` (`nantharat@rocket.in.th`) — **do not delete** |
| Products / purchases / wallet / activities / missions / mkt / funnel / RFM / AMP | all **0** |

Cleanup key for anything we insert: `metadata.seed = 'SEED-AUS-V2'` and/or `external_ref LIKE 'AUSV2-%'`. **Do not** put `SEED-` in customer-visible names, member codes, SKU names, or campaign titles.

---

## What to borrow from rocket-demo (sequence only)

From `demo/rocket-demo/` — **pattern**, not code copy-paste onto this merchant.

1. **Masters first.** Tiers/stores/products/earn exist before any purchase row. Missions/personas/tags after catalog (missions filter `product_ids` / `category_ids`).
2. **People second.** Signup date is the left edge of that person’s ledger. `fn_ensure_member_code` after insert. Wallet row at 0.
3. **Archetypes drive propensity**, not random uniform buys. Decay after signup; win-back bump at 45–90 days; payday/weekend/campaign boosts.
4. **Line items before header totals.** `purchase_items_ledger.sku_id` → `product_sku_master`. Header `final_amount` = sum of lines.
5. **Wallet after purchase.** Backfill: insert `wallet_ledger` + roll `user_wallet` (do **not** call `chokepoint_post_wallet_transaction` 10k times). Rate: **1 point / ฿10**.
6. **Engagement ledgers last**, then **recompute** (RFM, funnel, AMP, marketing attribution). Historical mission progress is **inserted** to match purchases — routers will not replay 6 months.
7. **Thai identity.** Combinatorial given × surname pools; unique `tel`; romanized `fullname`; nickname in `fullname` as `ชื่อ นามสกุล (ชื่อเล่น)`.
8. **`skip_cdc = true`** on bulk member/purchase/wallet inserts.

**Do not borrow:** `custom_internal_demo_*` (hard-locked to rocket-demo), skincare SKUs, 10s `pg_sleep` day loop, daily cron, `SEED-RKT` labels, Member/Ultra tier, 28-person New CRM seed.

**Where the SQL lives:** `demo/ausiris-demo/` as **plain scripts** the next thread runs once via Supabase MCP `execute_sql`. No `custom_ausiris_demo_*` functions. No cron. After the rows exist, the scripts can sit in the repo as a paper trail; they are not a daily engine.

---

## Types (create in this order)

1. **Merchant config** — locale TH/THB, earn 1pt/฿10, RFM on purchase, funnel 5 stages, mkt `u_shape` / 30d lookback.
2. **Catalog** — brand → category → product → SKU. Physical (bar, jewelry, silver) **and** trading (spot gold, ออมทอง plans as SKUs).
3. **Places / channels** — `store_master` rows for POS, vending, app, web, marketplace. Purchases stamp `store_id` + `store_code`.
4. **Loyalty masters** — keep 3 tiers; add personas + tags; attach `reward_points_conditions` to the **existing** 7 rewards.
5. **Engagement masters** — custom activity types, marketing campaigns + identifiers, missions (product-filtered), native leaderboard views, campaign-activity grouping, funnel, AMP audiences.
6. **Member** — `user_accounts` with write-once acquisition, LINE on most, persona, tier, consents.
7. **Purchase** — `purchase_ledger` + `purchase_items_ledger` (SKU FK). Not copied onto `activity_ledger`.
8. **Activity** — CDP events via `fn_log_user_activity` / batched insert matching that shape. Purchases stay out.
9. **Wallet** — earn (`source_type=purchase` or `activity`) and burn (`reward_redemption`). Running balance matches 360 header.
10. **Redemption** — `reward_redemptions_ledger` against **existing** reward ids.
11. **Mission / leaderboard facts** — progress + completions consistent with purchases; leaderboard views read purchases.
12. **Derived** — `rfm_user_score`, funnel membership, `mkt_purchase_attribution`, `amp_audience_member`.

---

## Volume (10,000 members / 6 months)

Anchor **today = seed date**. Window: `current_date - 180` → `current_date`.

Signup curve (same idea as rocket-demo `target_members`): start ~12% of 10k by day 0 of the window, reach 10,000 on the last day. Payday (25th–month-end) and campaign windows accelerate both signups and buys.

| Entity | Target | Why |
|---|---|---|
| Members | **10,000** | User override of the brief’s 28–40 |
| Buyers (ever purchased) | ~5,800 (58%) | Leaves unpaid leads for funnel + high-intent AMP |
| Purchases | ~14,000–16,000 | ~2.5 per buyer; Champions 8–20; savers monthly DCA |
| Purchase line items | ~18,000–22,000 | 1–3 SKUs; trading often 1 line |
| Activities | ~55,000–70,000 | Dense on VIP + unpaid; almost none on Lost |
| Wallet earns | ~1 per purchase + ~8k engagement bonuses | 360 wallet story |
| Wallet burns / redemptions | ~1,200 members, ~1,500 rows | Catalog + first-trade discount |
| Mission completions | enough that grouping reports are non-empty | Product-scoped goals |
| Marketing campaigns | 9 (mixed ROI) | Attribution + exec ROI |
| Grouping campaigns | 4 objectives | Mission/reward ROI by objective |
| Named 360 tour members | 12 | Talk track; one **canonical** extra-dense |

RFM after compute must be **non-empty in every default segment** (Champions … Lost + Regulars). Funnel all 5 stages non-empty, latest-stage-wins (Program Member leaves Repeat).

---

## Archetypes (statistical 10k)

Assign at signup. Weights must sum to 1. Purchases/activities are drawn from these, **then** RFM/funnel are computed — do not stamp RFM by hand except as a post-check on named people.

| Code | Weight | Line mix | Recency intent | Tier bias | Funnel landing |
|---|---|---|---|---|---|
| `whale_trader` | 6% | spot gold heavy | last 14d | Platinum | Repeat / Program |
| `loyal_saver` | 18% | ออมทอง monthly | last 20d | Gold | Program |
| `bar_shopper` | 14% | 1g/5g/ทองเล็ก | last 45d | Silver–Gold | Repeat |
| `jewelry_gifter` | 12% | Iris SKUs, campaign-tied | last 60d | Silver–Gold | First / Repeat |
| `cooling_vip` | 8% | old high spot | last buy 45–90d | Gold/Platinum lag | Repeat (not Program if quiet) |
| `hibernating` | 10% | old mixed | last buy >180d | Silver | old stage honest |
| `high_intent_unpaid` | 12% | **zero purchases** | gold_price_view 7d | Silver | Engaged |
| `new_lead` | 10% | signup ≤14d | campaign_touch only | Silver | Lead |
| `first_purchase` | 8% | 1 saving or bar 14–28d ago | browsing after | Silver | First Purchase |
| `omni_program` | 2% | saving + bar + POS/vending | last 21d | Gold+ | Program |

Tier assignment **after** 6-month spend (not at signup):

| 6-month qualifying spend | Tier |
|---|---|
| ≥ ฿500,000 | Platinum |
| ≥ ฿80,000 | Gold |
| else | Silver (entry) |

Status may lag RFM on `cooling_vip` (Platinum + At Risk) — that is the win-back talk track.

---

## Catalog (must exist before purchases)

### Brands

`Ausiris` · `Ausiris Next` · `My Gold Plus` · `Iris Jewel` · `Ausiris Express`

### Categories (line of business)

| Category | What it is |
|---|---|
| `Gold Trading` | Spot buy/sell summaries (not a full trading ledger) |
| `Gold Saving` | DCA / lump ออมทอง |
| `Gold Bar` | ทองแท่ง / ทองเล็ก |
| `Silver` | Silver bar / coin |
| `Jewelry` | Iris fashion / gift |

### SKUs (codes must look operational)

Trading (amounts are **THB order notional** typical of a summary ingest):

- `AUS-SPOT-965-025B` ทอง 96.5% 0.25 บาท  
- `AUS-SPOT-965-050B` 0.50 บาท  
- `AUS-SPOT-965-1B` 1 บาท  
- `AUS-SPOT-965-2B` 2 บาท  
- `AUS-SPOT-999-1B` ทอง 99.99% 1 บาท  

Saving:

- `AUS-SAVE-DCA-500` ออมทองรายเดือน ฿500  
- `AUS-SAVE-DCA-1000` ฿1,000  
- `AUS-SAVE-DCA-3000` ฿3,000  
- `AUS-SAVE-LUMP-10K` ออมก้อน ฿10,000  
- `AUS-SAVE-LUMP-50K` ฿50,000  

Physical gold:

- `AUS-BAR-1G` · `AUS-BAR-5G` · `AUS-BAR-1SL` (1 สลึง) · `AUS-BAR-1B` (1 บาท) · `AUS-BAR-2B`

Silver:

- `AUS-SLV-BAR-10G` · `AUS-SLV-BAR-1KG` · `AUS-SLV-COIN-1OZ`

Jewelry (Iris):

- `IRIS-NL-MOTHER` สร้อย Mother’s Day  
- `IRIS-RG-MINI` แหวนมินิมอล  
- `IRIS-BR-LIVE` กำไล Live drop  
- `IRIS-ER-GIFT` ต่างหูของขวัญ  
- `IRIS-NL-DAILY` สร้อยใส่ทุกวัน  

Prices: bars/jewelry realistic THB; saving SKUs = plan amount; spot SKUs = typical notional (hundreds of thousands for 1 บาท).

### Stores / channels (`store_master`)

| `store_code` | Name | Used by |
|---|---|---|
| `AUS-NEXT-APP` | Ausiris Next | spot_gold |
| `AUS-PLUS-APP` | My Gold Plus | gold_saving |
| `AUS-EXPRESS-WEB` | Ausiris Express | small bar |
| `AUS-POS-SILOM` | Ausiris Gold Silom | POS gold |
| `AUS-POS-SIAM` | Ausiris Gold Siam | POS gold |
| `AUS-POS-CNX` | Ausiris Gold Chiang Mai | POS gold |
| `AUS-POS-SLV-TDP` | Ausiris Silver True Digital Park | silver POS |
| `AUS-VD-TDP` | Ausiris Vending True Digital Park | vending |
| `AUS-SHOPEE` · `AUS-LAZADA` · `AUS-TIKTOK` | marketplace | bars / jewelry |
| `AUS-IRIS-LIVE` | Iris Jewel Live | jewelry |

Purchase `transaction_source` / metadata `line_of_business`: `spot_gold` \| `gold_saving` \| `small_bar` \| `jewelry` \| `silver`.

---

## Rewards (existing — do not recreate)

Merchant already has:

| Name | Role in demo |
|---|---|
| ส่วนลด 50% สำหรับผู้ใช้ครั้งแรก | In-house first-trade / fee-style privilege (stand-in for brief `FEE_DISC_50`) |
| Lazada E-Voucher 20 บาท | Catalog |
| Central E-Voucher 50 บาท | Catalog |
| Starbucks E-Voucher 50 บาท | Catalog |
| Shopee E-Voucher 20 บาท | Catalog |
| E-Coupon มูลค่า 100 บาท | Catalog |
| Stamping 200+ Credit | Saving / stamp story |

**Gap:** `reward_points_conditions` are empty. Before any burn, upsert conditions (suggested): Shopee/Lazada 200 pts, Starbucks/Central 500, E-Coupon 800, Stamping 300, First-trade 50% 1,500. Do not invent a parallel catalog.

Burns: `redeem_reward_with_points` is **live** and slow — for 1,500 historical rows insert `reward_redemptions_ledger` + matching `wallet_ledger` burn, `skip_cdc=true`, then recompute `user_wallet`.

---

## Personas and tags

**Persona group:** `Ausiris Customers`

| Persona | Code | Who |
|---|---|---|
| Gold Trader | `aus-trader` | Next / spot |
| Gold Saver | `aus-saver` | My Gold Plus |
| Bar & Gift | `aus-bar` | Express / marketplace ทองเล็ก |
| Jewelry | `aus-jewel` | Iris |
| Lapsed Investor | `aus-lapsed` | cooling / hibernating |

Tags (internal, not `SEED-` in the visible name): `VIP Trader`, `New Member`, `At Risk`, `Saver Streak`, `App Engager`, `Marketplace Shopper`.

---

## Identity and names

- `firstname` / `lastname`: Thai official name.  
- `fullname`: `FirstnameEN LastnameEN (Nickname)` e.g. `Thanawat Sukkasem (Ton)`.  
- Nickname pool separate from given names (ต้น, มิ้น, บอล, เจน, โอ๊ค, เฟิร์น, …).  
- Mix: ~55% Thai-script primary, some English-given + Thai surname, some nicknames-only display in fullname.  
- Unique `tel` (`08xxxxxxxx` / `06xxxxxxxx` / `09xxxxxxxx`).  
- `member_code` via `fn_ensure_member_code` (real-looking, not `DEMO-AUS-001`).  
- LINE on ~75%. Email on ~40%. Birth month on ~30% (birthday AMP).  
- PDPA: `channel_line` / `channel_email` true on people AMP will “send” to.  
- Acquisition write-once: `acquisition_source`, UTM set, `acquisition_campaign_id`, `acquired_at = created_at`.  
- Hidden: `metadata.seed='SEED-AUS-V2'`, `metadata.archetype`, `skip_cdc=true`.

Reuse and **extend** rocket-demo given/surname pools (`demo/rocket-demo/config/01_pools.sql`) plus nicknames. Combinatorial 80×80 is enough for 10k without collision if you also mix middle digits of tel.

Preserve the existing test account.

---

## Named tour members (hand-authored, extra history)

Create **after** the 10k generator (or reserved ids inside it) so phones are stable for the talk track.

| # | Role | Must show on 360 |
|---|---|---|
| **C0 Canonical** | Omni Program + Champion | All activity types, saving + bar + one POS or vending, earn **and** burn, first-trade 50% **used**, 2 attributed campaigns, Gold+, LINE+email, dense 6-month timeline |
| C1 | Champion VIP trader | Many `gold_price_view` + spot purchases; Platinum; fee-style redeem used on a later spot order |
| C2 | Loyal saver | 6× monthly `AUS-SAVE-DCA-*` + `savings_deposit_confirm` + ออมต่อเนื่อง mission |
| C3 | Bar / Tonglek | Express or Shopee bars + mission_progress + Shopee voucher redeem |
| C4 | Jewelry / Mothers Day | Iris SKU + FB campaign_touch + attributed purchase |
| C5 | Cooling VIP | High old M, last buy 60d, recent price views, **unused** first-trade reward |
| C6 | Recovered At Risk | Same as C5 **plus** one Email/LINE win-back attributed buy |
| C7 | Hibernating | Last buy ~200d, almost no activities |
| C8 | High-intent unpaid | Price views + alert, **zero** purchases, **zero** purchase-earns |
| C9 | Welcome lead | ≤10d, TikTok/FB touch + LINE add, maybe KYC only |
| C10 | First purchase | One bar/saving 3 weeks ago |
| C11 | Silver POS walk-in | TDP silver or vending_dispense |

Pick **one stable phone for C0** (do not reuse 0800000002 if it still lives on New CRM — generate a fresh memorable number e.g. `0812345678` and print it in the run report).

C0 gets extra: campaign_touch on 3 campaigns, mission complete + in-progress, leaderboard-visible spend, both partner + in-house redemption, mixed channels.

---

## CDP activity types

Keep platform: `page_view`, `link_click`, `campaign_touch`.

Add Ausiris customs (`activity_type_master.merchant_id = ausiris`):

| Code | Properties (minimum) |
|---|---|
| `gold_price_view` | `metal`, `duration_sec`, `page_path` |
| `price_alert_subscribe` | `metal`, `threshold_thb` |
| `kyc_complete` | `method` |
| `savings_deposit_confirm` | `month`, `amount_thb`, `sku_code` |
| `mission_progress` | `mission_code`, `step` |
| `vending_dispense` | `location` |
| `workshop_rsvp` | `event_name` |

`page_path` examples: `/gold-price`, `/saving/dca`, `/express/bar-1g`, `/jewel/pdp`.

Stamp `mkt_campaign_id` + UTM on `campaign_touch` and on **purchases** (metadata / identifier fields the attribution job reads). Do **not** insert a `purchase` activity.

Write path: `fn_log_user_activity` if `p_occurred_at` can be historical; else batch insert into `activity_ledger` with the same columns that function writes (`properties` typed, `source='seed'`).

---

## Marketing campaigns (ROI objects)

9 flights across 6 months. Identifiers: `utm_campaign` + LINE param. Windows overlap lookback 30d. Budgets in THB.

| Code (hidden) | Visible name | Channel | Intent | ROI story |
|---|---|---|---|---|
| `aus-line-gold` | LINE Gold Saving Push | line | conversion / saving | **Strong** |
| `aus-fb-mother` | Facebook Mother's Day Gold | facebook | jewelry | **Strong** |
| `aus-g-brand` | Google Brand Ausiris | google | trading acquire | Strong |
| `aus-email-wb` | Email Win-back Investors | email | win-back | Medium |
| `aus-ws-series` | Gold Workshop Series | event | education | Medium |
| `aus-tt-teaser` | TikTok Gold Teaser | tiktok | cheap leads | **Weak** (high budget, low attributed rev) |
| `aus-line-bar` | LINE ทองเล็ก Express | line | bar | Strong |
| `aus-tt-live` | TikTok Iris Live | tiktok | jewelry | Medium |
| `aus-pay-day` | Payday Gold Top-up | line | saving | Strong |

Attribution: `mkt_config` `u_shape`, 30 days. After purchases, `SELECT fn_mkt_compute_purchase_attribution();` (merchant-scoped if the fn allows; otherwise run and accept it computes all active merchants).

---

## Missions (product as goal, points/rewards as outcome)

Create with `bff_upsert_mission`. `condition_type=purchase`, filters on `category_ids` / `sku_ids`. Outcomes: points and/or **existing** reward id.

| Mission | Goal | Outcome | Objective bucket |
|---|---|---|---|
| ออมต่อเนื่อง 3 เดือน | 3× `Gold Saving` count | 300 pts + Stamping reward | Retention |
| ทองเล็กสะสม | 2× `AUS-BAR-1G` or `AUS-BAR-5G` | 150 pts + Shopee voucher | Product push — bar |
| นักลงทุนเริ่มต้น | 1× `Gold Trading` | 200 pts + first-trade 50% | Acquisition / first trade |
| ซื้อทองครบ 1 บาท | sum `Gold Bar` ≥ 1 บาท notional (or ฿50k) | 400 pts | Product push — bar |
| ของขวัญ Iris | 1× `Jewelry` | 100 pts + E-Coupon 100 | Product push — jewelry |
| ข้ามไลน์ (ออม+แท่ง) | saving AND bar (standard AND) | 250 pts | Cross-sell |
| Milestone ยอดซื้อ | spend ฿10k / ฿50k / ฿200k | 50 / 200 / 1,000 pts | Loyalty spend |
| เงินเดือนออม | 1× DCA in calendar month, repeatable | 80 pts | Retention |

Then **backfill** `mission_progress` / completions / outcome wallet rows so they match actual SKU purchases. Refresh `refresh_mission_conditions_mv()` after insert.

---

## Leaderboards (native)

Create two views **with `merchant_id`**, names:

- `v_lb_ausiris_gold_spend` — 180d completed purchase `final_amount` where category Gold Trading **or** Gold Bar  
- `v_lb_ausiris_saving_streak` — count of Gold Saving purchases 180d  

Register via `bff_upsert_leaderboard_campaign`. `source_kind=native`, `path` e.g. `ausiris-gold-ranking`, `top_x=20`, `user_key_field=user_id`. C0 and whale_traders must appear in the gold board; loyal_savers on the saving board.

---

## Campaign activity grouping (objective / ROI reports)

Four **grouping** campaigns (`campaign` + `campaign_activity` + `campaign_mapping`) — not `mkt_campaign` and not `campaign_master`.

| Grouping campaign | Activities | Map to |
|---|---|---|
| หาลูกค้าใหม่ | First trade mission, TikTok teaser, Google brand (mission + rewards used as welcome) | `นักลงทุนเริ่มต้น`, first-trade 50% reward |
| รักษาลูกค้าออมทอง | Saving streak mission, payday mission, Stamping reward | ออมต่อเนื่อง, เงินเดือนออม, Stamping |
| ดันสินค้าแท่งและจิวเวล | Bar + jewelry missions, Shopee/E-Coupon rewards | ทองเล็ก, ของขวัญ Iris, Shopee, E-Coupon |
| วินแบ็คและ VIP | Workshop RSVP mission if any, Central/Starbucks as VIP perk | Milestone spend, Central, Starbucks |

Use `bff_upsert_campaign`. Each real mission/reward maps to **one** activity only.

---

## Funnel, RFM, AMP

**Funnel** `Ausiris Gold Customer Journey` — latest-stage-wins:

1. Lead — has account  
2. Engaged — `gold_price_view` or `page_view` in 30d  
3. First Purchase — ≥1 completed purchase  
4. Repeat Buyer — ≥2 purchases  
5. Program Member — Gold Saving purchase **or** mission complete **or** Gold+ tier  

**RFM** `bff_upsert_rfm_settings` recency=purchase, 12-month window, default segment map, then `fn_rfm_compute_scores('b7794d29-2df7-47e2-a707-5654fe9f71c4')`.

**AMP audiences** via `bff_create_audience` (rule-only, count > 0):

| Audience | Rule intent |
|---|---|
| VIP exclusive | RFM Champions OR Platinum |
| Savers special | Program Member + saving purchase 90d |
| Bar / mission | mission_progress 60d OR small_bar 60d |
| Jewelry 30d | jewelry purchase or Iris campaign_touch 30d |
| Win-back | RFM At Risk |
| Reactivation | Hibernating OR Lost |
| High-intent unpaid | gold_price_view 7d AND no purchases |
| Welcome | Funnel Lead AND created ≤14d |
| Convert to repeat | Funnel First Purchase |

Optional: one workflow each for VIP / special offer / win-back **if** time; membership + last activity is enough without live LINE send.

---

## Earn studio

`create_complete_earn_factor_setup` for Ausiris:

- Base rate 10 THB = 1 point, all 3 tiers  
- Gold+ multiplier 1.5×  
- Optional weekend multiplier on Jewelry + Gold Bar  

Historical wallet earns still written at 1pt/฿10 **net** so 360 balances look consistent even if live earn graph is richer going forward.

---

## How the one-shot is run (not a new tool)

There is **no new Cursor tool, MCP server, or daily job**. The next thread writes INSERT/SELECT SQL and executes it once against project `wkevmsedchftztoolkmi`.

Rocket-demo wrapped the same idea in `custom_internal_demo_*` **plus a nightly cron** so that merchant keeps growing. Ausiris does not need that. 10k members × 6 months is a **single backfill**.

Scripts under `demo/ausiris-demo/` (run in order, once):

| File | Does |
|---|---|
| `01_masters.sql` | stores, brands, categories, products, SKUs, earn, activity types, personas, tags, reward points conditions, mkt campaigns, funnel, rfm config |
| `02_engagement.sql` | missions, leaderboard views + campaigns, grouping campaigns, AMP audiences |
| `03_members.sql` | 10k `user_accounts` + wallets + codes + acquisition (`generate_series`) |
| `04_ledgers.sql` | purchases+items, activities, wallet earn, redemptions, mission progress |
| `05_named_tour.sql` | C0–C11 extra rows |
| `06_recompute.sql` | call **existing** RPCs: RFM, funnel, AMP, mkt attribution, mission MV |
| `07_verify.sql` | blocking checklist |

If a statement is too large for one MCP call, split batches (e.g. members 1–2500, 2501–5000). That is still one shot, not a platform.

Do **not** `CREATE FUNCTION custom_ausiris_demo_*`. Do **not** register pg_cron. Temporary `DO $$ … $$` blocks inside a script are fine.

Idempotent enough to retry: delete prior `SEED-AUS-V2` facts (not sales rewards) then re-insert. Never `DELETE FROM reward_master`. Never touch other merchants.

**Do not** loop 180 days with pause. Use set-based inserts:

- members: `generate_series(1,10000)` + hash for names/dates
- purchases/activities: member × day where `hash(user,day) < propensity`

Deterministic `md5(user_id || day || salt)` so a retry is stable.

---

## Process (actors)

1. **Human** — approve writes on live Ausiris (this clarification already does).  
2. **Agent** — write the SQL files, execute them once via MCP `execute_sql`, in the file order above.  
3. **Platform** — existing RPCs only (`fn_rfm_compute_scores`, funnel reconcile, AMP reconcile, `fn_mkt_compute_purchase_attribution`).  
4. **Agent** — run verify queries.  
5. **Human** — walk admin: campaigns ROI → funnel → RFM → C0 360 → C8 unpaid → AMP counts.

---

## Write-path rules (do not violate)

| Fact | How |
|---|---|
| Members | `INSERT user_accounts` + `fn_ensure_member_code` + `user_wallet` 0. No Auth users. |
| Purchases | Insert ledger + items with real `sku_id`. Optional `bulk_insert_purchases_with_items` if it honors historical `completed_at` and `skip_cdc`. |
| Wallet historical | Direct `wallet_ledger` + balance rollup. Live chokepoint only if debugging one named user. |
| Activities | Same shape as `fn_log_user_activity`. |
| Redemptions | Ledger + wallet burn; existing reward ids only. |
| Mission history | Insert progress/completions consistent with SKU purchases. |
| Derived | Always the platform functions, never hand-stamped RFM/funnel/attribution on the 10k. Named users: **shape inputs** so compute lands them in the right bucket; if one named user is wrong, fix their purchases/dates and recompute. |

---

## Edge cases

- **Do not wipe sales rewards or the 3 tiers.**  
- **Do not** point rocket-demo cron at Ausiris.  
- **Do not** seed wholesale ร้านทอง.  
- **Do not** put ounce balances / fee math on the profile.  
- **Do not** duplicate purchases on `activity_ledger`.  
- **10k + 60k activities** can lock tables — wrap in one session, `skip_cdc`, disable heavy triggers if a trigger fires per row (inspect purchase/wallet triggers before insert; if earn trigger double-writes points, skip it for historical rows the same way rocket-demo backfill sets `earnable` processed flags).  
- If `fn_mkt_compute_purchase_attribution` is global, say so in the run log; still required for ROI.  
- Reward names are Thai partner vouchers — talk track maps “ส่วนลด 50% สำหรับผู้ใช้ครั้งแรก” to first eligible spot trade, not a second secret SKU.  
- Existing test user stays; exclude from RFM talk track.

---

## Verification (blocking)

After recompute, the run must print a JSON summary. Fail the job if any check fails.

1. Members = 10,000 ± 5 (plus the 1 pre-existing).  
2. Every SKU used on a purchase exists in `product_sku_master`.  
3. No purchase without items; header amount = item sum.  
4. Wallet header = sum of ledger for C0 and a random sample of 20.  
5. RFM: all default segments count > 0.  
6. Funnel: all 5 stages > 0; Program Member not also counted as Repeat (latest-wins).  
7. Each AMP audience in the table above count > 0.  
8. TikTok Teaser attributed revenue << LINE Saving / FB Mothers Day.  
9. C0: ≥6 activity types, ≥1 earn, ≥1 burn, ≥1 in-house + ≥1 catalog redemption, ≥2 LOBs, acquisition + attributed campaign.  
10. C8: activities > 0, purchases = 0.  
11. Grouping report: each of 4 objectives has mapping counts > 0.  
12. Leaderboard views return rows for Ausiris only.

Walk order for tomorrow: Marketing campaigns → Reports ROI → Acquisition → Funnel → RFM → Audience builder → C0 360 → C5/C6 win-back → C8 unpaid.

---

## Next-thread prompt (paste this)

```
Execute the Ausiris full demo seed plan in .cursor/plans/ausiris-full-demo-seed-20260824.md

Merchant: Ausiris / ausiris / b7794d29-2df7-47e2-a707-5654fe9f71c4
Do not touch rocket-demo or New CRM.
Keep existing 7 rewards and 3 tiers (Silver/Gold/Platinum).
10,000 members over 6 months. One-shot SQL in demo/ausiris-demo/ run via execute_sql. No new Postgres functions, no cron.
Borrow rocket-demo sequence only (masters → members → FK-linked ledgers → recompute).
Named canonical 360 customer extra-dense. Verify the blocking checklist then give me the C0 phone and the walk order.
```

---

## Out of scope

- Wholesale, live fee engine, KYC documents, CS inbox, AI Decisioning fake metrics.  
- Continuous daily generator, `custom_ausiris_demo_*` functions, or any cron.  
- Recreating rewards.  
- Ultra / Member tier.  
- Seeding on New CRM (`09b45463-…`).
