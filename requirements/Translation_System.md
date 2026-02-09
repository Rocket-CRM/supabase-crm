# Translation System - Complete Architecture & Implementation Guide

## Executive Summary

The Supabase CRM implements a sophisticated multi-language translation system supporting both **dynamic entity-based translations** (rewards, forms, personas) and **static UI text translations** (page titles, buttons, messages). The system leverages a two-layer architecture with merchant-specific default language support, Redis caching for performance, and complete database isolation per translation domain.

**Supported Languages:** English (en), Thai (th), Japanese (ja), Chinese (zh)

**Key Features:**
- Merchant-specific default language configuration
- Automatic fallback chains (requested → merchant_default → English)
- Isolated Redis caches per domain (no cross-contamination)
- Sub-100ms response times via intelligent caching
- Centralized management via single API endpoints

---

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Dynamic Entity Translations](#dynamic-entity-translations)
- [Static UI Translations](#static-ui-translations)
- [Cache Architecture](#cache-architecture)
- [Merchant Language Configuration](#merchant-language-configuration)
- [API Reference](#api-reference)
- [Adding New Translations](#adding-new-translations)
- [Best Practices](#best-practices)

---

## Architecture Overview

### Two Translation Systems

```
┌─────────────────────────────────────────────────────────────┐
│ TRANSLATION SYSTEM                                          │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────────────────────────┐  ┌────────────────────┐ │
│  │ DYNAMIC TRANSLATIONS         │  │ STATIC UI TEXT     │ │
│  │ (Entity-based)               │  │ (Page-based)       │ │
│  ├──────────────────────────────┤  ├────────────────────┤ │
│  │ • Rewards                    │  │ • Page titles      │ │
│  │ • Form fields                │  │ • Buttons          │ │
│  │ • Personas                   │  │ • Error messages   │ │
│  │ • Consent versions           │  │ • Dialog text      │ │
│  │ • Categories                 │  │ • Labels           │ │
│  │                              │  │                    │ │
│  │ Table: translations          │  │ Table: ui_trans... │ │
│  │ Cache: Per feature           │  │ Cache: Isolated    │ │
│  └──────────────────────────────┘  └────────────────────┘ │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Database Tables

**1. `translations` (Dynamic Content)**
```sql
├─ entity_type: 'reward', 'form_field', 'persona', 'consent_version'
├─ entity_id: UUID of the entity
├─ field_name: 'name', 'description_headline', 'label', etc.
├─ language_code: 'en', 'th', 'ja', 'zh'
├─ translated_value: The translated text
└─ merchant_id: UUID (merchant-specific)
```

**2. `ui_translations` (Static UI Text)**
```sql
├─ page_key: 'signup_form', 'rewards', 'profile_edit'
├─ field_key: 'header_page_title', 'popup_button_confirm'
├─ language_code: 'en', 'th', 'ja', 'zh'
├─ translated_value: The translated text
├─ merchant_id: NULL (global) or UUID (merchant override)
└─ category: 'button', 'label', 'error', 'message', 'title'
```

**3. `merchant_languages` (Configuration)**
```sql
├─ merchant_id: UUID
├─ language_code: 'en', 'th', 'ja', 'zh'
├─ language_name: 'English', 'ไทย', '日本語', '中文'
├─ is_default: BOOLEAN (one per merchant)
├─ is_active: BOOLEAN
└─ display_order: INTEGER
```

---

## Dynamic Entity Translations

### How It Works

Dynamic translations are tied to specific database entities (rewards, form fields, personas). Each entity has its own UUID, and translations reference that UUID.

**Example: Reward Translation**

```sql
-- Reward in reward_master
id: '123e4567-...'
merchant_id: 'merchant-abc'
name: 'Coffee Mug'  -- English base content

-- Thai translation in translations table
entity_type: 'reward'
entity_id: '123e4567-...'  -- References the reward
field_name: 'name'
language_code: 'th'
translated_value: 'แก้วกาแฟ'
```

### Supported Entity Types

| Entity Type | Source Table | Translatable Fields |
|-------------|--------------|---------------------|
| `reward` | `reward_master` | name, description_headline, description_body, description_tc, description_slip |
| `reward_category` | `reward_category` | name |
| `form_field` | `form_fields` | label, placeholder, help_text |
| `form_field_option` | `form_field_options` | option_label |
| `form_field_group` | `form_field_groups` | group_name |
| `user_field_config` | `user_field_config` | label, placeholder, help_text |
| `persona` | `persona_master`, `persona_group_master` | persona_name, group_name |
| `consent_version` | `consent_versions` | title, preview, content |
| `communication_topic` | `communication_topics` | topic_name |
| `tier` | `tier_master` | tier_name |

### Translation Pattern

**Cache Build Phase:**
```sql
-- Store ALL languages in cache
'translations', (
  SELECT jsonb_object_agg(lang.language_code, lang.translations)
  FROM (
    -- Merchant default language from master table
    SELECT 
      v_default_language as language_code,
      jsonb_build_object(
        'name', r.name,
        'description_headline', r.description_headline,
        ...
      ) as translations
    
    UNION ALL
    
    -- Other languages from translations table
    SELECT 
      t.language_code,
      jsonb_object_agg(t.field_name, t.translated_value)
    FROM translations t
    WHERE t.entity_id = r.id
      AND t.entity_type = 'reward'
      AND t.language_code != v_default_language
    GROUP BY t.language_code
  ) lang
)
```

**Result in Cache:**
```json
{
  "translations": {
    "en": {
      "name": "Coffee Mug",
      "description_headline": "Premium Ceramic"
    },
    "th": {
      "name": "แก้วกาแฟ",
      "description_headline": "เซรามิกพรีเมียม"
    }
  }
}
```

**Request-Time Extraction:**
```sql
-- Extract specific language with fallback chain
v_name := COALESCE(
  reward->'translations'->p_language->>'name',      -- Requested language
  reward->'translations'->v_default_language->>'name',  -- Merchant default
  reward->>'name'                                    -- Base value
)
```

### Key APIs Using Dynamic Translations

**1. Rewards Catalog** (`api_get_rewards_full_cached`)
```bash
POST /rest/v1/rpc/api_get_rewards_full_cached
{
  "p_language": "th"
}
```

**2. User Profile Template** (`bff_get_user_profile_template`)
```bash
POST /rest/v1/rpc/bff_get_user_profile_template
{
  "p_mode": "new",
  "p_language": "th",
  "p_merchant_code": "newcrm"
}
```

**3. Mark Redemption Used** (`api_mark_redemption_used`)
```bash
POST /rest/v1/rpc/api_mark_redemption_used
{
  "p_redemption_code": "RWD000123",
  "p_language": "th"
}
```

---

## Static UI Translations

### How It Works

Static UI translations are global text elements (page titles, buttons, error messages) that don't belong to specific database entities.

**Example: Signup Form Button**

```sql
-- In ui_translations table
page_key: 'signup_form'
field_key: 'connect_line_button'
language_code: 'th'
translated_value: 'เชื่อมต่อบัญชี LINE'
merchant_id: NULL  -- Global for all merchants
```

### Naming Convention

Field keys use **section prefixes** for organization:

| Prefix | Usage | Example |
|--------|-------|---------|
| `header_` | Page headers | `header_page_title`, `header_my_reward` |
| `list_` | List view elements | `list_button_redeem`, `list_collect_points` |
| `details_` | Detail view elements | `details_tab_description`, `details_used_at` |
| `filter_` | Filter tabs/buttons | `filter_redeemed`, `filter_used` |
| `popup_` | Dialog/modal content | `popup_redeem_confirm_title`, `popup_button_confirm` |
| (none) | Generic page-level | `page_title`, `button_back` |

### Current UI Pages

**1. Signup Form** (`signup_form`) - 27 fields

**Authentication:**
- `connect_line_button`, `connect_phone_button`

**Phone & OTP:**
- `phone_label`, `phone_placeholder`, `otp_button`, `otp_title`, `otp_subtitle`

**Errors:**
- `error_required_fields`, `error_invalid_phone`, `error_invalid_otp`, `error_otp_expired`

**Navigation:**
- `button_back`, `button_next`, `button_submit`, `button_skip`

**Consent:**
- `consent_accept_all`, `consent_required_message`

**Form Fields:**
- `field_postcode`

---

**2. Rewards Page** (`rewards`) - 25 fields

**Header:**
- `header_page_title` → "รายการของรางวัล"
- `header_my_reward` → "ของรางวัลของฉัน"
- `header_points` → "คะแนน"

**List View:**
- `list_collect_points` → "สะสมคะแนน"

**Details View:**
- `details_button_redeem` → "แลก"
- `details_redeem_limit` → "จำกัดการแลก"
- `details_eligible_tiers` → "ระดับที่สามารถแลกได้"
- `details_tab_description`, `details_tab_terms`
- `details_tab_code`, `details_tab_qr_code`, `details_tab_bar_code`
- `details_button_use` → "ใช้"
- `details_expiry` → "Not available" / "ไม่มีข้อมูล"
- `details_used_at` → "ใช้เมื่อ"

**Filters:**
- `filter_redeemed` → "แลกแล้ว"
- `filter_used` → "ใช้แล้ว"
- `filter_expired` → "หมดอายุ"

**Popups:**
- `popup_redeem_confirm_title` → "แลกเลยไหม?"
- `popup_redeem_confirm_message` → "กรุณายืนยันการแลก"
- `popup_button_cancel`, `popup_button_confirm`
- `popup_success_title` → "แลกสำเร็จ"
- `popup_success_message` → "คุณต้องการทำอะไรต่อ?"
- `popup_button_see_wallet`, `popup_button_use_now`

---

**3. Redemption Status** (`redemption_status`) - 5 statuses

- `status_used` → "ใช้แล้ว"
- `status_redeemed` → "แลกแล้ว"
- `status_expired` → "หมดอายุ"
- `status_cancelled` → "ยกเลิกแล้ว"
- `status_pending` → "รอดำเนินการ"

---

### Global Formula for Component Binding

```javascript
// Formula: static translation (page, field, data)

// Priority logic:
// 1. If data has value → use it
// 2. Otherwise → lookup from translation variable

return (data && data.trim() !== '') 
    ? data 
    : (variables?.['b3741529-ee96-4b1b-9430-07ffc6c832ab']?.[page]?.[field] || '');
```

**Usage:**
```javascript
// Component props:
page: "rewards"
field: "header_page_title"
data: ""

// Result: "รายการของรางวัล"
```

### API for Static UI

**Endpoint:** `GET /rest/v1/rpc/get_ui_translations`

**Get Single Page:**
```bash
POST /rest/v1/rpc/get_ui_translations
{
  "p_page_key": "signup_form",
  "p_language": "th"
}
```

**Get ALL Pages (Recommended for App Init):**
```bash
POST /rest/v1/rpc/get_ui_translations
{
  "p_page_key": null,
  "p_language": "th"
}
```

**Response Structure:**
```json
{
  "cache_hit": true,
  "language": "th",
  "pages": {
    "signup_form": {
      "page_title": "ลงชื่อเข้าใช้เพื่อดำเนินการต่อ",
      "connect_line_button": "เชื่อมต่อบัญชี LINE",
      ...
    },
    "rewards": {
      "header_page_title": "รายการของรางวัล",
      "popup_redeem_confirm_title": "แลกเลยไหม?",
      ...
    }
  }
}
```

**Frontend Usage:**
```javascript
// Load once on app initialization
const { data } = await supabase.rpc('get_ui_translations', {
  p_page_key: null,
  p_language: 'th'
});

// Store in app state
const translations = data.pages;

// Use throughout app
<h1>{translations.rewards.header_page_title}</h1>
<button>{translations.rewards.popup_button_confirm}</button>
```

---

## Cache Architecture

### Isolated Redis Databases

Each translation domain uses its own dedicated Upstash Redis database for complete isolation:

```
Upstash Databases (4 Isolated):

1. supabase-rewards-cache (mutual-stud-37574)
   └─ merchant:X:rewards:all_languages
   └─ Purpose: Rewards catalog with translations
   └─ TTL: 5 minutes

2. supabase-user-profile-cache (crisp-bison-32725)
   └─ merchant:X:user_profile_template:all_languages
   └─ Purpose: Form fields, personas, consent
   └─ TTL: 5 minutes

3. crm-merchant-config-cache (sweet-cardinal-5243)
   └─ merchant:config:{merchant_code}
   └─ Purpose: Merchant settings, default language
   └─ TTL: 30 minutes

4. supabase-ui-translations (free-hound-25865)
   └─ ui:{page_key}:lang:{language}
   └─ ui:all_pages:lang:{language}
   └─ Purpose: Static UI text
   └─ TTL: 1 hour
```

### Why Isolation?

**Benefits:**
1. ✅ Bug in one domain doesn't affect others
2. ✅ Independent monitoring and cost tracking
3. ✅ Can flush one cache without affecting others
4. ✅ Different TTLs per use case
5. ✅ Clear ownership and separation of concerns

**Before (Coupled):**
```
All caches in one database → Change to UI breaks rewards ❌
```

**After (Isolated):**
```
Each cache in own database → UI changes isolated ✅
```

### Cache Invalidation

**Dynamic Translations:**
- Automatic triggers on entity changes (reward_master, translations table)
- Example: Edit reward → cache invalidates → next request rebuilds

**Static UI Translations:**
- Automatic trigger on ui_translations table changes
- Example: Update button text → all language caches clear

**Merchant Config:**
- Automatic trigger on merchant_master or merchant_languages changes
- Example: Change default language → config cache clears

---

## Merchant Language Configuration

### Setup

Each merchant configures their supported languages in `merchant_languages` table:

```sql
-- Example: Syngenta (Thai-first merchant)
merchant_id: syngenta-uuid
language_code: 'th'
is_default: true  ← Thai is primary language

merchant_id: syngenta-uuid
language_code: 'en'
is_default: false  ← English is secondary
```

```sql
-- Example: New CRM (English-first merchant)
merchant_id: newcrm-uuid
language_code: 'en'
is_default: true  ← English is primary

merchant_id: newcrm-uuid
language_code: 'th'
is_default: false  ← Thai is secondary
```

### How Default Language Works

**Cache Building:**
- Master table content (reward_master.name, form_field.label) is labeled with merchant's default language
- Not hardcoded as 'en' anymore

**Example:**
```json
// Syngenta (default: th)
{
  "translations": {
    "th": {...},  // ← From master table columns
    "en": {...}   // ← From translations table
  }
}

// NewCRM (default: en)  
{
  "translations": {
    "en": {...},  // ← From master table columns
    "th": {...}   // ← From translations table
  }
}
```

**Fallback Chain:**
```
Requested Language → Merchant Default → English → Raw Value
```

---

## API Reference

### Dynamic Translation APIs

#### 1. `api_get_rewards_full_cached(p_language)`

**Purpose:** Get rewards catalog with translations

**Request:**
```bash
POST /rest/v1/rpc/api_get_rewards_full_cached
{
  "p_language": "th"
}
```

**Response:**
```json
{
  "data": [
    {
      "id": "...",
      "name": "Coffee Mug",  // Base
      "translations": {
        "en": {"name": "Coffee Mug", "description_headline": "..."},
        "th": {"name": "แก้วกาแฟ", "description_headline": "..."}
      },
      "category_id": [...],
      "image": [...],
      "points": {"fallback": 100},
      "visibility": "user"
    }
  ],
  "categories": [...],
  "cache_hit": true,
  "default_language": "en"
}
```

**Performance:**
- Cache hit: ~50-100ms
- Cache miss: ~160ms (first call per merchant)
- Cache TTL: 5 minutes

---

#### 2. `bff_get_user_profile_template(p_mode, p_language, p_merchant_code, p_event_code)`

**Purpose:** Get form template with translated fields

**Request:**
```bash
POST /rest/v1/rpc/bff_get_user_profile_template
{
  "p_mode": "new",
  "p_language": "th",
  "p_merchant_code": "newcrm"
}
```

**Response:**
```json
{
  "default_fields_config": [
    {
      "group_name": "ข้อมูลพื้นฐาน",
      "fields": [
        {
          "field_key": "email",
          "label": "อีเมล",
          "placeholder": "your@email.com",
          "help_text": "เราจะส่งรหัสยืนยันไปที่อีเมลนี้"
        }
      ]
    }
  ],
  "custom_fields_config": [...],
  "persona": {...},
  "pdpa": [...],
  "cache_hit": true,
  "language": "th",
  "default_language": "en"
}
```

**Performance:**
- Cache hit (new mode): ~106ms
- Cache miss: ~160ms
- Edit mode: +user queries (expected)

---

#### 3. `api_mark_redemption_used(p_redemption_code, p_language)`

**Purpose:** Mark redemption as used with translated response

**Request:**
```bash
POST /rest/v1/rpc/api_mark_redemption_used
{
  "p_redemption_code": "RWD000123",
  "p_language": "th"
}
```

**Response:**
```json
{
  "success": true,
  "data": {
    "redemption_id": "...",
    "redemption_code": "RWD000123",
    "status": "used",
    "status_translation": "ใช้แล้ว",
    "reward_name": "กล่องของขวัญพิเศษ",
    "description_headline": "ของขวัญพรีเมียม",
    "description_body": "รับกล่องของขวัญ...",
    "used_at": "2026-01-06T...",
    "language": "th",
    "default_language": "en"
  }
}
```

---

### Static UI Translation API

#### `get_ui_translations(p_page_key, p_language, p_merchant_code)`

**Purpose:** Get static UI text for pages

**Single Page:**
```bash
POST /rest/v1/rpc/get_ui_translations
{
  "p_page_key": "rewards",
  "p_language": "th"
}
```

**All Pages:**
```bash
POST /rest/v1/rpc/get_ui_translations
{
  "p_page_key": null,
  "p_language": "th"
}
```

**Response:**
```json
{
  "cache_hit": false,
  "language": "th",
  "pages": {
    "signup_form": {
      "page_title": "ลงชื่อเข้าใช้เพื่อดำเนินการต่อ",
      "otp_button": "ขอรหัส OTP",
      ...
    },
    "rewards": {
      "header_page_title": "รายการของรางวัล",
      "popup_button_confirm": "ยืนยัน",
      ...
    }
  }
}
```

**No Authentication Required:** Public endpoint (for login/signup pages)

**Performance:**
- Cache hit: ~50ms (Redis fetch + JSONB parsing)
- Cache miss: ~100ms (query + cache store)
- Cache TTL: 1 hour

---

## Merchant Default Language Implementation

### Before (Hardcoded 'en')

```sql
-- Old approach
SELECT 
  'en' as language_code,  -- ❌ Hardcoded
  json_build_object('name', r.name) as translations
```

**Problem:** Thai-first merchants had content mislabeled as English

---

### After (Merchant-Specific)

```sql
-- New approach
SELECT language_code INTO v_default_language
FROM merchant_languages 
WHERE merchant_id = v_merchant_id AND is_default = true;

SELECT 
  v_default_language as language_code,  -- ✅ Dynamic
  json_build_object('name', r.name) as translations
```

**Benefits:**
- ✅ Syngenta (Thai-first): Content correctly labeled as 'th'
- ✅ NewCRM (English-first): Content correctly labeled as 'en'
- ✅ Fallback behavior matches merchant intent

---

## Adding New Translations

### Adding Dynamic Entity Translations

**For existing entities (rewards, forms, etc.):**

```sql
-- Add Thai translation for a reward
INSERT INTO translations (
    merchant_id,
    entity_type,
    entity_id,
    field_name,
    language_code,
    translated_value
) VALUES (
    'merchant-uuid',
    'reward',
    'reward-uuid',
    'name',
    'th',
    'แก้วกาแฟพรีเมียม'
);
```

**Via Admin UI:** Use translation management interface

---

### Adding Static UI Translations

**For new page:**

```sql
INSERT INTO ui_translations (merchant_id, page_key, field_key, language_code, translated_value, category)
VALUES
-- English
(NULL, 'new_page', 'header_title', 'en', 'Page Title', 'title'),
(NULL, 'new_page', 'button_submit', 'en', 'Submit', 'button'),

-- Thai
(NULL, 'new_page', 'header_title', 'th', 'หัวข้อหน้า', 'title'),
(NULL, 'new_page', 'button_submit', 'th', 'ส่ง', 'button'),

-- Japanese
(NULL, 'new_page', 'header_title', 'ja', 'ページタイトル', 'title'),
(NULL, 'new_page', 'button_submit', 'ja', '送信', 'button'),

-- Chinese
(NULL, 'new_page', 'header_title', 'zh', '页面标题', 'title'),
(NULL, 'new_page', 'button_submit', 'zh', '提交', 'button');
```

**Remember to:**
1. Use NULL for global translations
2. Follow naming convention (section prefixes)
3. Add all 4 languages
4. Clear cache after adding

---

### Merchant-Specific Overrides (Optional)

```sql
-- Override for specific merchant
INSERT INTO ui_translations (
    merchant_id,
    page_key,
    field_key,
    language_code,
    translated_value
) VALUES (
    'syngenta-uuid',  -- Specific merchant
    'signup_form',
    'page_title',
    'th',
    'เข้าสู่ระบบ Syngenta Grower Club'  -- Custom title
);
```

**Lookup Priority:**
```
Merchant-specific → Global → Fallback to English
```

---

## Performance Optimization

### Cache Strategy Summary

| Domain | Cache Miss | Cache Hit | TTL | When to Invalidate |
|--------|-----------|-----------|-----|-------------------|
| **Rewards** | ~160ms | ~100ms | 5 min | Reward/translation changes |
| **User Profile** | ~160ms | ~106ms | 5 min | Form/persona changes |
| **UI Translations** | ~100ms | ~50ms | 1 hour | UI text changes |
| **Merchant Config** | ~10ms | ~2ms | 30 min | Merchant settings change |

### Why Different TTLs?

| Cache | TTL | Reasoning |
|-------|-----|-----------|
| Rewards | 5 min | Balances freshness vs DB load |
| User Profile | 5 min | Form structure changes moderately |
| UI Translations | 1 hour | Static text rarely changes |
| Merchant Config | 30 min | Settings very rarely change |

### Extraction Overhead

**Current approach:**
- Store ALL languages in one cache key
- Extract requested language at request time (JSONB operations)
- Cost: ~50-80ms per request (even on cache hit)

**Why not pre-extract?**
- User has many languages that change often
- Pre-extraction would require cache per language (4x memory)
- More complex invalidation (4 keys to clear vs 1)

**Trade-off accepted:** Extraction overhead (50-80ms) vs simpler cache management

---

## Best Practices

### 1. Translation Content Guidelines

**DO:**
- ✅ Keep translations purely static (no `{variables}` in UI translations)
- ✅ Use consistent tone across languages
- ✅ Translate error messages clearly
- ✅ Respect cultural context (formal vs informal)

**DON'T:**
- ❌ Use machine translation without review
- ❌ Mix languages in single field
- ❌ Include dynamic values in static translations
- ❌ Copy-paste without cultural adaptation

---

### 2. Field Key Naming

**Pattern:** `{section}_{element_type}_{description}`

**Examples:**
```
header_page_title           ← Section: header, Type: page, What: title
details_tab_description     ← Section: details, Type: tab, What: description
popup_button_confirm        ← Section: popup, Type: button, What: confirm
filter_redeemed             ← Section: filter, (implied: button/tab)
```

**Consistency is key** - makes it easier to find and maintain translations

---

### 3. Cache Management

**Clear cache when:**
- Adding new translations
- Changing translation values
- Adding new pages
- Modifying default language

**Commands:**
```sql
-- Clear UI translations
SELECT fn_invalidate_ui_translations_cache();

-- Clear rewards cache
SELECT fn_invalidate_merchant_rewards_cache('merchant-uuid');

-- Clear user profile cache
SELECT fn_invalidate_user_profile_template_cache('merchant-uuid');
```

**Via Upstash MCP:**
```javascript
mcp_upstash_redis_database_run_redis_commands({
  database_id: 'c9383be7-a2ec-45ff-a921-c5282ba495e3',  // UI translations
  commands: [['FLUSHALL']]
});
```

---

### 4. Testing Translations

**Verify all languages:**
```bash
# English
curl ... -d '{"p_page_key": "rewards", "p_language": "en"}'

# Thai
curl ... -d '{"p_page_key": "rewards", "p_language": "th"}'

# Japanese
curl ... -d '{"p_page_key": "rewards", "p_language": "ja"}'

# Chinese
curl ... -d '{"p_page_key": "rewards", "p_language": "zh"}'
```

**Check fallback behavior:**
- Request language with no translation → should fallback to default/English
- Missing field → should show base value

---

### 5. Frontend Integration

**App Initialization:**
```javascript
// Load all UI translations once
const { data } = await supabase.rpc('get_ui_translations', {
  p_page_key: null,
  p_language: userLanguage
});

// Store in global state
window.i18n = data.pages;

// Or use React Context
const TranslationContext = React.createContext(data.pages);
```

**Language Switching:**
```javascript
// User changes language
const switchLanguage = async (newLang) => {
  const { data } = await supabase.rpc('get_ui_translations', {
    p_page_key: null,
    p_language: newLang
  });
  
  setTranslations(data.pages);  // Update state
};
```

**Component Usage:**
```javascript
// Access translations via global formula or state
<h1>{translations.rewards.header_page_title}</h1>
<button>{translations.rewards.popup_button_confirm}</button>
```

---

## Common Issues & Solutions

### Issue: UI Translations Not Updating

**Symptom:** Changed translation in database but UI still shows old text

**Cause:** Browser or Redis cache

**Solution:**
1. Clear Redis cache (via MCP or SQL)
2. Hard refresh browser (Ctrl+Shift+R)
3. Check if using correct cache database

---

### Issue: Wrong Language Showing

**Symptom:** Requested Thai but getting English

**Cause:** Translation doesn't exist in database

**Solution:**
1. Check if translation exists:
```sql
SELECT * FROM ui_translations 
WHERE page_key = 'rewards' AND field_key = 'header_page_title' AND language_code = 'th';
```
2. If missing, add translation
3. Clear cache

---

### Issue: Cache Hit Always False

**Symptom:** Every request shows `cache_hit: false`

**Possible Causes:**
1. Cache SET is failing silently
2. Cache GET retrieving from wrong database
3. `cache_hit` field was stored in cached data (bug - fixed)

**Debug:**
```sql
-- Test cache manually
SELECT extensions.rewards_cache_set('test', '{"hello":"world"}', 'EX', 60);
SELECT extensions.rewards_cache_get('test');  -- Should return data

-- Check what's in Redis
-- Via Upstash MCP
mcp_upstash_redis_database_run_redis_commands({
  database_id: '...',
  commands: [['KEYS', '*']]
});
```

---

### Issue: Merchant Default Language Not Working

**Symptom:** Thai-first merchant content showing as English in cache

**Cause:** Cache built before merchant default language fix

**Solution:**
1. Clear all caches
2. Verify merchant_languages.is_default is set correctly
3. Call API to rebuild cache with new logic

---

## Migration Guide

### Adding Language to Existing Merchant

```sql
-- 1. Add language configuration
INSERT INTO merchant_languages (merchant_id, language_code, language_name, is_default, display_order)
VALUES 
('merchant-uuid', 'ja', '日本語', false, 3);

-- 2. Add translations for key entities
INSERT INTO translations (merchant_id, entity_type, entity_id, field_name, language_code, translated_value)
SELECT 
    merchant_id,
    'reward',
    id,
    'name',
    'ja',
    name || ' (JP)'  -- Placeholder - replace with actual translation
FROM reward_master
WHERE merchant_id = 'merchant-uuid';

-- 3. Clear caches
SELECT fn_invalidate_merchant_rewards_cache('merchant-uuid');
```

---

### Changing Merchant Default Language

```sql
-- 1. Update default flag
UPDATE merchant_languages
SET is_default = false
WHERE merchant_id = 'merchant-uuid';

UPDATE merchant_languages
SET is_default = true
WHERE merchant_id = 'merchant-uuid' AND language_code = 'th';

-- 2. Clear ALL caches for this merchant
-- (Merchant config, rewards, user profile, UI if merchant-specific)

-- 3. Next request will rebuild with new default
```

---

## Current Translation Coverage

### Dynamic Translations

| Entity Type | Total Translations | Languages |
|-------------|-------------------|-----------|
| `user_field_config` | 122 | th (39), ja (39), zh (39), en (5) |
| `reward` | 32 | Multiple |
| `form_field_option` | 31 | th |
| `persona` | 24 | th (8), ja (8), zh (8) |
| `form_field` | 18 | th (12), en (3), others (3) |
| `reward_category` | 10 | Multiple |
| `communication_topic` | 8 | th |
| `consent_version` | 6 | th |

**Total:** 251 dynamic translations across 11 entity types

---

### Static UI Translations

| Page | Fields | Total Translations |
|------|--------|-------------------|
| `signup_form` | 27 | 108 (27 × 4 languages) |
| `rewards` | 26 | 104 (26 × 4 languages) |
| `redemption_status` | 5 | 20 (5 × 4 languages) |

**Total:** 58 fields × 4 languages = **232 static UI translations**

---

## Database Schema Reference

### `translations` Table

```sql
CREATE TABLE translations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    merchant_id UUID NOT NULL,
    entity_type TEXT NOT NULL,
    entity_id UUID NOT NULL,
    field_name TEXT NOT NULL,
    language_code TEXT NOT NULL,
    translated_value TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    UNIQUE(entity_type, entity_id, field_name, language_code)
);
```

---

### `ui_translations` Table

```sql
CREATE TABLE ui_translations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    merchant_id UUID DEFAULT NULL,
    page_key TEXT NOT NULL,
    field_key TEXT NOT NULL,
    language_code TEXT NOT NULL,
    translated_value TEXT NOT NULL,
    category TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    UNIQUE(merchant_id, page_key, field_key, language_code)
);
```

---

### `merchant_languages` Table

```sql
CREATE TABLE merchant_languages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    merchant_id UUID NOT NULL,
    language_code TEXT NOT NULL,
    language_name TEXT NOT NULL,
    is_default BOOLEAN DEFAULT false,
    is_active BOOLEAN DEFAULT true,
    display_order INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    UNIQUE(merchant_id, language_code)
);
```

---

## Conclusion

The translation system provides comprehensive multi-language support through:

1. **Dual Architecture:** Dynamic entity translations + static UI text
2. **Merchant Flexibility:** Configurable default languages per merchant
3. **Performance:** Isolated Redis caching with <100ms response times
4. **Scalability:** Handles high traffic with 99%+ cache hit rates
5. **Maintainability:** Clear separation of concerns, organized field naming
6. **Developer Experience:** Simple APIs, automatic fallbacks, type-safe

**Current Coverage:**
- 4 languages fully supported
- 483 total translations (251 dynamic + 232 static)
- 2 pages (signup_form, rewards) with complete UI coverage
- Ready for expansion to additional pages and languages

---

*Document Version: 1.0*  
*Last Updated: January 6, 2026*  
*System: Supabase CRM - Translation System*














