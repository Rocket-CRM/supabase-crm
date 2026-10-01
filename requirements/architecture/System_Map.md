# System Map

Where Rocket CRM loyalty + CS code runs, which repo owns it, and how writers should look things up. Routing reference only — signatures and schemas live in registries and live Supabase.

Owner surfaces: (meta) loyalty-admin, loyalty-user, Shopify, LINE, Open API, CS agent desk

## Repos and what each owns

| Repo | Owns |
| --- | --- |
| **supabase-crm** | Postgres schema, RPCs (`bff_*`, `api_*`, `fn_*`, triggers), Supabase Edge Functions, canonical `requirements/**`, registries, migration/deploy source of truth for DB. |
| **loyalty-admin** | Merchant admin UI (Polaris): configuration, reporting, operational tools. Calls `bff_*` with admin JWT. |
| **loyalty-user** | Member-facing web app, LINE LIFF surfaces, and the **online store** `/store`: our custom Shopify storefront on the Shopify Admin API (spec `loyalty-user/docs/ONLINE_STORE.md`). Calls member `bff_*` and edge proxies. Does not host the Shopify plugin's widget or extensions. |
| **rewarding-shopify** | **Shopify plugin** (the Shopify app): OAuth / install and access scopes, embedded admin shell, theme app extension / storefront widget on the merchant's own theme, checkout / discount / customer-account / admin extensions, billing hooks, storefront session bridge, Shopify Admin API calls that are not in Postgres. Spec `Shopify.md`. |
| **crm-event-processors** | Long-running Node on Render: outbox → Inngest publisher, integration outbox consumers (webhook, Klaviyo), optional legacy Kafka consumer code, scheduled jobs (expiry, loyalty cache). |
| **amp-ai-service** | Inngest-driven AMP analysis / recommendation workers (marketing agent jobs). |
| **messaging-service** | LINE (and related) message send/delivery helpers used by notifications and CS paths. |
| **cs-ai-service** | CS AI pipeline workers (classification, suggestions) when not inline in edge/RPC. |
| **futurepark-upload-receipt** | FuturePark receipt upload + OCR handoff service (client-specific). |
| **crm-knowledge** | CRM Knowledge MCP server: chunks `requirements/**`, `search_docs` / `get_section` for agents. |
| **rocket-agent-plugins** | Cursor eng/sales plugins, commercial copy views — orchestration only; product truth stays in **supabase-crm** docs. |

Sibling clones typically live under `~/Documents/rocket/`. Cross-check deployed Render services in `requirements/REGISTRY_RENDER.md` § Render Services.

## Runtime tiers

| Tier | What it is | When it runs | Where to discover |
| --- | --- | --- | --- |
| **Postgres RPC** | `bff_*` (admin/member UI), `api_*` (external integrators), `fn_*` (internal), `trigger_*` (row hooks) | Synchronous request/transaction path | `REGISTRY_SUPABASE.md` grep → Supabase MCP `pg_proc` |
| **Supabase Edge Functions** | Deno HTTP handlers: webhooks, lightweight external APIs, embedding jobs, auth bridges | On HTTP invoke or scheduled edge cron | `REGISTRY_RENDER.md` `E:` lines; `list_edge_functions` |
| **Render web services** | Always-on Node (consumers, MCP, Shopify app, AI workers) | Process loops, Inngest serve, Kafka subscribe | `REGISTRY_RENDER.md` `R:` lines |
| **Render cron jobs** | One-shot containers on a schedule (expiry batch, cache refresh) | Cron expression UTC | `REGISTRY_RENDER.md` `C:` / `R:` lines |
| **pg_cron** | Jobs inside Postgres (housekeeping, refreshes, small SQL) | Cron in DB | `REGISTRY_RENDER.md` § Operational pg_cron |
| **PGMQ** | Postgres-backed queues for async handoff | Worker polls / notifies | `REGISTRY_RENDER.md` `Q:` lines |
| **Inngest** | Durable workflows (delayed awards, AMP, some integrations) | Event → function steps | Domain doc System § Flows + `REGISTRY_RENDER.md` Inngest section |
| **Chokepoint outbox → Inngest / integrations** | Domain events after canonical writes | Same transaction as ledger; async drain on Render | `CRM_Event_Driven_Architecture.md`, `crm-event-processors` |

**Rule of thumb:** UI and integrators call **RPC or edge**; heavy fan-out and retries belong in **Inngest, Render consumers, or queues** — not new logic in triggers unless the plan says otherwise.

## Surfaces

| Surface | User | Rendered by | Backend entry |
| --- | --- | --- | --- |
| **Loyalty admin** | Merchant staff | loyalty-admin | Admin JWT → `bff_*` |
| **Member web app** | End customer | loyalty-user | Member session → `bff_*` / edge |
| **LINE** | End customer | loyalty-user (LIFF) + messaging-service | LINE webhooks, notification delivery |
| **Shopify plugin on the merchant's theme** | Shopper on the merchant's own Shopify store | rewarding-shopify widget + theme / checkout / customer-account extensions | `rewarding-shopify`, member session edge, domain doc `### Shopify` deltas |
| **Online store (custom Shopify storefront)** | Shopper on our frontend | loyalty-user `/store` | Shopify Admin GraphQL with the plugin app's token; pays on Shopify-hosted checkout; spec `loyalty-user/docs/ONLINE_STORE.md` |
| **Shopify embedded admin** | Merchant in Shopify Admin | rewarding-shopify + loyalty-admin embed | Shopify session + entitlements |
| **Open API** | Partner systems | — | `api_*` + API keys (`Open_API.md`) |
| **Front Line / store staff** | Staff at counter | loyalty-admin (limited) | Frontline BFFs (`Frontline_Admin_Actions.md`) |
| **CS agent desk** | Support agents | CS admin UI (separate app paths) | `cs_*` RPCs, channels, AI pipeline |

Platform-wide Shopify plumbing (OAuth, billing, webhook receiver, routing table) stays in `requirements/Shopify.md`. Feature-specific Shopify behaviour is documented under each domain’s `### Shopify` subsection.

The online store (`/store`) is a different domain from the plugin. Its spec is `loyalty-user/docs/ONLINE_STORE.md`, not `Shopify.md`. It runs on the plugin's shop install, access scopes, and `orders/paid` earn webhook, so a store feature that needs a new Shopify permission is also a plugin change.

## Auth contexts

| Context | Who | How resolved | Conventions |
| --- | --- | --- | --- |
| **Merchant admin** | Logged-in merchant user | Admin JWT → `get_current_merchant_id()` chain | `.cursor/rules/11-auth-conventions.mdc` |
| **Member** | Loyalty end user | Member session JWT (incl. Shopify-issued shared module) | `Authentication.md`, `Signup_Login.md` |
| **API key / partner** | Server-to-server | Key → merchant scope on `api_*` | `Open_API.md` |
| **Service role** | Workers, reconcile, cron | Supabase service key — never in browser | Edge/Render env only |
| **Superadmin** | Rocket operators | Elevated admin paths | `Superadmin_Functions.md` |

When writing Journeys, name the **auth context** implicitly via which surface/repo is acting — do not document JWT shapes in domain docs (System may name the RPC that enforces auth).

## Read order for writers

1. **Registry grep** — `REGISTRY_SUPABASE.md` / `REGISTRY_RENDER.md` for the function, table, edge fn, or service name.
2. **CRM Knowledge** — `search_docs` on the feature question; `get_section(path, "Journeys > Shopify")` when you know the spine subsection (`H2 > H3`).
3. **Live Supabase** — `information_schema` + `pg_proc` signatures to confirm columns and args (docs can lag).
4. **App repo** — loyalty-admin / loyalty-user / rewarding-shopify for page names, visible states, and BFF call sites (Journeys truth).
5. **This map** — when the question is “which repo or tier,” not “what is the business rule.”

Closeout after behaviour changes: `.cursor/rules/06-update-docs.mdc` and `.cursor/rules/13-requirements-writing.mdc`.

## Related

- Event topology — `requirements/CRM_Event_Driven_Architecture.md`
- BFF naming — `requirements/BFF_Conventions.md`
- Shopify hub — `requirements/Shopify.md`
- Domain index — `requirements/domains/_index.md`
