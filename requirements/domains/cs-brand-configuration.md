# CS Brand Configuration

> Per-domain reference. Read ONLY when working on this domain. For the keyword → file map, see `_index.md`.

**Keywords:** brand_config, voice, tone, guardrails, model_config, action_config, outbound, cs_brand_config, voice_preset, forbidden_phrases, escalation_triggers

**Source:** `CS_Feature_Spec.md` (section 4.1)

**Tables:** `cs_brand_config`

**Functions (planned):**

| Function | Type | Purpose |
|---|---|---|
| `cs_bff_get_brand_config` | BFF | Get brand AI configuration |
| `cs_bff_upsert_brand_config` | BFF | Update brand AI configuration |

**Key Business Rules (summary):**
- One row per merchant (UNIQUE on merchant_id)
- Guardrails are distributed: brand-level in this table, per-procedure in `cs_procedures`, per-action in `action_config`
- Override chain: procedure config > channel config > brand config
- Model pipeline stages configured in `model_config` JSONB (intent, reasoning, embedding, verification models)

---
