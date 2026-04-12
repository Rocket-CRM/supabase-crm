# CS Tickets — List + Detail

## What This Is

Ticket management for tracking customer issues to resolution. Tickets are structured work items — distinct from conversations (which are the real-time message threads). A simple question answered by AI needs no ticket. A refund request, complaint, or multi-step issue gets a ticket.

- **List page** — Browse, filter, search tickets. Supports table view and Kanban board view.
- **Detail page** — Full ticket view with linked conversations, timeline, custom fields, SLA status

The AI in this project should use its own judgment for what UI layout and interaction patterns produce the best UX for **managing customer service tickets with SLA tracking**. Study how Zendesk's ticket views, Freshdesk's ticket management, or Linear's issue tracker approach this — then decide the best structure.

---

## FE Project Context

| Layer | Tech |
|---|---|
| Framework | Next.js 16 (App Router, React 19) |
| UI | Shopify Polaris v13 (the only component library) |
| Backend | All data via `supabase.rpc()` |
| Auth | Supabase Auth, JWT carries merchant context |
| Forms | `react-hook-form` + `zod` |

### Routes

```
src/app/(admin)/cs-tickets/            → Ticket list (table + kanban views)
src/app/(admin)/cs-tickets/[id]/       → Ticket detail
```

---

## Backend Connection — Tables & RPCs

### Core Table

**`cs_tickets`**

| Column | Type | Notes |
|---|---|---|
| `id` | uuid PK | |
| `merchant_id` | uuid FK | |
| `ticket_number` | text | Auto-generated: "TKT-2026-00001". UNIQUE per merchant. |
| `ticket_type` | text | `refund`, `cancellation`, `complaint`, `product_inquiry`, `shipping`, `account`, `general` |
| `status` | text | `new`, `open`, `in_progress`, `waiting_on_customer`, `escalated`, `resolved`, `closed`, `reopened` |
| `priority` | text | `urgent`, `high`, `normal`, `low` |
| `subject` | text | "Refund for order #12345" |
| `description` | text | AI-generated or agent-written summary |
| `contact_id` | uuid FK → cs_contacts | |
| `assigned_agent_id` | uuid FK → admin_users | Nullable |
| `assigned_team_id` | uuid FK → admin_teams | Nullable |
| `parent_ticket_id` | uuid FK → cs_tickets | Nullable — for parent-child tickets |
| `sla_policy_id` | uuid FK → cs_sla_policies | |
| `sla_response_due_at` | timestamptz | Calculated from SLA policy |
| `sla_resolution_due_at` | timestamptz | |
| `source` | text | `conversation`, `email`, `web_form`, `internal`, `api` |
| `tags` | text[] | |
| `custom_fields` | jsonb | Configurable per merchant |
| `first_response_at` | timestamptz | |
| `resolved_at` | timestamptz | |
| `closed_at` | timestamptz | |
| `created_at` | timestamptz | |
| `updated_at` | timestamptz | |

**`cs_ticket_events`** — Audit trail (INSERT-only)

| Column | Type | Notes |
|---|---|---|
| `id` | uuid PK | |
| `merchant_id` | uuid | |
| `ticket_id` | uuid FK → cs_tickets | |
| `event_type` | text | `created`, `status_changed`, `assigned`, `escalated`, `priority_changed`, `sla_warning`, `sla_breached`, `note_added`, `action_taken`, `child_created`, `resolved`, `closed`, `reopened` |
| `actor_type` | text | `contact`, `agent`, `ai`, `system`, `rule` |
| `actor_id` | uuid | |
| `event_data` | jsonb | `{from_status: "open", to_status: "in_progress"}` |
| `created_at` | timestamptz | |

### RPCs — Ticket List

| RPC | Purpose | Notes |
|---|---|---|
| `cs_bff_get_tickets` | List tickets with filters | Params: status, priority, ticket_type, assigned_agent_id, assigned_team_id, contact_id, tags, sla_status (on_track/warning/breached), date_range, search, pagination, sort_by |
| `cs_bff_get_ticket_counts` | Badge counts for views | Returns counts for: My Tickets, Unassigned, All Open, Overdue, Waiting on Customer, Resolved (pending close) |
| `cs_bff_get_tickets_kanban` | Kanban board data | Returns tickets grouped by status column, with summary data per card |
| `cs_bff_bulk_update_tickets` | Bulk actions | Params: ticket_ids[], action (assign, change_status, change_priority, add_tag, close). For bulk operations. |

### RPCs — Ticket Detail

| RPC | Purpose | Notes |
|---|---|---|
| `cs_bff_get_ticket` | Full ticket detail | Returns: ticket fields + linked conversations (via cs_conversations.ticket_id) + ticket events timeline + customer profile + SLA countdown |
| `cs_bff_update_ticket` | Update ticket fields | Params: ticket_id, fields to update (status, priority, assigned_agent_id, assigned_team_id, tags, custom_fields, description) |
| `cs_bff_get_ticket_timeline` | Event timeline | Params: ticket_id. Returns chronological list of all ticket_events + linked conversation messages interleaved. |
| `cs_bff_create_child_ticket` | Create sub-ticket | Params: parent_ticket_id, ticket_type, priority, subject, description, assigned_team_id |
| `cs_bff_link_conversation` | Link conversation to ticket | Params: ticket_id, conversation_id |
| `cs_bff_add_ticket_note` | Add internal note | Params: ticket_id, content |

---

## Key Domain Concepts the UI Must Support

### 1. Ticket Lifecycle

```
[New] → [Open] → [In Progress] → [Waiting on Customer] → [Resolved] → [Closed]
                       ↑                    |                    ↑          |
                       |                    ↓                    |          ↓
                  [Escalated]         customer replies       auto-close  [Reopened] → [Open]
```

Status transitions should be intuitive — dropdown or button actions depending on context.

### 2. Views

Pre-built views with badge counts:
- **My Tickets** — Assigned to current agent
- **Unassigned** — No agent assigned
- **All Open** — All non-closed tickets
- **Overdue** — SLA breached
- **Waiting on Customer** — Awaiting customer response
- **Resolved (pending close)** — Resolved but not yet closed

Custom views: save filter combinations as named views (channel + status + priority + tags + date range).

### 3. Kanban Board View

Alternative to table view. Columns = ticket statuses. Cards show: ticket number, subject, customer name, priority badge, SLA countdown, assignee avatar.

Drag-and-drop between columns to change status.

### 4. SLA Indicators

Visual SLA status on every ticket:
- **On track** (green) — within SLA targets
- **Warning** (yellow) — approaching deadline (e.g., within 10 min)
- **Breached** (red) — past SLA deadline

Show both response SLA and resolution SLA separately.

### 5. Parent-Child Tickets

Complex issues split into sub-tickets. Parent ticket shows its children. Parent resolves when all children resolve. Visual hierarchy (tree or nested list).

### 6. Ticket Timeline

Chronological view of everything that happened:
- Status changes
- Agent assignments
- Messages from linked conversations
- Internal notes
- Actions taken (refund processed, voucher created)
- SLA events (warning, breach)

Each event shows actor (who), action (what), and timestamp.

### 7. Ticket + Conversation Relationship

Tickets link to conversations via `cs_conversations.ticket_id`. Multiple conversations can link to the same ticket (customer follows up days later — new conversation, same ticket). The detail page should show all linked conversations.

---

## Key UX Requirements

1. The list page needs to handle both table and kanban views. Toggle between them. Both views share the same filters.

2. Bulk actions are important — agents often need to close or reassign multiple tickets at once.

3. SLA countdowns should be visually prominent — this drives agent urgency.

4. The timeline on the detail page is the single source of truth for what happened with a ticket.

---

## What NOT to Build (Backend Handles These)

- SLA timer calculation (accounting for business hours, pauses) — backend computes
- Ticket auto-creation from conversations — backend/AI creates tickets when needed
- SLA breach notifications — backend sends alerts via Slack/LINE Notify
- Auto-close after timeout — backend handles scheduled closures
