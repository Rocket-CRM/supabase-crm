# CS Customers — List + Detail

## What This Is

Customer management for the CS module. Customers (contacts) are people who contact the brand for support. A single customer may appear across multiple platforms (Shopee buyer, LINE user, WhatsApp phone — all the same person). This page manages unified customer profiles, cross-platform identity linking, and customer memory.

- **List page** — Browse, search, filter customer contacts
- **Detail page** — Full customer profile with conversation history, tickets, platform identities, loyalty data, and AI memory

The AI in this project should use its own judgment for what UI layout and information architecture produce the best UX for **viewing and managing customer support profiles with cross-platform identity**. Study how Intercom's People section, Zendesk's customer profiles, or CRM contact detail pages approach this — then decide the best structure.

---

## FE Project Context

| Layer | Tech |
|---|---|
| Framework | Next.js 16 (App Router, React 19) |
| UI | Shopify Polaris v13 (the only component library) |
| Backend | Complex operations via `supabase.rpc()`. Simple reads/writes via `supabase.from()` (RLS handles merchant scoping). |
| Auth | Supabase Auth, JWT carries merchant context |
| Forms | `react-hook-form` + `zod` |

### Routes

```
src/app/(admin)/cs-customers/           → Customer list
src/app/(admin)/cs-customers/[id]/      → Customer detail profile
```

---

## Backend Connection — Tables & RPCs

### Core Tables

**`cs_contacts`** — Unified contact record

| Column | Type | Notes |
|---|---|---|
| `id` | uuid PK | |
| `merchant_id` | uuid FK | |
| `display_name` | text | |
| `email` | text | |
| `phone` | text | |
| `language` | text | Detected or stated preference |
| `crm_user_id` | uuid | Link to loyalty `user_master.id`. Nullable — not all contacts are loyalty members. |
| `tags` | text[] | |
| `custom_fields` | jsonb | |
| `first_contact_at` | timestamptz | |
| `last_contact_at` | timestamptz | |
| `created_at` | timestamptz | |
| `updated_at` | timestamptz | |

**`cs_platform_identities`** — Cross-platform identity mapping

| Column | Type | Notes |
|---|---|---|
| `id` | uuid PK | |
| `merchant_id` | uuid FK | |
| `contact_id` | uuid FK → cs_contacts | |
| `platform_type` | text | `shopee`, `lazada`, `tiktok`, `line`, `whatsapp`, `facebook`, `instagram`, `email`, `web`, `voice` |
| `platform_user_id` | text | Buyer ID, LINE UID, phone number, email address |
| `platform_display_name` | text | |
| `linked_at` | timestamptz | |

**`cs_customer_memory`** — Cross-session personalization

| Column | Type | Notes |
|---|---|---|
| `id` | uuid PK | |
| `contact_id` | uuid FK → cs_contacts | |
| `merchant_id` | uuid FK | |
| `category` | text | `health`, `preference`, `interest`, `logistics`, `issue`, `feedback`, `communication`, or merchant-custom |
| `key` | text | `allergy`, `delivery_preference`, `skin_type` |
| `value` | text | "Allergic to marine collagen" |
| `confidence` | float | 0.0–1.0 |
| `source_conversation_id` | uuid | Which conversation extracted this |
| `expires_at` | timestamptz | PDPA compliance. Nullable = no expiry. |
| `created_at` | timestamptz | |

### RPCs — Customer List

| RPC | Purpose | Notes |
|---|---|---|
| `cs_bff_get_contacts` | List contacts | Supports: search by name/email/phone, filter by tags, filter by language, filter by platform_type, pagination, sort by last_contact_at |
| `cs_bff_get_contact_stats` | Summary statistics | Total contacts, new this week/month, by platform breakdown |

### RPCs — Customer Detail

| RPC | Purpose | Notes |
|---|---|---|
| `cs_bff_get_contact_detail` | Full customer profile | Returns: contact fields + platform identities + customer memory + conversation summary stats + loyalty data (if crm_user_id linked, via CRM bridge) |
| `cs_bff_get_contact_conversations` | Conversation history | Params: contact_id, pagination. Returns: conversation list with channel, status, last message, date. |
| `cs_bff_get_contact_tickets` | Ticket history | Params: contact_id, pagination. Returns: tickets linked to this customer. |
| `cs_bff_get_contact_memory` | Customer memory entries | Params: contact_id. Returns all memory records grouped by category. |
| `cs_bff_update_contact` | Edit contact fields | Params: contact_id, fields to update (name, email, phone, tags, custom_fields) |
| `cs_bff_upsert_contact_memory` | Add/edit memory entry | Params: contact_id, category, key, value, expires_at. Manual memory entry by agent/admin. |
| `cs_bff_delete_contact_memory` | Delete memory entry | Params: memory_id. For PDPA "forget me" requests. |
| `cs_bff_merge_contacts` | Merge duplicate contacts | Params: primary_contact_id, secondary_contact_id. Re-points all platform identities, conversations, tickets, memory from secondary to primary. |
| `cs_bff_link_platform_identity` | Manually link identity | Params: contact_id, platform_type, platform_user_id. For manual identity resolution. |
| `cs_bff_unlink_platform_identity` | Remove identity link | Params: identity_id |

**Direct CRUD (use `supabase.from()`):**
- List contacts: `supabase.from('cs_contacts').select('*').eq('merchant_id', merchantId)` with search/filters
- Update contact: `supabase.from('cs_contacts').update({ display_name, email, ... }).eq('id', contactId)`
- Memory CRUD: `supabase.from('cs_customer_memory')` for list (by contact_id), insert, update, delete
- Unlink identity: `supabase.from('cs_platform_identities').delete().eq('id', identityId)`

**RPCs (use `supabase.rpc()`):**
- `cs_bff_get_contact_details` — contact + identities + memory + recent conversations (joins)
- `cs_bff_get_contact_conversations` — conversation history with last message preview
- `cs_bff_get_contact_tickets` — ticket history for contact
- `cs_bff_get_contact_stats` — summary statistics
- `cs_bff_merge_contacts` — merge duplicate contacts (multi-table atomic)
- `cs_bff_link_platform_identity` — link with duplicate validation

### Loyalty Data (via CRM Bridge)

When `crm_user_id` is populated, the detail page also displays loyalty data fetched from the CRM project:

| Data | Source | Notes |
|---|---|---|
| Points balance | CRM bridge | Current wallet balance |
| Tier | CRM bridge | Current tier name and status |
| Active rewards | CRM bridge | Unredeemed rewards/vouchers |
| Purchase history | CRM bridge | Recent transactions |

This data is fetched by the backend RPC (`cs_bff_get_contact_detail` includes it when `crm_user_id` exists). The FE just displays what the RPC returns.

---

## Key Domain Concepts the UI Must Support

### 1. Cross-Platform Identity

One customer can be known across multiple platforms:
- Shopee buyer "abc123"
- LINE user "U1234"
- WhatsApp +6681234567
- Email john@example.com

The detail page should show all linked platform identities. Allow manual linking/unlinking. Show a suggestion when the system detects a potential match ("This Shopee buyer has the same phone as this LINE user — link?").

### 2. Customer Memory

AI-extracted persistent facts about the customer. Displayed grouped by category:

| Category | Example Memories |
|---|---|
| `health` | "Allergic to marine collagen" |
| `preference` | "Prefers fragrance-free products", "Prefers email communication" |
| `interest` | "Interested in Stem Cell product line" |
| `logistics` | "Ship to office, not home" |
| `issue` | "Had bad experience with shipping in March 2026" |
| `feedback` | "Gave positive feedback on Collagen Cream" |

Memory entries show:
- Category + key + value
- Confidence score
- Source conversation (clickable link)
- Expiry date (if set)

Admins can manually add, edit, or delete memory entries. Delete is important for PDPA "forget me" compliance.

### 3. Contact Merging

When duplicate contacts exist (same person, different records), admins can merge them. The merge operation:
- Keeps the primary contact's fields
- Re-points all platform identities from secondary to primary
- Re-points all conversations and tickets
- Merges memory entries
- Soft-deletes the secondary contact

### 4. Loyalty Integration

If the contact is a loyalty member (crm_user_id linked), show loyalty data alongside CS data: points, tier, rewards, recent purchases. This gives agents full context.

---

## Key UX Requirements

1. The list page should support fast search (agents often look up customers by phone number or name mid-conversation).

2. The detail page is information-dense — customer profile, platform identities, memory, conversations, tickets, loyalty data. The AI should decide the best layout to avoid overwhelming the user while keeping all data accessible.

3. Memory management should feel lightweight — quick to scan, easy to add/remove entries.

4. Platform identity section should visually indicate which platforms the customer is connected on (icons/badges).

---

## What NOT to Build (Backend Handles These)

- Automatic identity resolution (matching phone/email across platforms) — backend handles on message receipt
- Memory extraction from conversations — async LLM job runs after conversation resolves
- CRM bridge data fetching — backend RPC fetches loyalty data and includes in response
- PDPA compliance automation — backend handles data retention policies and expiry
