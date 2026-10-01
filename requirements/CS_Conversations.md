# CS Conversations

Thread of messages between a **contact** and the brand on a channel credential, with assignment, status, optional ticket link, procedure state, CSAT, and audit events.

Owner surfaces: loyalty-admin **CS Inbox**, edge ingress, Inngest CS worker, AI pipeline

## Concept

**Conversation** — Container for status, priority, assignee/team, modality (chat/voice/etc.), intent, active procedure, platform thread id, optional ticket link.

**Message** — Customer, agent, AI, or system row; internal **notes** use a dedicated message type invisible to the member.

**Conversation event** — Append-only case log (assign, status, escalate, procedure step, CSAT) — not duplicated as chat lines.

**Contact** — CS person linked to the thread; see **`CS_Channels.md`**.

**Ticket** — Parallel SLA/triage object when enabled; conversation may reference `ticket_id` (`CS_Unified_Inbox.md`, `CS_SLA.md`).

## Rules

- **Foreign keys (live)** — `credential_id` → `merchant_credentials`; `contact_id` → `cs_contacts`; `assigned_team_id` → `admin_teams`; `assigned_agent_id` → `admin_users`.
- **Status values** — `open`, `pending`, `snoozed`, `resolved`, `closed`; valid transitions enforced in BFF/product layer (reopen from resolved/closed when member returns within threading rules).
- **Assignment** — Changes write `assigned` events with from/to metadata and optional note; not copied into `cs_messages`.
- **Marketplace threading** — One platform `conversation_id` maps 1:1 to `platform_conversation_id`.
- **Owned channels** — Session timeout and threading interval from credential/brand config decide reopen vs new conversation (defaults in System).
- **Events** — `cs_conversation_events` is insert-only.
- **Outbound dedup** — System/AI identical content within 60s returns existing message id (prevents double-send retries).
- **Topic change** — Same conversation thread continues; separate ticket for second issue is planned product behavior (`CS_Unified_Inbox.md`).

## Journeys

### Admin journey

| Knob | Effect |
| --- | --- |
| Status / priority | Queue filters and SLA |
| Assign agent / team | Ownership, web push, workload |
| Tags / intent | Routing and analytics |
| Procedure binding | `active_procedure_id` + `procedure_state` |
| CSAT | Score/comment on resolve flow |

| Page | Owning repo | BFF / RPC |
| --- | --- | --- |
| **CS Inbox** (list) | loyalty-admin | `cs_bff_list_conversations`, `cs_bff_get_conversation_counts` |
| Thread + case log | loyalty-admin | `cs_bff_get_conversation_details`, `cs_bff_update_conversation`, `cs_bff_send_message` |
| **CS Case Logs** | loyalty-admin | Event-oriented views on same tables |

1. Open **CS Inbox** → filter → select conversation.
2. Read messages and case log sidebar.
3. Reply (`cs_bff_send_message`) or add internal note.
4. Assign, change status/priority, or clear assignee with optional assignment note.
5. Bind or advance procedure; resolve when done (`cs_fn_resolve_conversation` path via BFF).

### Member journey

1. Member sends message on channel → webhook → `cs_api_receive_message`.
2. Member sees replies in native UI when outbound delivery succeeds (`cs-send-message` or browser SDK transport).
3. After resolve, CSAT prompt when configured (`cs_bff_submit_csat`, CSAT capture trigger on messages).

## System

### Data model

**`cs_conversations`** (live columns include): `modality`, `ticket_id`, `csat_score`, `csat_submitted_at`, `csat_comment`, `updated_at`, plus status, priority, assignment, intent, procedure fields, `platform_conversation_id`, timestamps.

**`cs_messages`** — `sender_type` (`customer`, `agent`, `ai`, `system`); `message_type` includes `text`, `image`, `product_card`, `order_card`, `voice_transcript`, `file`, `note`; `metadata` for platform ids and delivery.

**`cs_conversation_events`** — `event_type` includes `created`, `message_received`, `assigned`, `status_changed`, `action_executed`, `escalated`, `resolved`, `procedure_step_completed`, `csat_submitted`; `actor_type` + `event_data` jsonb.

Triggers: outbound delivery on message insert; CSAT reply capture on insert (`REGISTRY_SUPABASE.md`).

### Functions

| Function | Role |
| --- | --- |
| `cs_api_receive_message` | Master inbound: contact resolve, upsert conversation, insert message |
| `cs_fn_upsert_conversation` | Threading / platform id / session rules |
| `cs_fn_insert_message` | Insert + last_message_at + event; dedup for system/ai |
| `cs_fn_load_conversation_context` | AI bundle: messages, contact, memory, ticket, config, procedure |
| `cs_fn_resolve_conversation` | Resolve conversation (+ linked ticket when applicable) |
| `cs_fn_save_procedure_state` | Persist procedure step state on row |
| `cs_bff_list_conversations` | Inbox list with preview and unread |
| `cs_bff_get_conversation_details` | Thread + events + related objects |
| `cs_bff_update_conversation` | Status, assignment, tags, intent, custom fields |
| `cs_bff_send_message` | Agent reply or note |
| `cs_bff_submit_csat` | Record CSAT |

### Flows

**Inbound** — Edge webhook → `cs_api_receive_message` → Inngest `cs/message.received` → `inngest-cs-serve` pipeline (`CS_AI_Pipeline.md`) → optional outbound send.

**Human reply** — BFF insert message → delivery trigger → channel adapter.

**Lifecycle** — Open ↔ pending/snoozed → resolved → closed; reopen when member messages within threading interval.

**Session defaults (configurable per channel)** — LINE: 24h session / 48h threading; WhatsApp: 24h/24h; email threading 72h; web chat session 30m; voice: new conversation per call.

### External services

- `inngest-cs-serve` (Edge), Render agent/MCP layer per `CS_AI_Pipeline.md`
- `cs-send-message`, channel-specific edges (`CS_Channels.md`)

### Known gaps

- Topic-split ticket behavior may be partial vs Phase-2 spec — verify inbox UI.
- Pipeline routing (`cs/agent.decide`, AgentKit) evolves — treat `CS_AI_Pipeline.md` as runtime source.

## Related

- **CS_Unified_Inbox.md** — Queue UX, tickets, views.
- **CS_AI_Pipeline.md** — Post-insert AI processing.
- **CS_Channels.md** — Ingress and credentials.
- **CS_Procedures.md** — Procedure columns and state.
- **CS_SLA.md** — Ticket timers when linked.
