# CS Unified Inbox

Agent workspace in loyalty-admin: triage **conversations** (live threads) alongside **tickets** (structured work), filters, assignment, and copilot panels.

Owner surfaces: loyalty-admin **CS Inbox**, **CS Supervisor**, web push (`cs-web-push`)

## Concept

**Conversation** — Real-time message thread on a credential; list + thread UI in **CS Inbox**.

**Ticket** — Structured issue with type, status, SLA fields, optional parent/child; may link to one or more conversations via `cs_conversations.ticket_id`.

**View / filter** — Status, assignee, team, modality, search — implemented as BFF list params (saved custom views are product roadmap).

**Agent workspace layout** — Conversation list, chat thread, content sidebar (contact, loyalty snapshot, knowledge/resource search, case log).

**Supervisor** — Team load and analytics on separate pages (`CS_Analytics.md`, **CS Supervisor**).

## Rules

- **Conversation vs ticket** — Simple FAQ may resolve with conversation only; tracked issues get a ticket (manual, rules engine, or AI policy).
- **Reopen vs new conversation** — Threading rules in **`CS_Conversations.md`** (marketplace platform id vs owned-channel timeouts).
- **Multi-issue chat** — Prefer new ticket per issue, same conversation thread (no forced thread split for the member).
- **Assignment** — Agent or team on conversation and/or ticket; changes notify assignee when web push enabled (`CS_Platform_Features.md`).
- **Member** — No Rocket-hosted inbox; members stay on channel UI.

## Journeys

### Admin journey

| Knob | Effect |
| --- | --- |
| List filters | Status, priority, assignee, team, modality, search |
| Assignment | Ownership + `assigned` case events |
| Snooze / resolve | Queue removal and SLA stop |
| Content panel | Knowledge search, resource send, contact history |
| Push subscription | Browser notify on assign + inbound |

| Page | Owning repo | BFF / RPC |
| --- | --- | --- |
| **CS Inbox** | loyalty-admin | `cs_bff_list_conversations`, `cs_bff_get_conversation_details`, `cs_bff_update_conversation`, `cs_bff_send_message`, `cs_bff_get_conversation_counts` |
| Contact sidebar | loyalty-admin | `cs_bff_get_contact_conversations`, `cs_bff_get_contact_tickets`, `cs_bff_get_loyalty_snapshot_for_contact` |
| Copilot panel | loyalty-admin | Knowledge/resource search BFFs, `cs_bff_send_resource` |
| Tickets (when exposed) | loyalty-admin | `cs_bff_list_tickets`, `cs_bff_get_ticket_details`, `cs_bff_update_ticket` |
| Agents / teams pickers | loyalty-admin | `cs_bff_list_agents`, `cs_bff_list_teams` |

1. Open **CS Inbox** → choose filter tab or search.
2. Select row → load thread, case log, contact sidebar.
3. Reply, assign (optional note), change status/priority, snooze, or resolve.
4. Search knowledge or resources in content panel; send resource card when allowed.
5. Create or update linked ticket when issue needs SLA tracking (`cs_bff_update_ticket`).
6. Register push once (`cs_bff_upsert_push_subscription`) for assignment alerts.

### Member journey

1. Member messages on connected channel (unchanged native UI).
2. Sees agent or AI replies when delivery succeeds — no separate member portal for inbox.

## System

### Data model

- **`cs_conversations`** — Thread state, `ticket_id` FK when linked (`CS_Conversations.md`).
- **`cs_tickets`** — `ticket_number`, `ticket_type`, status lifecycle, assignment, SLA due columns, `parent_ticket_id`, contact link.
- **`cs_ticket_events`** — Append-only ticket audit (parallel to conversation events).

### Functions

Conversation BFFs listed above; ticket BFFs: `cs_bff_list_tickets`, `cs_bff_get_ticket_details`, `cs_bff_update_ticket`, `cs_bff_get_contact_tickets`. Auto-assign helpers: `cs_fn_auto_assign` (`CS_Rules_Engine.md`). SLA: `cs_fn_assign_sla`, `cs_fn_check_sla_breaches` (`CS_SLA.md`).

### Flows

**Triage** — List RPC with filters → detail RPC loads messages + `events` + ticket snippet.

**Ticket auto-create** — Rules engine or AI policy (`cs_fn_evaluate_rules`, pipeline) — not every merchant enables all triggers.

**Follow-up conversation** — New thread may attach to open ticket for same contact (product logic in upsert + ticket BFFs).

**Realtime** — Inbox refreshes via client polling/subscriptions; full WebSocket spec in legacy plan — verify FE before claiming SSE.

### External services

- Edge `cs-web-push` for agent notifications.
- `CS_Live_Assist.md` for draft/summary UX in thread.

### Known gaps (legacy plan §2 vs shipped)

Many items from the original unified-inbox product spec are **not fully shipped** — treat as roadmap unless verified in loyalty-admin `cs-inbox`:

- Kanban ticket board, saved custom views, bulk actions, merge/split conversation, side conversations, forward-to-email, collision detection, undo send.
- Cross-channel single thread (contact profile links channels; separate conversations per credential remain normal).
- Rich ticket field catalog (resolution category, root cause) — verify ticket form vs `cs_tickets.custom_fields` only.

Shipped core: conversation list + thread, assignment events, case log, contact/history sidebar, loyalty snapshot, knowledge/resource panel, push registration, ticket tables + BFFs in registry.

## Related

- **CS_Conversations.md** — Messages, events, threading.
- **CS_SLA.md** — Business hours and breach checks.
- **CS_Rules_Engine.md** — Auto-assign, auto-ticket, auto-tag.
- **CS_Live_Assist.md** — Suggested replies and summaries.
- **CS_Platform_Features.md** — Roles, teams, notifications.
