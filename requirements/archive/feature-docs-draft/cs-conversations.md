# Feature Guide: CS Conversations

## 1. Overview

Conversations are the core communication layer of the CS module — every customer interaction across every channel flows through them. When a customer sends a message on LINE, WhatsApp, Facebook, Shopee, or any connected channel, the system creates (or reopens) a conversation and routes it into a unified inbox where agents and AI respond.

The inbox is a 3-panel workspace: conversation list on the left, chat thread in the center, customer details on the right. Agents see all channels in one place — no switching between Shopee chat, LINE OA, and WhatsApp Business. Messages from the customer arrive in real time; agents (or AI) reply from the same thread. The system tracks the full lifecycle from first message through resolution, logging every status change, assignment, and internal note as an immutable event trail.

Two design decisions shape how conversations work: (1) **threading logic** — configurable per-channel rules that determine when a new message continues an existing conversation vs. creates a new one, preventing fragmented customer histories; (2) **AI-first pipeline** — inbound messages flow through an AI agent that can resolve simple queries autonomously, activate procedures (AOPs), or escalate to human agents, all within the same conversation thread.

## 2. Key Concepts

**Conversation** — A message thread between a customer and the business on a specific channel. Contains messages, status, priority, assignment, and optional procedure state. One customer can have many conversations over time, but typically only one active conversation per channel at a time. Example: Customer sends "Where is my order?" on LINE → a conversation is created.

**Message** — A single entry in a conversation thread. Has a sender type, content, and message type. Messages are append-only — they cannot be edited or deleted.

**Sender Type** — Who sent the message: `customer` (end user on their channel), `agent` (human CS agent), `ai` (AI agent), `system` (automated notifications like status changes or assignment events).

**Message Type** — The content format: `text` (plain text), `image` (photo attachment), `product_card` (marketplace product), `order_card` (order details), `voice_transcript` (transcribed voice message), `file` (document attachment), `note` (internal — invisible to customer).

**Internal Note** — A message with `message_type = 'note'`. Visible only to agents in the inbox. Never delivered to the customer's channel. Used for handoff context, investigation notes, or team coordination.

**Conversation Status** — The lifecycle state: `open` (active, needs attention), `pending` (awaiting action), `snoozed` (temporarily hidden, resurfaces at set time), `resolved` (issue addressed), `closed` (fully complete). See Business Rules for valid transitions.

**Priority** — Urgency level: `urgent`, `high`, `normal`, `low`. Displayed as a color strip on the conversation list item (red for urgent, yellow for high). Can be set manually or by routing rules.

**Assignment** — Which agent or team is responsible for a conversation. Can be assigned to an individual agent (`assigned_agent_id`) or a team (`assigned_team_id`). Unassigned conversations appear in the "Unassigned" inbox view.

**Threading Interval** — The time window after a conversation is resolved/closed during which a new message from the same customer on the same channel reopens the existing conversation instead of creating a new one. Configurable per channel. Example: LINE threading interval = 48h. Customer messages 24h after resolution → same conversation reopens. Customer messages 72h after → new conversation.

**Session Timeout** — For active (open/pending) conversations, the maximum idle time before the system closes the conversation as inactive and creates a new one on the next message. Example: Web chat session timeout = 30 minutes.

**Conversation Event** — An immutable audit log entry recording what happened: `created`, `message_received`, `assigned`, `status_changed`, `action_executed`, `escalated`, `resolved`, `procedure_step_completed`, `csat_submitted`. INSERT-only, never updated. Each event records the actor type (`customer`, `agent`, `ai`, `system`, `rule`) and a JSON payload.

**Procedure State** — When an AOP (automated operating procedure) is active on a conversation, the current step, collected data, and tool results are stored as JSON in `procedure_state`. See CS Procedures guide.

**Inbox View** — A filtered subset of conversations. Built-in views: My Open, Unassigned, All Open, Overdue, Resolved. Each view shows a badge count.

**Content Panel** — A slide-out panel within the chat thread for accessing knowledge base articles or canned responses without leaving the conversation.

## 3. Configuration Reference

### Channel Threading (per channel, in cs_channels.config)

| Setting | What it controls | Example | Default |
|---|---|---|---|
| Session timeout | Idle time before active conversation auto-closes | 24h (LINE) | Channel-dependent |
| Threading interval | Window to reopen resolved/closed conversation | 48h (LINE), 24h (WhatsApp) | Channel-dependent |

**Default intervals by channel:**

| Channel | Session Timeout | Threading Interval |
|---|---|---|
| LINE | 24h | 48h |
| WhatsApp | 24h | 24h |
| Email | — | 72h |
| Web chat | 30 min | — |
| Voice | — (every call = new) | — |
| Shopee/Lazada/TikTok | Platform-controlled | Platform-controlled |

### Conversation Fields

| Setting | What it controls | Example | Default |
|---|---|---|---|
| Priority | Urgency level on conversation | `urgent` | `normal` |
| Tags | Free-form labels for categorization | `["refund", "vip"]` | `[]` |
| Intent | AI-detected customer intent | `refund_request` | null |
| Custom fields | Merchant-defined structured data | `{"order_number": "12345"}` | `{}` |

### Brand Configuration (cs-brand-config page)

Channel-level settings (session timeouts, threading intervals, AI behavior, auto-assignment rules) are configured per brand in the **CS Brand Config** page. This is separate from individual conversation settings.

## 4. Agent Journey

**Repo:** `Rocket-CRM/loyalty-admin`

**Route map:**

| Page Name | Current Route | BFF / Data Source |
|---|---|---|
| CS Inbox | `/cs-inbox` | `cs_bff_list_conversations()`, `cs_bff_get_conversation_details()` |
| CS Brand Config | `/cs-brand-config` | Brand config BFF |
| CS Analytics | `/cs-analytics` | Analytics queries |

### 4a. Work the Inbox

1. Open **CS Inbox** — 3-panel layout fills the viewport (no page header)
2. **Left panel** shows conversation list with view tabs: My Open, Unassigned, All Open, Overdue, Resolved — each with badge count
3. Search bar filters conversations by customer name or message content
4. Each conversation row shows: customer initials avatar, customer name, last message preview (prefixed "You:" or "AI:" for non-customer senders), channel badge (LINE, Shopee, WA, etc.), time-ago, unread count badge, priority color strip (red = urgent, yellow = high)
5. Click a conversation (or press J/K to navigate) → **center panel** loads the chat thread
6. **Thread header** shows: customer avatar + name, channel badge, status, priority dropdown, Assign/Transfer/Resolve buttons, sidebar toggle

### 4b. Respond to a Conversation

1. Read the message history in the chat thread (customer messages, AI replies, system events displayed chronologically)
2. Type a reply in the composer at the bottom → send (delivers to customer's channel)
3. To add an internal note: switch to note mode → type → send (note is visible only to agents, never delivered to customer)
4. To access knowledge base articles or canned responses: toggle the **Content Panel** (slides out within the thread area)

### 4c. Manage a Conversation

1. **Assign**: click "Assign" button (or press A) → modal with agent list → select agent → toast "Assigned to [name]"
2. **Change priority**: use the priority dropdown in the thread header (Urgent / High / Normal / Low)
3. **Resolve**: click "Resolve" button (or press E) → conversation moves to Resolved view → toast "Conversation resolved"
4. **Reopen**: on a resolved/closed conversation, click "Reopen" (or press E) → returns to Open
5. **Create ticket**: from the customer sidebar, click "Create Ticket" → modal to fill ticket details → links ticket to this conversation
6. **Update tags**: edit tags in the customer sidebar
7. **View customer profile**: sidebar shows customer details, loyalty member link, past conversations, linked tickets

### 4d. Keyboard Shortcuts

| Key | Action |
|---|---|
| J / K | Navigate conversations down / up |
| E | Resolve (or Reopen if already resolved) |
| A | Open assign modal |
| Cmd/Ctrl + Shift + S | Toggle customer sidebar |

## 5. Customer Experience

The customer interacts entirely through their own messaging channel. There is no dedicated "CS app" — the experience is native to LINE, WhatsApp, Facebook Messenger, Shopee Chat, etc.

**Channel map:**

| Channel | Customer Interface | Message Types Supported |
|---|---|---|
| LINE | LINE app chat | Text, image, file |
| WhatsApp | WhatsApp chat | Text, image, file |
| Facebook/Instagram | Messenger / DM | Text, image |
| Shopee/Lazada/TikTok | Platform chat window | Text, image, product card, order card |
| Email | Email thread | Text, file |
| Web chat | Embedded widget on website | Text, image, file |
| Voice | Phone call → transcribed | Voice transcript |

### 5a. Customer Sends a Message

1. Customer sends a message on their channel (e.g., types "Where is my order?" in LINE)
2. System receives webhook → resolves customer identity → creates or reopens a conversation
3. AI agent evaluates the message, may respond automatically (from knowledge base) or activate a procedure
4. If AI cannot resolve, conversation is assigned to a human agent
5. Customer sees the reply in their channel — indistinguishable from a human or AI sender (no "AI" label on customer side)

### 5b. Customer Receives a Response

1. Agent or AI reply appears as a new message in the customer's chat
2. Rich content (product cards, order cards) renders natively on supported platforms
3. Customer can continue the conversation by sending another message

### 5c. Conversation Ends

1. When the issue is resolved, the conversation moves to resolved status
2. Customer may receive a CSAT survey (if configured)
3. If customer messages again within the threading interval → same conversation reopens
4. If customer messages after the threading interval → new conversation is created with fresh context

## 6. Perspectives

### 6a. For CS Supervisors / Managers

**Key monitoring questions:**

| Question | Where to look |
|---|---|
| How many conversations are waiting? | Inbox view badge counts (Unassigned, All Open) |
| Which agents are overloaded? | Agent assignment distribution in CS Analytics |
| Are SLAs being met? | Overdue view count + CS Analytics |
| What topics are driving volume? | Conversation tags + AI-detected intents |
| Is AI resolving enough autonomously? | AI vs. human resolution ratio in analytics |

**Assignment oversight:** Supervisors can reassign any conversation via the Assign modal. The "Unassigned" view surfaces conversations that need routing. Collision detection shows when another agent is viewing the same conversation.

### 6b. For Marketing

**Customer engagement data available from conversations:**
- Volume by channel (which channels customers prefer)
- Peak contact hours and response time trends
- Top intents and topics (what customers ask about most)
- Resolution patterns (AI-resolved vs. human-resolved)
- CSAT scores post-resolution

**Use cases:** Channel preference data informs where to invest in customer communication. Intent analysis reveals product/service pain points before they become widespread issues. Conversation volume spikes correlate with campaign launches or service disruptions.

### 6c. For Testers

**Status transitions to verify:**

| From | To | Trigger |
|---|---|---|
| (none) | Open | New inbound message creates conversation |
| Open | Pending | Agent or system sets pending |
| Open/Pending | Snoozed | Agent snoozes with a future time |
| Open/Pending | Resolved | Agent clicks Resolve (or AI resolves) |
| Resolved | Closed | Auto-close after configured period |
| Resolved/Closed | Open | Customer sends new message within threading interval |
| (none) | Open | Customer sends message after threading interval (new conversation) |

**Threading logic assertions:**

- ASSERT: Message within session timeout on active conversation → appended to same conversation, no new conversation created
- ASSERT: Message after session timeout on active conversation → old conversation closed as inactive, new conversation created
- ASSERT: Message within threading interval on resolved conversation → conversation reopens to Open status
- ASSERT: Message after threading interval on resolved conversation → new conversation created
- ASSERT: Marketplace channels (Shopee, Lazada, TikTok) → follow platform's own threading, mapped 1:1 by `platform_conversation_id`
- ASSERT: Voice calls always create a new conversation

**Message handling assertions:**

- ASSERT: Internal note (`message_type = 'note'`) is never delivered to customer's channel
- ASSERT: `cs_fn_insert_message` dedup guard → identical message (same conversation + sender_type + content + message_type) within 60s returns existing message_id instead of creating duplicate
- ASSERT: Every status change, assignment, and message creates a `cs_conversation_events` record
- ASSERT: Events are INSERT-only — no UPDATE or DELETE on `cs_conversation_events`

**Config → expected behavior:**

| Config | Expected Behavior |
|---|---|
| LINE threading_interval = 48h, customer messages 24h after resolve | Same conversation reopens |
| LINE threading_interval = 48h, customer messages 72h after resolve | New conversation created |
| Web chat session_timeout = 30min, idle for 45min then new message | Old conversation closed, new one created |
| Priority = urgent | Red color strip on conversation list item |
| Conversation unassigned | Appears in "Unassigned" inbox view |
| Agent sends note | Note visible in thread, not delivered to customer channel |

**Cross-feature scenarios:**
- Conversation with active procedure → `procedure_state` updates on each AOP step
- AI resolves conversation → `cs_conversation_events` records `resolved` with `actor_type = 'ai'`
- Customer contacts on Shopee AND LINE → two separate conversations, but linked under one `cs_customers` profile
- Agent creates ticket from conversation → ticket linked to `conversation_id`

## 7. Business Rules

**Rule:** One active conversation per customer per channel. A new inbound message on a channel with an existing open/pending conversation is appended to that conversation.
**Example:** Customer sends "Hello" then "Where's my order?" on LINE 5 minutes apart → both messages in same conversation.

**Rule:** Threading interval determines reopen vs. new creation. Within the interval, resolved/closed conversations reopen. After the interval, a new conversation is created.
**Example:** LINE threading_interval = 48h. Resolved conversation, customer messages 36h later → reopens. Messages 60h later → new conversation.

**Rule:** Session timeout applies only to active conversations (open/pending). If the conversation is idle beyond the timeout, the system closes it as inactive and creates a new conversation on the next message.
**Example:** Web chat timeout = 30 min. No messages for 45 min → old conversation closed. Customer types again → new conversation.

**Rule:** Marketplace channels follow the platform's native threading. Shopee, Lazada, and TikTok Shop provide their own `conversation_id` — the system maps 1:1 and does not apply its own threading logic.
**Example:** Shopee buyer sends messages across different days in the same Shopee chat thread → all map to one conversation.

**Rule:** Internal notes are never delivered to the customer's channel. They exist only in the inbox thread for agent coordination.
**Example:** Agent adds note "Checking with warehouse team" → customer sees nothing new in their LINE chat.

**Rule:** Conversation events are append-only. Every status change, assignment, message receipt, and action execution is logged as an immutable event. Events cannot be modified or deleted.
**Example:** Conversation assigned → reassigned → resolved generates three separate event records.

**Rule:** Message deduplication prevents duplicate AI/system messages. If an identical message (same conversation + sender_type + content + message_type) is inserted within 60 seconds, the existing message_id is returned.
**Example:** Retry logic triggers duplicate AI response → second insert returns the first message_id, no duplicate in thread.

**Rule:** Topic change mid-conversation does not split the thread. AI creates a new ticket for the second issue while continuing the same conversation.
**Example:** Customer asks about a refund, then asks about store hours → one conversation, two tickets.

**Rule:** Voice calls always create a new conversation. There is no threading interval for voice — each call is a distinct conversation.

## 8. Related Features

| Feature | Connection to Conversations |
|---|---|
| CS Knowledge Base | AI agent retrieves articles to answer customer questions within conversations. Agents access via Content Panel. See `CS_Knowledge_Base.md`. |
| CS Channels | Each conversation is tied to a channel (LINE, Shopee, etc.). Channel config controls threading intervals and session timeouts. See `CS_Channels.md`. |
| CS Procedures (AOPs) | Active procedure state is stored on the conversation. AOP steps execute within the conversation thread. See `CS_Procedures.md`. |
| CS Customers | Conversations are linked to a customer profile. Multiple conversations across channels are unified under one customer. See `CS_Channels.md` (customers section). |
| CS Teams | Conversations can be assigned to teams for group routing. See CS Teams configuration. |
