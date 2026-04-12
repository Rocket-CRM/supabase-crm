# CS Brand / AI Config

## What This Is

A single settings page where the brand admin configures how the AI agent behaves across all conversations. This is the "personality and rules" configuration — brand voice, guardrails, guidance rules, model settings, and outbound messaging preferences.

This is a settings page, not a list+config. One configuration per merchant (singleton).

The AI in this project should use its own judgment for what UI layout, section organization, and form patterns produce the best UX for **configuring an AI customer service agent's behavior and personality**. Study how Intercom's Fin settings, ChatGPT's custom instructions, or enterprise AI configuration panels approach this — then decide the best structure.

---

## FE Project Context

| Layer | Tech |
|---|---|
| Framework | Next.js 16 (App Router, React 19) |
| UI | Shopify Polaris v13 (the only component library) |
| Backend | Complex operations via `supabase.rpc()`. Simple reads/writes via `supabase.from()` (RLS handles merchant scoping). |
| Auth | Supabase Auth, JWT carries merchant context |
| Forms | `react-hook-form` + `zod` |

### Route

```
src/app/(admin)/cs-brand-config/
```

### Page Pattern

Settings page: one RPC to fetch current config, one RPC to save. Uses the standard get + upsert pattern.

---

## Backend Connection — Tables & RPCs

### Core Tables

**`cs_merchant_config`** — One row per merchant. AI behavior defaults.

| Column | Type | Notes |
|---|---|---|
| `id` | uuid PK | |
| `merchant_id` | uuid FK (UNIQUE) | One per merchant |
| `voice_preset` | text | `professional`, `friendly`, `casual`, `formal`, `playful` |
| `voice_description` | text | Free-text custom voice: "Speak like a friendly skincare expert who avoids jargon and adds gentle humor" |
| `language` | text | `th`, `en`, `mixed` |
| `guidance_rules` | jsonb | Communication style, clarification rules, content source preferences, spam handling |
| `model_config` | jsonb | `{provider, model, temperature, max_tokens, intent_model, embedding_model, hallucination_check_enabled, bad_actor_screening_enabled, supervisor_verification: {enabled, for_action_types}}` |
| `outbound_config` | jsonb | Quiet hours, cooldown, blackout dates for proactive outreach |
| `created_at` | timestamptz | |
| `updated_at` | timestamptz | |

**`cs_merchant_guardrails`** — Rows per guardrail rule. Global behavioral guardrails.

| Column | Type | Notes |
|---|---|---|
| `id` | uuid PK | |
| `merchant_id` | uuid FK | |
| `category` | text | `topic_boundary`, `escalation_trigger`, `forbidden_phrase`, `required_behavior`, `language_rule`, `communication_style` |
| `rule_content` | text | Natural language: "Never discuss competitor products" |
| `rule_config` | jsonb | Optional structured config for rules needing parameters (keyword lists, sentiment thresholds) |
| `is_active` | boolean | Toggle without deleting |
| `priority` | int | Higher = evaluated first |
| `created_at` | timestamptz | |
| `updated_at` | timestamptz | |

### RPCs

| RPC | Purpose | Notes |
|---|---|---|
| `cs_bff_get_brand_config` | Fetch current config | Returns: cs_merchant_config row + all cs_merchant_guardrails rows for this merchant |
| `cs_bff_upsert_brand_config` | Save config | Params: voice_preset, voice_description, language, guidance_rules, model_config, outbound_config. Upserts cs_merchant_config. |
| `cs_bff_get_guardrails` | List all guardrail rules | Returns guardrails with category, content, is_active, priority. Filterable by category. |
| `cs_bff_upsert_guardrail` | Create/update a guardrail rule | Params: id (null for new), category, rule_content, rule_config, is_active, priority |
| `cs_bff_delete_guardrail` | Delete a guardrail rule | Params: guardrail_id |
| `cs_bff_reorder_guardrails` | Reorder priority | Params: ordered list of guardrail_ids with new priority values |

**Direct CRUD (use `supabase.from()`):**
- Upsert brand config: `supabase.from('cs_merchant_config').upsert({ merchant_id, voice_preset, ... })`
- Guardrails CRUD: `supabase.from('cs_merchant_guardrails')` for insert, update, delete individual rules

**RPCs (use `supabase.rpc()`):**
- `cs_bff_get_brand_config` — returns config + all guardrails in one call (two tables)
- `cs_bff_reorder_guardrails` — batch update priorities atomically

---

## Key Domain Concepts the UI Must Support

### 1. Brand Voice Configuration

- **Voice preset** — Dropdown: Professional, Friendly, Casual, Formal, Playful
- **Custom voice description** — Free-text field for nuanced instructions: "Speak like a friendly skincare expert who uses simple language, avoids jargon, and adds gentle humor"
- **Language** — Primary language: Thai, English, Mixed (Thai-English code-switching)
- **Emoji usage** — On / Off / Moderate
- **Response length** — Concise / Balanced / Detailed

### 2. Guidance Rules

Natural language instructions that shape AI behavior across all conversations. Organized by category:

| Category | Example Rules |
|---|---|
| **Communication style** | "Always use formal Thai (ครับ/ค่ะ) unless customer uses casual first", "Keep responses under 3 sentences for simple questions" |
| **Context and clarification** | "Always ask for order number before looking up order status", "Don't ask for info the customer already provided" |
| **Content and sources** | "For ingredient questions, reference the product spec sheet, not marketing page", "Never quote prices — always link to the product page" |
| **Escalation rules** | "If customer mentions legal action, escalate immediately", "If customer sends 2+ angry messages, offer to connect with a human" |
| **Spam handling** | "If message appears to be spam or bot-generated, do not respond" |
| **Sensitive topics** | "Never give medical advice", "Never discuss competitor products" |

### 3. Guardrails (Behavioral Rules)

Each guardrail is a separate toggleable rule with:

| Category | Format | Example |
|---|---|---|
| `topic_boundary` | Natural language | "Never discuss competitor products" |
| `escalation_trigger` | Natural language + optional structured config | "Escalate when customer mentions legal action" (+ config: `{keywords: ["lawyer", "sue", "legal"]}`) |
| `forbidden_phrase` | Natural language + keyword list | "Never say 'I'm just an AI' or 'I don't have feelings'" (+ config: `{phrases: ["just an AI", "I'm a bot"]}`) |
| `required_behavior` | Natural language | "Always apologize first when customer reports a problem" |
| `language_rule` | Natural language | "Always respond in the same language the customer uses" |
| `communication_style` | Natural language | "Never use ALL CAPS in responses" |

Guardrails can be individually enabled/disabled and reordered by priority.

### 4. Model Configuration

Advanced settings (may be hidden behind an "Advanced" section):
- Provider and model selection
- Temperature setting
- Hallucination check toggle
- Bad actor screening toggle
- Supervisor verification — enable/disable, configure which action types require verification

### 5. Outbound Config

Settings for proactive AI outreach:
- Quiet hours (don't send messages between 10 PM – 8 AM)
- Cooldown period (min time between outbound messages to same customer)
- Blackout dates (holidays, etc.)

---

## Key UX Requirements

1. This is a dense settings page. Organize into clear sections — the AI should decide the best grouping and navigation (tabs, accordion, sidebar nav, etc.).

2. Voice configuration should feel tangible — consider a "preview" or example showing how the AI would respond with current settings.

3. Guardrails should be easy to add, toggle, reorder. Each rule is a card or row that can be enabled/disabled individually.

4. Changes should be saveable as a whole (not per-field auto-save) with clear dirty-state indication.

---

## What NOT to Build (Backend Handles These)

- Runtime application of guardrails to AI prompts — backend injects active guardrails into LLM system prompt
- Model switching/routing — backend infrastructure concern
- Guardrail violation detection — backend monitors in real-time
