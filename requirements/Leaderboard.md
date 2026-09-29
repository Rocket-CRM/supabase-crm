# Leaderboard

Public ranked tables (top spenders, campaign rankings) configured in admin and rendered in the member app — **native** (Supabase views) or **legacy** (Metabase card).

Owner surfaces: loyalty-admin (**Leaderboards**), loyalty-user (`/lb/{path}` native, `/leaderboard/{path}` legacy)

## Concept

A leaderboard is a campaign type that shows members a ranked list — typically top spenders on a product or channel during a campaign window — so they compete for a privilege the merchant grants outside the system (e.g. the top 10 meet a celebrity). In Action → Condition → Outcome terms the action is usually purchasing and the in-system result is only the rank; the real outcome is fulfilled offline.

The design separates data from display. Engineering first builds a **data view** that already computes the ranking basis for that campaign (e.g. one entitlement per 500 THB of participating-product spend, per member); the leaderboard only reads that view and decides which fields to show, how to rank, and how many rows. A new calculation therefore needs a new view; re-labelling, re-ranking, or masking an existing one is admin-only work.

**Leaderboard campaign** — Name, campaign code (keys participation records), public path, CRM version, data view, display settings, columns, personal quota, ranking.

**CRM version (source kind)** — *New CRM* reads a view in this database; *Legacy CRM* reads a Metabase card over the old CRM's separate database. Must match where the brand's data lives; most brands are on New CRM.

**Data view** — The per-campaign dataset, one row per member. Every field it exposes is offered to the admin; nothing is shown until picked.

**Participation gate** — Optional. When on, members must tap Participate before the table and their own quota appear; when off, anyone with the link sees it.

**Columns** — The subset of view fields shown, each with a display label, order, and optional masking (hide N characters in the middle) for personal data such as name or phone. Internal ids stay hidden by not being picked.

**Ranking** — Rank field, direction (usually descending), and Top X rows shown (typically ~20).

**Personal quota** — The signed-in member's own value (e.g. entitlements or spend), matched via a member key field; shown even when the member is outside Top X.

**Display mode** — *Ranked* (table plus optional personal quota) or *Quota only* (banner, copy, and one personal quota card — no table). Works on both CRM versions.

Not the same as mission rankings (see Mission) or campaign activity grouping.

## Rules

- Native view names must match `v_lb_*` or `mv_lb_*` and include `merchant_id`; Check/save rejects others.
- Reader RPCs never accept client-supplied SQL identifiers — only `datawh_table_code` from the campaign row (allowlisted `format('%I', …)`).
- Wrong member route for source kind → redirect to the correct path.
- Native rows: server ranks and caps `top_x`; if the signed-in member is outside `top_x` but on the view, their row is appended for quota only.
- Legacy path uses old CRM `?token=` identity and Metabase JSON API; native uses loyalty JWT (`user_accounts.id` on participation).
- Translations: default copy on `campaign_leaderboard`; other languages via **Translation_System** `entity_type = leaderboard`. Table cell values are not translated.
- `quota_only` save requires `user_key_field` and one column with `personal_quota_enabled`; rank field is not required (`top_x` still stored, unused).
- `quota_only`: member app server strips fetched rows to the signed-in member's own row before render (legacy Metabase result included); no match → quota `0`. No member identity (missing/invalid legacy `?token=`, no native session) → member-not-found + open member app instead of the card.
- No-participate quota: set `requires_participation = false`; legacy Metabase card only needs rows keyed by `user_key_field` (no participation filter).

## Journeys

### Admin journey

| Knob | Effect |
| --- | --- |
| Campaign name / code | List label; code keys participation records |
| CRM version (source kind) | Native view vs Metabase card; switching clears the source |
| Public path | Member URL segment (unique per merchant) |
| Require participation | Join gate before table/quota |
| View / table name (or Metabase code) | Dataset read; **Check** / load lists its fields as column candidates |
| Display (`display_mode`) | Ranked table vs Personal quota only (hides Columns + Ranking sections) |
| Banners, page header, description | Page chrome (default language) |
| Columns: show, label, order, mask + mask characters | Which fields members see, how they are titled and ordered, how many middle characters are hidden |
| Member key field | Matches the signed-in member to a row |
| Personal quota field + label | The member's own value shown beside the table (or alone in quota-only) |
| Ranked field / direction / Top X | Sort basis, order, and row cap (ranked only) |

| Page | Owning repo | BFF / RPC |
| --- | --- | --- |
| Leaderboards | loyalty-admin | `bff_get_leaderboard_campaigns`, `bff_get_leaderboard_campaign`, `bff_upsert_leaderboard_campaign`, `bff_inspect_leaderboard_source` |

1. **Leaderboards** lists existing campaigns → **Create leaderboard** (or open one).
2. **Campaign** section: name, code, CRM version, public path, participation gate, active.
3. **Data source**: native — paste the view name → **Check**; legacy — Metabase card id → load fields. The fetched field list feeds the next sections.
4. **Display settings**: banners, display mode, page header and description.
5. **Columns** (ranked only): tick fields to show, set labels and order, mask personal data.
6. **Personal quota**: member key field, quota field, quota label.
7. **Ranking** (ranked only): ranked field, direction, Top X.
8. Save; translate optional copy under **Translation → Leaderboards**.

### Member journey

| Route | Source | RPCs |
| --- | --- | --- |
| `/lb/{path}` | Native | `api_get_leaderboard_campaign`, `api_get_leaderboard_rows`, `api_check_leaderboard_participation`, `api_join_leaderboard` |
| `/leaderboard/{path}` | Legacy | `check_campaign_participation_text`, `add_campaign_participant_text`, Metabase query |

1. Member opens the campaign link; app loads localized banner, header, and description.
2. If participation required and not joined → banner and copy with **Participate** only; no table or quota.
3. Join writes `campaign_participation` (`userid` + `userid_text` = native user uuid); the page then reveals the data.
4. Ranked: Top X rows with the chosen columns (masked where configured) plus the member's own quota, still shown if they rank below Top X. `quota_only`: centered quota card only.
5. Language toggle refreshes campaign RPC; static chrome uses `ui_translations` `page_key = leaderboard`.

## System

### Data model

| Table | Role |
| --- | --- |
| `campaign_leaderboard` | Config (`source_kind`, `display_mode` `ranked`\|`quota_only`, `path`, `datawh_table_code`, `user_key_field`, `columns_config`, `rank_config`, `top_x`, `requires_participation`, copy) |
| `campaign_master` | Campaign code/name for participation |
| `campaign_participation` | Join log (native uuid on `userid` + `userid_text`) |

### Functions

| Function | Caller | Role |
| --- | --- | --- |
| `bff_get_leaderboard_campaigns` | Admin | List |
| `bff_get_leaderboard_campaign` | Admin | `new` / `edit` |
| `bff_upsert_leaderboard_campaign` | Admin | Upsert |
| `bff_inspect_leaderboard_source` | Admin | Native column inspect |
| `api_get_leaderboard_campaign` | Member | Public config + translations |
| `api_get_leaderboard_rows` | Member | Ranked data + participation gate |
| `api_check_leaderboard_participation` / `api_join_leaderboard` | Member | Native join flow |
| `check_campaign_participation_text` / `add_campaign_participant_text` | Legacy | Text user ids |

### Flows

**Native view authoring (engineering)** — Create `v_lb_<merchant_code>_<slug>` or materialized `mv_lb_*` with `merchant_id`; optional join to `campaign_participation` in SQL; refresh MVs via `pg_cron` + `REFRESH MATERIALIZED VIEW CONCURRENTLY`.

### Known gaps

- Legacy campaigns remain on Metabase until rebuilt as native views.
- Participate-on without view-side participation filter still requires product join for visibility; ranked set is whatever the view returns.

## Related

- **Translation_System.md** — Leaderboard entity translations.
- **Mission.md** — Separate `get_mission_leaderboard` rankings.
