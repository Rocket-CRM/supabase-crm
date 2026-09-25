# Jorakay — remaining 138 users (apply-ready manifest)

**Generated:** 2026-09-12 · Same rules as 15-user `DATA-ADJUSTMENT-MANIFEST.md` / `Plan.md`.

| Artifact | Path |
|----------|------|
| User targets | `data/user-targets-remaining-138.json` |
| Earn UPDATE rows | `data/row-level-targets-remaining-138.csv` (545 rows) |
| Earn INSERT rows | `data/ledger-inserts-remaining-138.csv` (10 rows) |

**Wallet target:** `stg_point_balance` + native earns − native burns − expiry burns (staging Mongo headline; **verify live Mongo at apply**).

**Before apply:** Re-run `sql/export-earn-rows-remaining-138.sql` + `sql/export-native-ledger-remaining-138.sql`; confirm `stg_mongo_balance` vs live `GIVEN.balance`.

## Summary

- Users computed: **138**
- Earn row UPDATEs: **545**
- Orphan-wallet INSERTs: **10**
- `user_wallet` deltas: **4**
- Residual lot-sum flags: **0**
- Errors: **0**

## `user_wallet` UPDATE candidates

| mongo_id | user_id | now → target | delta |
|----------|---------|--------------|-------|
| `65413f54d6b1732a1ec5f909` | `169434fe-4c0c-46b4-9c9b-15dac2e90009` | 41988.0 → **39059.0** | -2929.0 |
| `6a4dd4dbe7aba5deb5edde98` | `6761dc57-bcf6-4d5f-a1a0-16c0610a3ac3` | 1194.0 → **1979.0** | 785.0 |
| `65413f4ad6b1732a1ec5efdd` | `6f264737-7583-48ab-ab51-28193e758805` | 1211.0 → **1188.0** | -23.0 |
| `65413f57d6b1732a1ec5fbcd` | `15fd0ace-9201-4d3b-9329-cec5c18cfee8` | 10658.0 → **10670.0** | 12.0 |
