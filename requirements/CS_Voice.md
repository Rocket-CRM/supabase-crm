# CS Voice

Inbound/outbound **phone** CS: ElevenLabs STT/TTS with **custom LLM** (`voice-custom-llm` edge → Render `/api/cs-voice-turn` graph executor); same AOPs and MCP tools as chat.

Owner surfaces: Twilio telephony, ElevenLabs agent, loyalty-admin **CS Brand Config** / **CS Call Logs**

## Concept

**Voice call** — `cs_voice_calls` row 1:1 with `cs_conversations` where `modality='voice'`.

**Turn** — Transcript in → entity extract + AOP prefetch → single LLM call → streamed text to TTS.

**Warm transfer** — `transferred_to` agent + `transfer_summary` for human pickup.

**Platform vs merchant creds** — ElevenLabs API key platform-level; agent id and inbound numbers per merchant in `voice_config`.

## Rules

- ElevenLabs performs audio only — no reasoning on their side.
- Each inbound call creates a **new** conversation (no merge with prior chat threads).
- Contact resolved by caller phone via `cs_fn_resolve_contact` with voice platform type.
- Post-call memory + analytics via Inngest `cs/voice.call_ended` / `cs/voice.post-call` (same memory agent as chat).
- POC issues (step advancement, latency) may affect demo — check `docs/cs_voice_poc_status.md` before demos.

## Journeys

### Admin journey

| Knob | Effect |
| --- | --- |
| `cs_bff_upsert_voice_config` | Agent id, greeting, language, inbound numbers |
| Phone purchase | **`CS_Phone_Number_Purchasing.md`** |

| Page | Owning repo | BFF |
| --- | --- | --- |
| **CS Brand Config** / voice settings | loyalty-admin | `cs_bff_upsert_voice_config`, `cs_bff_get_brand_config` |
| **CS Call Logs** | loyalty-admin | `cs_bff_get_voice_calls`, `cs_bff_get_voice_call_details` |

1. Configure ElevenLabs agent id and numbers.
2. Purchase Twilio number with voice webhook.
3. Test widget or live call; review call log + inbox thread.

### Member journey

1. Dials merchant number → Twilio → ElevenLabs stream ↔ custom LLM endpoint.
2. Hears AI responses; may request human per procedure (`escalate_to_human`).
3. Call ends → optional CSAT follow-up channel `(pipeline config)`.

## System

### Data model

**`cs_voice_calls`** — Links `conversation_id`, `elevenlabs_call_id`, phones, direction, status, timestamps, `recording_url`, `full_transcript`, transfer fields, `disposition`.

**`cs_merchant_config.voice_config`** — jsonb: `elevenlabs_agent_id`, voice id, greeting mode, `inbound_phone_numbers`.

### Functions

| Function | Role |
| --- | --- |
| `cs_fn_create_voice_call` | Start record at call start |
| `cs_fn_update_voice_call` | Status, duration, recording, transcript |
| `cs_bff_get_voice_calls` / `_get_voice_call_details` | Admin logs |
| `cs_bff_upsert_voice_config` | Save merchant voice settings |

### Edge / Render

| Component | Role |
| --- | --- |
| `webhook-twilio-voice` | Call start → conversation + voice call + stream TwiML |
| `webhook-elevenlabs` | Lifecycle, session → conversation map, call ended |
| `voice-custom-llm` | OpenAI-compatible endpoint → graph executor |
| `cs-ai-service` `/api/cs-voice-turn` | Prefetch + one LLM call + action list |

Secrets: `ELEVENLABS_API_KEY`, `GRAPH_EXECUTOR_URL`, platform OpenAI on Render.

### Flows

Call start → resolve contact → upsert voice conversation → create voice call → ElevenLabs STT → custom LLM → graph executor → TTS stream.

Call end → update call row → Inngest post-call (memory, analytics).

Chat vs voice orchestration comparison: **`CS_AI_Pipeline.md`**.

### Known gaps

- POC: step advancement and ~2.5s latency vs <1.5s target — engineering backlog.
- Outbound voice campaigns — **`CS_Platform_Features.md`** roadmap only.

## Related

- **CS_AI_Pipeline.md** — Voice path branch and graph executor tiers.
- **CS_Phone_Number_Purchasing.md** — Number and webhook setup.
- **CS_Procedures.md** — Spoken AOP navigation.
- **CS_Unified_Inbox.md** — Voice threads in queue.
