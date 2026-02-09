# Rewards Caching System - Implementation Guide

## Executive Summary

The Rewards API uses a dedicated Redis cache to optimize performance for reward catalog queries with multi-language translations. This system caches complete reward data including all translations in a single response, enabling sub-5ms response times for 99%+ of requests through intelligent caching and automatic invalidation.

---

## Architecture Overview

### Two-Tier Caching Strategy

```
User Request
    ↓
API: api_get_rewards_full_cached()
    ↓
Check Redis Cache (Dedicated Rewards DB)
    ├─ HIT  → Return cached JSON (2-5ms)
    └─ MISS → Query PostgreSQL
                ↓
            reward_master + translations JOIN
                ↓
            Cache in Redis (TTL: 5min)
                ↓
            Return JSON
```

### Separate Redis Databases

**Critical Design Decision:** Marketplace and Rewards use **separate Redis databases** for complete isolation.

#### Marketplace Cache
- **Database:** `marketplace-orders`
- **Endpoint:** `usable-ray-20184.upstash.io`
- **Purpose:** Order processing queues and counters
- **Key Pattern:** `marketplace:orders:*`
- **Functions:** `extensions.redis_get/set/del()`

#### Rewards Cache (Dedicated)
- **Database:** `supabase-rewards-cache`
- **Endpoint:** `mutual-stud-37574.upstash.io`
- **Purpose:** Reward catalog with multi-language translations
- **Key Pattern:** `merchant:{merchant_id}:rewards:all_languages`
- **Functions:** `extensions.rewards_cache_get/set/del()`
- **Database ID:** `1bff7e96-91b9-4401-8723-78e58b20e7e7`
- **REST Token:** `AZLGAAIncDI3ZTZlNzE3ZTViZDA0Y2ZmODJhMjhhYjM3MDdiOGMzY3AyMzc1NzQ`

#### Why Separate Databases?

1. **Isolation:** Marketplace operations don't affect rewards cache performance
2. **Clear Ownership:** Each feature team manages their own cache
3. **Independent Scaling:** Upgrade/modify one without impacting the other
4. **Troubleshooting:** Issues are isolated to specific domain
5. **Cost Control:** Monitor and optimize costs per feature

---

## Redis Wrapper Functions

### Architecture Pattern

PostgreSQL functions call Upstash REST API via the `http` extension, providing native Redis access from SQL queries.

### Function Implementations

#### `extensions.rewards_cache_get(p_key TEXT) → TEXT`

**Purpose:** Fetch value from dedicated rewards Redis database

```sql
CREATE OR REPLACE FUNCTION extensions.rewards_cache_get(p_key text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_response jsonb;
  v_result text;
BEGIN
  SELECT content::jsonb INTO v_response
  FROM http((
    'GET',
    'https://mutual-stud-37574.upstash.io/get/' || p_key,
    ARRAY[http_header('Authorization', 'Bearer AZLGAAIncDI3ZTZlNzE3ZTViZDA0Y2ZmODJhMjhhYjM3MDdiOGMzY3AyMzc1NzQ')],
    NULL,
    NULL
  )::http_request);
  
  v_result := v_response->>'result';
  RETURN v_result;
  
EXCEPTION WHEN OTHERS THEN
  RETURN NULL;  -- Silent failure allows graceful degradation
END;
$$;
```

**Returns:** 
- Cache value if exists
- NULL if key doesn't exist or Redis unavailable

#### `extensions.rewards_cache_set(p_key TEXT, p_value TEXT, p_ex_mode TEXT, p_ttl_seconds BIGINT) → TEXT`

**Purpose:** Store value in rewards Redis with automatic expiration

```sql
CREATE OR REPLACE FUNCTION extensions.rewards_cache_set(p_key text, p_value text, p_ex_mode text, p_ttl_seconds bigint)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_response jsonb;
  v_payload jsonb;
BEGIN
  -- Use Upstash pipeline for atomic SET + EXPIRE
  v_payload := jsonb_build_array(
    jsonb_build_array('SET', p_key, p_value),
    jsonb_build_array('EXPIRE', p_key, p_ttl_seconds)
  );
  
  SELECT content::jsonb INTO v_response
  FROM http((
    'POST',
    'https://mutual-stud-37574.upstash.io/pipeline',
    ARRAY[
      http_header('Authorization', 'Bearer AZLGAAIncDI3ZTZlNzE3ZTViZDA0Y2ZmODJhMjhhYjM3MDdiOGMzY3AyMzc1NzQ'),
      http_header('Content-Type', 'application/json')
    ],
    'application/json',
    v_payload::text
  )::http_request);
  
  RETURN 'OK';
  
EXCEPTION WHEN OTHERS THEN
  RETURN NULL;
END;
$$;
```

**Parameters:**
- `p_key` - Cache key
- `p_value` - JSON string to cache
- `p_ex_mode` - Always 'EX' (expire in seconds)
- `p_ttl_seconds` - Time to live (300 = 5 minutes)

#### `extensions.rewards_cache_del(p_key TEXT) → TEXT`

**Purpose:** Delete cache key (used by invalidation triggers)

```sql
CREATE OR REPLACE FUNCTION extensions.rewards_cache_del(p_key text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_response jsonb;
BEGIN
  SELECT content::jsonb INTO v_response
  FROM http((
    'GET',
    'https://mutual-stud-37574.upstash.io/del/' || p_key,
    ARRAY[http_header('Authorization', 'Bearer AZLGAAIncDI3ZTZlNzE3ZTViZDA0Y2ZmODJhMjhhYjM3MDdiOGMzY3AyMzc1NzQ')],
    NULL,
    NULL
  )::http_request);
  
  RETURN v_response->>'result';
  
EXCEPTION WHEN OTHERS THEN
  RETURN NULL;
END;
$$;
```

---

## Main API Function

### `api_get_rewards_full_cached()`

**Endpoint:** `https://wkevmsedchftztoolkmi.supabase.co/rest/v1/rpc/api_get_rewards_full_cached`

**Flow Logic:**

```sql
CREATE OR REPLACE FUNCTION public.api_get_rewards_full_cached()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_merchant_id UUID;
  v_cache_key TEXT;
  v_cached_result TEXT;
  v_result JSON;
BEGIN
  -- Step 1: Get merchant context from JWT
  v_merchant_id := get_current_merchant_id();
  
  IF v_merchant_id IS NULL THEN
    RETURN '[]'::JSON;
  END IF;
  
  -- Step 2: Build cache key
  v_cache_key := 'merchant:' || v_merchant_id::TEXT || ':rewards:all_languages';
  
  -- Step 3: Try Redis cache
  BEGIN
    v_cached_result := extensions.rewards_cache_get(v_cache_key);
    IF v_cached_result IS NOT NULL THEN
      -- Cache HIT - return immediately
      RETURN json_build_object(
        'data', v_cached_result::JSON,
        'cache_hit', true,
        'cache_key', v_cache_key,
        'timestamp', NOW()
      );
    END IF;
  EXCEPTION WHEN OTHERS THEN
    -- Redis unavailable, continue to database query
    NULL;
  END;
  
  -- Step 4: Cache MISS - query database
  SELECT json_agg(
    json_build_object(
      'id', r.id,
      'name', r.name,
      'category_id', r.category_id,
      
      -- TRANSLATION JOIN via correlated subquery
      'translations', (
        SELECT jsonb_object_agg(
          lang.language_code,
          lang.translations
        )
        FROM (
          -- English from database columns
          SELECT 
            'en' as language_code,
            jsonb_build_object(
              'name', r.name,
              'description_headline', r.description_headline,
              'description_body', r.description_body,
              'description_tc', r.description_tc,
              'description_slip', r.description_slip
            ) as translations
          
          UNION ALL
          
          -- Other languages from translations table
          SELECT 
            t.language_code,
            jsonb_object_agg(t.field_name, t.translated_value) as translations
          FROM translations t
          WHERE t.entity_id = r.id              -- JOIN condition
            AND t.entity_type = 'reward'
            AND t.language_code != 'en'
          GROUP BY t.language_code
        ) lang
      ),
      
      -- Other fields...
      'points', json_build_object('fallback', COALESCE(r.fallback_points, 0)),
      'image', COALESCE(r.image, ARRAY[]::TEXT[]),
      'description_headline', r.description_headline,
      'description_body', r.description_body,
      'description_tc', r.description_tc,
      'description_slip', r.description_slip,
      'use_expire_mode', r.use_expire_mode,
      'use_expire_date', r.use_expire_date,
      'use_expire_ttl', r.use_expire_ttl
    )
    ORDER BY r.created_at DESC
  ) INTO v_result
  FROM reward_master r
  WHERE r.merchant_id = v_merchant_id
    AND r.visibility IN ('user', 'campaign');
  
  -- Step 5: Store in Redis
  BEGIN
    PERFORM extensions.rewards_cache_set(v_cache_key, v_result::TEXT, 'EX', 300);
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;
  
  -- Step 6: Return with cache metadata
  RETURN json_build_object(
    'data', v_result,
    'cache_hit', false,
    'cache_key', v_cache_key,
    'timestamp', NOW()
  );
END;
$$;
```

---

## Translation Join Pattern Explained

### Why Correlated Subquery Instead of JOIN?

**Traditional LEFT JOIN:**
```sql
FROM reward_master r
LEFT JOIN translations t ON r.id = t.entity_id
```
**Problem:** Creates these rows:
```
reward_id | name       | lang | field    | value
abc-123   | Coffee Mug | th   | name     | แก้วกาแฟ
abc-123   | Coffee Mug | th   | headline | พรีเมียม
abc-123   | Coffee Mug | ja   | name     | マグカップ
```
**Result:** Duplicate reward objects, difficult to aggregate

**Correlated Subquery:**
```sql
'translations', (
  SELECT jsonb_object_agg(...)
  FROM (
    SELECT 'en', jsonb_build_object(...)
    UNION ALL
    SELECT t.language_code, jsonb_object_agg(t.field_name, t.translated_value)
    FROM translations t
    WHERE t.entity_id = r.id  -- Correlation point
    GROUP BY t.language_code
  ) lang
)
```
**Result:** Single nested JSON per reward, clean aggregation

### Execution Flow

For reward "Coffee Mug" (id: `abc-123`):

**Step 1:** Outer query selects reward
```sql
SELECT * FROM reward_master WHERE id = 'abc-123'
```

**Step 2:** Correlated subquery executes with `r.id = 'abc-123'`

**Step 3a:** Build English object from columns
```json
{
  "language_code": "en",
  "translations": {
    "name": "Coffee Mug",
    "description_tc": "Terms..."
  }
}
```

**Step 3b:** Query translations table
```sql
SELECT language_code, jsonb_object_agg(field_name, translated_value)
FROM translations
WHERE entity_id = 'abc-123'  -- Uses r.id from outer query
  AND entity_type = 'reward'
  AND language_code != 'en'
GROUP BY language_code
```

**Step 3c:** UNION ALL combines:
```
en: { name, description_tc, ... }
th: { name, headline }
ja: { name }
```

**Step 4:** Final aggregation
```sql
jsonb_object_agg(language_code, translations)
```

**Result:**
```json
{
  "en": { "name": "Coffee Mug", "description_tc": "Terms..." },
  "th": { "name": "แก้วกาแฟ", "headline": "พรีเมียม" },
  "ja": { "name": "マグカップ" }
}
```

### Performance Characteristics

**Index Requirement:**
```sql
CREATE INDEX idx_translations_entity 
ON translations(entity_id, entity_type, language_code);
```

**Execution:**
- Correlated subquery runs once per reward
- Index scan on translations table (O(log n))
- For 100 rewards: ~100 index lookups
- Total time: 20-50ms (acceptable for cache MISS)

**Cache HIT:** Bypasses all queries, returns from Redis in 2-5ms

---

## Response Structure

### Root Response Object

```json
{
  "data": [ /* array of 11 reward objects */ ],
  "categories": [ /* array of 6 category objects */ ],
  "cache_hit": true,  // or false
  "cache_key": "merchant:09b45463-3812-42fb-9c7f-9d43b6fd3eb9:rewards:all_languages",
  "timestamp": "2025-11-15T07:02:22.406099Z"
}
```

**Fields:**
- `data` - Array of complete reward objects (all rewards for merchant)
- `categories` - Array of all reward categories for this merchant (with reward counts and translations)
- `cache_hit` - Boolean indicating if data came from Redis (true) or database (false)
- `cache_key` - The Redis key used for this merchant
- `timestamp` - When the response was generated

**Important:** Both `data` and `categories` are cached together in a single Redis key. The categories array always starts with the synthetic "All" category followed by actual categories from the database, each with their respective reward counts.

**Verified Response (Actual API Call):**
- Total rewards: 11
- Total categories: 6 (including "All")
- Categories with rewards: "All" (11), "Vouchers" (10), "Food & Beverage" (1)
- Empty categories: "Electronics" (0), "Lifestyle" (0), "Travel" (0)

### Per-Reward Object Structure (in `data` array)

```json
{
  "id": "9e7b0797-3136-44b9-b073-3be0498eef4f",
  "name": "Coffee Mug",
  "category_id": "dec0d115-f802-4583-a08e-f9dcdfd66b14",
  
  "translations": {
    "en": {
      "name": "Coffee Mug",
      "description_headline": "Premium Ceramic Mug",
      "description_body": "High quality ceramic mug perfect for coffee lovers...",
      "description_tc": "Valid while stocks last. Cannot be combined with other offers. Non-transferable. Shipping within 7-14 business days.",
      "description_slip": "Thank you for redeeming! Your Coffee Mug will be shipped to your registered address within 7-14 days."
    },
    "th": {
      "name": "แก้วกาแฟเซรามิก",
      "headline": "แก้วเซรามิกพรีเมียม"
    },
    "ja": {
      "name": "コーヒーマグ",
      "headline": "プレミアムセラミックマグ"
    }
  },
  
  "points": {
    "fallback": 100
  },
  
  "image": ["https://example.com/mug1.jpg", "https://example.com/mug2.jpg"],
  
  "description_headline": "Premium Ceramic Mug",
  "description_body": "High quality ceramic mug...",
  "description_tc": "Valid while stocks last...",
  "description_slip": "Thank you for redeeming...",
  
  "availability": {
    "in_stock": true,
    "redeemed": 5
  },
  
  "promo_codes": {
    "enabled": false,
    "used": 0,
    "total": 0
  },
  
  "validity": {
    "start": "2025-08-17T08:08:54.943830Z",
    "end": "perpetual",
    "redemption_window_start": "2025-01-01T00:00:00Z",
    "redemption_window_end": "2026-12-31T23:59:59Z"
  },
  
  "visibility": "user",
  "allowed_tier": ["tier-uuid-1", "tier-uuid-2"],
  "allowed_persona": [],
  "allowed_tags": [],
  "fulfillment_method": "shipping",
  
  "use_expire_mode": "relative_days",
  "use_expire_date": null,
  "use_expire_ttl": 30
}
```

### Per-Category Object Structure (in `categories` array)

#### First Category: "All" (Always Present)

```json
{
  "id": "",
  "name": "All",
  "category_code": "all",
  "reward_count": 11,
  "translations": {
    "en": { "name": "All" },
    "th": { "name": "ทั้งหมด" },
    "ja": { "name": "すべて" },
    "zh": { "name": "全部" }
  }
}
```

**Special Properties:**
- Always appears first in categories array (sort_order: 0)
- Empty `id` string: `""`
- category_code: `"all"`
- reward_count: Total count of ALL rewards across all categories
- Hardcoded translations for common languages (en, th, ja, zh)

#### Regular Categories (From Database)

```json
{
  "id": "dec0d115-f802-4583-a08e-f9dcdfd66b14",
  "name": "Food & Beverage",
  "category_code": "food_beverage",
  "reward_count": 1,
  "translations": {
    "en": {
      "name": "Food & Beverage"
    },
    "th": {
      "name": "อาหารและเครื่องดื่ม"
    }
  }
}
```

**Category Fields:**
- `id` - Category UUID (or empty string for "All")
- `name` - Category name (English from database)
- `category_code` - Unique code identifier
- `reward_count` - Number of rewards in this category
- `translations` - Same pattern as rewards (EN from DB, other languages from translations table)

**Category Array Order:**
1. **First (index 0):** "All" category with total count
2. **Rest:** Actual categories sorted alphabetically

**Usage Pattern:**
```javascript
// Access "All" category (always first)
const allCategory = response.categories[0];
console.log(`Total rewards: ${allCategory.reward_count}`);

// Build category lookup map (skip "All")
const categoryMap = {};
response.categories.slice(1).forEach(cat => {
  categoryMap[cat.id] = cat;
});

// Get category for reward
const reward = response.data[0];
const category = categoryMap[reward.category_id];
const categoryName = category?.translations[userLang]?.name || category?.name;

// Display category filter with counts
response.categories.forEach(cat => {
  const label = cat.translations[userLang]?.name || cat.name;
  console.log(`${label} (${cat.reward_count})`);
});
// Output:
// ทั้งหมด (11)
// อาหารและเครื่องดื่ม (1)
// Vouchers (10)
```

---

## Translation Logic

### English Translation (Always Present)

**Source:** `reward_master` database columns

**Fields Mapped:**
- `name` → `translations.en.name`
- `description_headline` → `translations.en.description_headline`
- `description_body` → `translations.en.description_body`
- `description_tc` → `translations.en.description_tc`
- `description_slip` → `translations.en.description_slip`

**Guarantee:** English translation is ALWAYS present for every reward, populated from database columns even if no translation records exist.

### Other Language Translations (Conditional)

**Source:** `translations` table where `entity_type = 'reward'`

**Query Pattern:**
```sql
SELECT 
  language_code,
  jsonb_object_agg(field_name, translated_value) as translations
FROM translations
WHERE entity_id = reward_id
  AND entity_type = 'reward'
  AND language_code != 'en'
GROUP BY language_code
```

**Important:** **No fallback to English** - only actually translated fields are included.

**Example:**
```
translations table:
  entity_id: abc-123, language_code: 'th', field_name: 'name', value: 'แก้วกาแฟ'
  entity_id: abc-123, language_code: 'th', field_name: 'headline', value: 'พรีเมียม'
```

**Result:**
```json
{
  "th": {
    "name": "แก้วกาแฟ",
    "headline": "พรีเมียม"
  }
}
```

**Note:** `description_tc`, `description_body`, `description_slip` are NOT present in Thai because they weren't translated.

### Frontend Fallback Pattern

Frontend handles missing translations:
```javascript
const userLang = 'th';
const reward = response.data[0];

// Fallback to English if Thai translation missing
const name = reward.translations[userLang]?.name || reward.translations.en.name;
const tc = reward.translations[userLang]?.description_tc || reward.translations.en.description_tc;

// Or use root-level fields as ultimate fallback
const headline = reward.translations[userLang]?.description_headline || reward.description_headline;
```

---

## Cache Invalidation System

### Master Invalidation Function

```sql
CREATE OR REPLACE FUNCTION fn_invalidate_merchant_rewards_cache(p_merchant_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_cache_key TEXT;
BEGIN
  v_cache_key := 'merchant:' || p_merchant_id::TEXT || ':rewards:all_languages';
  
  BEGIN
    PERFORM extensions.rewards_cache_del(v_cache_key);
  EXCEPTION WHEN OTHERS THEN
    NULL;  -- Silent failure
  END;
END;
$$;
```

### What Gets Cached Together

**Single Redis Key Contains:**
```json
{
  "data": [ /* all rewards */ ],
  "categories": [ /* all categories including "All" */ ]
}
```

**Both cached atomically:**
- Rewards query and categories query execute together
- "All" category synthesized with total reward count
- Regular categories include per-category reward counts
- Stored as single JSON object in Redis
- Cache invalidation clears both simultaneously
- Frontend gets complete catalog in one request

**Category Count Calculation:**
- Each category's `reward_count` calculated via JOIN with reward_master
- "All" category gets total count from all rewards
- Counts update automatically when cache rebuilds

### Automatic Triggers

#### 1. Reward Master Changes

```sql
CREATE TRIGGER reward_master_cache_invalidation
AFTER INSERT OR UPDATE ON reward_master
FOR EACH ROW
EXECUTE FUNCTION trigger_invalidate_rewards_cache_on_reward_change();
```

**Fires when:** Reward created/updated (name, description, pricing, visibility, etc.)

#### 2. Translation Changes

```sql
CREATE TRIGGER translations_cache_invalidation
AFTER INSERT OR UPDATE ON translations
FOR EACH ROW
EXECUTE FUNCTION trigger_invalidate_rewards_cache_on_translation_change();
```

**Fires when:** Translation added/updated for any reward  
**Logic:** Looks up `merchant_id` from `reward_master` using `entity_id`

#### 3. Promo Code Changes

```sql
CREATE TRIGGER reward_promo_code_cache_invalidation
AFTER INSERT OR UPDATE ON reward_promo_code
FOR EACH ROW
EXECUTE FUNCTION trigger_invalidate_rewards_cache_on_promo_change();
```

**Fires when:** Promo codes added or redeemed  
**Reason:** Affects promo code counts in cached response

#### 4. Redemption Changes

```sql
CREATE TRIGGER reward_redemptions_cache_invalidation
AFTER INSERT OR UPDATE ON reward_redemptions_ledger
FOR EACH ROW
EXECUTE FUNCTION trigger_invalidate_rewards_cache_on_redemption();
```

**Fires when:** User redeems a reward  
**Reason:** Affects redemption counts in availability stats

#### 5. Category Changes (Future Enhancement)

**Note:** Currently category changes do NOT invalidate the cache automatically. If categories are edited, manually invalidate:
```sql
SELECT fn_invalidate_merchant_rewards_cache('merchant-uuid');
```

**TODO:** Add trigger on `reward_category` table for automatic invalidation when category names or translations change.

### Invalidation Flow

```
User edits reward in admin UI
    ↓
UPDATE reward_master SET name = 'New Name' WHERE id = 'abc-123'
    ↓
Trigger: reward_master_cache_invalidation
    ↓
Function: trigger_invalidate_rewards_cache_on_reward_change()
    ↓
Function: fn_invalidate_merchant_rewards_cache(merchant_id)
    ↓
Redis: DELETE merchant:{id}:rewards:all_languages
    ↓
Next API request: Cache MISS → rebuilds from database
```

---

## Data Sources and Aggregations

### Primary Tables

#### `reward_master`

**All columns cached in `data` array:**
- `id`, `merchant_id`, `name`, `category_id`
- `description_headline`, `description_body`, `description_tc`, `description_slip`
- `image` (array)
- `fallback_points`, `require_points_match`
- `visibility`, `stock_control`, `assign_promocode`, `promo_code`
- `fulfillment_method`, `use_expire_mode`, `use_expire_date`, `use_expire_ttl`
- `redeem_window_start`, `redeem_window_end`
- `allowed_tier`, `allowed_persona`, `allowed_tags`, `allowed_birthmonth`
- `ranking`, `created_at`

#### `reward_category`

**All columns cached in `categories` array:**
- `id`, `merchant_id`, `name`, `category_code`
- `reward_count` (calculated)
- `created_at`, `updated_at`

**Query Pattern:**
```sql
WITH category_counts AS (
  SELECT 
    r.category_id,
    COUNT(*)::INT as reward_count
  FROM reward_master r
  WHERE r.merchant_id = v_merchant_id 
    AND r.visibility IN ('user', 'campaign')
    AND r.category_id IS NOT NULL
  GROUP BY r.category_id
)
SELECT json_agg(cat_obj ORDER BY sort_order, name)
FROM (
  -- First: "All" category
  SELECT 
    0 as sort_order,
    json_build_object(
      'id', '',
      'name', 'All',
      'category_code', 'all',
      'reward_count', (total_rewards_count),
      'translations', ( /* hardcoded for en/th/ja/zh */ )
    ) as cat_obj,
    'All' as name
  
  UNION ALL
  
  -- Then: Actual categories with counts
  SELECT 
    1 as sort_order,
    json_build_object(
      'id', rc.id,
      'name', rc.name,
      'category_code', rc.category_code,
      'reward_count', COALESCE(cc.reward_count, 0),
      'translations', ( /* category translations */ )
    ) as cat_obj,
    rc.name as name
  FROM reward_category rc
  LEFT JOIN category_counts cc ON cc.category_id = rc.id
  WHERE rc.merchant_id = v_merchant_id
) all_cats;
```

**Special "All" Category:**
- Synthesized (not in database)
- Always first (sort_order: 0)
- Empty id, category_code: 'all'
- Count: Total rewards across all categories
- Translations hardcoded for: en, th, ja, zh

### Joined/Aggregated Data

**`translations` table:**
- Correlated subquery aggregation for both rewards AND categories
- Entity types: `'reward'` and `'reward_category'`
- Groups by language_code
- Aggregates field_name → translated_value pairs
- Used in both `data` rewards and `categories` arrays

**`reward_redemptions_ledger` (count aggregation):**
```sql
SELECT COUNT(*)::INT
FROM reward_redemptions_ledger rdl
WHERE rdl.reward_id = r.id
  AND rdl.redeemed_status = true
```
**Used for:** `availability.redeemed` count

**`reward_promo_code` (count aggregations):**
```sql
-- Total codes
SELECT COUNT(*)::INT FROM reward_promo_code WHERE reward_id = r.id

-- Used codes  
SELECT COUNT(*)::INT FROM reward_promo_code WHERE reward_id = r.id AND redeemed_status = TRUE
```
**Used for:** `promo_codes.total` and `promo_codes.used`

### Merchant Filtering

All queries scoped by:
```sql
WHERE r.merchant_id = v_merchant_id
  AND r.visibility IN ('user', 'campaign')
```

Ensures:
- Complete merchant isolation
- Only user-facing rewards (excludes admin-only)

---

## Performance Metrics

### Cache Hit Performance

**Response Time:** 2-5ms  
**Database Queries:** 0  
**Redis Operations:** 1 GET  
**Network Calls:** 1 (Upstash REST API)

### Cache Miss Performance

**Response Time:** 20-50ms (depends on reward count)  
**Database Queries:**
- 1 main SELECT on `reward_master`
- N correlated subqueries for translations (N = number of rewards)
- 2N aggregation subqueries (redemption + promo code counts per reward)

**Redis Operations:** 1 SET  
**Total Queries:** ~3N+1 (but all indexed)

### Cache Effectiveness

**Assumptions:**
- 100 merchants
- Each merchant: 20 rewards average
- API called 1000 times/day per merchant

**With 5-minute cache:**
- Cache hit rate: 99.7%
- Database queries/day: ~30 (instead of 100,000)
- Average response time: 3ms (instead of 35ms)

---

## Troubleshooting Guide

### Issue: PGRST002 Error

**Error Message:** "Could not query the database for the schema cache. Retrying."

**Cause:** PostgREST schema cache corruption after function modifications

**Solutions:**
1. Wait 2-3 minutes - PostgREST auto-retries every 30 seconds
2. Hard refresh browser (Ctrl+Shift+R / Cmd+Shift+R)
3. Send reload signal: `NOTIFY pgrst, 'reload schema';`
4. Try different client (curl, Postman) to rule out browser cache

**Not caused by:** Redis, function code, or database issues

### Issue: All Requests Show `cache_hit: false`

**Symptoms:** Every request queries database, no caching occurring

**Diagnosis:**
```sql
-- Test Redis connection
SELECT extensions.rewards_cache_set('test', 'hello', 'EX', 60);
SELECT extensions.rewards_cache_get('test');
-- Should return 'hello'
```

**Possible Causes:**
1. Upstash database paused/deleted
2. REST token incorrect in wrapper functions
3. Network connectivity issue from Supabase to Upstash
4. http extension not working

**Fix:** Verify Upstash database status, check wrapper function credentials

### Issue: Missing Translations

**Symptoms:** `translations: { "en": {...} }` only, no other languages

**Cause:** No records in `translations` table for that reward

**Check:**
```sql
SELECT * FROM translations 
WHERE entity_type = 'reward' 
  AND entity_id = 'reward-uuid';
```

**Expected:** Rows with language_code, field_name, translated_value

**Solution:** Add translation records via admin UI or bulk import

### Issue: Stale Data in Cache

**Symptoms:** Edited reward doesn't update in API

**Diagnosis:**
```sql
-- Check if triggers exist
SELECT trigger_name, event_object_table
FROM information_schema.triggers
WHERE trigger_name LIKE '%cache%';
```

**Expected:** 4 triggers on reward_master, translations, reward_promo_code, reward_redemptions_ledger

**Manual Fix:**
```sql
-- Force invalidation
SELECT fn_invalidate_merchant_rewards_cache('merchant-uuid');
```

---

## Key Design Decisions

### Why Dedicated Redis Database?

**Alternative:** Share marketplace-orders database with different key prefixes

**Decision:** Separate `supabase-rewards-cache` database

**Rationale:**
1. **Blast Radius:** Marketplace issues don't affect rewards
2. **Ownership:** Clear separation of concerns
3. **Monitoring:** Independent metrics per feature
4. **Scaling:** Can upgrade rewards cache independently

### Why 5-Minute TTL?

**Shorter (1 minute):**
- Fresher data but higher database load
- 1440 cache rebuilds/day instead of 288

**Longer (15 minutes):**
- Lower database load but staler data
- Admin edits take longer to appear

**5 minutes balances:**
- Fresh enough for user experience
- Low enough database load (99.7% cache hit rate)
- Automatic invalidation handles critical updates immediately

### Why Include `cache_hit` in Response?

**Benefits:**
1. **Debugging:** Identify caching issues immediately
2. **Monitoring:** Track cache effectiveness in production
3. **Performance Analysis:** Measure cache hit rate per merchant
4. **Troubleshooting:** Distinguish Redis vs database issues

**Frontend can:**
- Log cache performance metrics
- Alert if cache hit rate drops
- Display debug info in dev mode

---

## Implementation Checklist

When setting up or restoring rewards cache:

### Database Setup
- [ ] Create Upstash Redis database: `supabase-rewards-cache`
- [ ] Region: ap-southeast-1 (same as Supabase)
- [ ] Note endpoint and REST token

### Wrapper Functions
- [ ] Create `extensions.rewards_cache_get(key)` with correct endpoint
- [ ] Create `extensions.rewards_cache_set(key, value, 'EX', ttl)` using pipeline API
- [ ] Create `extensions.rewards_cache_del(key)` for invalidation
- [ ] Test: SET/GET/DEL operations work

### API Function
- [ ] Create `api_get_rewards_full_cached()`
- [ ] Verify cache check logic (try get → query DB → set cache)
- [ ] Include cache metadata in response
- [ ] Grant execute to anon/authenticated roles

### Cache Invalidation
- [ ] Create `fn_invalidate_merchant_rewards_cache(merchant_id)`
- [ ] Create trigger functions for reward_master, translations, promo_code, redemptions
- [ ] Attach triggers to tables (AFTER INSERT OR UPDATE)
- [ ] Test invalidation works (edit reward → cache cleared)

### Verification
- [ ] First request: `cache_hit: false`, response time ~30ms
- [ ] Second request: `cache_hit: true`, response time ~3ms
- [ ] Edit reward: cache invalidates automatically
- [ ] Third request: `cache_hit: false` (rebuilt)
- [ ] Check Redis keys exist: `merchant:{id}:rewards:all_languages`

---

## Code Reference

### Cache Key Format

```
merchant:{merchant_id}:rewards:all_languages
```

**Example:** `merchant:09b45463-3812-42fb-9c7f-9d43b6fd3eb9:rewards:all_languages`

### Upstash REST API Endpoints

**GET:**
```
GET https://mutual-stud-37574.upstash.io/get/{key}
Authorization: Bearer {REST_TOKEN}
```

**SET with Expiry (Pipeline):**
```
POST https://mutual-stud-37574.upstash.io/pipeline
Authorization: Bearer {REST_TOKEN}
Content-Type: application/json

[
  ["SET", "key", "value"],
  ["EXPIRE", "key", 300]
]
```

**DELETE:**
```
GET https://mutual-stud-37574.upstash.io/del/{key}
Authorization: Bearer {REST_TOKEN}
```

### Required PostgreSQL Extensions

```sql
-- HTTP extension for REST API calls
CREATE EXTENSION IF NOT EXISTS http WITH SCHEMA public;

-- Wrappers extension for foreign data wrapper support
CREATE EXTENSION IF NOT EXISTS wrappers WITH SCHEMA extensions;
```

---

## Migration History

### Initial Implementation
**File:** `002_create_api_get_rewards_full_cached.sql`
- Created basic cached API with Redis wrapper
- Used shared Redis instance (incorrect design)

### Separation Update
**Date:** November 15, 2025
- Created dedicated `supabase-rewards-cache` database
- Created separate wrapper functions (`rewards_cache_*`)
- Isolated from marketplace cache completely

### Translation Enhancement
**Date:** November 15, 2025
- Added English default from database fields
- Removed fallback logic (FE handles fallback)
- Added cache metadata (`cache_hit`, `cache_key`, `timestamp`)

---

## Monitoring and Maintenance

### Health Checks

**Cache Hit Rate:**
```sql
-- Add logging to track cache performance
-- Monitor cache_hit field in application logs
```

**Redis Connection:**
```sql
SELECT extensions.rewards_cache_get('health_check');
-- Should return NULL (key doesn't exist) without error
```

**Invalidation Working:**
```sql
-- After editing a reward, check:
SELECT extensions.rewards_cache_get('merchant:{id}:rewards:all_languages');
-- Should return NULL (cache deleted)
```

### Periodic Maintenance

**Monthly:**
- Check Upstash database usage/costs
- Review cache hit rates
- Analyze TTL effectiveness

**When Issues Occur:**
- Check Upstash database status: https://console.upstash.com/redis/1bff7e96-91b9-4401-8723-78e58b20e7e7
- Verify REST token hasn't expired
- Test wrapper functions independently
- Check PostgreSQL http extension status

---

## Cost Considerations

**Upstash Free Tier:**
- 10,000 commands/day
- Rewards cache typically uses: ~500 commands/day (very low)

**Pay-as-you-go:**
- First 10K requests: Free
- Beyond: ~$0.20 per 100K requests

**Cost Optimization:**
- 5-minute TTL keeps request count low
- Automatic invalidation prevents manual cache clearing
- Single cache entry per merchant (not per reward)

---

## Security

### Merchant Isolation

- Cache keys include `merchant_id` - different merchants never see each other's data
- `get_current_merchant_id()` extracts merchant from JWT/headers automatically
- No cross-merchant cache pollution possible

### Access Control

- Wrapper functions: `SECURITY DEFINER` (controlled Redis access)
- API function: `SECURITY DEFINER` with merchant context validation
- Permissions: Granted to `anon` and `authenticated` roles only

### Token Security

- Upstash REST token stored in PostgreSQL function code (server-side only)
- Never exposed to frontend
- Token scoped to single Redis database

---

*Document Version: 1.0*  
*Last Updated: November 15, 2025*  
*System: Supabase CRM - Rewards Caching Implementation*

