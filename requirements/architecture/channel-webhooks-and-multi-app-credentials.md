# Channel Webhooks & Multi-App Credentials

> Established 2026-06-12 with the Lazada CS chat integration. Governs how platform webhooks, OAuth token lifecycles, and outbound delivery are structured when one platform serves multiple modules (orders vs CS chat) through multiple Open Platform apps.

## Core principle — share downstream engines by domain, share upstream utilities by transport

Webhook traffic is split on two axes:

- **Upstream (transport)** is per **(platform, app)**: each Open Platform app has its own callback URL and signing secret, so each gets a thin endpoint adapter (~50–150 lines). Never funnel two apps through one URL by trial-signing multiple secrets.
- **Downstream (domain engine)** is shared per **event domain**, regardless of platform:

| Domain engine | Contract | Used by |
|---|---|---|
| Order ingest (`marketplace-ingest` lib) | normalize → Kafka `marketplace.orders` / Inngest `marketplace/order-received` | `webhook-marketplace-{tiktok,shopee,lazada}` |
| CS chat ingest (`cs-ingest` lib) | `cs_api_receive_message` RPC → Inngest `cs/message.received` (non-blocking) | `webhook-lazada-cs` (canonical); `webhook-doopage-cs` (Shopee via DooPage); `webhook-line` (inlines same contract, migration candidate) |
| LINE webhook fan-out | pass-through raw LINE body + `x-line-signature` after HMAC | `webhook-line` (`fanOutLineWebhook`; `credentials.webhook_fanout_destinations` on `line_messaging`) |
| Custom webhook proxy | filter → transform → forward | `custom_webhook_*` fns (see `requirements/Custom_Webhooks.md`) |

Shared transport utilities (bundled as `lib/` files in each edge fn): platform signature verification (parametrized by key/secret — e.g. `lazada-signature.ts`), `log-event.ts` (`custom_webhook_events` audit row per request), fast-2xx discipline (Lazada requires 2xx within ~500ms; after signature passes, processing failures are logged and still answered 200).

An adapter owns only: signature verification, payload filtering (e.g. buyer messages only), and field mapping. It owns no destination logic — except LINE webhook fan-out, because the platform allows only one callback URL, so copies must leave `webhook-line` after HMAC.

## Multi-app credential model (`merchant_credentials`)

One platform may have several Open Platform apps ("plays"). All share `service_name`; rows are discriminated by `scope text[]`:

| App | `service_name` | `scope` | Signed with |
|---|---|---|---|
| Lazada order app 117176 | `lazada` | `NULL` (legacy shape) | `LAZADA_APP_KEY/SECRET` |
| Lazada CS IM app 137891 | `lazada` | `{cs}` | `LAZADA_CS_APP_KEY/SECRET` |

Rules:

- `credentials.app_key` is stored in the jsonb at token exchange and is the **routing key** for every later signing decision (refresh, outbound send).
- Any query on a multi-app `service_name` MUST filter scope (`contains('scope', ['cs'])` for CS rows, `scope IS NULL` for order rows). Unfiltered `(merchant_id, service_name, environment)` lookups collide.
- Webhook credential resolution: `external_id` (seller/shop id from the push) + scope filter + `is_active`.

## Token lifecycle — one function per platform, routed by app profile

- **Exchange**: `marketplace-lazada-exchange-token` takes `app: 'order' | 'cs'` (default `order`), resolving the env key pair and scope shape from an `APP_PROFILES` registry. Extend the registry for a new app; do not clone the function.
- **Refresh**: `marketplace-token-refresh` (hourly cron) resolves the signing secret per row via `credentials.app_key` → env map. Deactivation policy: `is_active = false` **only on explicit platform rejection** of the token (`permanent: true`); transient failures (network, rate limit, missing/unknown env config) keep the row active and retry next run. A config gap must never kill a live credential.

## Outbound delivery — messaging-service adapter registry

Exception: DooPage `send_message` uses Browser SDK (`cs-send-message` → `delivery.mode=browser_sdk` / `doopage-cs-sign-send`), not the `/send` adapter registry.

Render `messaging-service` (`Rocket-CRM/messaging-service`, `messaging-service-li40.onrender.com`) is the single outbound engine: `POST /send` → adapter registry (`LINE`, `SMS`, `EMAIL`, `LAZADA`) + recipient resolution.

- **Session-addressed platforms** (Lazada IM): replies target the platform conversation, not a user id — recipient resolves to `cs_conversations.platform_conversation_id` (the IM `session_id` written by the inbound webhook). Only `conversation_id`-based sends are possible. Registered in `SESSION_ADDRESSED_PLATFORMS` in `resolve-recipient.ts`.
- App-level secrets (e.g. `LAZADA_CS_APP_KEY/SECRET`) live in Render env; per-merchant tokens come from `merchant_credentials` at send time (scope-filtered for multi-app platforms).

## Adding a new chat channel (checklist)

1. New seller authorization → extend the platform's exchange function `APP_PROFILES` (or create one per this shape if the platform is new). Pick the scope shape.
2. Inbound → new `webhook-<platform>-cs` edge fn: signature lib (parametrized) + filter + mapping → `cs-ingest` lib. Log to `custom_webhook_events`.
3. Refresh → add the env pair to the platform's secret map if the platform has refresh tokens.
4. Outbound → new adapter in `messaging-service` + registry entry + recipient resolution (session-addressed or identity-addressed); add the `service_name` → channel mapping in `cs-send-message`'s `CHANNEL_MAP`.
5. Registries: `REGISTRY_RENDER.md` `E:`/`R:` lines; domain detail in `CS_Channels.md`.

## Known debt

- `webhook-line` predates `cs-ingest` and inlines the contract — migrate when next touched.
- `webhook-shopee` retired (HTTP 410); Shopee CS chat is `webhook-doopage-cs` → `cs-ingest` (DooPage transport).
- `cs-ingest` lib is currently bundled inside `webhook-lazada-cs`; copies in future webhook fns must stay byte-identical until a shared deploy mechanism exists (same convention as `marketplace-webhook/lib/`).
