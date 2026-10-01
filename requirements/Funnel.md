# Funnel

Ordered **journey stages** where each stage is an AMP audience bound to a funnel; reconcile assigns each member to the highest matching stage and logs transitions for conversion metrics.

Owner surfaces: loyalty-admin (**Funnels** builder, funnel report, members report funnel filter)

## Concept

**Funnel** — Named pipeline (`funnel_master`) with description and active flag per merchant.

**Stage** — Dynamic AMP audience with `funnel_id` and `funnel_sort_order`; entry rules use the same condition language and compiler as workflow audiences.

**Transition ledger** — Append-only `funnel_transition_ledger` rows: from-stage, to-stage (null = entered or left funnel), `occurred_at`.

**Reconcile** — Batch job recomputes stage membership (latest sort order wins); funnel-bound audiences skip the normal dynamic resnapshot loop.

## Rules

- **Latest-stage-wins** — User is placed on the highest `funnel_sort_order` stage whose conditions match; not monotonic in v1 — users can move backward when they stop matching deeper stages.
- **Cadence** — `fn_funnel_reconcile_all()` runs inside hourly `fn_amp_reconcile_dynamic_audiences()`; saving an active funnel triggers immediate `fn_funnel_reconcile` for that funnel.
- **Stage lifecycle** — Upsert creates/updates stage audiences via audience BFF internals; removed stages delete their audience rows; ledger history is retained.
- **Metrics** — Conversion and drop-off read the ledger; current stage for reporting also exposed on members report rows.

## Journeys

### Admin journey

| Knob | Effect |
| --- | --- |
| Stage conditions | Who qualifies for each stage |
| `funnel_sort_order` | Precedence when multiple stages match |
| Funnel `is_active` | Enables reconcile |
| Date window | Metrics series and KPIs |

| Page | Owning repo | BFF / RPC |
| --- | --- | --- |
| Funnels | loyalty-admin | `bff_list_funnels`, `bff_get_funnel_details`, `bff_upsert_funnel`, `bff_delete_funnel` |
| Funnel report | loyalty-admin | `bff_get_funnel_metrics` (compare / export) |
| Members report | loyalty-admin | `bff_report_members_rows` + `p_filters.funnel_id` |

1. **Funnels** — define stages (AMP conditions) and ordering; save triggers reconcile when active.
2. Builder shows inline 7/30/90-day stage metrics via `bff_get_funnel_metrics`.
3. **Funnel report** — custom range (`p_from`/`p_to`) or window; optional daily series.
4. **Members report** — filter or column for current funnel stage name.

### Member journey

None — stage membership is computed server-side. Members do not see funnel stage labels unless another surface exposes them (e.g. admin Customer 360 / **Activity_Attribution.md**).

## System

### Data model

| Table | Role |
| --- | --- |
| `funnel_master` | Funnel definition (`name`, `description`, `is_active`) |
| `funnel_transition_ledger` | Transition history (`from_stage_audience_id`, `to_stage_audience_id`) |
| `amp_audience_master` | Stage storage: nullable `funnel_id`, `funnel_sort_order` |

### Functions

| Function | Role |
| --- | --- |
| `fn_funnel_reconcile(p_funnel_id)` | Recompute membership + write ledger diffs |
| `fn_funnel_reconcile_all()` | All active funnels (hourly path) |
| `bff_list_funnels()` | Admin list |
| `bff_get_funnel_details(p_funnel_id, p_mode)` | Edit payload |
| `bff_upsert_funnel(..., p_stages jsonb)` | Create/update stages + reconcile when active |
| `bff_delete_funnel(p_funnel_id)` | Remove funnel |
| `bff_get_funnel_metrics(p_funnel_id, p_window, p_from, p_to, p_include_series)` | Per-stage counts, conversion, optional series; list mode when `p_funnel_id` null |

**Metrics shape (detail):** per stage `current_members`, `entered_in_window`, `converted_to_next`, `left_funnel`, `conversion_rate`; KPIs for in-funnel and headline conversion.

### Flows

```
Hourly AMP reconcile → fn_funnel_reconcile_all
Save active funnel → fn_funnel_reconcile (immediate)
Member activity → conditions change → next reconcile moves stage → ledger append
```

### Known gaps

- No dedicated member-facing funnel UI; product analytics are admin/reporting only.

## Related

- **AMP_Workflows.md** — Audience condition compiler and reconcile cron.
- **Activity_Attribution.md** — Customer 360 `funnel_stage` slice.
- **RFM_Scoring.md** — Often reviewed alongside segmentation reports.
