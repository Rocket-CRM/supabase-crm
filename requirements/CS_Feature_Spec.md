# CS Feature Spec

Customer Service module umbrella on the shared CX Platform: omnichannel conversations, AI-assisted replies, knowledge and procedures, and the agent workspace — composed at runtime, not a single configurable “CS agent” row.

Owner surfaces: loyalty-admin (CS settings + agent inbox), member messaging channels (LINE, marketplace IM, SMS/voice where enabled)

## Concept

**CX Platform modules** — Loyalty (points, tiers, rewards), AMP (marketing automation), and CS (support) share one Supabase project, auth, and merchant scope. CS reads loyalty context when a contact links to a member; it does not replace loyalty ledgers.

**Conversation** — The runtime hub: messages, assignment, status, AI vs human handling, optional procedure state, and audit events. Everything else feeds this object.

**Contact** — The CS person record; may link to a loyalty member when identified. Cross-channel identities resolve to one contact.

**Channel credential** — Merchant connection to a platform (marketplace, LINE, Twilio, etc.); ingress and outbound send are scoped per credential.

**Knowledge & procedure** — Articles (and sources) for retrieval; procedures (AOPs) for intent-specific steps, tone overrides, and tool use.

**Brand configuration** — Voice, models, outbound limits, and tool allowlists composed into each AI turn; guardrails may also live in dedicated guardrail rows.

**Agent workspace** — Unified inbox, copilot drafts, takeover, macros, voice widgets — same conversation record as autonomous AI.

**Automation layers** — CS **workflows** (deterministic rules on events) run beside **procedures** (multi-turn AI-guided playbooks). See `CS_Rules_Engine.md` and `CS_Procedures.md`.

Modular `CS_*.md` files own product depth; this file routes to them and holds cross-cutting platform truth only.

## Rules

- CS AI behavior is a **composition** of merchant config + guardrails + retrieval + active procedure + action registry + contact memory + message history — not one `cs_agent` entity (contrast AMP `amp_agent`).
- **Tenant isolation** — Merchant A knowledge, config, and conversations never leak into merchant B (RLS via `get_current_merchant_id()`).
- **Override chain for voice** — Procedure tone override → channel/credential config → merchant brand defaults (detail in `CS_Platform_Features.md`, `CS_Procedures.md`).
- **Escalation and guardrail hits** must be auditable on the conversation event stream; human takeover blocks autonomous outbound sends until released (inbox rules in `CS_Unified_Inbox.md`, `CS_Conversations.md`).
- **Transactional facts** (order status, stock, refunds) come from **tools** against live APIs — not from stale embeddings (`CS_AI_System.md`, `CS_Actions.md`).
- **Spec vs deployed** — Phase-1 names in old design docs (`cs_customers`, `cs_channels`, `cs_brand_config`, `cs_teams`) map to live objects below; do not implement from retired DDL blocks.

## Journeys

### Admin journey

| Knob | Effect |
| --- | --- |
| Module / plan gate | CS sidebar and inbox visible when merchant entitlements allow |
| Channel credentials | Which platforms ingest and send |
| Brand / guardrails / voice | Default AI behavior and safety |
| Knowledge & sources | Retrieval corpus and sync |
| Procedures | Intent → AOP steps and tools |
| Workflows & rules | Pre-AI automation (assign, tag, auto-reply) |
| Teams & roles | Routing, RBAC for CS pages |
| SLA & business hours | Timers and breach handling |

| Admin area (loyalty-admin) | Truth doc |
| --- | --- |
| CS Inbox | `CS_Unified_Inbox.md`, `CS_Conversations.md` |
| CS Channels | `CS_Channels.md`, `CS_Channel_Connectors.md` |
| CS Customers | `CS_Channels.md` |
| CS Knowledge | `CS_Knowledge_Base.md` |
| CS Procedures | `CS_Procedures.md` |
| CS Workflows | `CS_Rules_Engine.md` |
| CS Teams / CS Roles | `CS_Platform_Features.md` |
| CS Brand Config | `CS_Platform_Features.md`, `CS_AI_Pipeline.md` |
| CS Analytics / Supervisor | `CS_Analytics.md` |
| CS Case Logs / Call Logs | `CS_Conversations.md`, `CS_Voice.md` |
| Phone numbers | `CS_Phone_Number_Purchasing.md` |

1. Enable CS module (plan + sidebar).
2. Connect channel credentials; verify webhook test (`CS_Channels.md`).
3. Publish knowledge and procedures for top intents.
4. Set brand voice, guardrails, and allowed actions.
5. Define teams, roles, assignment rules, and SLA policies.
6. Pilot in **CS Inbox** with agents; tune workflows and pipeline (`CS_Live_Assist.md`).

### Agent journey

Agent desk = admin. Detail lives in `CS_Unified_Inbox.md` and `CS_Live_Assist.md` — not duplicated here.

1. Open **CS Inbox** → filter queue → open conversation.
2. Review AI draft or history; edit, approve send, or take human-only control.
3. Run procedure steps or permitted actions (orders, resources, tags).
4. Resolve, snooze, or escalate; CSAT and analytics follow modular rules.

### Member journey

1. Member messages on a connected channel (marketplace chat, LINE, SMS, voice, web widget where enabled).
2. Platform delivers webhook → contact resolve → conversation thread.
3. Member sees AI or human replies in the native channel UI; errors are channel-specific (`CS_Channel_Connectors.md`).

## System

### Module map (authoritative doc per concern)

| Concern | Doc |
| --- | --- |
| Umbrella / routing | This file |
| Ingress, contacts, memory | `CS_Channels.md` |
| Per-platform connectors | `CS_Channel_Connectors.md` |
| Threads, messages, events | `CS_Conversations.md` |
| Inbox UX, views, assignment | `CS_Unified_Inbox.md` |
| Knowledge, embeddings, sources | `CS_Knowledge_Base.md` |
| AOPs, compile, versioning | `CS_Procedures.md` |
| AI product vision | `CS_AI_System.md` |
| Deployed pipeline & models | `CS_AI_Pipeline.md` |
| Workflows, auto-rules | `CS_Rules_Engine.md` |
| Action registry, marketplace/loyalty tools | `CS_Actions.md` |
| SLA, business hours | `CS_SLA.md` |
| Copilot, drafts, assist | `CS_Live_Assist.md` |
| Metrics, QA, supervisor | `CS_Analytics.md` |
| Brand, teams, roles, notifications | `CS_Platform_Features.md` |
| Twilio numbers | `CS_Phone_Number_Purchasing.md` |
| Voice calls, STT/TTS | `CS_Voice.md` |

### Data model (live `cs_*` tables — verified Postgres)

Grouped by owning doc; shared loyalty/admin tables (`merchant_credentials`, `admin_users`, `admin_teams`, `workflow_*`, `action_registry`) participate but are not CS-prefixed.

| Group | Tables |
| --- | --- |
| Contacts & memory | `cs_contacts`, `cs_platform_identities`, `cs_customer_memory` |
| Conversations | `cs_conversations`, `cs_messages`, `cs_conversation_events` |
| Tickets / SLA | `cs_tickets`, `cs_ticket_events`, `cs_sla_policies`, `cs_business_hours` |
| Knowledge | `cs_knowledge_sources`, `cs_knowledge_articles`, `cs_knowledge_embeddings` |
| Procedures | `cs_procedures` |
| Config & guardrails | `cs_merchant_config`, `cs_merchant_guardrails` |
| Telephony | `cs_phone_numbers`, `cs_voice_calls` |
| Agent notify | `cs_agent_push_subscriptions` |

**Phase-1 spec → deployed rename map**

| Retired spec name | Live |
| --- | --- |
| `cs_customers` | `cs_contacts` |
| `cs_channels` | `merchant_credentials` (`scope` includes `cs`) + `cs_conversations.credential_id` |
| `cs_teams` | `admin_teams` (CS team BFFs) |
| `cs_brand_config` | `cs_merchant_config` (+ `cs_merchant_guardrails` for rule rows) |
| `cs_agent_profiles` | Operational fields via admin/team/list BFFs (no standalone profile table in live DB) |
| `workflow_action_type_config` (CS actions) | `action_registry` + `action_caller_config` (`CS_Actions.md`) |

Column-level contracts: modular docs + `REGISTRY_SUPABASE.md` — not duplicated here.

### Functions (patterns)

- **Ingress API** — `cs_api_receive_message` (normalized receive from edges and internal callers).
- **BFF layer** — `cs_bff_*` for loyalty-admin (list/get/upsert conversations, knowledge, procedures, channels, teams, roles, analytics, voice).
- **Domain helpers** — `cs_fn_*` (resolve contact/conversation, insert message, SLA, rules evaluation, knowledge search, procedure state, memory extract, voice call lifecycle).
- **Loyalty admin menu** — `bff_get_analytics_menu` includes CS analytics entries where entitled.

Registry grep: `requirements/REGISTRY_SUPABASE.md` § CS (other), CS Channels, Conversations, Knowledge, Procedures, Voice.

### Flows

**Sync path (message in)** — Edge webhook (per `CS_Channel_Connectors.md`) → validate credential → `cs_api_receive_message` / handler chain → `cs_fn_resolve_contact` → `cs_fn_upsert_conversation` → `cs_fn_insert_message` → optional `cs_fn_evaluate_rules` (workflows) → enqueue AI processing.

**Async path (AI reply)** — Inngest / worker (`inngest-cs-serve` on Supabase Edge per `REGISTRY_RENDER.md`; pipeline stages in `CS_AI_Pipeline.md`) loads `cs_fn_load_merchant_ai_config`, retrieval, procedure, tools → draft → guardrails → outbound via `cs-send-message` / channel adapters.

**Human path** — Agent sends via `cs_bff_send_message`; outbound delivery trigger on `cs_messages` insert.

**Shared automation** — CS-domain rows on `workflow_master` (see `CS_Rules_Engine.md`) complement procedures; AMP marketing workflows remain a separate module.

### External services

- Supabase Edge: channel webhooks (`webhook-line`, marketplace chat edges), `cs-send-message`, `cs-loyalty-bridge`, `cs-phone-numbers`, `cs-web-push`, `inngest-cs-serve`.
- Render / workers: AI pipeline service referenced in `CS_AI_Pipeline.md` (orchestration detail there).
- Third-party: marketplace chat APIs, LINE, Twilio (SMS/voice), ElevenLabs (voice — `CS_Voice.md`).

### Known gaps

- Retired **Phase-1 DDL** (13-table monolith with `cs_channels` / `cs_customers`) remains in git history only — do not treat as migration source.
- **Product vision doc** (`CS_AI_System.md` technical tail) may describe tables or stages not yet deployed — `CS_AI_Pipeline.md` wins for runtime.
- **Ticket vs conversation** — Both `cs_tickets` and `cs_conversations` exist; unified inbox product rules in `CS_Unified_Inbox.md`.
- Registry/README may lag new BFFs — verify signatures via Supabase MCP before citing args in feature docs.

## Related

- **CS_Conversations.md** — Message model, statuses, events.
- **CS_Unified_Inbox.md** — Agent queue and assignment UX.
- **CS_AI_Pipeline.md** — Deployed AI stages (over `CS_AI_System.md` vision).
- **CS_Channels.md** — Credentials, contacts, memory.
- **Marketplace.md** — Order scope vs CS IM credential scope on shared marketplace tables.
- **domains/_index.md** — Keyword routing to all CS docs.
