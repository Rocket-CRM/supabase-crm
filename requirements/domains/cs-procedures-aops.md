# CS Procedures (AOPs)

> Per-domain reference. Read ONLY when working on this domain. For the keyword → file map, see `_index.md`.

**Keywords:** procedure, aop, agent_operating_procedure, intent, trigger_intent, flexibility, strict, guided, agentic, compiled_steps, raw_content, tone_override, cs_procedures, step, tool_reference, data_needs, action_tools, entity_extractors, step_topic, required_variables, prefetch, graph_executor, deterministic_prefetch, code_conditions, variables_in, variables_out, query_hints, args_from

**Source:** `CS_Procedures.md`

**Tables:** `cs_procedures`, `cs_action_config`, `workflow_action_type_config` (domain='cs')

**Functions:**

| Function | Type | Purpose |
|---|---|---|
| `cs_bff_get_procedures` | BFF | List procedures for a merchant |
| `cs_bff_upsert_procedure` | BFF | Create or update procedure (auto-compiles, auto-versions) |
| `cs_fn_get_active_procedure` | Backend | Get active procedure for merchant + intent |
| `cs_fn_compile_procedure` | Backend | Enriches compiled_steps with data_needs (args_from mapping), action_tools (requires_confirmation), entity_extractors (order_number regex, platform/product keywords). Resolves tool_type from cs_action_config → falls back to workflow_action_type_config. |
| `cs_fn_seed_action_config` | Backend | Seeds cs_action_config for a merchant from workflow_action_type_config registry. Called on CS activation or platform connection. |

**CS Action Registry (workflow_action_type_config, domain='cs'):**

| action_type | tool_type | What it does |
|---|---|---|
| `lookup_order` | data | Fetch order by number + platform from marketplace API |
| `get_recent_orders` | data | Fetch recent orders for contact (optional platform filter) |
| `check_product_stock` | data | Check product availability on platform |
| `get_product_price` | data | Get current price on platform |
| `get_customer_profile` | data | Fetch CRM loyalty data via bridge |
| `search_products` | data | Search product catalog by keyword/category/filters on platform |
| `check_promotion` | data | Check active promotions/coupons on platform, or validate a specific promo code |
| `get_order_shipping` | data | Get shipping address, tracking info, carrier details for an order |
| `recommend_products` | data | AI-assisted product recommendations from platform catalog (context + filters) |
| `cancel_order` | action | Cancel order on marketplace (requires platform + order_number) |
| `process_refund` | action | Process refund on marketplace (requires platform + order_number) |
| `create_order` | action | Create new order on platform (phone orders, replacement orders). Requires items, shipping address, customer email |
| `update_order` | action | Modify existing order (shipping address, notes, items) before shipment |
| `apply_coupon` | action | Apply promo/coupon code to an existing order or give to customer |
| `create_voucher` | action | Create loyalty or platform voucher/coupon |
| `create_ticket` | action | Create support ticket from conversation |
| `close_conversation` | action | Mark conversation resolved |
| `trigger_csat_survey` | action | Send satisfaction survey |

**Key Business Rules (summary):**
- Flexibility spectrum: `strict` (follow exactly) → `guided` (adapt flow) → `agentic` (advisory only)
- Versioning: new edit = new row with version+1, old row set `is_active = false`
- Only one active version per `trigger_intent` per merchant
- `@ToolName` references in `raw_content` validated against `cs_action_config` for the merchant
- `compiled_steps` contains enhanced graph structure: per-step `data_needs` (source + args_from + when), `action_tools` (tool + args_from + requires_confirmation), `entity_extractors` (regex for order_number, keyword for platform/product), `step_topic`, `required_variables`
- `platform` is a first-class variable: extracted from customer message via keyword extractor, collected by AI if not mentioned, required by all marketplace data/action tools
- Conversation channel ≠ order platform (customer on LINE may ask about Shopee order)
- Graph executor reads `data_needs` and calls data tools directly as code — LLM never makes data tool calls
- 3-tier prefetch: Tier 1 (data tools in data_needs), Tier 2 (knowledge/conversation only), Tier 3 (no AOP, explorer fallback)
- Per-merchant action overrides in `cs_action_config`: action_constraints (max_amount, blocked_statuses, requires_confirmation), seeded from registry via `cs_fn_seed_action_config`

---
