# Custom Webhooks

Merchant-specific **inbound** HTTP adapters (HookDeck-style filter → transform → forward) and CRM-triggered **outbound** forwards to MCA plays / Open API / Pipedream — audited in Postgres. Not the productized merchant outbound webhook (see **Outbound_Integrations.md**).

Owner surfaces: Supabase Edge (deployed per merchant/integration); ops/debug via SQL on audit table; no loyalty-admin configuration UI

## Concept

**Integration handler** — A thin Edge Function config over shared `createWebhookHandler()`: optional custom header auth, JSON filter expressions, body transform, HTTP forward to a fixed destination, standardized HTTP responses.

**Filter match** — When filter fails, handler returns `200` with `{ "accepted": false, "reason": "filtered" }`, does **not** call the destination, and (by design) does **not** write an audit row — avoids Postgres saturation under noisy POS feeds.

**Audit event** — One row in `custom_integration_events` per handled invocation that reached auth/filter logging policy: forwards, auth failures, invalid JSON, destination errors. `custom_webhook_events` is an updatable view over the same storage for legacy inserts.

**CRM-triggered webhook** — DB triggers on `purchase_ledger`, `user_accounts`, or `user_wallet` POST into Jorakay Edge handlers (no inbound third-party body); respects `skip_cdc` on purchase paths where documented.

**Replay job** — One-off Edge (`custom_webhook_drpong_zort_replay`) re-sends historical Waiting/Success BigCommerce RTS traffic from audit rows (limited after filtered events stopped being persisted).

## Rules

- All listed Edge Functions deploy with **`verify_jwt: false`** — callers use integration auth (e.g. header `key1`) or are invoked from DB triggers/service role, not Supabase anon JWT.
- **Auth failure** → `401`; still audited with `auth_ok = false`.
- **Invalid JSON** → error response audited with `error_message` (e.g. `invalid_json`).
- **Filter pass** → transform runs; destination HTTP status and body captured on the audit row; inbound query string forwarded to destination unchanged.
- **Jorakay receipt trigger** (`trg_jorakay_receipt_webhook` on `purchase_ledger`) — no POST when `skip_cdc` is true (cutover/backfill convention).
- **Jorakay loyalty trigger** on `user_wallet` — no `skip_cdc` column; suppress via `app.skip_side_effects` or disable trigger for wallet backfills.
- **Dr.PONG router** — Single ZORT URL; channel + HTTP method + payment/status determine CRM OpenAPI vs Pipedream vs filtered skip (marketplace channels filtered).
- **Registry note** — `REGISTRY_SUPABASE.md` lists view `custom_webhook_events`; canonical table is `custom_integration_events` (verified live).

## Journeys

### Admin journey

Member journey: **none**. Merchant staff do not configure these handlers in loyalty-admin; routing and secrets are code/env per integration.

| Actor | Action |
| --- | --- |
| Platform / integration engineer | Deploy or update Edge slug under `.cursor/deploy/custom-webhook/`; set env (e.g. `DRPONG_CRM_API_KEY`); point vendor URL at `…/functions/v1/<slug>` |
| Ops / support | Query `custom_integration_events` for `function_slug`, `filter_matched`, `destination_status`, `error_message` |

1. Vendor (ZORT, Packhai, etc.) POSTs to the public Edge URL.
2. Handler auth → filter → optional transform → forward.
3. On failure, ops uses audit row + `destination_response_raw` to diagnose vendor vs destination.

### Member journey

None — members never interact with custom webhook endpoints directly. Downstream effects (receipt earn, CRM rows) surface through normal loyalty journeys (**Purchase_Transaction**, wallet) after successful forwards.

## System

### Data model

| Object | Role |
| --- | --- |
| `custom_integration_events` | Append-only audit of webhook handler runs |
| `custom_webhook_events` | View (updatable) over integration events for compat |

Key columns: `function_slug`, `event_kind` (`forward`, `inbound`, `outbound`, `replay`), `request_*`, `auth_ok`, `filter_matched`, `filter_reason`, `destination_*`, `duration_ms`, `error_message`, optional `bill_number`, `customer_phone`. RLS on; Edge uses service role for inserts.

### Edge functions (live slugs)

Base URL: `https://wkevmsedchftztoolkmi.supabase.co/functions/v1/`

| Slug | Auth | Filter / route | Transform / destination |
| --- | --- | --- | --- |
| `custom_webhook_drpong_zort_pos` | none | Channel router (POS vs BigCommerce vs marketplace) | POS → CRM OpenAPI receipts; BC Waiting/Success+Paid → Pipedream |
| `custom_webhook_yuedpao_zort_pos` | `key1` | phone + channel + paid | Headers + `createReceiptWorkflow` |
| `custom_webhook_4care_zort_create_bill` | `key1` | exclude `1st Party E-Commerce` | `createReceiptWorkflow` |
| `custom_webhook_kao_packhai` | none | `ChannelName=LINE` | Pass-through → Pipedream |
| `custom_webhook_jorakay_receipts` | none (trigger) | `purchase_ledger.skip_cdc` | MCA play `integration_jorakay_crm_receipts` |
| `custom_webhook_jorakay_loyalty` | none (trigger) | none | MCA play `integration_jorakay_crm_loyalty_update` |
| `custom_webhook_jorakay_contacts` | none (trigger) | per trigger fn | MCA / HubSpot contact sync (paired with `trg_jorakay_contact_webhook`) |
| `custom_webhook_drpong_zort_replay` | service | reads audit history | Re-forward RTS rounds to Pipedream (`dry_run` default true) |

Shared library (reference deploy tree): `.cursor/deploy/custom-webhook/` — `hookdeck-filter.ts`, `handler.ts`, `log-event.ts`.

### Database triggers (Jorakay)

| Trigger | Table | Calls |
| --- | --- | --- |
| `trg_jorakay_receipt_webhook` | `purchase_ledger` | `jorakay_notify_receipt_webhook()` → `custom_webhook_jorakay_receipts` |
| `trg_jorakay_contact_webhook` | `user_accounts` | `jorakay_notify_contact_webhook()` → `custom_webhook_jorakay_contacts` |
| `trg_jorakay_loyalty_webhook` | `user_wallet` | `jorakay_notify_loyalty_webhook()` → `custom_webhook_jorakay_loyalty` |

### Flows

**Inbound vendor**

```
POST Edge (no Supabase JWT)
  → auth_ok?
  → filter_matched? (if false: 200 filtered, no audit row)
  → transform → HTTP destination
  → insert custom_integration_events (forward path)
```

**Dr.PONG ZORT router (summary)**

| Channel | Method | Payment/status | Outcome |
| --- | --- | --- | --- |
| `Dataslot - POS` | ADD/UPDATE order + payment | Success + Paid | CRM OpenAPI receipts |
| `Web_Rocket bigcommerce` | UPDATEORDER | Waiting or Success + Paid | Pipedream |
| Marketplace | any | any | `unsupported_channel` filter |
| any | UPDATEORDERTRACKING | — | `filtered_method_tracking` |

Env: `DRPONG_CRM_API_KEY` for CRM OpenAPI.

### External services

- **Pipedream** — Dr.PONG BigCommerce RTS, Kao Packhai LINE pass-through (URLs in handler config).
- **MCA plays** — Jorakay receipt / loyalty / contact integration names in handler config.
- **Open API `createReceiptWorkflow`** — YUEDPAO / 4care ZORT paths.
- **Render `n8n-replacement`** — Related legacy receipt/contact proxy (see `REGISTRY_RENDER.md`); distinct from Edge slugs above.

### Known gaps

- Custom webhook Edge slugs are not enumerated in `REGISTRY_RENDER.md` (grep registry lag); live list from Supabase `list_edge_functions`.
- `custom_webhook_drpong_zort_replay` depends on historical audit rows; filtered traffic after 2026-07-17 is not stored — replay cannot see new filtered Waiting events.
- No self-serve admin UI to add merchants; each integration is a new Edge deploy/config.

## Related

- **Outbound_Integrations.md** — Merchant-configured signed outbound events + Klaviyo (product path).
- **Purchase_Transaction.md** — Receipt ledger rows fed by createReceiptWorkflow / Open API after ZORT forwards.
- **Third_Party_Integrations.md** — Judge.me, Klaviyo inbound, etc. (different ingress patterns).
