# Universal Action System (Shared)

> Per-domain reference. Read ONLY when working on this domain. For the keyword → file map, see `_index.md`.

**Keywords:** action_registry, action_category, action_caller_config, rule_type_registry, entity_registry, intent_registry, rules_code, rules_prompt, fn_execute_action, fn_verify_action_rules, fn_validate_rules_code

**Source:** `docs/universal_action_system.md`, `docs/UNIVERSAL_ACTION_ENHANCEMENT_PLAN.md`

**Tables:** `action_registry` (renamed from `workflow_action_type_config`), `action_category`, `action_caller_config` (replaces `cs_action_config` + `amp_agent_action`), `rule_type_registry`, `entity_registry`, `intent_registry`

| Function | Type | Purpose |
|---|---|---|
| `fn_get_action_registry_cached` | Internal | Load all action_registry rows (cached) |
| `fn_validate_rules_code` | Internal | Save-time validation of rules_code against rule_type_registry |
| `fn_verify_action_rules` | Internal | Runtime enforcement: merge + verify rules_code at execution time |
| `fn_execute_action` | Internal | Universal dispatcher: routes by domain to correct handler |
| `bff_upsert_action_category` | BFF | CRUD action categories with rules_code validation |
| `bff_upsert_action_caller_config` | BFF | CRUD caller config with rules_code validation |
| `bff_list_rule_types` | BFF | List rule keys for admin UI |
| `bff_upsert_intent` | BFF | CRUD intents |
| `bff_list_intents` | BFF | List system + merchant intents |
| `cs_fn_load_merchant_ai_config` | Internal | Load AI config (brand, guardrails, category thinking, platforms) |
| `cs_fn_load_action_config` | Internal | Load registries for dynamic tool generation |
| `cs_fn_load_available_resources` | Internal | Load resources for delivery actions |

**Key Business Rules (summary):**
- Universal action system shared across CS, Loyalty/AMP, and future modules
- Three rule types by consumer: `rules_prompt` (LLM), `rules_code` (code), `rules` (both)
- Three rule levels that can only narrow: System → Caller → Runtime
- `rule_type_registry` is single source of truth for rule keys — validates at save-time and enforces at runtime
- `action_caller_config` unifies CS and AMP action config with `caller_type` discriminator
- `intent_registry` holds system intents (merchant_id=NULL) and merchant-specific intents
- `action_macro` supports system-level templates (merchant_id=NULL) and merchant-level customizations

---

## Files NOT Relevant to Frontend

| File | Reason |
|---|---|
| `CRM_Event_Driven_Architecture.md` | Backend infra: CDC, Kafka, Render consumers, replication slots |
| `Inngest_Primer.md` | Backend infra: Inngest workflow engine concepts and patterns |
| `Superadmin_Functions.md` | Admin-only: service-role-key functions for merchant/admin management |
| `Custom_Reward_Scripts.md` | Backend: merchant-specific custom SQL functions for complex earn logic |
| `Ecommerce_Marketplace_Integration.md` | Backend infra: Hookdeck → Kafka → Render consumer for marketplace webhooks |
| `MARKETPLACE_SETUP.md` | Backend infra: Kafka topic setup, API keys, Hookdeck configuration |
| `Code_Import_System.md` | Backend/admin: bulk CSV import of promotional codes via Render service |
| `Reward_Cache_Implementation.md` | Backend infra: Redis caching strategy for rewards API |
| `ACTIVITY_WALLET_INTEGRATION.md` | Backend reference: detailed `chokepoint_post_wallet_transaction` call for activity approval |
| `Package_Contract_Benefit.md` | (In `/requirements/` parent folder if present) Backend: contract/package management |
| `AMP - AI Decisioning.md` | (In `/requirements/` parent folder if present) Backend: AI decisioning engine |

---
