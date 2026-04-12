# CS Procedures (AOPs) — List + Config

## What This Is

Two pages for managing Agent Operating Procedures (AOPs) — the natural-language workflows that define how the AI agent handles specific customer intents (refund requests, order tracking, product inquiries, complaints, etc.).

- **List page** — Browse, search, filter, activate/deactivate procedures
- **Config page** — Create or edit a single procedure (natural language editor + metadata + guardrails + testing)

The AI in this project should use its own judgment for what UI layout, editor experience, and interaction patterns produce the best UX for **authoring and managing AI operating procedures**. Think about how Decagon's AOP editor, Intercom's Workflows builder, or a modern CMS content editor would approach this — then decide the best structure.

---

## FE Project Context

| Layer | Tech |
|---|---|
| Framework | Next.js 16 (App Router, React 19) |
| UI | Shopify Polaris v13 (the only component library) |
| Rich text | TipTap (available for the procedure content editor) |
| Backend | Complex operations via `supabase.rpc()`. Simple reads/writes via `supabase.from()` (RLS handles merchant scoping). |
| Auth | Supabase Auth, JWT carries merchant context |
| Forms | `react-hook-form` + `zod` |

### Routes

```
src/app/(admin)/cs-procedures/           → List page
src/app/(admin)/cs-procedures/[id]/      → Create/Edit config page
```

### Page Pattern

Follows the standard list + config pattern:
- List: RSC calls server action → passes data to client component
- Config: `p_mode: "new" | "edit"` pattern — one RPC to fetch (returns empty template for new, populated data for edit), one RPC to save

---

## Backend Connection — Tables & RPCs

### Core Table

**`cs_procedures`**

| Column | Type | Notes |
|---|---|---|
| `id` | uuid PK | |
| `merchant_id` | uuid FK | |
| `name` | text | "Refund Request Handler" |
| `description` | text | What this procedure does and when it applies |
| `trigger_intent` | text | `refund_request`, `order_tracking`, `product_inquiry`, `complaint`, etc. |
| `flexibility` | text | `strict`, `guided`, `agentic` |
| `raw_content` | text | Natural language AOP — the full procedure text the LLM reads at runtime |
| `compiled_steps` | jsonb | Parsed structure: step list, tool refs, branch map, code conditions, data flow |
| `config` | jsonb | `{tone_override, max_turns, timeout}` |
| `guardrails` | jsonb | `{require_confirmation_before_action, blocked_actions, escalate_after_turns, supervisor_verification, policy_conditions}` |
| `is_active` | boolean | Only one active procedure per trigger_intent per merchant |
| `version` | int | Incremented on edit; old versions kept as is_active=false |
| `created_by` | uuid | |
| `created_at` | timestamptz | |

**Versioning model:** New edit = new row with version+1, old row set `is_active = false`. Uniqueness: one active procedure per `(merchant_id, trigger_intent)`.

### RPCs — List Page

| RPC | Purpose | Notes |
|---|---|---|
| `cs_bff_get_procedures` | List all procedures | Returns: id, name, description, trigger_intent, flexibility, is_active, version, created_at, created_by. Supports search, filter by trigger_intent, filter by is_active. |
| `cs_bff_activate_procedure` | Toggle is_active | Params: procedure_id, is_active. Enforces uniqueness — if activating, deactivates any other procedure with same trigger_intent. |
| `cs_bff_delete_procedure` | Soft delete / archive | Params: procedure_id |

### RPCs — Config Page

| RPC | Purpose | Notes |
|---|---|---|
| `cs_bff_get_procedure` | Fetch for edit or new | Params: procedure_id (for edit) or null (for new). Returns full procedure data including raw_content, config, guardrails. For new: returns template/defaults. |
| `cs_bff_upsert_procedure` | Save procedure | Params: full procedure payload. Creates new version if editing existing. Backend handles compilation (raw_content → compiled_steps). |
| `cs_bff_get_procedure_versions` | Version history | Params: procedure_id (original). Returns all versions for diff/rollback. |
| `cs_bff_get_available_actions` | List available @Tool references | Returns all registered MCP tools/actions for this merchant. Used for autocomplete when writing `@Tool Name` in the procedure editor. |
| `cs_bff_validate_procedure` | Validate before save | Params: raw_content. Backend validates: step numbering, @Tool references exist, {{variable}} paths valid, no dead-end branches. Returns validation errors. |

**Direct CRUD (use `supabase.from()`):**
- List procedures: `supabase.from('cs_procedures').select('*').eq('merchant_id', merchantId).order('created_at', { ascending: false })`
- Get single procedure: `supabase.from('cs_procedures').select('*').eq('id', procedureId).single()`
- Soft delete: `supabase.from('cs_procedures').update({ is_active: false }).eq('id', procedureId)`

**RPCs (use `supabase.rpc()`):**
- `cs_bff_upsert_procedure` — versioning logic
- `cs_bff_activate_procedure` — enforces uniqueness per trigger_intent
- `cs_bff_get_procedure_versions` — version history for a trigger_intent
- `cs_bff_get_available_actions` — list available @Tool references for autocomplete

---

## Key Domain Concepts the UI Must Support

### 1. Procedure Content Editor

The main editing surface for the natural language AOP. This is NOT a visual workflow builder — it's a **structured text editor** where the CX team writes procedures in a specific format:

```
AOP Name: Refund Request Handler
Description: Handle customer refund requests for delivered orders
Trigger Intent: refund_request
Flexibility: Guided

1. Step "Collect Order Info": Ask the customer for their order number.
   If the customer provides it in the initial message, skip asking.

2. Step "Lookup Order": Use @Lookup Order with the order number.
   - If not found: allow 2 retries, then escalate.

3. Step "Check Eligibility":
   CODE CONDITION: days_since_delivery <= 7 AND status == "delivered"
   - If eligible: Go to Step 4.
   - If not eligible: Go to Step 5.

4. Step "Process Full Refund": Confirm with customer. Use @Process Refund.

5. Step "Offer Store Credit": Offer 110% store credit. Use @Create Voucher.

6. Step "Escalate": Use @Escalate to Human with summary.

7. Step "Close": Thank customer. Use @Trigger CSAT Survey.
```

Key conventions the editor should understand:
- `@Tool Name` — references MCP tools (should autocomplete from available actions)
- `{{variable.field}}` — references data from previous steps
- `CODE CONDITION` — deterministic evaluation blocks
- `Go to Step N` — explicit flow control
- Step numbering is sequential with descriptive names

### 2. Flexibility Spectrum

Three levels, configurable per procedure (and potentially per step):

| Level | Behavior |
|---|---|
| **Strict** | AI follows EXACTLY step by step. No skipping. Only listed tools available per step. |
| **Guided** (default) | AI follows general flow. Can skip steps if data already collected. Still validates tool calls. |
| **Agentic** | AI uses procedure as guideline. Reasons freely. All tools available. |

### 3. Config Fields

- `tone_override` — overrides brand default voice for this procedure (e.g., "empathetic, apologetic" for refund handler)
- `max_turns` — maximum conversation turns before forced escalation
- `timeout` — max duration before procedure times out

### 4. Guardrails Fields

- `require_confirmation_before_action` — AI must ask "Shall I proceed?" before irreversible actions
- `blocked_actions` — list of @Tool names NOT available in this procedure
- `escalate_after_turns` — force escalation after N turns without resolution
- `supervisor_verification` — enable separate model verification for high-risk actions
- `policy_conditions` — structured conditions evaluated by engine (not AI)

### 5. Version History

Show version timeline. Allow diff comparison between any two versions. One-click rollback to previous version.

### 6. Template AOPs

For new procedures, offer pre-built templates:
- Refund Request Handler
- Order Tracking
- Product Inquiry
- Complaint Handler
- Return/Exchange
- Account Management

Each template is a starting point the CX team customizes.

---

## Key UX Requirements

1. The procedure editor is the centerpiece. It needs to feel like writing documentation, not programming. Syntax highlighting for `@Tool` references, `{{variables}}`, `CODE CONDITION` blocks, and `Step` markers.

2. Real-time validation — as the user types, highlight issues (unknown @Tool references, undefined variables, unreachable steps).

3. The list page should clearly show which procedures are active, which intents are covered, and which are drafts/inactive.

4. Version history should be accessible but not cluttered — the CX team is not git-savvy.

---

## What NOT to Build (Backend Handles These)

- Procedure compilation (raw_content → compiled_steps) — backend parses this on save
- Procedure execution at runtime — handled by Inngest + cs-ai-service
- Intent detection — backend AI handles matching customer messages to trigger_intents
- A/B testing traffic splitting — backend infrastructure concern
