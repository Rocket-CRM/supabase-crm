# Leaderboard

Public ranked tables (top spenders, campaign rankings) configured in admin and rendered in the member app — **native** (Supabase views) or **legacy** (Metabase card).

Owner surfaces: loyalty-admin (**Leaderboards**), loyalty-user (`/lb/{path}` native, `/leaderboard/{path}` legacy)

## Concept

**Leaderboard campaign** — Config on `campaign_leaderboard` tied to `campaign_master` for participation codes.

**Source kind** — `native` reads allowlisted `public.v_lb_*` / `public.mv_lb_*` views; `legacy` reads Metabase via card id in `datawh_table_code`.

**Participation gate** — When `requires_participation` is true, members must join (`campaign_participation`) before table and personal quota render.

**Column config** — Admin chooses visible columns, rank field, direction, `top_x`, center-masking, and member key for quota matching.

Not the same as `get_mission_leaderboard` (missions) or campaign activity grouping.

## Rules

- Native view names must match `v_lb_*` or `mv_lb_*` and include `merchant_id`; Check/save rejects others.
- Reader RPCs never accept client-supplied SQL identifiers — only `datawh_table_code` from the campaign row (allowlisted `format('%I', …)`).
- Wrong member route for source kind → redirect to the correct path.
- Native rows: server ranks and caps `top_x`; if the signed-in member is outside `top_x` but on the view, their row is appended for quota only.
- Legacy path uses old CRM `?token=` identity and Metabase JSON API; native uses loyalty JWT (`user_accounts.id` on participation).
- Translations: default copy on `campaign_leaderboard`; other languages via **Translation_System** `entity_type = leaderboard`. Table cell values are not translated.

## Journeys

### Admin journey

| Knob | Effect |
| --- | --- |
| Source kind | Native view vs Metabase card |
| Path | Public URL segment (unique per merchant) |
| `requires_participation` | Join gate before table/quota |
| Columns / rank / top_x | Table presentation |
| Banner + header copy | Page chrome |

| Page | Owning repo | BFF / RPC |
| --- | --- | --- |
| Leaderboards | loyalty-admin | `bff_get_leaderboard_campaigns`, `bff_get_leaderboard_campaign`, `bff_upsert_leaderboard_campaign`, `bff_inspect_leaderboard_source` |

1. **Leaderboards** → create/edit; pick New CRM vs Legacy (switch clears source).
2. Native: paste view name → **Check**; Legacy: Metabase card id → load fields.
3. Configure participation, columns, rank, masking, member key, banner.
4. Save; translate optional fields under **Translation → Leaderboards**.

### Member journey

| Route | Source | RPCs |
| --- | --- | --- |
| `/lb/{path}` | Native | `api_get_leaderboard_campaign`, `api_get_leaderboard_rows`, `api_check_leaderboard_participation`, `api_join_leaderboard` |
| `/leaderboard/{path}` | Legacy | `check_campaign_participation_text`, `add_campaign_participant_text`, Metabase query |

1. Load localized campaign config.
2. If participation required and not joined → show **Participate** only.
3. Join writes `campaign_participation` (`userid` + `userid_text` = native user uuid).
4. Load ranked rows; render columns and optional personal quota (match `user_key_field` to session user).
5. Language toggle refreshes campaign RPC; static chrome uses `ui_translations` `page_key = leaderboard`.

## System

### Data model

| Table | Role |
| --- | --- |
| `campaign_leaderboard` | Config (`source_kind`, `path`, `datawh_table_code`, `user_key_field`, `columns_config`, `rank_config`, `top_x`, `requires_participation`, copy) |
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
