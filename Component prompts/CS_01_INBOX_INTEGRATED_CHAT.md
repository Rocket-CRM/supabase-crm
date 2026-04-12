# CS Inbox — Integrated Chat

## What This Is

The primary workspace for CS agents and AI-assisted customer conversations. This is the most complex page in the CS module — a real-time, multi-panel interface where agents view, manage, and respond to customer conversations across all connected channels (Shopee, Lazada, TikTok Shop, LINE, WhatsApp, Facebook, Instagram, email, web chat, voice).

The AI in this project should use its own judgment for what UI layout, component structure, and interaction patterns produce the best UX for a **real-time omnichannel customer service inbox**. Study how Intercom, Zendesk, Freshdesk, Gorgias, and Duoke structure their agent workspaces — then decide the best approach using the available component libraries.

---

## FE Project Context

| Layer | Tech |
|---|---|
| Framework | Next.js 16 (App Router, React 19) |
| UI | Shopify Polaris v13 (the only component library) |
| Chat UI | **assistant-ui** (`ExternalStoreRuntime` adapter) — for the message thread and composer |
| Real-time | Supabase Realtime (`postgres_changes` on `cs_messages`) |
| Backend | Complex operations via `supabase.rpc()`. Simple single-table reads/writes via `supabase.from()` (RLS handles merchant scoping). |
| Auth | Supabase Auth, cookie-based SSR sessions. JWT carries merchant context. |
| Forms | `react-hook-form` + `zod` |

### Route

```
src/app/(admin)/cs-inbox/
```

### Chat Interface

The chat message thread and composer MUST use **assistant-ui** with `ExternalStoreRuntime`. assistant-ui provides `Thread`, `MessageList`, `Composer` components. The `ExternalStoreRuntime` adapter connects assistant-ui to Supabase-backed message persistence. Everything outside the chat thread (conversation list, sidebars, toolbars) uses Polaris components.

### Real-time Updates

Subscribe to Supabase Realtime `postgres_changes` on `cs_messages` table filtered by conversation_id. New messages from customers, AI, or other agents appear instantly without polling.

---

## Backend Connection — Tables & RPCs

### Core Tables (complex reads via RPCs; simple single-table reads via `supabase.from()`)

| Table | Purpose |
|---|---|
| `cs_conversations` | Conversation threads — status, priority, channel, assigned agent/team, tags, intent, active procedure |
| `cs_messages` | Messages within conversations — sender_type (contact/agent/ai/system), content, message_type (text/image/product_card/note), metadata |
| `cs_conversation_events` | Audit trail — status changes, assignments, actions taken, AI reasoning |
| `cs_contacts` | Customer profiles — name, email, phone, language, tags, custom fields |
| `cs_platform_identities` | Cross-platform identity mapping (Shopee buyer ID, LINE UID, etc.) |
| `cs_customer_memory` | Persistent memory — preferences, allergies, interests extracted from past conversations |
| `cs_tickets` | Linked tickets — structured work items with status, priority, SLA |
| `cs_procedures` | Active AOP running in the conversation (if any) |

### RPCs to Connect

**Conversation List (left panel):**

| RPC | Purpose | Params | Returns |
|---|---|---|---|
| `cs_bff_list_conversations` | List conversations with filters | `p_status`, `p_priority`, `p_assigned_agent_id`, `p_assigned_team_id`, `p_modality`, `p_search`, `p_limit`, `p_offset` | `{ conversations: [...], total: N }`. Each conversation includes: id, status, priority, modality, platform (line_messaging/shopee/lazada/etc.), tags, contact (id/display_name/phone/email), last_message (content/sender_type/message_type), unread_count, assigned_agent_id, assigned_team_id, credential_id, last_message_at, created_at |
| `cs_bff_get_conversation_counts` | Badge counts for views | (none) | Counts for: My Open, Unassigned, All Open, Overdue, Recently Resolved |

**Chat Thread (center panel):**

| RPC | Purpose | Params | Returns |
|---|---|---|---|
| `cs_bff_get_conversation_details` | Full conversation data | `p_conversation_id` | `{ conversation: {..., platform}, messages: [...], contact: {..., platform_identities: [...]}, ticket: {...} or null }` |
| `cs-send-message` (edge function) | Agent sends a message or internal note. **Call via `fetch()` to the edge function, NOT `supabase.rpc()`** — saves to DB AND delivers via messaging service. `verify_jwt: false` — auth handled inside. | POST body: `{ conversation_id, content, message_type, metadata }`. Auth: pass Supabase Auth JWT in Authorization header + apikey header. | `{ success: true, data: { message_id, delivery } }`. For notes (`message_type:'note'`), delivery is skipped. See `CS_OUTBOUND_FE_FIX.md` for full integration guide. |

**Conversation Actions (all handled by single function):**

| RPC | Purpose | Params |
|---|---|---|
| `cs_bff_update_conversation` | Update any conversation field: status, priority, assignment, tags, intent, custom_fields | `p_conversation_id`, `p_status`, `p_priority`, `p_assigned_agent_id`, `p_assigned_team_id`, `p_tags`, `p_intent`, `p_custom_fields` — all optional except conversation_id |

Use this single function for: assign, transfer, change status, change priority, update tags.

**Ticket from conversation:**

| RPC | Purpose | Params |
|---|---|---|
| `cs_bff_update_ticket` | Create ticket linked to conversation (pass conversation_id, omit ticket_id) | `p_conversation_id`, `p_contact_id`, `p_ticket_type`, `p_status`, `p_priority`, `p_subject`, `p_description` |

**Customer Sidebar (right panel):**

| RPC | Purpose | Params |
|---|---|---|
| `cs_bff_get_contact_details` | Full customer profile with platform identities, memory, etc. | `p_contact_id` |
| `cs_bff_get_contact_conversations` | Past conversations for this customer | `p_contact_id`, `p_limit`, `p_offset` |
| `cs_bff_get_contact_tickets` | Open tickets for this customer | `p_contact_id`, `p_limit`, `p_offset` |

**AI Features:**

| RPC / API | Purpose | Notes |
|---|---|---|
| `cs_bff_get_ai_suggested_reply` | AI draft reply | Returns suggested response based on conversation context, knowledge base, and brand voice. Agent can edit/approve/discard. |
| `cs_bff_get_canned_responses` | Saved reply templates | Searchable library of pre-written responses |

### Supabase Realtime Subscriptions

| Channel | Filter | Purpose |
|---|---|---|
| `postgres_changes` on `cs_messages` | `conversation_id = :selected` | Live message updates for active conversation |
| `postgres_changes` on `cs_conversations` | `assigned_agent_id = :current_user` OR `merchant_id = :mid` | Conversation list updates (new conversations, status changes, new messages) |

---

## Key UX Requirements

These are functional requirements the AI must satisfy. The visual design, layout proportions, component choices, and interaction patterns are up to the AI's judgment.

1. **Three-panel layout** — Conversation list | Chat thread | Context sidebar. But the AI should decide exact proportions, collapsibility, responsive behavior.

2. **Conversation list** — Filterable, searchable, sortable. Show: customer name, channel indicator, last message preview, time, unread badge, priority indicator, SLA countdown if approaching. Pre-built views (My Open, Unassigned, All Open, Overdue) plus custom filter creation.

3. **Chat thread** — Uses assistant-ui components. Shows messages from customer, agent, AI, and system events in chronological order. Internal notes visually distinct (only visible to agents). Message types: text, images, product cards, order cards, voice transcripts, system events.

4. **Composer** — Uses assistant-ui Composer. Rich text for email channel. Quick actions: canned responses, AI suggested reply, internal note toggle.

5. **Context sidebar** — Customer profile, platform identities, loyalty data, customer memory, linked ticket(s), conversation tags, active procedure status. The sidebar content should be contextual — show what's most useful for the current conversation.

6. **Real-time** — Messages appear instantly. Typing indicators where platform supports them. Conversation list updates when new messages arrive or status changes.

7. **Collision detection** — Show if another agent is viewing/typing in the same conversation.

8. **Keyboard shortcuts** — Navigate conversations, send replies, assign, close without mouse.

---

## What NOT to Build (Backend Handles These)

- Message delivery to platforms (Shopee/LINE/WhatsApp APIs) — the `cs-send-message` edge function handles save + delivery via messaging service
- AI reasoning and procedure execution — handled by cs-ai-service on Render via Inngest
- SLA timer calculation — backend computes, FE just displays the countdown
- Customer identity resolution — backend resolves on message receipt
