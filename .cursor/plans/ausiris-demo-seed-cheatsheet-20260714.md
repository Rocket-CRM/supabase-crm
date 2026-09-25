# Ausiris Demo Seed — Cheat Sheet (New CRM)

**Merchant:** New CRM (`newcrm` / `09b45463-3812-42fb-9c7f-9d43b6fd3eb9`)  
**Seed tags:** `DEMO-AUS-*` member codes, `SEED-AUS` on campaigns / external_ref / purchase metadata  
**Plan:** `~/.cursor/plans/ausiris_demo_seed_68b337b9.plan.md` (v4)

## Suggested walkthrough order

1. **Marketing → Campaigns** (`/marketing-campaigns`) — 6 SEED-AUS campaigns, budgets, ROI columns  
2. Open **FB Mothers Day Gold** or **LINE Gold Push** → Performance (date range last 45d) — strong attributed revenue  
3. Contrast **TikTok Gold Teaser** — high budget, weak attribution (฿2,500)  
4. **Reports → Marketing campaigns** (`/reports/marketing-campaigns`) — cross-campaign ROI (windows cover last 45d → ratio OK)  
5. **Reports → Acquisition** (`/reports/acquisition`) — facebook / line / google / tiktok / email mix  
6. **Audience Builder** — SEED-AUS audiences with live counts (rule-derived)  
7. **Funnels** (`/funnels`) — **SEED-AUS Gold Customer Journey** stages; Program Members left Repeat (latest-stage-wins)  
8. **Reports → Funnels / RFM / Activity / Exec overview**  
9. **Customer 360** — open example members below (RFM badge, acquisition, Activity tab)

## Seed volume

| Entity | Count |
| --- | --- |
| DEMO members | 28 (`DEMO-AUS-001` … `028`) |
| Seed activities | ~184 |
| Seed purchases | ~55 |
| Campaigns | 6 |
| Dynamic audiences | 9 (all non-zero) |
| Funnel | 1 × 5 stages |

## Loyalty program (backfilled)

| Action | What was seeded |
| --- | --- |
| Points earn | Purchase-linked (`source=purchase`, ~1pt/10 THB) + engagement bonus for all 28 DEMO |
| Points burn | Light burns on DEMO-AUS-001..008 (`source=reward_redemption`) |
| Tier | RFM-mapped: Champions→Platinum, Loyal/Big Spenders→Gold, mid→Silver, else Ultra |
| Tier progress | Sales metric with non-zero upgrade % |

Best 360 demo phone: **0800000002** (Platinum, ~11k pts).

## Campaign ROI direction (attributed revenue, approx)

| Campaign | Budget | Attributed rev (order of magnitude) |
| --- | --- | --- |
| LINE Gold Push | 8,000 | ~204k (strong) |
| FB Mothers Day Gold | 15,000 | ~201k (strong) |
| Google Brand Search | 12,000 | ~54k (strong) |
| Email Winback | 5,000 | ~21k (medium) |
| Workshop Series | 10,000 | ~9k (medium) |
| TikTok Gold Teaser | 20,000 | ~2.5k (weak) |

Config: `mkt_config` u_shape / 30d lookback. Campaign windows ≈ today−60d → today+7d.

## Audiences (example member)

| Audience | Members | Example |
| --- | --- | --- |
| Acquired from Facebook | 8 | DEMO-AUS-001 |
| Acquired from LINE | 6 | DEMO-AUS-005 |
| Acquired from Google | 7 | DEMO-AUS-009 |
| App engagers 30d | 20 | DEMO-AUS-001 |
| Price-alert subscribers | 7 | DEMO-AUS-003 |
| Savings plan members | 6 | DEMO-AUS-001 |
| RFM Champions | 3 | DEMO-AUS-002 (+ Siriporn) |
| RFM At Risk | 3 | (existing buyer e.g. Ploy) |
| High intent unpaid | 5 | DEMO-AUS-014 (gold_price view, no purchase) |

## Funnel stages (current members after reconcile)

| Stage | Members (approx) |
| --- | --- |
| Lead | 6 |
| Engaged | 5 |
| First Purchase | 6 |
| Repeat Buyer | 6 |
| Program Member | 6 |

**Talk track:** Program Members are removed from Repeat (latest-stage-wins) — not churn.

## Cleanup

```sql
-- Sketch only — run deliberately
-- DELETE seed purchases / activities / DEMO users / SEED campaigns+identifiers+attribution
-- Deactivate/delete SEED audiences + Gold Journey funnel
-- Optional: fn_rfm_compute_scores(newcrm) after member delete
```

Filter keys: `member_code LIKE 'DEMO-AUS-%'`, `metadata->>'seed' = 'SEED-AUS'`, `external_ref LIKE 'SEED-AUS%'`, `name LIKE 'SEED-AUS%'`.
