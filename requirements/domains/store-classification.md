# Store Classification

> Per-domain reference. Read ONLY when working on this domain. For the keyword → file map, see `_index.md`.

**Keywords:** store, store attribute, store category, store sub-attribute, attribute set, store classification, location, channel, store master, store code

**Source:** `Store_Attribute_Classification.md`

**FE-Relevant Sections:**

| Section Heading | Lines | What it contains |
|---|---|---|
| Three-Tier Hierarchical Structure | 8–16 | Category → Attribute → Sub-Attribute hierarchy |
| Core Tables | 44–163 | All 7 tables: store_master, categories, attributes, sub-attributes, assignments, sets, set_members |
| Business Rule Abstraction via Attribute Sets | 209–259 | Broad/selective/mixed inclusion patterns for business rules |
| Store Assignment Data Model (ER Diagram) | 555–601 | Entity relationship diagram |
| Store Classification Patterns | 853–948 | E-commerce, shopping mall, retail chain examples |

**Supabase Functions (FE-callable):**

| Function | Parameters | Returns | Lines |
|---|---|---|---|
| `get_store_attribute_sets(store_id)` | `store_id (uuid)` | `UUID[]` — array of attribute set IDs the store belongs to | 607–639 |
| `get_store_classification_summary(store_id)` | `store_id (uuid)` | Human-readable classification paths for UI display | 826–836 |

**Key Business Rules (summary):**
- 3-tier hierarchy: Category → Attribute → Sub-Attribute (sub-attribute is optional)
- Stores can be classified across multiple categories simultaneously
- Attribute Sets group attributes/sub-attributes for business rule targeting (earn factors, campaigns)
- `store_master.store_code` is text-based (POS-friendly); resolution to UUID happens internally
- Set membership supports both broad (entire attribute) and specific (single sub-attribute) inclusion

---
