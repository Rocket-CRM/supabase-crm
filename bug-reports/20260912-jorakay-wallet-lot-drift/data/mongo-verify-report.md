# Mongo verify report (staging vs live snapshot)

Snapshot: `/Users/rangwan/Documents/rocket/supabase-crm/bug-reports/20260912-jorakay-wallet-lot-drift/data/live-mongo-snapshot.json`
Fetched at: 2026-09-12T04:42Z
Users in snapshot: 153
GIVEN rows in snapshot: 19484

## A) Headline (classification stg_point_balance vs live)

- Users checked: 153
- Mismatches / missing: **2**

| mongo_id | stg | live | diff | flag |
|----------|-----|------|------|------|
| 65413f54d6b1732a1ec5f909 | 44773.0 | 42668.0 | -2105.0 | stg_live_mismatch |
| 65f418434aaafb5d9c6567bc | 2437.0 | 1216.0 | -1221.0 | stg_live_mismatch |

## B) Earn-level (migrated earns with mongo_id)

- Mismatches / missing: **992**

Top users by mismatch count:

- `6566b316285bf1f861c02126`: 139
- `679b5621738c06b72462eb29`: 99
- `69a141e528fa02e24cb7f910`: 83
- `67c917a2c336839338cc12a8`: 81
- `65413f78d6b1732a1ec616f1`: 59
- `6805c2ca234f173997c1367c`: 59
- `6583b8aaf8e9301fa214d75e`: 49
- `67026fc7ecd4c2068ffcbe57`: 43
- `65413f51d6b1732a1ec5f601`: 36
- `677dd6c88cb32551667d8b87`: 28
- `65e810a3a09d42f469aad503`: 27
- `65413f8ad6b1732a1ec625e5`: 22
- `69f580122c7cc9555b88fbef`: 20
- `68ddf023234c171c8f55fa45`: 20
- `69990eb58fed8f405589ea22`: 17
