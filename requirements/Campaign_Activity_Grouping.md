# Campaign Activity Grouping

**Keywords:** campaign, campaign_sub, campaign_activity, campaign_mapping, report grouping, sub campaign, activity name, mission mapping, reward mapping, survey mapping

**Purpose.** Taxonomy for grouping loyalty program events into named **activities** under campaigns (and optional sub-campaigns). Real program records (missions, rewards, surveys) are linked via **`campaign_mapping`**. Admin UI lives in the **loyalty admin** project.

**Not the same as `campaign_master`.** `campaign_master` powers leaderboard/participation campaigns.

---

## Terminology

| Term | Table | Meaning |
|---|---|---|
| **Campaign** | `campaign` | Top-level report bucket |
| **Sub campaign** | `campaign_sub` | Optional sub-bucket |
| **Activity** | `campaign_activity` | Stand-alone named layer — admin label for reports (e.g. "Summer bundle"). **Not** a mission/reward/survey. |
| **Mapping** | `campaign_mapping` | Links a real program record to an activity |

```
Campaign
├── Activity ("Summer bundle")          ← campaign_activity
│     ├── Mapping → Reward A            ← campaign_mapping
│     ├── Mapping → Mission B
│     └── Mapping → Survey C
└── Sub Campaign
      └── Activity → Mappings...
```

**Rules**

- Each activity has an admin-defined **name**.
- Each activity has **many mappings** (mix of mission / reward / survey).
- Each `(activity_type, entity_id)` is **unique per merchant** — one real record maps to one activity only.
- Activity placement: direct on campaign (`campaign_sub_id IS NULL`) or under a sub campaign.

---

## Tables

### `campaign`

| Column | Type | Notes |
|---|---|---|
| `id` | uuid PK | |
| `merchant_id` | uuid NOT NULL | |
| `name` | text NOT NULL | |
| `is_active` | boolean | default `true` |
| `created_at` / `updated_at` | timestamptz | |

### `campaign_sub`

| Column | Type | Notes |
|---|---|---|
| `id` | uuid PK | |
| `merchant_id` | uuid NOT NULL | |
| `campaign_id` | uuid NOT NULL | FK → `campaign`, ON DELETE CASCADE |
| `name` | text NOT NULL | |
| `is_active` | boolean | default `true` |
| `created_at` / `updated_at` | timestamptz | |

### `campaign_activity`

Named activity layer (stand-alone grouping unit for reports).

| Column | Type | Notes |
|---|---|---|
| `id` | uuid PK | |
| `merchant_id` | uuid NOT NULL | |
| `campaign_id` | uuid NOT NULL | FK → `campaign`, ON DELETE CASCADE |
| `campaign_sub_id` | uuid NULL | FK → `campaign_sub`. NULL = direct under campaign |
| `name` | text NOT NULL | Admin-defined activity name |
| `is_active` | boolean | default `true` |
| `created_at` / `updated_at` | timestamptz | |

### `campaign_mapping`

Maps a real program record to a `campaign_activity`.

| Column | Type | Notes |
|---|---|---|
| `id` | uuid PK | |
| `merchant_id` | uuid NOT NULL | |
| `campaign_activity_id` | uuid NOT NULL | FK → `campaign_activity`, ON DELETE CASCADE |
| `activity_type` | text NOT NULL | `mission` \| `reward` \| `survey` |
| `entity_id` | uuid NOT NULL | Target row in mission / reward_master / form_templates |
| `created_at` | timestamptz | |

**Unique constraints**

- `(merchant_id, activity_type, entity_id)`
- `(campaign_activity_id, activity_type, entity_id)`

**Entity resolution**

| `activity_type` | Table | Name column |
|---|---|---|
| `mission` | `mission` | `mission_name` |
| `reward` | `reward_master` | `name` |
| `survey` | `form_templates` | `name` |

**RLS:** `merchant_isolation` on all four tables.

---

## Functions

| Function | Parameters | Returns |
|---|---|---|
| `bff_list_campaigns` | none | Campaign list: `sub_campaign_count`, `activity_count`, `mapping_count` |
| `bff_list_campaign_mappings` | `p_campaign_id uuid DEFAULT NULL` | Flat grid — one row per mapping |
| `bff_get_campaign_details` | `p_campaign_id`, `p_mode` | Hierarchical campaign → activities → mappings |
| `bff_upsert_campaign` | `p_campaign_id`, `p_name`, `p_is_active`, `p_activities`, `p_sub_campaigns` | Atomic nested upsert |
| `bff_delete_campaign` | `p_campaign_id` | CASCADE delete |
| `bff_search_campaign_mapping_entities` | `p_activity_type`, `p_search`, `p_limit` | Entity picker for new mappings |
| `fn_validate_campaign_mapping_entity` | merchant + type + entity | boolean |
| `fn_campaign_mapping_entity_name` | same | display name |

### Deprecated (removed)

- `campaign_activity_entity` → renamed **`campaign_mapping`**
- `bff_list_campaign_activity_mappings` → **`bff_list_campaign_mappings`**
- `bff_upsert_campaign_with_mappings` → **`bff_upsert_campaign`**
- `bff_search_campaign_activity_entities` → **`bff_search_campaign_mapping_entities`**
- `fn_validate_campaign_activity_entity` → **`fn_validate_campaign_mapping_entity`**
- `fn_campaign_activity_entity_name` → **`fn_campaign_mapping_entity_name`**

---

## BFF Contracts

### `bff_list_campaign_mappings`

One row per **mapping**:

```json
{
  "mapping_id": "uuid",
  "activity_id": "uuid",
  "activity_name": "Summer bundle",
  "activity_is_active": true,
  "campaign_id": "uuid",
  "campaign_name": "text",
  "campaign_sub_id": "uuid|null",
  "campaign_sub_name": "text|null",
  "is_direct_campaign_activity": true,
  "activity_type": "reward",
  "entity_id": "uuid",
  "entity_name": "text",
  "created_at": "timestamptz"
}
```

### `bff_get_campaign_details`

```json
{
  "activities": [
    {
      "id": "uuid",
      "name": "Summer bundle",
      "is_active": true,
      "mappings": [
        { "id": "uuid", "activity_type": "reward", "entity_id": "uuid", "entity_name": "..." }
      ]
    }
  ],
  "sub_campaigns": [
    {
      "id": "uuid",
      "name": "Week 1",
      "activities": [ { "name": "...", "mappings": [ ... ] } ]
    }
  ]
}
```

### `bff_upsert_campaign`

Activity shape:

```json
{
  "id": "uuid|null",
  "name": "Summer bundle",
  "is_active": true,
  "mappings": [
    { "id": "uuid|null", "activity_type": "reward", "entity_id": "uuid" }
  ]
}
```

- `name` required on each activity.
- `mappings` replaces legacy `entities` key (`entities` still accepted temporarily on upsert).
- Save response counts: `mappings_created/updated/deleted/skipped`.

---

## Report Join Pattern

```sql
SELECT c.name AS campaign, ca.name AS activity, count(*) AS redemptions
FROM reward_redemptions_ledger rrl
JOIN campaign_mapping cm
  ON cm.entity_id = rrl.reward_id
 AND cm.activity_type = 'reward'
 AND cm.merchant_id = rrl.merchant_id
JOIN campaign_activity ca ON ca.id = cm.campaign_activity_id
JOIN campaign c ON c.id = ca.campaign_id
WHERE rrl.merchant_id = :merchant_id
GROUP BY c.name, ca.name;
```
