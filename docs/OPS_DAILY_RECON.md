# Ops daily recon

## Purpose

Nightly health report across production merchants: wallet integrity, crons/backlog, activity silence vs 28-day baseline, marketplace channel connection, and earn/pipeline health.

## Functions

| Function | Use |
| --- | --- |
| `fn_ops_daily_recon(p_day)` | Full compute (~5–15 min). **SQL editor / pg_cron only** — not MCP or HTTP RPC (caller timeouts). |
| `fn_ops_daily_recon_refresh(p_day)` | Runs recon with 15m `statement_timeout`, replaces cache row for `p_day` (default: prior BKK calendar day). |
| `fn_ops_daily_recon_get(p_day)` | **Automation default:** returns cached JSON for `p_day`; fast; errors if cache missing. |

## Schedule

- **pg_cron:** `ops-daily-recon-refresh` — `22 0 * * *` (00:22 UTC ≈ 07:22 Asia/Bangkok).
- **Cache table:** `public._ops_daily_recon_cache` (`result` jsonb).

## CRM / Slack workflow

1. Call `SELECT public.fn_ops_daily_recon_get()` (optional `p_day` for backfill).
2. If `status` = `error` and message mentions missing cache, either wait for cron or run `fn_ops_daily_recon_refresh` in SQL editor.
3. Do **not** call `fn_ops_daily_recon()` from Sales CRM MCP — Supabase MCP `execute_sql` times out before the function finishes.

## Manual backfill

```sql
SELECT public.fn_ops_daily_recon_refresh('2026-09-16'::date);
```
