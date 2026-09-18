# CS Channel Connectors

Per-platform **ingress and send** capabilities — what each channel supports live vs roadmap; pair with credentials in **`CS_Channels.md`**.

Owner surfaces: Supabase Edge webhooks, Render `messaging-service`, DooPage browser SDK for Shopee send

## Concept

**Connector** — Webhook receiver + outbound adapter for a platform type on `merchant_credentials`.

**Live vs roadmap** — Registry and deploy list win over matrix below.

**Transport override** — Same platform type (e.g. `shopee`) may use DooPage transport for chat while orders use separate credential row.

## Rules

- **Deployed ingress (verify `REGISTRY_RENDER.md`)** — `webhook-line`, `webhook-lazada-cs`, `webhook-doopage-cs`, `webhook-twilio-sms`, `webhook-twilio-voice`; retired `webhook-shopee` → 410.
- **Marketplace chat** — Platform `conversation_id` / session id required on send (Lazada session on `cs_conversations.platform_conversation_id`).
- **Shopee chat** — Rocket uses DooPage partner path, not direct Shopee Chat API.
- **Rate limits / retries** — Adapter responsibility; failures in message `metadata`.
- **WhatsApp / email / web widget / Meta** — Matrix entries may be **partial or planned** — confirm before sales claims.

## Journeys

### Admin journey

1. Enable credential on **CS Channels** / Integrations Hub.
2. Register webhook URL and secrets at provider.
3. Send test inbound; for Shopee CS complete DooPage OAuth (`doopage-cs-*` edges).

### Member journey

Native marketplace or messaging app UI only.

## System

### Live paths (summary)

| Platform | Ingress | Outbound |
| --- | --- | --- |
| LINE | `webhook-line` → ingest | messaging-service LINE adapter |
| Lazada CS IM | `webhook-lazada-cs` → `cs-ingest` | messaging-service Lazada CS adapter |
| Shopee CS | `webhook-doopage-cs` → ingest | Browser SDK (`delivery.mode=browser_sdk`) |
| SMS | `webhook-twilio-sms` | Twilio via messaging-service / TwiML |
| Voice | `webhook-twilio-voice` | ElevenLabs + graph executor (`CS_Voice.md`) |

Shared downstream: `cs_api_receive_message`, Inngest `cs/message.received`, `cs-send-message`.

### Capability matrix (product target)

**Marketplace** — Text, product/order/voucher cards where API allows; TikTok 12h response SLA external constraint.

**Messaging apps** — LINE flex/rich menu; Meta handover; WhatsApp templates and 24h window rules.

**Email / widget** — Threading, embed widget, pre-chat form `(roadmap for many merchants)`.

**Voice** — Inbound/outbound telephony detail in **`CS_Voice.md`**, **`CS_Phone_Number_Purchasing.md`**.

### Known gaps

- Full Meta/email/widget connectors may lack production edges — grep `list_edge_functions` / registry before enablement.
- Connector doc §1.x from legacy plan mixed shipped and future — default to **`CS_Channels.md`** for Lazada/DooPage/LINE truth.

## Related

- **CS_Channels.md** — Credentials, fan-out, multi-app Lazada.
- **CS_Conversations.md** — Persisted threads.
- **CS_Actions.md** — Marketplace tool availability per platform.
