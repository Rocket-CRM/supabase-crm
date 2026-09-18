# Action Macro (Shared)

> Per-domain reference. Read ONLY when working on this domain. For the keyword → file map, see `_index.md`.

**Keywords:** action_macro, macro, macro_context, execute_macro, multi_step_action, parameterized_action, variable_definitions, variable_constraints, approval_threshold, guardrail, action_sequence

**Source:** `Action_Macro.md`

**Tables:** `action_macro`, `action_macro_context`

| Function | Type | Purpose |
|---|---|---|
| `bff_upsert_macro_with_contexts` | BFF | Create/update macro + context bindings |
| `bff_get_macro_details` | BFF | Get macro + contexts (new/edit mode) |
| `bff_list_macros` | BFF | List macros, optionally by context_type |
| `bff_delete_macro` | BFF | Delete macro (contexts cascade) |
| `fn_validate_macro_variables` | Internal | Validate variables against Layer 1 + Layer 2 constraints |
| `fn_check_macro_approval` | Internal | Check approval thresholds |
| `fn_execute_macro` | Internal | Orchestrate macro execution |

**Key Business Rules (summary):**
- Shared entity — used by CS Agent, CS AI, AMP AI Agent, AMP Rule-Based
- Macros define steps + variable definitions (the ceiling)
- `action_macro_context` binds macros to contexts with narrowed variable constraints
- Three guardrail layers: macro ceiling → context constraints → runtime (AMP budgets, CS guardrails, RBAC)
- Approval thresholds: auto-approve below X, require approval X–Y, block above Y
- Execution routes value/classification actions to `fn_execute_action` (universal dispatcher), content actions to `cs_messages`, system actions to `cs_conversations`

---
