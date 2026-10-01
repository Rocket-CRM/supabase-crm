# RFM Scoring

Recency, frequency, and monetary scores per member on a configurable rolling window — recomputed on a schedule for segmentation, AMP conditions, and reporting.

Owner surfaces: loyalty-admin (**RFM settings**, RFM reports, members report segment column)

## Concept

**RFM config** — One row per merchant: active flag, `window_months`, `recency_source` (purchases vs a specific activity type), optional `band_thresholds`, ordered `segment_map`.

**User score** — Latest R/F/M quintiles (1–5), derived segment label, raw metrics, `computed_at` in `rfm_user_score` (typed table for audience indexes and CDC hygiene).

**Segment map** — First matching rule wins; defaults via `fn_rfm_default_segment_map()` (Champions … Lost + Regulars catch-all).

**Audience consumption** — `rfm_user_score` is a whitelisted AMP collection; hourly audience reconcile unchanged.

## Rules

- **Daily compute** — `fn_rfm_compute_scores(p_merchant_id)` processes all merchants with active config when `p_merchant_id` is null (cron job `rfm-daily-compute`, documented as `30 17 * * *` UTC).
- **Quintiles** — NTILE(5) over in-window members with `frequency > 0`; zero-activity members get score 1 on all axes.
- **Monetary** — Always purchase revenue in window; recency/frequency follow `recency_source`.
- **Segments** — Walk `segment_map` top to bottom; catch-all prevents null segment.
- **Reporting** — Segment membership uses latest `rfm_user_score`; period revenue in report RPCs is a separate `purchase_ledger` rollup in `[p_from, p_to)`.

## Journeys

### Admin journey

| Knob | Effect |
| --- | --- |
| `is_active` | Enables compute for merchant |
| `window_months` | Lookback |
| `recency_source` / activity type | R and F inputs |
| `band_thresholds` | Fixed quintile cuts; null = NTILE |
| `segment_map` | Label rules on R×F×M |

| Page | Owning repo | BFF / RPC |
| --- | --- | --- |
| RFM settings | loyalty-admin | `bff_get_rfm_settings`, `bff_upsert_rfm_settings`, `bff_get_rfm_distribution` |
| RFM report | loyalty-admin | `bff_report_rfm_segment`, `bff_report_rfm_segment_rows` |
| Members report | loyalty-admin | `bff_report_members_rows` (`rfm_segment` filter/column) |
| Customer 360 | loyalty-admin | `bff_admin_get_member_360` → `rfm` object |

1. Enable RFM and set window + recency source on **RFM settings**.
2. Review distribution KPIs (`computed_at`, coverage).
3. Drill **RFM report** by segment; export rows (max limit 5000 per page).
4. Use scores in AMP workflows via `rfm_user_score` collection.

### Member journey

None — no member-facing RFM screen. Segment-driven offers only appear when other features reference the score.

## System

### Data model

| Table | Role |
| --- | --- |
| `rfm_config` | Per-merchant settings (`is_active`, `recency_source`, `recency_activity_type_id`, `window_months`, `band_thresholds`, `segment_map`) |
| `rfm_user_score` | Unique `(merchant_id, user_id)` — `r_score`, `f_score`, `m_score`, `rfm_segment`, raw metrics, `computed_at` |

### Functions

| Function | Role |
| --- | --- |
| `fn_rfm_compute_scores(p_merchant_id)` | Batch recompute |
| `fn_rfm_default_segment_map()` | Seed segment rules |
| `bff_get_rfm_settings` / `bff_upsert_rfm_settings` | Admin config |
| `bff_get_rfm_distribution` | KPIs, optional heatmap / revenue rollup |
| `bff_report_rfm_segment` | Segment analytics + series |
| `bff_report_rfm_segment_rows` | Paginated / CSV member rows |
| `bff_get_workflow_collections_v4_extensions` + `fn_amp_assert_collection` | Expose `rfm_user_score` to AMP |

**Report sorts (rows RPC):** `period_revenue_*`, `last_activity_at_*`, `monetary_*`, `member_name_*`, `period_orders_*`, `recency_days_*`.

### Flows

```
Cron rfm-daily-compute → fn_rfm_compute_scores
AMP hourly reconcile → reads rfm_user_score like other collections
Admin reports → latest score + optional period purchase rollup
```

### External services

Scheduled job name `rfm-daily-compute` — verify deployment in Supabase `cron.job` / ops runbook (`REGISTRY_RENDER.md` does not list this cron).

### Known gaps

- RFM cron not enumerated in `REGISTRY_RENDER.md` at last registry grep — confirm live schedule in DB.

## Related

- **Purchase_Transaction.md** — Ledger inputs for F/M and default recency.
- **Activity_Based_Earning.md** — Optional recency activity type.
- **AMP - Rule Based.md** — Conditions on `rfm_user_score`.
