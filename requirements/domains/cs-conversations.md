# CS Conversations

> Per-domain reference. Read ONLY when working on this domain. For the keyword → file map, see `_index.md`.

**Keywords:** conversation, message, inbox, chat, reply, assign, resolve, close, reopen, ticket, priority, snoozed, pending, open, cs_conversations, cs_messages, cs_conversation_events, sender_type, message_type, note, internal_note, procedure_state

**Source:** `CS_Conversations.md`

**Tables:** `cs_conversations`, `cs_messages`, `cs_conversation_events`

**Functions (planned):**

| Function | Type | Purpose |
|---|---|---|
| `cs_bff_get_conversations` | BFF | Get conversation list for inbox |
| `cs_bff_get_conversation_detail` | BFF | Get single conversation with messages and events |
| `cs_bff_assign_conversation` | BFF | Assign conversation to agent or team |
| `cs_bff_update_conversation_status` | BFF | Change conversation status |
| `cs_fn_upsert_conversation` | Backend | Create or update conversation from webhook |
| `cs_fn_insert_message` | Backend | Insert message and update timestamps |
| `cs_fn_log_event` | Backend | Log a conversation event |

**Key Business Rules (summary):**
- Status lifecycle: `open` → `pending` → `snoozed` → `resolved` → `closed` (reopen on new message)
- One active conversation per customer per channel at a time
- Threading interval per channel determines new vs. existing conversation
- Internal notes (`message_type = 'note'`) are never sent to the customer
- Conversation events are append-only (INSERT-only, never updated)
- `procedure_state` tracks active AOP step for UI display

---
