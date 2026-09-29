# Store Attribute Classification

Merchant-defined **store taxonomy** (category → attribute → sub-attribute), **per-store assignments**, and **attribute sets** that group stores for earn rules, receipt OCR, redemption stock, reporting, and admin scope.

Owner surfaces: loyalty-admin (taxonomy, sets, store master, front-line store scope), loyalty-user (receipt upload channel/store pickers), purchase and earn pipelines that resolve store context

## Concept

Merchants sell through hundreds of outlets and want to treat them by group, not one by one: "5× points at large provincial branches", "this reward only in Bangkok". Store attributes describe each store along independent **dimensions** the merchant chooses—retail chain, size, region, building, floor, opening hours—so rules target a description ("Provincial", "Size L") and new stores inherit the right behaviour the moment they are classified. Which dimensions to create follows how the brand wants to group stores, not a fixed schema. (Old CRM called this *Store Property*.)

**Store** — An operational outlet row with a stable code, display name, active flag, and optional address or integration metadata. Purchases and member flows attach a store (UUID) when attribution matters.

**Category** — One dimension (for example Chain, Size, Location). Exactly one category groups each attribute.

**Store channel** — The one category flagged as the **retail-chain dimension** (Watsons, HomePro, Konvy…). It is an ordinary dimension with one extra job: receipt flows group stores by it, so the approver and the member pick a chain first, then a store in that chain. Old CRM kept channel as a separate object; here it is just the flagged dimension, so chains get sets, rules, and reporting for free.

**Store property** — The one category flagged to print as the store's label on Front Line receipt slips and purchase history (attribute names only).

**Attribute** — A value within a category (for example Online marketplace, Bangkok, Flagship). Required parent for sub-attributes.

**Sub-attribute** — Optional finer grain under an attribute (for example Shopee under Online marketplace). Assignments may stop at attribute level when sub-attribute detail is unnecessary.

**Assignment** — Links one store to one attribute (and optional sub-attribute) within a category. Admin typically configures one pick per category per store.

**Attribute set** — A named, reusable target that earn conditions, missions, receipt rules, and stock pick instead of store lists. Members may pin an entire attribute (all its sub-attributes), a single sub-attribute, or an individual store row. A set is a **union**: a store qualifies when it matches **any** member row or is listed directly — unless the set lists it as an **excluded store**. A set does not intersect dimensions; "Provincial **and** Size L" is expressed by pinning those stores.

**Partner merchant** — Separate registry for partner entities tied to a merchant (Open API / partner flows); not the same as store master, but shares merchant isolation.

## Rules

- **Store code required and unique** — Every store needs a code (save fails without one); for a given merchant, `store_code` is unique on `store_master`. Upsert rejects duplicates.
- **Taxonomy codes** — Category, attribute, and sub-attribute codes are unique within the merchant at their level (enforced on upsert/delete helpers).
- **Soft delete on taxonomy** — Categories, attributes, and sub-attributes use `is_deleted` (not a separate active flag on those tables). Deleted nodes are hidden from admin pickers; historical assignment rows are not automatically purged.
- **Store active flag** — `active_status = false` hides the store from member pickers and active admin lists; existing ledger rows keep their store reference.
- **Assignment shape** — Each assignment row requires category, attribute, and store; `sub_attribute_id` is optional. Admin save replaces all assignments for that store (delete then insert).
- **One pick per category (admin UX)** — Store master UI maps each category to at most one attribute/sub-attribute selection; empty category means no row for that category.
- **Set membership — attribute member** — Set member with `attribute_id` and null `sub_attribute_id`: any store assigned to that attribute qualifies, including any sub-attribute under it.
- **Set membership — sub-attribute member** — Set member with `sub_attribute_id`: only stores assigned to that exact sub-attribute qualify.
- **Set membership — store pin** — Set member with `store_id`: that store qualifies regardless of taxonomy match (used for store-specific rule targets).
- **Set membership — excluded store** — Set member with `store_id` and `exclude = true`: that store never qualifies for the set, even when an attribute, sub-attribute, or store pin in the same set matches it (exclusion wins). Only stores can be excluded; attribute or sub-attribute rows with `exclude` are rejected. A set with only exclusions matches nothing (admin blocks saving it).
- **Set member soft delete** — Set members use `is_deleted`; list UIs count only non-deleted members.
- **Resolution output** — One matcher, `store_matches_any_attribute_set`, defines membership (includes, store pins, exclusions). `get_store_attribute_sets(store_id)` and `store_matches_attribute_set` delegate to it, so earn, mission, and receipt-approval checks agree. Consumers use set IDs, not hand-maintained store lists.
- **Channel category** — At most one non-deleted category per merchant is `is_store_channel` (unique index). Turning the flag on for a category turns it off on the previous one in the same save. Its attributes are the channels in receipt channel → store pickers (`get_store_channels`, admin review modal). No flagged category → the channel list is empty, so receipt channels should use store-only selection.
- **Store-property category** — At most one non-deleted category per merchant is `is_store_property` (unique index; same toggle behaviour). Its attribute names are the store label on Front Line slips and purchase history.
- **Set semantics are OR** — Within a set, members are alternatives, even across categories; there is no intersection operator.
- **Merchant isolation** — All classification tables carry `merchant_id`; admin BFFs and JWT-scoped reads filter by current merchant.

Example (set matching): A set member “Online marketplace” (attribute only) includes a store assigned “Channel → Online marketplace → Shopee”. A set member “Shopee” (sub-attribute only) includes that store but excludes a store assigned only “Online marketplace” without the Shopee sub-attribute. A set “Merchandise → Beauty” with excluded store “Watsons” includes every Beauty store except Watsons. A set with “Provincial” (Location) and “Size L” (Size) matches every provincial store and every L store—not only provincial L stores.

## Journeys

### Admin journey

| Knob | Effect |
| --- | --- |
| Categories / attributes / sub-attributes | Merchant taxonomy tree (dimension → value → optional finer value) |
| Store channel toggle (per category) | Marks the retail-chain dimension used by receipt channel → store pickers; one per merchant, switching moves it |
| Store property toggle (per category) | Marks the dimension printed as the store label on Front Line slips/history; one per merchant |
| Attribute sets | Reusable targets for earn conditions, OCR rules, and other store-scoped config |
| Store master | Create outlets, address fields, active flag, per-category assignments |
| Set members | Attribute-wide, sub-attribute-specific, or direct stores (one row may hold several stores, picked by name/code search) |
| Excluded stores | Stores removed from the set regardless of matching members |

| Page | Owning repo | BFF / RPC |
| --- | --- | --- |
| Store attributes master | loyalty-admin | `get_store_attributes_hierarchy`, `upsert_store_attributes_jsonb`, `delete_store_attributes_jsonb` |
| Store attribute sets (list) | loyalty-admin | Direct read on `store_attribute_sets` + member counts (list RPC bypassed — broken column reference) |
| Store attribute set (detail) | loyalty-admin | `get_store_attribute_set_members_with_category`, `upsert_store_attribute_set_with_members`, `admin_delete_store_attribute_set` |
| Stores master | loyalty-admin | `get_stores_by_merchant`, `bff_upsert_store_master`, `bff_delete_store_master`; assignments via `store_attribute_assignments` table |
| Front line / events / rewards (store scope) | loyalty-admin | Store pickers and stock scoped by store master rows |

1. On **Store attributes master**, add one category per dimension the brand groups by, then its attributes (and sub-attributes if needed); toggle **Store channel** on the retail-chain category and, if used, **Store property** on the label category; Save (deletions ask for confirmation first).
2. On **Store attribute sets**, create sets and add members (broad attribute, specific sub-attribute, or searched direct stores), then optionally list **Excluded stores**. Save is blocked when a store is both a direct store and excluded, or when only exclusions exist.
3. On **Stores master**, create or edit stores (store code required), set active status and location fields, then assign one value per category—for the store-channel category, the chain the store belongs to.
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
| `store_attribute_set_members` | Set membership: exactly one of `attribute_id`, `sub_attribute_id`, `store_id`; `exclude` (store rows only); `is_deleted` |
| `partner_merchant` | Partner registry (`partner_code`, `partner_name`, `active_status`) for partner-scoped integrations |

Unique business key: `(merchant_id, store_code)` on store master. Taxonomy upserts enforce code uniqueness per merchant at each level.

### Functions

| Function | Role |
| --- | --- |
| `get_store_attributes_hierarchy` | Admin: nested categories → attributes → sub-attributes for master and taxonomy pages |
| `upsert_store_attributes_jsonb` / `delete_store_attributes_jsonb` | Admin: batch upsert or soft-delete taxonomy nodes |
| `bff_upsert_store_master` / `bff_delete_store_master` | Admin: create/update store row; delete path may hard- or soft-delete depending on references |
| `get_store_attribute_set_members_with_category` | Admin: load set header + members with category context (`new` / `edit`); store members grouped into one included row and one excluded row (`store_assignments`, `exclude`) |
| `upsert_store_attribute_set_with_members` | Admin: upsert set metadata and replace member rows (one store per element, optional `exclude`) |
| `admin_delete_store_attribute_set` | Admin: remove a set |
| `store_matches_any_attribute_set` | Core: the single membership matcher — store matches any of the given sets (includes, pins, exclusions) |
| `get_store_attribute_sets` | Core: UUID[] of the merchant's sets a store matches (delegates to the matcher); used by mission evaluation and receipt approval rules |
| `store_matches_attribute_set` | Predicate: store (id or code) matches one set (delegates to the matcher) |
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

**Set save (sync):** Upsert set header → replace members (attribute, sub-attribute, store pins, excluded stores) → downstream rules reference set id.

**Set resolution (sync):** `store_matches_any_attribute_set` per set: any included member matches (assignment on attribute / sub-attribute, or store pin) and no excluded-store row for that store → consumed by earn eligibility (`evaluate_earn_conditions_core`), mission conditions (`fn_evaluate_mission_conditions` via `get_store_attribute_sets`), and receipt approval rules (Edge `receipt-approval-rules` via `get_store_attribute_sets`). OCR set rules key on channel attribute members only. `fn_get_futurepark_baht_per_point` reads `EARN_RATE_25/50` store pins directly and ignores excluded rows.

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
