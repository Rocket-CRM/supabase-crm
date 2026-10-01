# CS Channels

How merchants **connect platforms** (credentials), resolve **contacts** across identities, and store durable **customer memory** for AI context.

Owner surfaces: loyalty-admin (**CS Channels**, **CS Customers**), Integrations Hub (credential secrets), edge webhooks (ingress), AI pipeline (memory read/write)

## Concept

**Channel credential** — Merchant connection row shared with loyalty integrations; CS traffic uses credentials whose scope includes CS.

**Contact** — Canonical CS person for a merchant; optional link to a loyalty member when identified.

**Platform identity** — External sender id per platform (marketplace buyer id, LINE user id, phone, email).

**Customer memory** — Durable facts extracted from resolved conversations, with confidence and optional expiry for privacy.

**Transport** — Some marketplaces use partner webhooks (e.g. DooPage for Shopee chat) while platform type on messages stays the native channel name.

## Rules

- Retired Phase-1 **`cs_channels` / `cs_customers` tables are not deployed** — use `merchant_credentials` + `cs_contacts` + `cs_platform_identities`.
- **`merchant_credentials.scope`** is a text array; CS filters with overlap on `{cs}`. A row may be `{earn,cs}` for shared LINE credentials.
- **Identity resolution** runs before conversation create: inbound `(platform_type, platform_user_id)` → contact + identity row.
- **Merge** — Secondary contact re-points identities, conversations, tickets, and memory to primary; secondary row deleted (`cs_bff_merge_contacts` / `cs_fn_merge_contacts`).
- **Memory** — Writes require source conversation; upsert key `(contact, merchant, category, key)`; expired rows ignored at retrieval; PDPA delete clears all memory for a contact.
- **Secrets** — Tokens and webhook secrets live in credential JSON; never copy into message bodies or logs.
- **Order vs CS marketplace rows** — Same seller may have one credential with `scope IS NULL` (orders) and one with `scope @> {cs}` (chat); order sync must not read CS rows.

## Journeys

### Admin journey

| Knob | Effect |
| --- | --- |
| Connect / edit credential | Enables ingress and outbound for that platform |
| `channel_config` | Rate limits, session timeout, voice overrides, transport flags |
| Integration Hub fields | Platform-specific secrets, webhook fan-out (LINE) |
| Contact merge | Unifies duplicate persons across channels |

| Page | Owning repo | BFF / RPC |
| --- | --- | --- |
| **CS Channels** | loyalty-admin | `cs_bff_get_channels`, `cs_bff_upsert_channel` |
| **CS Customers** | loyalty-admin | Contact list/detail (table reads + `cs_bff_get_contact_details`) |
| Integrations Hub | loyalty-admin | `bff_get_integration_config`, `bff_upsert_integration_config` |

1. Open **CS Channels** → connect marketplace, LINE, Twilio, or other supported type.
2. Complete OAuth or paste credentials in Integrations Hub where required.
3. Copy webhook URL from channel row; register at platform (or configure LINE fan-out destinations on LINE Messaging credential).
4. Send test inbound; confirm contact and conversation appear in **CS Inbox**.
5. Optionally review **CS Customers** for duplicates and merge.

### Member journey

1. Member sends message in platform-native UI (marketplace chat, LINE, SMS, etc.).
2. Platform or partner webhook hits Rocket edge → signature verify → shared ingest.
3. System resolves contact → attaches to conversation → member sees reply in same UI.
4. If webhook misconfigured, member sees no response; merchant sees disconnected health on **CS Channels**.

## System

### Data model

| Table | Role |
| --- | --- |
| `merchant_credentials` | Channel connection: `service_name`, `scope`, `external_id`, `credentials` jsonb, `channel_config`, webhook URL, health |
| `cs_contacts` | Person: display, email, phone, language, tags, `crm_user_id` (nullable loyalty link), timestamps |
| `cs_platform_identities` | FK `contact_id` (not `customer_id`), `platform_type`, `platform_user_id`, display name |
| `cs_customer_memory` | FK `contact_id`, category/key/value, confidence, `source_conversation_id`, `expires_at` |

Unique identity: `(contact_id, platform_type, platform_user_id)`. Memory upsert index: `(contact_id, merchant_id, category, key)`.

Phone inventory (`cs_phone_numbers`) and voice routing: **`CS_Phone_Number_Purchasing.md`**, **`CS_Voice.md`** — not duplicated here.

### Functions

| Function | Role |
| --- | --- |
| `cs_api_receive_message` | Normalized ingress entry (platform type, user id, content, conversation id) |
| `cs_fn_resolve_contact` | Find or create contact + identity |
| `cs_fn_merge_contacts` | Server-side merge |
| `cs_bff_merge_contacts` | Admin merge action |
| `cs_fn_extract_customer_memory` | Batch upsert memories after conversation |
| `cs_bff_get_channels` / `cs_bff_upsert_channel` | CS channel list and create/update |
| `cs_bff_get_contact_details` | Sidebar: identities, memory, recent conversations |
| `cs_bff_get_contact_conversations` | History list |
| `cs_bff_get_contact_stats` | Customer list aggregates |
| `cs_bff_get_loyalty_snapshot_for_contact` | Linked member snapshot in inbox |

Direct Supabase reads/updates on contacts and memory where RLS allows (customer list UI).

### Flows

**Identity resolution** — Webhook payload → lookup `cs_platform_identities` by merchant + platform + user id → existing contact or insert contact + identity.

**Cross-platform linking** — Same phone/email or agent-initiated merge; auto-suggest is product/UI layer on merge BFFs.

**Memory** — After resolve, async extraction (pipeline) calls `cs_fn_extract_customer_memory`; next turn loads rows into AI context (`CS_AI_Pipeline.md`).

**LINE fan-out** — Single LINE webhook URL on `webhook-line`; optional `webhook_fanout_destinations` on LINE Messaging credential posts copy to partners (HTTPS, `{messaging_channel_id}` substitution); fire-and-forget.

**Lazada CS IM** — Separate Open Platform app with `scope '{cs}'`; inbound `webhook-lazada-cs` → `cs-ingest` → `cs_api_receive_message` + Inngest `cs/message.received`; outbound `cs-send-message` → messaging-service Lazada adapter (session id on conversation). Order app credentials remain `scope IS NULL`.

**Shopee chat (DooPage)** — CS shop link: `service_name='shopee'`, `scope='{cs}'`, `channel_config.transport='doopage'`. Inbound `webhook-doopage-cs`; outbound browser SDK mode from `cs-send-message` / `doopage-cs-sign-send` (not messaging-service POST). Retired `webhook-shopee` → 410.

**Supported platform types (ingress)** — Shopee, Lazada, TikTok Shop, LINE, Meta, WhatsApp, email, web widget, voice/SMS via Twilio — capability matrix in **`CS_Channel_Connectors.md`**.

### External services

- Edge: `webhook-line`, `webhook-lazada-cs`, `webhook-doopage-cs`, `webhook-twilio-sms`, `doopage-cs-get-auth-url`, `doopage-cs-exchange-token`, shared `lib/cs-ingest.ts`.
- Render: `messaging-service` outbound adapters (Lazada CS, LINE, etc.).
- Architecture refs: `requirements/architecture/channel-webhooks-and-multi-app-credentials.md`, `requirements/architecture/doopage-partner-handoff.md`.

### Known gaps

- `webhook-shopee` retired; direct Shopee API path not available — DooPage transport required.
- `webhook-line` still inlines ingest; migration to shared `cs-ingest` is a candidate.
- Integration registry field groups evolve — verify `integration_type_master` / field definitions in DB when documenting new platforms.

## Related

- **CS_Channel_Connectors.md** — Per-platform message types and limits.
- **CS_Phone_Number_Purchasing.md** — Twilio search/purchase/release.
- **CS_Conversations.md** — Threads after ingress.
- **CS_Unified_Inbox.md** — Contact sidebar in agent desk.
- **CS_AI_Pipeline.md** — Memory injection into prompts.
- **CS_Feature_Spec.md** — Umbrella rename map.
