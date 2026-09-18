# Notification Service

Per-merchant, per-channel (LINE Flex + Email) messages when loyalty domain events fire, plus scheduled **expiry reminders** on a separate clock path (no outbox / Inngest).

Owner surfaces: loyalty-admin (`/settings/notifications`), Shopify embedded admin (Email-only customer notifications), members (receive only)

## Concept

The notification service tells members what happened in the loyalty program on the channels they opted into. Merchants configure which **catalog events** fire on LINE and/or Email, edit templates, and set when **expiry reminders** run. Members do not configure notifications; they receive pushes or emails when rules pass.

**Notification (event-driven)** — Something happened in the ledger (purchase completed, points earned, tier change, etc.). A chokepoint outbox row is published to Inngest; a thin **notification router** maps the payload to `(event_key, sub_event)` and runs the shared delivery engine → `notification_log`.

**Reminder (clock scan)** — No domain event: a cron asks “who has points or rewards expiring soon?” using finder RPCs, then uses the **same** resolver/render/send engine. Discovery never shares code with event routers (no cross-leak).

**Catalog event** — Canonical `(event_key, sub_event)` in `notification_event_catalog` with system defaults, available merge fields, and per-channel default on/off. Merchants override enablement, selected fields, and templates in settings.

**Template** — LINE: Flex JSON with `${placeholders}` and `_field` visibility markers. Email: structured `email_template` (subject, title, body, button, banner) plus optional **appearance** (from-name, logo, colors).

**Channel** — `line` (Messaging API push; requires `line_id` + `channel_line`) or `email` (requires member email; sends via Render **messaging-service**, `no-reply@rocket.in.th`). SMS column exists in schema; no sender yet.

**Delivery engine** — Resolve (`fn_resolve_notification_for_event`) → enrich (`detail_url`, `hero_image_url`, reward/tier names) → render Flex or HTML → push/send → log. Implemented in Node (`crm-event-processors/src/notification/deliver-notification.ts`) for reminders and in Deno (`inngest-event-router-serve` `processNotification`) for event routers — kept in parity by hand.

**Cross-module messaging** — AMP workflows and CS outbound use `messaging-service` `POST /send` with different auth and audit tables. Loyalty notifications still call LINE push directly (optional `MESSAGING_SERVICE_URL` proxy) after resolve; consolidation to `/send` with `source: notification` is planned.

## Rules

- **Send gate (per channel)** — A message is sent only when: catalog row exists and is active; merchant has enabled the event for that channel (override or catalog default); member exists; channel prerequisites pass (`line_id` + `channel_line` for LINE, email present for Email); active template exists (merchant override beats system default); merchant LINE messaging token present when channel is LINE; idempotency allows send. Otherwise the engine returns `should_send: false` with a `skip_reason` (see System). Terminal skips `DISABLED`, `NO_CATALOG`, and `ALREADY_SENT` are not written to `notification_log` (high-volume silence).
- **Notifications vs reminders** — Event routers never call expiry finders; the expiry cron never reads chokepoint topics. Both may call the same resolver with different `source_event_id` shapes (event id vs deterministic expiry key).
- **Idempotency** — Inngest router `idempotency` keys (24h) + resolver `ALREADY_SENT` on prior `notification_log.status = sent` + unique `(merchant_id, event_key, sub_event, source_event_id, channel)`.
- **Retries** — Inngest notification routers use step retries (e.g. 3). Transient resolver/LINE 5xx/network throws so Inngest retries. LINE 429 logs `LINE_RATE_LIMITED` without throw. User blocked bot logs failure and posts `chokepoint_post_user_event` to set `channel_line = false` (no direct user UPDATE). Reminder cron: transient failure leaves merchant unmarked so the next 15-minute tick retries; `ALREADY_SENT` dedups within a run.
- **Wallet earn mapping** — Only `transaction_type = earn` and `component = base` maps to `currency.earned`. Bonus, adjustment, and reversal earns do not notify.
- **Ticket unit coalesce (LINE wallet only)** — Multi-unit ticket earns emit N wallet chokepoint events; the wallet notification router sends one LINE message per award call (`unit_index === 1`, display amount from `unit_total` when present). Points without `unit_*` unchanged.
- **Purchase timing** — `purchase.created` can notify (catalog default ON for LINE and Email). Syngenta-style pending orders do not use `completed` until the order actually completes (typically after line-item completion). `promo_applied` and other verbs do not map.
- **Referral notifications** — Catalog includes `referral.completed`, `referral.friend_rewarded` (from `crm.events.referral` settled/claimed semantics) and `referral.shared` (Email default ON, LINE off; **catalog-only** until share-via-email UI exists — no router maps `action.referral_share`). Klaviyo uses different metric names (`referral.friend_claimed`, `referral.completed`) on the integration path — see `Outbound_Integrations.md` / reference MD Part 1; do not confuse with notification `(event_key, sub_event)` pairs.
- **Email test send** — Admins may send a draft to one address; rate limit five per merchant per ten minutes; does not create a normal notification log row.
- **Resolver security** — `fn_resolve_notification_for_event` is `service_role` only (returns LINE channel access token). Never grant to `anon` / `authenticated`.

## Journeys

### Admin journey

| Page | Owning repo | BFF / RPC |
| --- | --- | --- |
| Notifications | loyalty-admin | `bff_get_notification_settings`, `bff_upsert_notification_settings` |
| Email template editor (per event) | loyalty-admin | `bff_upsert_notification_settings` (rows + optional `p_appearance`), `sendTestNotificationEmail` (server action) |
| Shopify Customer notifications | loyalty-admin (embedded) | Same BFFs; Email-only subset |

| Setting | Effect on behaviour |
| --- | --- |
| Per-event channel toggle | LINE and/or Email per catalog row (`merchant_notification_settings.channel`) |
| Selected fields (LINE) | Subset of `available_fields`; drives `_field` rows in Flex |
| Template mode | System default vs merchant custom Flex / HTML |
| Email appearance | From-name, logo, colors (`merchant_notification_appearance`; falls back to display settings) |
| Expiry reminder schedule | `run_local_time` + `timezone` on `merchant_expiry_reminder_settings` (default 09:00 Asia/Bangkok) |
| Enable `currency.expiring_soon` / `redemption.expiring_soon` | Gates reminder cron per channel (not wallet/redemption expire events) |

1. Open **Settings → Notifications** (tabs: All, LINE, Email).
2. Configure **expiry reminder** schedule above the tabs (applies to reminder catalog rows).
3. On **All** or a channel tab, enable events and adjust LINE field selection or open the Email editor for an event.
4. For Email, use the full-page editor: left column for enablement, system/custom mode, banner, copy, variables; right column sticky preview; optional test send to one address.
5. Save — `bff_upsert_notification_settings` validates known events and `selected_fields ⊆ available_fields`.

Common pitfalls: enabling reminders without enabling `expiring_soon` rows; expecting adjustment earns to notify; Syngenta orders notifying on `created` vs `completed` by design; Shopify embed hides receipt / purchase-item / package events but keeps referral Email rows.

### Member journey

| Surface | Owning repo | Behaviour |
| --- | --- | --- |
| LINE OA | loyalty-user / LINE client | Flex push when event enabled and `channel_line` true |
| Email inbox | messaging-service | Branded HTML when event enabled and email on file |

1. Member completes an in-program action (purchase, earn, redeem, tier change, signup, referral settlement, etc.).
2. If the merchant enabled the matching catalog event for the member’s channel and prerequisites pass, the member receives one message (or none — no member-facing error surface).
3. Expiry reminders arrive on the merchant’s scheduled local time when `expiring_soon` is enabled for that channel.

### Shopify

Embedded **Customer notifications** is Email-only (no LINE/Email channel switcher). Receipt upload, purchase line-item, and package-grant events are hidden from the list. Global appearance and expiry schedule sit above the event list. Referral rows remain visible (`referral.completed`, `referral.friend_rewarded`, Invite a friend / `referral.shared` Email-only). Platform plumbing stays in `Shopify.md`.

## System

### Data model

| Table | Role |
| --- | --- |
| `notification_event_catalog` | System-owned catalog: `event_key`, `sub_event`, `source_topic`, `available_fields`, `default_selected_fields`, `default_enabled`, `default_enabled_email` |
| `merchant_notification_settings` | Per `(merchant_id, event_key, sub_event, channel)` — `enabled`, `selected_fields` |
| `notification_template` | `flex_template` (LINE) and/or `email_template` jsonb; `merchant_id` NULL = system default |
| `merchant_notification_appearance` | Email branding overrides |
| `notification_log` | Append-only audit: `status` (`sent` \| `failed` \| `skipped`), `skip_reason`, unique per `(merchant_id, event_key, sub_event, source_event_id, channel)` |
| `merchant_expiry_reminder_settings` | Reminder clock: `run_local_time`, `timezone`, `last_ran_local_date` |
| `chokepoint_event_outbox` | Upstream event source for notifications (not for reminders) |

RLS: merchant isolation on tenant tables; catalog is system read.

### Functions

| Function | Role |
| --- | --- |
| `bff_get_notification_settings()` | Admin JWT — catalog grid merged with merchant overrides (+ appearance load path in app) |
| `bff_upsert_notification_settings(p_rows, p_language, p_appearance)` | Admin JWT — upsert settings; validate events and fields |
| `fn_resolve_notification_for_event(..., p_channel default 'line')` | **service_role** — single-roundtrip send/skip verdict + template + token |
| `fn_validate_notification_flex_template` | Admin-side Flex validation |
| `fn_notification_template_field_allowlist` / `fn_extract_notification_template_field_refs` | Field picker and template ref extraction |
| `fn_list_due_expiry_reminder_merchants(p_channel)` | Reminder gate (enabled events + local time + not ran today) |
| `fn_find_points_expiring_soon` / `fn_find_rewards_expiring_soon` | Reminder candidate rows (keyset 200) |
| `fn_mark_expiry_reminder_ran` | After successful merchant reminder pass |

Resolver skip reasons (representative): `INVALID_INPUT`, `NO_CATALOG`, `DISABLED`, `NO_USER`, `USER_NOT_FOUND`, `NO_LINE_ID`, `USER_CHANNEL_OFF`, `ALREADY_SENT`, `NO_TEMPLATE`, `NO_MERCHANT_TOKEN`, `ERROR`.

### Flows

**Event-driven (live path)**

```
Chokepoint writers → chokepoint_event_outbox
  → OutboxPublisher (crm-event-processors, OUTBOX_PUBLISHER_ENABLED, Inngest mode)
  → inngest-event-router-serve: notification-{purchase,purchase-item,wallet,tier,user,redemption,receipt}-router
  → processNotification (Deno) — same steps as deliver-notification.ts
  → notification_log
```

**Retired:** Kafka `NotificationConsumer` on `crm-event-processors` (`NOTIFICATION_CONSUMER_ENABLED`, `KAFKA_CONSUMERS_ENABLED`) — Confluent deactivated 2026-07-07; class retained for deletion with other Kafka consumers. Do not treat `REGISTRY_RENDER.md` prose that lists NotificationConsumer as the active notification path as current; reminders still use the same Render image via `expiry-reminder-batch` only.

**Reminders**

```
Render Cron expiry-reminder-batch (*/15 min)
  → fn_list_due_expiry_reminder_merchants
  → per merchant serial: finders → deliverNotification (Node) chunks of 50
  → fn_mark_expiry_reminder_ran (skipped on transient error)
```

Lead days: system default 7 (points) / 3 (rewards) on `merchant_expiry_reminder_settings` — not merchant-editable in UI v1. `currency.expiring_soon` / `redemption.expiring_soon` use `source_topic = crm.jobs.expiry_reminder` in catalog; they are **not** mapped from wallet `expire` or redemption `entitlement_expired` events.

### Router mapping (Inngest)

Publish topic `crm.events.*` → Inngest `crm/<domain>.event`. Only mapped rows reach the resolver.

| Source | Condition | Maps to | `source_event_id` |
| --- | --- | --- | --- |
| `crm.events.purchase` | `event` ∈ created, completed, cancelled, refunded | `purchase.<event>` | `purchase_id` |
| `crm.events.purchase_item` | item completed verbs | `purchase_item.completed` | `item_id` |
| `crm.events.wallet` | earn+base / burn / expire | `currency.*` | `wallet_ledger_id` (unit 1 when ticket expand) |
| `crm.events.tier_change` | change_type | `tier.<change_type>` | `tier_change_ledger_id` |
| `crm.events.user` | `event = create`, `skip_cdc` false | `signup.signup` | `user_id` |
| `crm.events.redemption` | issued, used, cancelled, entitlement_*, package_entitlement_created | `redemption.*` | `redemption_id` |
| `crm.events.receipt` | submitted, rejected | `receipt.<event>` | `receipt_upload_id` |
| `crm.events.referral` | settled referrer → completed; settled/claimed friend → friend_rewarded | `referral.*` | `referral_ledger_id` or `claim_id` |

Dropped at router (examples): redemption `unmarked_used`, `entitlement_use_reversed`, `entitlement_total_adjusted`; referral `applied`, `clawed_back`. `referral.shared` is not on `crm.events.referral`.

**Referral router gap (verified 2026-09-17):** DB catalog and `chokepoint_post_referral_event` are live. Mapping above matches `.cursor/deploy/inngest-event-router-serve` `notification-referral-router`, but **`supabase/functions/inngest-event-router-serve` does not yet register that router** — referral LINE/Email will not fire on the Inngest path until the deploy artifact is merged into the edge function source and redeployed. Retired `NotificationConsumer` also does not subscribe to `crm.events.referral`.

### Event catalog (live defaults)

Verified via Supabase `notification_event_catalog` (2026-09-17). `default_enabled` = LINE unless noted; Email column = `default_enabled_email`.

| event_key | sub_event | source_topic | LINE | Email |
| --- | --- | --- | --- | --- |
| purchase | created | crm.events.purchase | ON | ON |
| purchase | completed | crm.events.purchase | ON | OFF |
| purchase | cancelled | crm.events.purchase | OFF | OFF |
| purchase | refunded | crm.events.purchase | ON | OFF |
| purchase_item | completed | crm.events.purchase_item | ON | OFF |
| currency | earned | crm.events.wallet | ON | OFF |
| currency | burned | crm.events.wallet | OFF | OFF |
| currency | expired | crm.events.wallet | OFF | OFF |
| currency | expiring_soon | crm.jobs.expiry_reminder | OFF | OFF |
| tier | upgrade | crm.events.tier_change | OFF | ON |
| tier | initial | crm.events.tier_change | ON | OFF |
| tier | downgrade | crm.events.tier_change | OFF | OFF |
| signup | signup | crm.events.user | ON | OFF |
| redemption | issued | crm.events.redemption | ON | ON |
| redemption | used | crm.events.redemption | ON | OFF |
| redemption | cancelled | crm.events.redemption | OFF | OFF |
| redemption | entitlement_used | crm.events.redemption | ON | OFF |
| redemption | entitlement_expired | crm.events.redemption | ON | OFF |
| redemption | package_granted | crm.events.redemption | OFF | OFF |
| redemption | expiring_soon | crm.jobs.expiry_reminder | OFF | OFF |
| receipt | submitted | crm.events.receipt | ON | OFF |
| receipt | rejected | crm.events.receipt | ON | OFF |
| referral | completed | crm.events.referral | ON | OFF |
| referral | friend_rewarded | crm.events.referral | ON | OFF |
| referral | shared | action.referral_share | OFF | ON |

System Flex templates (v2): hero image block, footer URI button (`detail_url`), enriched fields — seeded/migrated via `notification_flex_v2*` migrations.

### Flex templates

Stored in `notification_template.flex_template`:

1. **`_field` markers** — Object shown only when field name ∈ merchant `selected_fields`.
2. **`${field_name}`** — Substituted from chokepoint payload plus router enrichments (`reward_name`, `tier_name`, `detail_url`, `hero_image_url`).

If a selected `_field` row still has unresolved placeholders after enrichment, drop the entire row (never ship partial Flex). Merchant template row wins over system (`ORDER BY merchant_id NULLS LAST LIMIT 1`). Admin custom Flex overrides exist in schema; authoring UI for merchant overrides is still limited (system/custom toggle on Email; LINE picker-driven defaults).

### External services

| Service | Role |
| --- | --- |
| `inngest-event-router-serve` | Hosts notification routers; concurrency limit 5 per router id |
| `crm-event-processors` | OutboxPublisher; `expiry-reminder-batch` job |
| LINE Messaging API | Push (`LINE_PUSH_URL` or default); optional `MESSAGING_SERVICE_URL` proxy |
| `messaging-service` | Email send (`no-reply@rocket.in.th`); planned unified `/send` for notifications |
| Inngest | Step retry, idempotency window |

Env (notifications): `OUTBOX_PUBLISHER_ENABLED=true`; legacy `NOTIFICATION_CONSUMER_ENABLED` / Redis dedup keys are not the live event path.

### Verification (ops)

```sql
-- Resolver smoke (service_role only)
SELECT fn_resolve_notification_for_event(
  '<merchant_id>'::uuid, 'purchase', 'completed',
  '<user_id>'::uuid, '<purchase_id>'::uuid, 'line'
);

SELECT status, skip_reason, event_key, sub_event, channel, created_at
FROM notification_log
WHERE merchant_id = '<merchant_id>'
ORDER BY created_at DESC LIMIT 20;
```

### Known gaps

- **Referral Inngest router** — Deploy copy includes `notification-referral-router`; edge function repo under `supabase/functions/` does not — see Router mapping.
- **`referral.shared`** — Configurable in admin; no send path until share-via-email product ships.
- **REGISTRY_RENDER.md** — Still describes `NotificationConsumer` as active; event notifications use Inngest routers; only `expiry-reminder-batch` uses the notification engine on that service for scheduled work.
- **Merchant Flex override authoring** — Schema supports merchant templates; limited admin surface vs Email editor.
- **Email last mile** — Resolver + router render HTML; consolidation to `messaging-service` `/send` with `source: notification` not complete.
- **Birthday catalog events** — Not shipped.
- **Notification log admin UI** — Not shipped.

## Related

- **CRM_Event_Driven_Architecture.md** — Outbox → Inngest chokepoint routing.
- **Inngest_Primer.md** — Router hosting and idempotency.
- **Referral.md** — Referral chokepoint events and notification catalog coupling.
- **Outbound_Integrations.md** — Klaviyo referral metric names (integration layer, not notification catalog keys).
- **Currency.md** / **Reward.md** — Wallet expiry and entitlement sources for reminders.
- **Purchase_Transaction.md** — Purchase / purchase_item chokepoint events.
- **Shopify.md** — Embedded admin routing to Customer notifications.
