# CS Actions

Registered **tools** the AI and agents may invoke: marketplace APIs, loyalty bridge writes, and custom HTTP actions — governed per merchant via action registry and caller config.

Owner surfaces: loyalty-admin action settings, `cs-ai-service` `/mcp`, Edge `cs-loyalty-bridge`

## Concept

**Action registry** — Platform catalog of operations, schemas, risk class (`action_registry`).

**Caller config** — Per-merchant enablement and limits (`action_caller_config`, `cs_fn_load_action_config`, `cs_fn_seed_action_config`).

**DATA vs ACTION tool** — Read-only lookups vs mutating marketplace/loyalty operations — voice graph prefetches DATA tools in code.

**Loyalty bridge** — Points/tags/personas via CRM MCP / chokepoints — same audit path as AMP.

## Rules

- **Disabled actions** never appear on MCP even if in global registry.
- **Loyalty writes** must use bridge (`chokepoint_post_wallet_transaction`, `fn_execute_amp_action`) — no direct wallet SQL from CS.
- **Platform vouchers** (Shopee/Lazada/TikTok shop promos) use marketplace APIs — **not** CRM voucher templates.
- **Loyalty vouchers/points** use CRM bridge — visible in loyalty analytics immediately.
- **High-risk actions** (large refund, account changes) require supervisor/confirmation per brand config and procedure steps.
- **Custom API builder, computer-use browser automation** — vision only; not deployed.

## Journeys

### Admin journey

| Knob | Effect |
| --- | --- |
| Enable action in caller config | Exposes MCP tool to AI |
| Marketplace credentials | Prerequisite for order/refund tools |
| Procedure `@` references | Which tools each AOP may call |

| Page | Owning repo | BFF / RPC |
| --- | --- | --- |
| CS actions / brand config | loyalty-admin | `cs_bff_get_available_actions`, upsert via brand/action BFFs |

1. Connect marketplace CS credentials (`CS_Channels.md`).
2. Seed or enable default action set for merchant.
3. Tighten allowlist before full autonomous AI.

### Agent journey

1. AI or procedure step proposes tool execution.
2. Agent confirms when policy requires; result logged on `cs_conversation_events` (`action_executed`).
3. Member sees outcome in channel (refund status, voucher message, etc.).

## System

### Data model

`action_registry`, `action_caller_config`; legacy name `workflow_action_type_config` retired.

### MCP (cs-ai-service)

Representative tools: `lookup_order`, `search_knowledge`, `process_refund`, `create_ticket`, `escalate_to_human`, `close_conversation`; loyalty tools proxy to **amp-ai-service** MCP (`award_points`, `assign_tag`, `assign_persona`).

Edge **`cs-loyalty-bridge`** for HTTP bridge patterns where MCP is not used.

### Marketplace capability (by maturity)

Order lookup, cancel, refund flows, voucher/card sends vary by connector — matrix in **`CS_Channel_Connectors.md`**. Shopify-specific bridges only when merchant on Shopify stack — no duplicate Shopify reference MD in this doc.

### Known gaps

- Custom API action builder, computer-use agent, full approval workflow UI — product spec only.
- Tool list must be verified in `cs-ai-service` repo `/mcp` manifest on each release.

## Related

- **CS_Procedures.md** — `@Tool Name` in AOPs.
- **CS_AI_Pipeline.md** — AgentKit and graph executor invocation.
- **CS_Channel_Connectors.md** — Platform API availability.
- **Action_Macro.md** — Human multi-step macros (loyalty module).
