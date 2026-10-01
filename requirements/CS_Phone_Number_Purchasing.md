# CS Phone Number Purchasing

Merchants **search, purchase, configure, and release** Twilio numbers (voice + SMS) via provider-abstracted edge function — BYOT or platform master subaccount.

Owner surfaces: loyalty-admin phone UI, Edge `cs-phone-numbers`, Twilio webhooks

## Concept

**Phone number record** — `cs_phone_numbers` links merchant, credential, E.164, provider SIDs, webhook flags.

**BYOT** — Merchant Twilio account in Integration Hub.

**Master subaccount** — Platform creates Twilio subaccount per merchant; credentials stored on `merchant_credentials`.

**Dual use** — Voice → ElevenLabs path; SMS → same CS ingest as chat (`CS_AI_Pipeline.md`).

## Rules

- Lookup inbound **To** number on every SMS/voice webhook to resolve merchant.
- Twilio request signature validation on webhooks.
- Purchase flow sets voice + SMS webhook URLs on Twilio after `cs_fn_upsert_phone_number`.
- Inbound SMS returns empty TwiML; reply async via pipeline/messaging-service.
- Release marks row `released` and clears webhook flags — does not delete Twilio number until adapter release completes.

## Journeys

### Admin journey

| Knob | Effect |
| --- | --- |
| Twilio integration | BYOT credentials or master mode |
| Search / purchase | Available numbers by country |
| Release | Decommission number |

| Page | Owning repo | Edge / RPC |
| --- | --- | --- |
| CS phone numbers | loyalty-admin | `cs-phone-numbers` edge (search, purchase, configure, release, provision-subaccount) |
| | | `cs_bff_get_phone_numbers`, `cs_bff_get_phone_number_details` |

1. Connect Twilio in Integrations Hub (`service_name='twilio'`).
2. Search → purchase → confirm webhooks configured flags true.
3. Test SMS and voice inbound (`CS_Voice.md`).

### Member journey

Standard carrier call/SMS to published E.164 — no Rocket UI.

## System

### Data model

**`cs_phone_numbers`** — columns include `provider`, `phone_number` (unique E.164), `provider_sid`, `capabilities`, `channel_use`, `status`, webhook booleans, cost fields — verified via registry + MCP.

### Functions

| Function | Role |
| --- | --- |
| `cs_fn_upsert_phone_number` | Persist after provider purchase |
| `cs_fn_release_phone_number` | Soft release |
| `cs_bff_get_phone_numbers` | Merchant list |
| `cs_bff_get_phone_number_details` | Detail + usage counts |

### Edge

| Edge | Role |
| --- | --- |
| `cs-phone-numbers` | TwilioAdapter: search, purchase, configure webhooks, release, subaccount provision |
| `webhook-twilio-sms` | Inbound SMS → `cs_api_receive_message` (`platform_type` sms) |
| `webhook-twilio-voice` | Inbound call → contact resolve → voice pipeline |

Integration Hub fields: `account_sid`, `auth_token`, `account_mode` (byot/master).

### Flows

Purchase: Admin → edge adapter → Twilio API → `cs_fn_upsert_phone_number` → webhook configuration.

Master: `provision-subaccount` action stores subaccount creds on merchant row for subsequent ops.

### Known gaps

- Outbound SMS via messaging-service Twilio adapter noted as pending in engineering notes — confirm before documenting SLA for SMS reply latency.
- Future providers (`vonage`, `telnyx`) — adapter pattern only; Twilio shipped.

## Related

- **CS_Voice.md** — After voice webhook.
- **CS_Channels.md** — Credential and Twilio integration model.
- **CS_Channel_Connectors.md** — SMS/voice connector row.
