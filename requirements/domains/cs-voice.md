# CS Voice

> Per-domain reference. Read ONLY when working on this domain. For the keyword → file map, see `_index.md`.

**Keywords:** voice, phone, call, inbound, outbound, stt, tts, speech_to_text, text_to_speech, elevenlabs, scribe, twilio, sip, telephony, recording, transcript, ivr, voice_call, cs_voice_calls, voice_config, graph_executor, deterministic_prefetch, custom_llm, vad, barge_in, warm_transfer

**Source:** `CS_Voice.md`

**Tables:** `cs_voice_calls`, `cs_merchant_config` (voice_config column). ElevenLabs API key is a platform-level Supabase secret, NOT in `merchant_credentials`.

| Function | Type | Purpose |
|---|---|---|
| `cs_fn_create_voice_call` | Backend | Insert voice call record, link to conversation |
| `cs_fn_update_voice_call` | Backend | Update call status, duration, recording, transcript |
| `cs_bff_get_voice_calls` | BFF | Admin: list voice calls with filters |
| `cs_bff_get_voice_call_details` | BFF | Admin: call detail + transcript + recording |
| `cs_bff_upsert_voice_config` | BFF | Admin: save voice settings |
| `voice-custom-llm` | Edge | ElevenLabs Custom LLM endpoint. Graph executor prefetch + single LLM call. |
| `webhook-elevenlabs` | Edge | Call lifecycle webhooks (call.started, call.ended) |
| `cs/voice.post-call` | Inngest | Post-call: transcript, memory extraction, CSAT, analytics |

**Architecture docs:** `docs/cs_voice_architecture.md`, `docs/cs_ai_message_journey.md` (Voice Path section), `docs/cs_ai_pipeline_steps.md` (Voice Pipeline section)
**POC status:** `docs/cs_voice_poc_status.md`

**Key Business Rules (summary):**
- ElevenLabs Custom LLM mode: STT/TTS/VAD/turn-taking/barge-in on ElevenLabs, all AI decisioning on cs-ai-service (Render)
- ElevenLabs API key is platform-level (Supabase secret), agent ID + phone numbers are per-merchant (cs_merchant_config.voice_config)
- Graph executor pattern: deterministic prefetch based on AOP step, single LLM call per turn (Haiku 4.5 for voice latency)
- Same AOPs, same MCP tools, same knowledge base as chat — different orchestration (graph executor vs AgentKit)
- Voice conversations use `cs_conversations.modality = 'voice'`, telephony metadata in `cs_voice_calls` (1:1)
- Contact resolved by phone number via `cs_fn_resolve_contact(platform_type='voice')`
- Post-call processing via Inngest (memory extraction, analytics) — same as chat post-resolution
- Prefetch works ~80% of turns; LLM falls back to explorer mode (tool-call loop) for unpredictable data needs

---
