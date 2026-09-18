# CS Phone Number Purchasing

> Per-domain reference. Read ONLY when working on this domain. For the keyword → file map, see `_index.md`.

**Keywords:** twilio, phone_number, purchase_number, sms, voice, provider, adapter, subaccount, byot, master, cs_phone_numbers, webhook_twilio_sms, webhook_twilio_voice

**Source:** `CS_Phone_Number_Purchasing.md`

**Tables:** `cs_phone_numbers`

**Functions (deployed):**

| Function | Type | Purpose |
|---|---|---|
| `cs_bff_get_phone_numbers` | BFF | List active numbers (provider-agnostic) |
| `cs_bff_get_phone_number_details` | BFF | Single number + 30-day stats |
| `cs_fn_upsert_phone_number` | Backend | Insert/update after provider purchase |
| `cs_fn_release_phone_number` | Backend | Mark released |

**Edge Functions (deployed):** `cs-phone-numbers` (adapter pattern), `webhook-twilio-sms`, `webhook-twilio-voice`

**Covers:** Phone number search/purchase/configure/release via provider-abstracted adapter pattern (Twilio first). BYOT + master subaccount models. Inbound SMS → CS conversation pipeline. Inbound voice → ElevenLabs connection.

---
