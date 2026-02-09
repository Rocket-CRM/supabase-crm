# Caching Design Methodology

## Core Principle

Cache expensive read operations that change infrequently. Keep database as source of truth.

## Architecture

```
Request → Check Redis Cache (Upstash)
    ├─ HIT   → Return cached data (2-5ms)
    └─ MISS  → Query PostgreSQL → Store in Redis → Return
```

Data flows one direction: PostgreSQL → Redis (never reverse).

## Implementation Logic

1. **Cache Key Structure:** `merchant:{merchant_id}:{feature_name}`
2. **TTL:** 5 minutes (cache expires automatically)
3. **RPC Function:** 
   - Query Redis for key
   - If not found, query PostgreSQL
   - Write result to Redis with TTL
   - Return to frontend
4. **Invalidation:** Triggers fire on data change, delete cache key immediately

## Platforms

| Component | Service | Purpose |
|-----------|---------|---------|
| Cache Store | Upstash Redis | Fast ephemeral key-value storage |
| Query Engine | Supabase PostgreSQL | Complex queries, joins, aggregations |
| Redis Access | Postgres Redis Wrapper | Allows SQL queries to read/write Redis directly |

### Why Postgres Redis Wrapper

Without wrapper:
```
RPC Function → HTTP call to Redis REST API → Serialize/deserialize
```

With wrapper (native):
```
RPC Function → SQL query directly to Redis → Native integration
```

Result: No extra HTTP roundtrips, cleaner code, faster.

## User Journey Example: Rewards Feature

**Scenario:** Frontend loads rewards page

### First User (T+0s)
1. Browser calls `GET /rpc/api_get_rewards_full_cached`
2. RPC function checks Redis key `merchant:abc123:rewards:all_languages`
3. Cache miss
4. Function queries PostgreSQL:
   - Join reward_master + translations + stock tables
   - Aggregate redemption counts
   - Format all languages as JSON
5. Result stored in Redis (TTL: 5 min)
6. Data returned to browser (2-3ms)

### Second User (T+2min, same merchant)
1. Browser calls same endpoint
2. RPC function checks Redis key
3. **Cache hit** - returns stored JSON
4. Data returned to browser (2-5ms)
5. User switches language - no API call needed, translations already in response

### Third User (T+5:01min - cache expired)
1. Browser calls endpoint
2. Cache miss (TTL expired)
3. PostgreSQL queried again
4. Fresh data cached for next 5 minutes

### Merchant Admin Edits Reward (T+3min)
1. Admin updates reward name
2. Database trigger fires
3. Cache key `merchant:abc123:rewards:all_languages` deleted from Redis
4. Next customer request queries fresh data from PostgreSQL
5. New data cached for 5 minutes

## Data Flow Diagram

```
┌─────────────────────┐
│  Frontend (WeWeb)   │
└──────────┬──────────┘
           │ RPC call
           ▼
┌─────────────────────────────────────┐
│  Supabase RPC Function              │
│  - Check Redis (Upstash)            │
│  - If miss: Query PostgreSQL        │
│  - Store result in Redis (TTL 5min) │
│  - Return JSON                      │
└─┬──────────────────────────┬────────┘
  │                          │
  │ Redis Wrapper           │ Source of Truth
  ▼                          ▼
┌──────────────────┐    ┌─────────────────────┐
│  Redis Cache     │    │  PostgreSQL         │
│  (Upstash)       │    │  - reward_master    │
│  Key-value store │    │  - translations     │
│  2-5ms response  │    │  - reward_stock     │
│  5 min TTL       │    │  - redemptions      │
└──────────────────┘    └─────────────────────┘
```

## When to Invalidate Cache

Cache is cleared when:
- Reward created/updated
- Translation added/changed
- Stock quantity modified
- Promo code used
- Redemption occurs

**Result:** Next request always gets fresh data, but within same 5-minute window, customers see consistent cache.

## Cached Function Naming Convention

### Pattern: `{prefix}_{scope}_{data_type}_cached`

| Component | Description | Example |
|-----------|-------------|---------|
| `{prefix}` | API layer: `api_` (frontend), `bff_` (backend), `admin_` (admin) | `api_`, `bff_` |
| `{scope}` | Data level: `get_`, `list_` | `get_`, `list_` |
| `{data_type}` | What data: `rewards`, `conditions`, `users`, `catalog` | `rewards` |
| `_cached` | Suffix indicating Redis caching | `_cached` |
| `_full` | Optional: indicates complete/enriched data | `_full_cached` |

### Examples

```
api_get_rewards_full_cached      - Frontend: complete reward data with all enrichments
api_list_merchants_cached         - Frontend: merchant list
bff_get_earn_conditions_cached    - Backend: earn condition groups
admin_get_dashboard_stats_cached  - Admin: dashboard aggregations
api_get_user_profile_cached       - User profile with all related data
```

### Why This Matters

- **`api_`** signals: callable by frontend, safe for external consumption
- **`_full`** signals: includes all enrichments (translations, aggregations, joins)
- **`_cached`** signals: performance optimized, automatic invalidation on change
- **Consistency** across team when building future features

## Multi-Language Example

Single cache entry contains all languages:
```json
{
  "id": "reward-123",
  "translations": {
    "en": { "name": "Coffee Mug", "headline": "..." },
    "th": { "name": "แก้ว", "headline": "..." },
    "ja": { "name": "マグカップ", "headline": "..." }
  },
  "points": 100,
  ...
}
```

Frontend receives all languages in one response. User switches language in UI without new API call—translations already loaded.
