# CS Channels & Customers

> Per-domain reference. Read ONLY when working on this domain. For the keyword → file map, see `_index.md`.

**Keywords:** channel, platform, shopee, lazada, tiktok, line, whatsapp, facebook, instagram, email, web_widget, voice, sms, twilio, phone_number, identity, identity_resolution, platform_identity, customer, cs_customer, cs_channels, cs_platform_identities, cs_customers, cs_phone_numbers, crm_user_id, memory, customer_memory, cs_customer_memory

**Source:** `CS_Channels.md`

**Tables:** `merchant_credentials` (scope text[] for module isolation), `cs_contacts`, `cs_platform_identities`, `cs_customer_memory`, `cs_phone_numbers` (provider-abstracted phone number inventory)

**Functions (deployed):**

| Function | Type | Purpose |
|---|---|---|
| `cs_bff_get_channels` | BFF | List credentials where `scope && ARRAY['cs']`. Returns config, health, conversation count. |
| `cs_bff_upsert_channel` | BFF | Create or update channel credential. `p_scope text[] DEFAULT '{cs}'`. |
| `cs_bff_get_contact_details` | BFF | Contact + platform identities + memory + recent conversations |
| `cs_fn_resolve_contact` | Backend | Find or create cs_contacts + cs_platform_identities |
| `cs_fn_merge_contacts` | Backend | Re-point identities, conversations, memory from secondary → primary |
| `cs_fn_extract_customer_memory` | Backend | Batch upsert memory entries post-resolution |
| `cs_bff_get_phone_numbers` | BFF | List all active purchased phone numbers (provider-agnostic) |
| `cs_bff_get_phone_number_details` | BFF | Single number details + 30-day stats |
| `cs_fn_upsert_phone_number` | Backend | Insert/update phone number after provider purchase |
| `cs_fn_release_phone_number` | Backend | Mark number released, clear webhooks |

**Outbound delivery:** Render `messaging-service` (`github.com/Rocket-CRM/messaging-service`, URL: `messaging-service-li40.onrender.com`). Central service with adapter + registry pattern for all outbound messaging (LINE, SMS, Email, future channels). Resolves recipients from `conversation_id` (CS), `user_id` (CRM), `contact_id` (CS), or direct IDs. Reads credentials from `merchant_credentials` at runtime. Uses `serviceNameToPlatform` map to translate `merchant_credentials.service_name` (e.g. `line_messaging`) to `cs_platform_identities.platform_type` (e.g. `line`). Called from two paths: (1) AI flow — `inngest-cs-serve` calls `/send` directly via fetch; (2) Agent portal — `cs_bff_send_message` calls `/send` via `pg_net.http_post` (async, uses vault `service_role_key` for auth).

**Key Business Rules (summary):**
- Channel credentials stored in `merchant_credentials` with `scope text[]` — e.g. `'{cs}'` or `'{earn,cs}'` for shared credentials
- One `cs_customer` per real person per merchant (multiple platform identities map to one)
- Identity resolution: webhook → platform_user_id lookup → existing or new customer
- `crm_user_id` links to loyalty module (nullable — CS can operate independently)
- Memory extracted asynchronously after conversation resolution
- Memory governance: expiration (PDPA), right to erasure, per-brand isolation

---
