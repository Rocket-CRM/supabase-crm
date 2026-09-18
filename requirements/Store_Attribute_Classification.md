# Store Attribute Classification

Merchant-defined **store taxonomy** (category → attribute → sub-attribute), **per-store assignments**, and **attribute sets** that group stores for earn rules, receipt OCR, redemption stock, reporting, and admin scope.

Owner surfaces: loyalty-admin (taxonomy, sets, store master, front-line store scope), loyalty-user (receipt upload channel/store pickers), purchase and earn pipelines that resolve store context

## Concept

Merchants operate many physical and digital outlets. The platform needs a consistent way to label each store (channel, region, format, partner, and custom dimensions) and to reuse those labels in rules without maintaining ad-hoc store lists.

**Store** — An operational outlet row with a stable code, display name, active flag, and optional address or integration metadata. Purchases and member flows attach a store (UUID) when attribution matters.

**Category** — A classification dimension the merchant defines (for example Channel, Region, Format). Exactly one category groups each attribute. Some categories are flagged for special product behaviour (receipt channel dimension, store-property dimension).

**Attribute** — A value within a category (for example Online marketplace, Bangkok, Flagship). Required parent for sub-attributes.

**Sub-attribute** — Optional finer grain under an attribute (for example Shopee under Online marketplace). Assignments may stop at attribute level when sub-attribute detail is unnecessary.

**Assignment** — Links one store to one attribute (and optional sub-attribute) within a category. Admin typically configures one pick per category per store.

**Attribute set** — A named, reusable bundle used by downstream rules. Members may pin an entire attribute (all its sub-attributes), a single sub-attribute, or an individual store row. A store qualifies for a set when its assignments match a member row, or when the set lists the store directly.

**Partner merchant** — Separate registry for partner entities tied to a merchant (Open API / partner flows); not the same as store master, but shares merchant isolation.

## Rules

- **Store code uniqueness** — For a given merchant, `store_code` is unique on `store_master`. Upsert rejects duplicates.
- **Taxonomy codes** — Category, attribute, and sub-attribute codes are unique within the merchant at their level (enforced on upsert/delete helpers).
- **Soft delete on taxonomy** — Categories, attributes, and sub-attributes use `is_deleted` (not a separate active flag on those tables). Deleted nodes are hidden from admin pickers; historical assignment rows are not automatically purged.
- **Store active flag** — `active_status = false` hides the store from member pickers and active admin lists; existing ledger rows keep their store reference.
- **Assignment shape** — Each assignment row requires category, attribute, and store; `sub_attribute_id` is optional. Admin save replaces all assignments for that store (delete then insert).
- **One pick per category (admin UX)** — Store master UI maps each category to at most one attribute/sub-attribute selection; empty category means no row for that category.
- **Set membership — attribute member** — Set member with `attribute_id` and null `sub_attribute_id`: any store assigned to that attribute qualifies, including any sub-attribute under it.
- **Set membership — sub-attribute member** — Set member with `sub_attribute_id`: only stores assigned to that exact sub-attribute qualify.
- **Set membership — store pin** — Set member with `store_id`: that store qualifies regardless of taxonomy match (used for exceptions or store-specific rule targets).
- **Set member soft delete** — Set members use `is_deleted`; list UIs count only non-deleted members.
- **Resolution output** — `get_store_attribute_sets(store_id)` (and `store_matches_attribute_set`) derive qualifying set IDs from assignments plus member rules; earn and condition evaluation consume set IDs, not hand-maintained store lists.
- **Channel category** — Exactly one category per merchant should be marked `is_store_channel` for receipt flows: `get_store_channels` exposes channel attributes for member channel → store selection.
- **Merchant isolation** — All classification tables carry `merchant_id`; admin BFFs and JWT-scoped reads filter by current merchant.

Example (set matching): A set member “Online marketplace” (attribute only) includes a store assigned “Channel → Online marketplace → Shopee”. A set member “Shopee” (sub-attribute only) includes that store but excludes a store assigned only “Online marketplace” without the Shopee sub-attribute.

## Journeys

### Admin journey

| Knob | Effect |
| --- | --- |
| Categories / attributes / sub-attributes | Merchant taxonomy tree; channel and store-property flags on categories |
| Attribute sets | Reusable targets for earn conditions, OCR rules, and other store-scoped config |
| Store master | Create outlets, address fields, active flag, per-category assignments |
| Set members | Attribute-wide, sub-attribute-specific, or direct store pins |

| Page | Owning repo | BFF / RPC |
| --- | --- | --- |
| Store attributes master | loyalty-admin | `get_store_attributes_hierarchy`, `upsert_store_attributes_jsonb`, `delete_store_attributes_jsonb` |
| Store attribute sets (list) | loyalty-admin | Direct read on `store_attribute_sets` + member counts (list RPC bypassed — broken column reference) |
| Store attribute set (detail) | loyalty-admin | `get_store_attribute_set_members_with_category`, `upsert_store_attribute_set_with_members`, `admin_delete_store_attribute_set` |
| Stores master | loyalty-admin | `get_stores_by_merchant`, `bff_upsert_store_master`, `bff_delete_store_master`; assignments via `store_attribute_assignments` table |
| Front line / events / rewards (store scope) | loyalty-admin | Store pickers and stock scoped by store master rows |

1. On **Store attributes master**, define categories and nested attributes/sub-attributes; mark the channel category when receipt upload should use channel → store steps.
2. On **Store attribute sets**, create sets and add members (broad attribute, specific sub-attribute, or pinned store).
3. On **Stores master**, create or edit stores, set active status and location fields, then assign one classification per category.
4. In **earn**, **receipt OCR**, **reward store stock**, or **event store allowlists**, reference attribute sets or store IDs rather than maintaining parallel store lists.

### Member journey

| Step | Owning repo | BFF / RPC |
| --- | --- | --- |
| Receipt channel (if configured) | loyalty-user | `get_store_channels` |
| Receipt store search / pick | loyalty-user | `bff_list_stores_for_receipt_upload`, `get_stores_by_channel` |
| Other store-scoped earn | loyalty-user | `get_stores_by_merchant` where surfaced |

1. When the merchant uses a channel dimension, member chooses a **channel** (store-channel attribute), then a **store** filtered to that channel and active stores.
2. When channel dimension is not used, member searches or picks from **active** stores exposed by the earn/receipt API.
3. If no store matches or store is inactive, the flow shows empty or validation error from the calling RPC (not a separate classification error code).

## System

### Data model

| Artifact | Role |
| --- | --- |
| `store_master` | Canonical store row: code, name, `active_status`, address/geo fields, receipt hints (`hint_receipt_storename`, `benchmark_receipts`, `manual_approve`), reward-stock flag `is_reward_stock`, optional `external_ref` / `metadata` |
| `store_attribute_categories` | Top-level dimension: codes/names, `is_deleted`, `is_store_channel`, `is_store_property` |
| `store_attributes` | Mid-level values under a category; `is_deleted` |
| `store_sub_attributes` | Optional third level under an attribute; `is_deleted` |
| `store_attribute_assignments` | Store ↔ category ↔ attribute (+ optional sub-attribute); one row per configured classification |
| `store_attribute_sets` | Named set (`set_code`, `name`) per merchant |
| `store_attribute_set_members` | Set membership: optional `attribute_id`, `sub_attribute_id`, or `store_id`; `is_deleted` |
| `partner_merchant` | Partner registry (`partner_code`, `partner_name`, `active_status`) for partner-scoped integrations |

Unique business key: `(merchant_id, store_code)` on store master. Taxonomy upserts enforce code uniqueness per merchant at each level.

### Functions

| Function | Role |
| --- | --- |
| `get_store_attributes_hierarchy` | Admin: nested categories → attributes → sub-attributes for master and taxonomy pages |
| `upsert_store_attributes_jsonb` / `delete_store_attributes_jsonb` | Admin: batch upsert or soft-delete taxonomy nodes |
| `bff_upsert_store_master` / `bff_delete_store_master` | Admin: create/update store row; delete path may hard- or soft-delete depending on references |
| `get_store_attribute_set_members_with_category` | Admin: load set header + members with category context (`new` / `edit`) |
| `upsert_store_attribute_set_with_members` | Admin: upsert set metadata and replace member rows |
| `admin_delete_store_attribute_set` | Admin: remove a set |
| `get_store_attribute_sets` | Core: UUID[] of set IDs a store matches via assignments + member rules |
| `store_matches_attribute_set` | Predicate: store (id or code) matches one set |
| `get_store_classifications` | Read classifications by store id or store code; optional category filter |
| `resolve_store_uuid` | Map store code → store UUID for integrations |
| `get_store_channels` | Member/admin: channel attributes (`is_store_channel` category) |
| `get_stores_by_channel` / `get_stores_by_merchant` | Member: list stores for picker or browse |
| `bff_list_stores_for_receipt_upload` | Member: searchable, paginated store list for receipt upload |
| `bff_admin_get_store_options` | Admin: compact store options for scoped UIs |
| Receipt OCR BFFs (`bff_get_receipt_ocr_*`, `fn_ocr_*`) | Resolve OCR products/rules/hints by `store_attribute_id` or `store_attribute_set_id` |

Legacy JSON upserts (`upsert_store_attributes`, `upsert_store_attribute_sets`, …) remain for older callers; admin surfaces prefer `*_jsonb` and `upsert_store_attribute_set_with_members`.

### Flows

**Taxonomy save (sync):** Admin posts hierarchy JSON → validate merchant → upsert categories/attributes/sub-attributes → soft-delete flagged nodes.

**Store save (sync):** `bff_upsert_store_master` validates code uniqueness → upsert row → admin optionally replaces assignment rows on `store_attribute_assignments`.

**Set save (sync):** Upsert set header → replace members (attribute, sub-attribute, and/or store pins) → downstream rules reference set id.

**Set resolution (sync):** Load store assignments → join to set members (attribute-wide, sub-attribute-specific, store pin) → distinct set ids → consumed by earn factor eligibility (`get_eligible_earn_factors_core` store/set conditions), OCR set rules, and similar condition entities.

**Receipt upload (sync):** Optional channel from `get_store_channels` → store from `bff_list_stores_for_receipt_upload` / `get_stores_by_channel` → purchase/receipt pipeline stores `store_id` UUID on ledger/upload rows.

**Purchase attribution:** `purchase_ledger.store_id` is a UUID FK to `store_master` (plus denormalized `store_code` where populated); external importers map codes via `resolve_store_uuid` before insert.

### External services

No dedicated Render/Inngest worker for classification; resolution runs inside Postgres functions invoked from BFFs and earn/purchase chokepoints.

### Known gaps

- **`get_store_attribute_sets_list`** — References non-existent column (`set_name`); loyalty-admin attribute set **list** uses direct table query instead. Fix RPC or retire from registry docs when cleaned up.
- **Documented helpers absent in DB** — Legacy doc listed `validate_store_classification_hierarchy` and `get_store_classification_summary`; not deployed (removed from this doc).
- **Store assignments in admin** — Stores master writes assignments via PostgREST table delete/insert, not a dedicated BFF; RLS must allow merchant-scoped mutation for admin role.
- **`bff_delete_store_master`** — Used from loyalty-admin but may lag `REGISTRY_SUPABASE.md`; verify registry on next regen.
- **Reporting SQL in old doc** — Example joins assumed text `store_id` on purchases; use UUID `store_id` + assignments when building reports.

## Related

- **Purchase_Transaction.md** — Purchase rows carry `store_id` / `store_code` for earn and limits.
- **Activity_Based_Earning.md** — Earn factors and conditions can scope by store and attribute sets.
- **Receipt_Upload_Earning.md** — Channel attributes and OCR hints/rules keyed by store attribute or set.
- **Reward.md** — Per-store redemption stock via `bff_upsert_reward_store_stock` and `is_reward_stock` stores.
- **Open_API.md** — Partner merchants and store-scoped API operations where applicable.
- **Earn_Channel.md** — Surfaces that lead members into store-scoped earn flows.
