# Feature Guide: Store & Partner Classification

## 1. Overview

Store & Partner Classification is how merchants organize their store network into structured groups that drive business rules across the platform. Instead of treating every store identically, merchants define classification dimensions — like sales channel, location, or business type — and assign stores to specific positions within those dimensions. These classifications then power targeted earn rates, campaign eligibility, and reporting.

The system uses a three-tier hierarchy: **Category** (the dimension), **Attribute** (major grouping), and **Sub-Attribute** (specific instance). A "Sales Channel" category might contain "Online Marketplace" as an attribute, with "Shopee" and "Lazada" as sub-attributes. Merchants group these classifications into **Attribute Sets** — named collections like "Premium Channels" — which other features reference for business rules. This decouples the classification structure from the rules that use it: when a new marketplace is added, the merchant updates the classification once and every rule that targets "Premium Channels" automatically includes it.

The entire feature is admin-facing. Members never interact with store classification directly — they experience its effects through differentiated earn rates, targeted campaigns, and store-specific promotions.

## 2. Key Concepts

**Store Master** — The central registry of all merchant stores. Each store has a unique `store_code` (human-readable, like "SHOPEE01") and a system-generated UUID. The store code is the identifier used by external systems (POS, e-commerce platforms); the UUID is used internally.

**Category** — A top-level classification dimension defined by the merchant. Examples: "Sales Channel", "Location", "Business Type", "Product Category". Each merchant creates categories relevant to their business model.

**Attribute** — A mid-level grouping within a category. Examples: under "Sales Channel" → "Online Marketplace", "Physical Store", "Own Online". Provides the primary classification level for most business rules.

**Sub-Attribute** — An optional third-level classification within an attribute. Examples: under "Online Marketplace" → "Shopee", "Lazada", "TikTok Shop". Enables granular targeting when the attribute level isn't specific enough.

**Store Assignment** — A link between a store and a position in the hierarchy. A store can have multiple assignments across different categories (e.g., classified under both "Sales Channel" and "Location" simultaneously). Assignments can point to an attribute directly or to a specific sub-attribute.

**Attribute Set** — A named grouping of attributes and/or sub-attributes used as a targeting handle for business rules. Instead of referencing individual classifications in every earn rule or campaign, the rule references a set. Example: "Premium Channels" set containing Shopee and Lazada sub-attributes.

**Set Member** — A single entry in an attribute set. Can reference either an attribute (broad inclusion — all sub-attributes under it qualify) or a specific sub-attribute (selective inclusion — only that sub-attribute qualifies).

**Broad Inclusion** — When a set member references an attribute, every store assigned to that attribute (regardless of sub-attribute) qualifies. Example: including "Online Marketplace" in a set means Shopee, Lazada, and TikTok Shop stores all match.

**Selective Inclusion** — When a set member references a specific sub-attribute, only stores with that exact sub-attribute qualify. Example: including only "Shopee" means Lazada stores do not match.

**Store Code Resolution** — The process of converting a text-based store code (from POS/e-commerce) to a UUID for internal lookups. Required because `purchase_ledger.store_id` stores text codes, not UUIDs.

## 3. Configuration Reference

### Store Master Fields

| Field | What it controls | Example | Default |
|---|---|---|---|
| Store code | Unique identifier per merchant (immutable after creation) | "SHOPEE01" | Required |
| Store name | Display name | "Shopee Flagship" | Required |
| Active status | Whether store appears in lists and qualifies for rules | true | true |
| Province | Location province | "Bangkok" | Empty |
| Address | Full address (multiline) | "123 Sukhumvit Rd" | Empty |
| Postcode | Postal code | "10110" | Empty |
| Coordinates | GPS position | "13.7563,100.5018" (lat,lng) | Empty |
| Location URL | Google Maps link | maps.google.com/... | Empty |
| External reference | External system identifier | "ERP-001" | Empty |

### Classification Hierarchy Fields

| Level | Fields | Constraint |
|---|---|---|
| Category | Code, Name, is_store_channel flag | Code unique per merchant |
| Attribute | Code, Name, parent Category | Code unique per merchant |
| Sub-Attribute | Code, Name, parent Attribute | Code unique per merchant |

### Attribute Set Fields

| Field | What it controls | Example | Default |
|---|---|---|---|
| Set name | Display name | "Premium Channels" | Required |
| Set code | Machine-readable identifier (auto-generated from name) | "PREMIUM_CHANNELS" | Required |
| Members | List of attribute or sub-attribute references | See set member patterns | Empty |

### Set Member Patterns

| Pattern | Member references | Effect |
|---|---|---|
| Broad inclusion | Attribute only (no sub-attribute) | All sub-attributes under that attribute qualify |
| Selective inclusion | Specific sub-attribute | Only that sub-attribute qualifies |
| Mixed | Combination of both in one set | Broad for some attributes, selective for others |

## 4. Admin Journey

**Repo:** `Rocket-CRM/loyalty-admin`

**Route map:**

| Page name | Current route | Data source |
|---|---|---|
| Store Master | `/stores-master` | `get_stores_by_merchant`, `bff_upsert_store_master` |
| Store Master Bulk Edit | `/stores-master/bulk-edit` | Batch store operations |
| Store Attributes Master | `/store-attributes-master` | `get_store_attributes_hierarchy`, `upsert_store_attributes_jsonb`, `delete_store_attributes_jsonb` |
| Attribute Set List | `/store-attributes-sets` | `store_attribute_sets` table query |
| Attribute Set Settings (create) | `/store-attributes-sets/new` | `get_store_attribute_set_members_with_category(mode='new')` |
| Attribute Set Settings (edit) | `/store-attributes-sets/{id}` | `get_store_attribute_set_members_with_category(mode='edit', id)` |

### 4a. Register a Store

1. From **Store Master**, click **"Add store"** — SidePanel opens with empty form
2. Enter store code (required, unique, immutable after creation) and store name (required)
3. Optionally fill address fields: province, postcode, coordinates, location URL, external reference
4. Toggle active status (default: active)
5. Click **"Create store"** — success toast, panel closes, list refreshes
6. Store code field becomes disabled on subsequent edits

### 4b. Define the Classification Hierarchy

1. Open **Store Attributes Master** — displays expandable tree of categories
2. Add a category: enter code and name. The `is_store_channel` flag marks whether this category represents a channel dimension.
3. Expand a category → add attributes with code and name
4. Expand an attribute → add sub-attributes with code and name
5. Click **"Save"** — sends full hierarchy to `upsert_store_attributes_jsonb`
6. To delete: select items → confirm in delete modal. Deleting a category cascades to its attributes and sub-attributes.

### 4c. Create an Attribute Set

1. From **Attribute Set List**, click **"Create attribute set"**
2. **Attribute Set Settings** opens — enter set name and set code (auto-generated from name, uppercase with underscores)
3. Click **"Add set member"** to add rows. Each row has cascading dropdowns: Category → Attribute → Sub-Attribute → Store
4. For broad inclusion: select a category and attribute, leave sub-attribute empty
5. For selective inclusion: select through to a specific sub-attribute
6. Click **"Create"** — saves via `upsert_store_attribute_set_with_members`

### 4d. Manage Stores in Bulk

1. From **Store Master**, click **"Bulk edit"** → navigates to **Store Master Bulk Edit**
2. Spreadsheet-style interface for editing multiple stores simultaneously
3. Make changes across rows → click **"Save"** to persist all changes in a single batch

### 4e. Common Admin Mistakes

- Creating stores with codes that don't match the POS system → earn factor lookups fail silently (no error, just no match)
- Deleting a category that's referenced by active attribute sets → set resolution returns incomplete results
- Creating an attribute set with no members → no stores will ever match the set
- Leaving the set code as auto-generated then renaming the set → code and name diverge, confusing other admins
- Forgetting to assign attributes to a new store → store exists in registry but doesn't appear in any attribute set

## 5. Member Experience

**Repo:** `Rocket-CRM/loyalty-user`

Store classification has no member-facing UI. The member app (`loyalty-user`) contains no store finder, store list, or location pages. Members experience store classification indirectly:

- Different earn rates when purchasing at stores in different attribute sets
- Campaign eligibility tied to store-targeted missions
- Store name appearing on transaction history entries

## 6. Perspectives

### 6a. For Customer Success / Support

**Elevator pitch:** "Store classification lets you organize your locations into groups — by channel, region, type, or anything else. These groups then control how many points customers earn at different stores, which promotions apply where, and how you analyze performance across your network."

**Top support questions:**

| Question | Answer |
|---|---|
| "A store isn't earning the right points rate" | Check: (1) Does the store code in the POS match `store_master.store_code`? (2) Is the store assigned to the correct attributes? (3) Is the relevant attribute set configured in the earn condition? |
| "I added a new store but it's not in any set" | Adding a store to the registry doesn't auto-assign classifications. Go to **Store Attributes Master** to assign attributes, then verify the attribute set includes those attributes. |
| "I deleted a category and earn rates broke" | Category deletion cascades to its attributes and sub-attributes. Any attribute sets referencing those now-deleted items will return incomplete results. Recreate the classification or update the affected sets. |
| "What does the store code need to match?" | The `store_code` must exactly match what the POS or e-commerce platform sends in the transaction. It's the bridge between external sales data and internal classification. |
| "How do I make all online stores get 2x points?" | Create an attribute set containing the "Online Marketplace" attribute (broad inclusion). Then create an earn condition targeting that set with a 2x rate. Any store classified under Online Marketplace — current and future sub-attributes — will qualify. |

**Config mistakes → fix:**

| Mistake | Symptom | Fix |
|---|---|---|
| Store code doesn't match POS | Purchases don't trigger store-based earn rules | Update store code to match POS exactly (requires creating a new store — codes are immutable) |
| Store not assigned to any attributes | Store never matches any attribute set | Assign attributes via Store Attributes Master |
| Attribute set references deleted sub-attribute | Set matches fewer stores than expected | Add replacement sub-attribute or switch to broad inclusion |
| Category deleted without checking dependent sets | Earn rules stop applying to affected stores | Recreate category structure or update affected attribute sets |

### 6b. For Marketing

**Value proposition:** Store classification enables location-targeted loyalty strategies. Instead of uniform earn rates, merchants can offer premium points at flagship stores, bonus multipliers for online channels, and region-specific campaigns — all without hardcoding individual stores into every rule.

**Use-case stories:**

1. **E-commerce brand** — Creates "Premium Channels" (Shopee + Lazada) with 2x earn rate and "Standard Channels" (TikTok Shop + physical stores) with 1x rate. Drives volume toward high-margin marketplaces.

2. **Shopping mall operator** — Classifies tenants by floor, business type, and lease tier. "Ground Floor F&B" set gets bonus points campaigns during lunch hours. "Premium Tenants" set receives exclusive promotional treatment.

3. **Multi-brand retailer** — Separates flagship CBD locations from express outlets. Flagship stores get experiential reward campaigns; express stores get quick-redemption promotions.

**Metrics that matter:** Points earned by channel type, transaction volume by attribute set, earn rate differential across store groups, campaign reach per set.

### 6c. For Testers

**Config → expected behavior:**

| Config | Expected behavior |
|---|---|
| Store assigned to "Online Marketplace → Shopee" | Store qualifies for any set containing "Online Marketplace" (broad) OR "Shopee" (selective) |
| Store assigned to "Physical Store" (no sub-attribute) | Store qualifies for sets containing "Physical Store" attribute; does NOT match sub-attribute-specific sets |
| Attribute set has no members | No stores match; earn conditions referencing this set never trigger |
| Store code "SHOPEE01" in purchase_ledger | System resolves via `store_master WHERE store_code = 'SHOPEE01'` → UUID → attribute set lookup |
| Category deleted with cascade | All child attributes and sub-attributes deleted; sets referencing them return fewer matches |
| Store `active_status = false` | Store hidden from admin list; existing assignments preserved for historical reporting |
| Set contains "Online Marketplace" (attribute) + "TikTok Shop" (sub-attribute) | Shopee store matches via broad inclusion; TikTok store matches via both broad AND selective; Physical store matches neither |

**Business rules as assertions:**

- ASSERT: Store with sub-attribute assignment matches sets that include either the parent attribute (broad) or the specific sub-attribute (selective)
- ASSERT: Store code resolution returns exactly one UUID per merchant; fails gracefully if store code not found
- ASSERT: `get_store_attribute_sets()` returns distinct set UUIDs — no duplicates even when a store matches a set through multiple paths
- ASSERT: Deleting a category via `delete_store_attributes_jsonb` cascades to its attributes and sub-attributes
- ASSERT: `store_code` is immutable after creation (UI disables field; backend enforces uniqueness)
- ASSERT: Set code auto-generates from set name as uppercase with underscores, editable manually
- ASSERT: Each set member must have at least an attribute, sub-attribute, or store selected — empty rows rejected

**Error states to test:**

- Store code not found in `store_master` → `get_store_attribute_sets` returns empty array, earn condition doesn't match
- Store exists but has no attribute assignments → returns empty array
- Attribute set exists but all referenced attributes/sub-attributes have been deleted → returns empty array
- Duplicate store code within same merchant → database constraint prevents creation, clear error returned
- Upsert store attributes with invalid hierarchy (sub-attribute referencing wrong parent) → validation rejects

**Cross-feature test scenarios:**

- Create store → assign attributes → add to set → create earn condition referencing set → submit purchase with matching store code → verify correct earn rate applied
- Remove a store's attribute assignment → verify store no longer matches the attribute set → earn rate falls back to default
- Add a new sub-attribute under an existing attribute → stores in sets with broad inclusion on that attribute automatically include the new sub-attribute (no set update needed)
- Concurrent store assignment updates → verify no race conditions in set resolution
- Deactivate a store (`active_status = false`) → store hidden from admin list, but existing assignments and historical transactions preserved

## 7. Business Rules

**Rule:** The classification hierarchy is strictly 3 levels: Category → Attribute → Sub-Attribute. Sub-attributes are optional — a store can be assigned at the attribute level without specifying a sub-attribute.
**Example:** "Physical Store" attribute with no sub-attributes; stores assigned directly to it.

**Rule:** A store can have multiple assignments across different categories but the combination of (store_id, category_id, attribute_id, sub_attribute_id) must be unique.
**Example:** A Shopee store assigned to both "Sales Channel → Online Marketplace → Shopee" and "Region → Thailand → Bangkok".

**Rule:** Attribute set matching uses dual-branch logic. A set member with only `attribute_id` (and null `sub_attribute_id`) triggers broad inclusion. A set member with only `sub_attribute_id` (and null `attribute_id`) triggers selective inclusion.
**Example:** "All Online Channels" set includes "Online Marketplace" attribute → every marketplace sub-attribute qualifies. "Premium Channels" set includes "Shopee" and "Lazada" sub-attributes → only those two qualify.

**Rule:** Store code is the integration key between external systems and the classification engine. `purchase_ledger.store_id` stores text codes, which must be resolved to UUIDs via `store_master` before attribute set lookup.
**Example:** POS sends store_id="SHOPEE01" → system looks up `store_master WHERE store_code='SHOPEE01' AND merchant_id=X` → returns UUID for set resolution.

**Rule:** Each merchant defines their own classification schema independently. Categories, attributes, and sets are fully isolated per merchant.
**Example:** Merchant A's "Sales Channel" category has no relationship to Merchant B's "Sales Channel" — they are separate entities.

**Rule:** Deleting a category cascades: all child attributes and their sub-attributes are also deleted. Deleting an attribute cascades to its sub-attributes.
**Example:** Deleting "Sales Channel" removes "Online Marketplace", "Physical Store", "Shopee", "Lazada", and all other children.

**Rule:** `store_code` is immutable after creation. The admin UI disables the field on edit; the database enforces uniqueness per merchant via `(merchant_id, store_code)` constraint.
**Example:** A store created with code "SHOP01" cannot be renamed to "STORE01" — a new store must be created instead.

**Rule:** Attribute sets that reference deleted attributes/sub-attributes do not error — they simply return fewer matches. The set itself remains valid.
**Example:** "Premium Channels" contains Shopee and Lazada. Lazada sub-attribute is deleted → set now only matches Shopee stores.

## 8. Related Features

| Feature | Connection to Store Classification |
|---|---|
| Currency / Earn Factors | Earn conditions can target `store_attribute_set` as an entity — stores in the set receive differentiated earn rates. See `Currency.md`. |
| Purchase Transactions | `purchase_ledger.store_id` contains the text store code that triggers store-based earn factor evaluation. See `Purchase_Transaction.md`. |
| Missions / Campaigns | Future: mission conditions can require purchases at stores in a specific attribute set. Foundation is ready. See `Mission.md`. |
| Reporting | Store classifications enable multi-dimensional performance analysis: sales by channel, revenue by region, transaction volume by store type. |
