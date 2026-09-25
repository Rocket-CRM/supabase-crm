# Ausiris demo seed

Merchant **Ausiris** (`ausiris` / `b7794d29-2df7-47e2-a707-5654fe9f71c4`).

One-shot set-based seed. **No cron.** Does not touch rocket-demo or New CRM. Keeps the existing 7 rewards and Silver / Gold / Platinum.

## Functions

| Function | Role |
|---|---|
| `custom_ausiris_demo_bootstrap_masters()` | Stores, catalog, earn, activity types, personas, tags, reward points, mkt, RFM config |
| `custom_ausiris_demo_bootstrap_consent()` | PDPA privacy notice + membership terms (Thai + English) |
| `custom_ausiris_demo_bootstrap_engagement()` | Missions, leaderboard views, grouping campaigns, funnel, AMP audiences |
| `custom_ausiris_demo_bootstrap_store_channels()` | CHANNEL + business-unit store attributes and assignments |
| `custom_ausiris_demo_seed_members(10000)` | 10k members + wallets + `fn_ensure_member_code` |
| `custom_ausiris_demo_seed_ledgers()` | Purchases, activities, wallet, redemptions, mission progress |
| `custom_ausiris_demo_seed_named_tour()` | C0–C11 extra-dense 360 rows |
| `custom_ausiris_demo_remap_purchase_channels()` | Stamp earn channels, spread bulk purchases across stores, fill silver |
| `custom_ausiris_demo_seed_promo_codes()` | Partner voucher codes (Shopee / Lazada / Central / Starbucks / E-Coupon): used, claimed, available |
| `custom_ausiris_demo_seed_workflows()` | Three AMP journeys (Welcome, Congratulations, Win-back) plus 6-month `workflow_log` / click series for AMP analytics |
| `custom_ausiris_demo_fill_amp()` | Stamp AMP membership from tags / purchases / signup (engine entered 0) |
| `custom_ausiris_demo_fill_attribution()` | Re-stamp activity/member campaign UUIDs from UTM text, fill ROI from purchase `metadata.utm_campaign` + a small TikTok sample, advance this merchant's attribution watermark |
| `custom_ausiris_demo_recompute()` | RFM, mkt attribution (global), funnel, AMP, then fill AMP + attribution |
| `custom_ausiris_demo_verify()` | Blocking checklist JSON |
| `custom_ausiris_demo_run()` | All of the above in order |

Cleanup key: `external_user_id LIKE 'AUSV2-%'`, `metadata.seed = SEED-AUS-V2`. Test user `nantharat@rocket.in.th` is not deleted.

## Run

```sql
SELECT custom_ausiris_demo_run();
```

Or step by step in that table order. `fn_mkt_compute_purchase_attribution()` is merchant-global.

## C0

Phone **0812345678**. Walk: Marketing campaigns → Reports ROI → Acquisition → Funnel → RFM → Audience builder → AMP analytics (Welcome / Congratulations / Win-back) → C0 360 → C5/C6 win-back → C8 unpaid.

Partner e-vouchers (Shopee / Lazada / Central / Starbucks / E-Coupon) have unique codes. Open the reward → promo codes to see Available / Claimed / Used. C0 holds claimed Shopee code `AUS-SHP-0001`.

Purchases are split across Ausiris business units and sales channels (Next trading, Gold Plus, Express web, gold/silver POS, vending, marketplace, Iris Live). Line items match that channel’s assortment.
