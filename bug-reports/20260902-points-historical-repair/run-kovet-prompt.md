# Kovet points wallet ↔ lot reconciliation — new thread prompt

Run the historical points repair for **Kovet** using the existing runbook and deployed functions. Same procedure that was completed for Jorakay on 2026-09-02.

**Open first:**
- `~/Documents/rocket/supabase-crm/bug-reports/20260902-points-historical-repair/Plan.md` (runbook — read § Operator runbook, § Model, § Hold gate, § Step 4, § Migration lifecycle)
- `~/Documents/rocket/supabase-crm/bug-reports/20260902-points-historical-repair/apply-track-a-kovet.sql`
- `~/Documents/rocket/supabase-crm/supabase/migrations/20260902100000_ttl_points_historical_repair.sql` (what the functions do — do not redeploy, already live)

**Merchant:** Kovet
- `merchant_id`: `c0db034a-cabc-44d2-87f0-e660a755237f`
- mongo `merchant_ref`: `674566c5fb5f29940476df88`
- `points_expiry_mode`: `ttl`
- Supabase project: `wkevmsedchftztoolkmi` (only this project; never `list_projects`)
- `sync_active`: already `false` — it must stay false forever after this

**Baseline (read-only, 2026-09-02), 3,150 wallets:**

| Measure | Value |
|---|---:|
| `wallet ≠ lots` today | 22 users, all `lots > wallet` |
| Step 1 (zero lots due at last old-CRM activity) | 7 users / 309 pts |
| Step 2 (FIFO lot reduction) | 15 users / 2,835 pts |
| Step 3 — wallet down | **702 users / 22,607 pts** |
| Held | 13 users, all `later_newcrm`; no `mongo_sync_gap`; sim reconciles for all |

Most of step 3 is **not** drift: ~700 members have wallet = lots, but the lots are past `expiry_date` and neither old CRM (no activity since) nor NewCRM nightly ever burned them. Step 3 burns them silently, backdated to the expiry date, no LINE. Nightly expiry would otherwise take the same points with a notification.

## Procedure

Heavy SQL (manifest build, batch applies) goes in the Supabase SQL editor; MCP may time out. Use MCP for reads and small checks.

**Phase A — read only**
1. Re-run § 0 preconditions and the drift query. Numbers should match the baseline; if they moved, say so before continuing.
2. Run the hold export for Kovet (`hold-export.sql` with `params` switched to the Kovet IDs above). List the 13 held users: `user_id`, `tel`, `hold_reasons`, `last_ts`, step amounts.

**Gate 1 — stop and show me:** baseline vs today, `users_wallet_down` / `total_wallet_down_pts`, the 13 held users. No writes until I say "approved".

**Phase B/C — Track A (clean cohort), after approval**
3. `SELECT fn_ttl_points_repair_build_manifest('c0db034a-cabc-44d2-87f0-e660a755237f'::uuid);` — save `run_id`. Manifest `summary` should be close to: clean_step1 ≈ 309 pts, clean_step2 ≈ 2,835 pts, clean_step3 ≈ 22,6xx pts minus whatever the 13 held users carry, held_users = 13.
4. Dry-run steps 1 → 2 → 3 (`p_dry_run := true`) and compare to the manifest summary. Stop if they disagree.
5. Live apply in batches, each step until it returns zero: step 1 (`500,false`), then step 2 (`500,false`), then step 3 (`200,false`). Report each step's totals.

**Phase D — the 13 held users**
6. For each, run § Step 4 investigation checklist and propose one resolution A–F with approved amounts. Show me the table.

**Gate 2 — stop and show me** the hold table. Writes for holds only after I approve per resolution (Track B: `fn_ttl_points_repair_build_hold_manifest` from `…110000_ttl_points_repair_track_b.sql`, pattern in `apply-track-b.sql`).

**Phase E — verify**
7. § Verify query: target `still_drift = 0` except unresolved holds.
8. Confirm no LINE/expiry events were emitted for the repair burns.
9. Append a "Status: done" line with run ids and final counts to the Kovet runbook section of `Plan.md`.

## Rules

- Read-only by default; every write waits for my explicit "approved" at the gates above.
- Never run `fn_hh_repair_*` (Her Hyness) on Kovet.
- Never invent user ids or run ids — take them from query results.
- Do not touch `newcrm-migration`, do not re-enable `sync_active`, do not remigrate.
- Chat markdown only, no Canvas. Lead with numbers; keep the tool trail out of the reply.
