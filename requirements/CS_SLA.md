# CS SLA

Response and resolution **timers** on tickets (and conversation-linked work) respecting business hours, pauses, and tier/channel policies.

Owner surfaces: loyalty-admin SLA settings, **CS Inbox** badges, rules/notifications on breach

## Concept

**SLA policy** — Target minutes for first response and resolution; linked from ticket row.

**Business hours** — Weekly schedule + holidays; deadline math skips off-hours when policy requires.

**Pause** — Waiting on customer or snooze stops resolution clock `(product must set ticket/conversation status)`.

**Breach** — Missed deadline drives notifications and workflow actions — urgency only, not refund logic.

## Rules

- **Assign policy** — `cs_fn_assign_sla(p_ticket_id, p_merchant_id, p_business_hours_id)` when ticket created or policy rules fire.
- **Deadline** — `cs_fn_calculate_sla_deadline(start, target_minutes, business_hours_id)` for due timestamps on ticket.
- **Breach scan** — `cs_fn_check_sla_breaches(p_merchant_id, p_warning_minutes)` for approaching/missed SLAs `(cron/event-driven — verify deploy)`.
- **Multiple policies** — VIP vs standard via assignment rules — not hard-coded in SLA functions.
- **AOP independence** — SLA answers *how fast*; procedures answer *what to do*.

## Journeys

### Admin journey

| Knob | Effect |
| --- | --- |
| SLA policies | Response/resolution targets |
| Business hours | Schedules per brand/team |
| Breach workflows | Notify, reassign, priority bump (`CS_Rules_Engine.md`) |

| Page | Owning repo | Tables / RPC |
| --- | --- | --- |
| SLA / hours settings | loyalty-admin | `cs_sla_policies`, `cs_business_hours` + BFFs `(grep registry)` |

1. Define business hours and holiday overrides.
2. Create policies and map via rules or ticket defaults.
3. Review compliance in **CS Analytics**.

### Agent journey

1. Inbox shows due times / breach risk on ticket sidebar when wired.
2. Snooze or mark waiting on customer — timer pauses per status rules.
3. First agent reply sets `first_response_at` on ticket `(via message/ticket helpers)`.

### Member journey

No SLA UI — may receive faster responses when policies and staffing align.

## System

### Data model

| Table | Role |
| --- | --- |
| `cs_sla_policies` | Named targets, channel/tier metadata in json/columns |
| `cs_business_hours` | Schedules, timezone, holiday json |
| `cs_tickets` | `sla_policy_id`, `sla_response_due_at`, `sla_resolution_due_at`, `first_response_at` |

### Functions

`cs_fn_assign_sla`, `cs_fn_calculate_sla_deadline`, `cs_fn_check_sla_breaches`, `cs_fn_first_response_at` (conversation/message helper).

### Flows

Ticket create/update → assign SLA → agents work → status pause/resume → breach job fires workflows/notifications → analytics aggregate compliance.

### Known gaps

- Full SLA reporting UI may lag `CS_Analytics.md` spec (compliance %, breach report).
- After-hours auto-behaviors (AI takeover message) — workflow product, not SLA table alone.

## Related

- **CS_Unified_Inbox.md** — Ticket sidebar timers.
- **CS_Rules_Engine.md** — Approaching breach triggers.
- **CS_Analytics.md** — SLA compliance metrics.
