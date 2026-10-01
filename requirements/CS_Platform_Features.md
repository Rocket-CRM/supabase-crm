# CS Platform Features

Cross-cutting CS product: **live** agent Web Push and team/role surfaces; **roadmap** simulator, public portal, proactive outbound, multi-tenant admin extras.

Owner surfaces: loyalty-admin CS settings, **CS Inbox** PWA, **CS Teams**, **CS Roles**, **CS Brand Config**

## Concept

**Agent notification** — Browser Notification API + Web Push when assigned or inbound on owned conversations.

**Team / role** — CS routing groups on `admin_teams`; CS RBAC via `cs_bff_*` role BFFs.

**Brand config** — Voice, models, outbound limits on `cs_merchant_config` (+ guardrail rows).

**Simulator / portal / outbound campaigns** — Product vision `(not deployed as described below)`.

## Rules

- **Web Push** — Standalone **CS Inbox** (`/cs-inbox`), not Shopify embedded iframe; auth via `cs_web_push_secret` on `cs-web-push` edge.
- **Triggers (v1)** — Conversation assigned to agent; inbound **contact** message on chat assigned to agent.
- **Member LINE/marketing pushes** — **`Notification_Service.md`** (loyalty) — different product.
- Simulator/outbound must respect consent and frequency caps when built.
- Verify each narrative feature against registry before implementation — this doc is not a schema contract.

## Journeys

### Admin journey

| Knob | Effect |
| --- | --- |
| Allow notifications | Browser permission + `cs_bff_upsert_push_subscription` |
| Teams / roles | Routing and page access |
| Brand config | Voice, AI defaults |

| Page | Owning repo | RPC |
| --- | --- | --- |
| **CS Inbox** | loyalty-admin | Push registration in `register-inbox-push.ts` |
| **CS Teams** | loyalty-admin | `cs_bff_list_teams`, `cs_bff_upsert_team`, … |
| **CS Roles** | loyalty-admin | `cs_bff_list_roles`, `cs_bff_upsert_role`, … |
| **CS Brand Config** | loyalty-admin | `cs_bff_get_brand_config`, `cs_bff_upsert_brand_config`, guardrail BFFs |

1. Configure teams and CS roles.
2. Set brand voice and guardrails.
3. Open **CS Inbox** → allow notifications / install PWA for push.
4. Use simulator or outbound when shipped.

### Member journey

Reactive chat today; public help center and proactive broadcasts `(roadmap)`.

## System

### Shipped

| Artifact | Role |
| --- | --- |
| `cs_agent_push_subscriptions` | Stored push endpoints per admin user |
| Edge `cs-web-push` | Delivers push on assign/inbound (`REGISTRY_RENDER.md`) |
| `cs_merchant_config` / `cs_merchant_guardrails` | Brand + rule rows |
| `admin_teams` + CS team BFFs | Routing groups |
| CS role BFFs | RBAC for CS pages |

### Roadmap (legacy §8–10 folded — not verified)

- Agent/voice simulator and regression test suites.
- A/B procedure experiments.
- Slack/Teams/LINE Notify supervisor alerts.
- Public KB site, customer portal, embeddable web forms with deflection.
- Proactive broadcast and outbound voice campaigns.
- Enterprise SSO, SOC2, on-prem narratives.

### Known gaps

Most §8–10 content from original plan remains **aspirational** — only push + teams/roles/brand config align with live admin routes and registry.

## Related

- **CS_Feature_Spec.md** — Module map.
- **CS_Unified_Inbox.md** — Where push attaches.
- **CS_AI_Pipeline.md** — Model/voice config consumption.
- **Notification_Service.md** — Member notifications (loyalty).
