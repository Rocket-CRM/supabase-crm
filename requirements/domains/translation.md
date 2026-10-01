# Translation

> Per-domain reference. Read ONLY when working on this domain. For the keyword → file map, see `_index.md`.

**Keywords:** translation, language, i18n, multi-language, Thai, English, Japanese, Chinese, ui translation, entity translation, default language, fallback

**Source:** `Translation_System.md`

**FE-Relevant Sections:**

| Section Heading | What it contains |
|---|---|
| `## Concept` | Dynamic vs member static vs admin static; default language; cache bundles |
| `## Rules` | Fallback chains, write chokepoints, cache invalidation, API separation |
| `## Journeys` | Global Settings languages; member `get_ui_translations`; admin `get_admin_ui_translations` |
| `## System` › Data model | Tables, entity types from `get_entity_type_config()`, page keys |
| `## System` › Functions | RPCs for UI copy, entity saves, export/gaps |

**Supabase Functions (FE-callable):**

| Function | Parameters | Returns | Lines |
|---|---|---|---|
| `bff_get_user_profile_template(p_language, ...)` | `p_language` | Template with translated labels in requested language | (Forms.md) |
| `api_get_rewards_full_cached()` | None | Rewards with all language translations embedded | (Reward.md) |

**Key Business Rules (summary):**
- Dynamic translations cover rewards, form fields, personas, consent versions
- Static UI translations cover page titles, buttons, error messages, labels
- Merchant-specific default language; automatic fallback chain
- Redis cached per domain (isolated caches); 5-min TTL
- All languages returned in single response for instant client-side language switching

---
