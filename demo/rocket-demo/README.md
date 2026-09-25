# Rocket Demo — seed + daily generator

Merchant **Rocket Demo** (`rocket-demo` / `fae172a5-de90-440e-a766-db6a5982cc9b`).

**CS seed** (AOPs, knowledge, inbox quick replies): see [`cs/README.md`](cs/README.md).

One Postgres generator produces coherent loyalty data for admin config pages and BigQuery reports. The 6-month backfill and the daily cron share the same engine.

**Shipped baseline (2026-07-22):** ~2500 members, ~32.6k purchases, ~41.4k wallet rows, ~8.8k redemptions, RFM scored for all members, cron `custom-internal-demo-daily` active. Admin owner login was not created (`admin_init_merchant_with_owner` hit an auth `confirmed_at` constraint) — add an admin via the usual merchant-admin invite flow before iframe deck login.

**Engagement layer (2026-07-29):** personas/tags, Earn Studio graph, 3 missions, 2 spin wheels, 2 surveys, AMP audiences + agents, plus historical enrich and daily engagement wave. Purchase baseline left intact (~33k).

**Store channels + coupon usage (2026-07-29):** 20 lifestyle stores across 6 sales channels (Flagship, Boutique Mall, Department Store, Specialty Retail, Own Online, Marketplace). Day generator marks matured redemptions used at offline retailers (`used_at` / `used_store_id`). One-shot `custom_internal_demo_enrich_redemption_usage()` backfilled historical usage (~65% used). Safe store/channel upsert: `custom_internal_demo_bootstrap_store_channels()` (does not wipe rewards).

## Objects

| Object | Role |
|---|---|
| `custom_internal_demo_config` | Single config/bookkeeping table (`kind` + `payload`) |
| `custom_internal_demo_bootstrap_merchant()` | One-time masters: tiers, stores, products, rewards, sales channels |
| `custom_internal_demo_bootstrap_store_channels()` | Safe upsert of stores + CHANNEL attributes + assignments (no reward wipe) |
| `custom_internal_demo_bootstrap_engagement()` | One-time engagement masters (personas, earn, missions, spin, surveys) |
| `custom_internal_demo_enrich_engagement()` | One-shot historical enrich over existing members |
| `custom_internal_demo_enrich_redemption_usage()` | One-shot mark historical redemptions used at retailer stores |
| `custom_internal_demo_generate_day(date, mode)` | One simulated day (`backfill` \| `live`) including engagement + coupon usage |
| `custom_internal_demo_generate_day_engagement(date, mode)` | Survey / mission / spin / tag trickle |
| `custom_internal_demo_seed_range(from, to, pause, mode)` | Loop days with `pg_sleep` between them |
| `custom_internal_demo_daily_job()` | Cron entry → `generate_day(current_date, 'live')` |
| Cron `custom-internal-demo-daily` | `0 20 * * *` UTC (~03:00 BKK) |

### Config `kind` values

`settings` · `archetype` · `given_name` · `surname` · `product` · `campaign` · `member_state` · `run_log` · `enrich_log`

## Runbook

### Bootstrap (once)

```sql
SELECT custom_internal_demo_bootstrap_merchant();
SELECT custom_internal_demo_bootstrap_engagement();
SELECT custom_internal_demo_bootstrap_profile_consent();
-- Or, on an already-seeded merchant, only expand stores/channels:
-- SELECT custom_internal_demo_bootstrap_store_channels();
```

### Full seed (~180 days)

Default pause is **10 seconds** between days (load shedding). For faster ops use `2`.

```sql
SELECT custom_internal_demo_seed_range(
  p_from := current_date - 180,
  p_to := current_date,
  p_pause_seconds := 10,
  p_mode := 'backfill'
);

SELECT custom_internal_demo_enrich_engagement();
SELECT custom_internal_demo_enrich_redemption_usage();
SELECT fn_rfm_compute_scores('fae172a5-de90-440e-a766-db6a5982cc9b'::uuid);
SELECT fn_amp_reconcile_dynamic_audiences();
```

Idempotent: days with an existing `run_log` row are skipped. Enrich uses `enrich_log` / `engagement_v1` and `redemption_usage_v1`.

### Daily (ongoing)

Cron calls `custom_internal_demo_daily_job()` which uses **live** mode (real wallet/redeem RPCs at small volume) and runs the engagement wave (persona on signup, survey/mission/spin trickle).

### Cleanup (merchant-scoped)

```sql
-- Facts only — keeps masters/config pools
DELETE FROM purchase_items_ledger WHERE merchant_id = 'fae172a5-de90-440e-a766-db6a5982cc9b';
DELETE FROM purchase_ledger WHERE merchant_id = 'fae172a5-de90-440e-a766-db6a5982cc9b';
DELETE FROM wallet_ledger WHERE merchant_id = 'fae172a5-de90-440e-a766-db6a5982cc9b';
DELETE FROM reward_redemptions_ledger WHERE merchant_id = 'fae172a5-de90-440e-a766-db6a5982cc9b';
DELETE FROM user_wallet WHERE merchant_id = 'fae172a5-de90-440e-a766-db6a5982cc9b';
DELETE FROM custom_internal_demo_config WHERE kind IN ('member_state', 'run_log');
DELETE FROM user_accounts WHERE merchant_id = 'fae172a5-de90-440e-a766-db6a5982cc9b' AND role = 'user';
```

### Tuning charts

Edit archetype / campaign rows in `custom_internal_demo_config`, delete `run_log` (+ facts if needed), re-run `seed_range`.

## Content rules

- Natural Thai names (combinatorial given × surname) — no `Demo 2` labels
- Skincare catalog when SKUs are needed; program framed as lifestyle retail
- Invisible seed tags only: `metadata.seed = SEED-RKT`, `external_ref LIKE 'SEED-RKT-%'`

## Repo layout

```
demo/rocket-demo/
  config/01_pools.sql          # authored pools
  waves/00_helpers.sql
  waves/01_bootstrap.sql
  waves/02_generate_day.sql
  waves/03_seed_range.sql
  waves/04_bootstrap_engagement.sql
  waves/05_enrich_engagement.sql
  waves/06_generate_day_engagement.sql
  waves/07_enrich_redemption_usage.sql
  README.md
```

When platform tables/RPCs this generator writes through change, update these files and redeploy the functions.
