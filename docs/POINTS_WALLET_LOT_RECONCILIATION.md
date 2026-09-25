# Points wallet ↔ lot reconciliation

Canonical operator runbook for migrated TTL merchants (Kovet, Jorakay, …).

**Full instructions:** [`bug-reports/20260902-points-historical-repair/Plan.md`](../bug-reports/20260902-points-historical-repair/Plan.md)

Quick links:

| Task | File |
|---|---|
| Plan + classify + hold gate + cutover rule | `bug-reports/20260902-points-historical-repair/Plan.md` |
| Apply Kovet (pending) | `bug-reports/20260902-points-historical-repair/apply-track-a-kovet.sql` |
| Jorakay (done 2026-09-02, `still_drift = 0`) | `bug-reports/20260902-points-historical-repair/apply-track-a.sql`, `apply-track-b*.sql` |
| Her Hyness (done — different repair) | `supabase/migrations/20260901044000_hh_wallet_lot_repair.sql` |

Rules: the migration loader stays a faithful mirror of old CRM (no reconciliation in initial load or daily sync). Reconcile **manually, once, at cutover** — old CRM points frozen → final sync → `sync_active = false` → run this runbook → NewCRM live — and never turn sync back on afterwards. Do **not** run the HH repair on other merchants.
