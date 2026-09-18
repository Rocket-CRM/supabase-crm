# Activity Earning

> Per-domain reference. Read ONLY when working on this domain. For the keyword → file map, see `_index.md`.

**Keywords:** activity, upload, image upload, admin approval, exercise, POSM, activity matrix, field definitions, primary dimension, secondary field, currency config, frequency limit

**Source:** `Activity_Based_Earning.md`

**FE-Relevant Sections:**

| Section Heading | Lines | What it contains |
|---|---|---|
| System Architecture — Data Flow | 26–74 | Upload flow and admin approval flow diagrams |
| Database Schema — activity_master | 80–157 | Field definitions JSONB structure (manual + auto_populate types) |
| Database Schema — activity_currency_config | 160–191 | Matrix cell structure (primary × secondary → points/tickets) |
| Database Schema — activity_upload_ledger | 193–215 | Upload record shape with status workflow |
| Frequency Limits | 305–343 | Reuses `transaction_limits` with `entity_type='activity'` |
| API — upload_activity_image | 411–450 | User upload endpoint, success/limit-exceeded responses |
| API — bff_approve_activity_upload | 454–510 | Admin approval with field values, success/validation-error responses |
| API — bff_get_activity_uploads | 514–557 | List pending uploads with pagination |
| API — bff_get_activity_matrix | 560–635 | Matrix configuration for FE rendering (pivot table) |
| API — api_get_activity_full | 348–406 | Complete activity config with WeWeb Data Grid columns and pivoted matrices |
| Frontend Integration Patterns | 1012–1135 | User upload flow, admin approval flow, matrix configuration flow code examples |
| Business Rules | 898–931 | Field validation, currency calculation, status workflow, direct currency award pattern |

**Supabase Functions (FE-callable):**

| Function | Parameters | Returns | Lines |
|---|---|---|---|
| `upload_activity_image(p_activity_id, p_image_url)` | `p_activity_id (uuid)`, `p_image_url (text)` | Success/limit-exceeded with upload_id | 411–450 |
| `bff_approve_activity_upload(p_upload_id, p_field_values)` | `p_upload_id (uuid)`, `p_field_values (jsonb)` | Points/tickets awarded, field values | 454–510 |
| `bff_get_activity_uploads(p_status_filter, p_activity_id, p_limit, p_offset)` | Status filter, activity ID, pagination | Upload list with user info | 514–557 |
| `bff_get_activity_matrix(p_activity_id)` | `p_activity_id (uuid)` | Matrix config, field definitions, pivot data | 560–635 |
| `api_get_activity_full(p_activity_id, p_mode)` | `p_activity_id (uuid)`, `p_mode (text)` | Columns + config with matrices array for Data Grid | 348–406 |
| `bff_upsert_activity_currency_matrix(p_activity_id, p_matrix_configs)` | `p_activity_id (uuid)`, `p_matrix_configs (jsonb[])` | Created/updated/deleted counts | 639–690 |

**Key Business Rules (summary):**
- Users upload images; admins review, fill field values, and approve → currency awarded directly
- Currency calculation: match `field_values` against `activity_currency_config` matrix (primary × secondary)
- Status workflow: `pending` → `approved` / `rejected` / `cancelled`
- Frequency limits checked at both upload time and approval time (race condition protection)
- Direct `chokepoint_post_wallet_transaction()` call (no CDC needed — synchronous admin action)

---
