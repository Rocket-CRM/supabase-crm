# AMP Workflow Builder — Frontend Component Specification

## Overview

The AMP Workflow Builder is a visual drag-and-drop workflow editor for creating automated marketing journeys. The component is self-contained — it fetches all necessary data from Supabase internally via RPC calls. No external WeWeb data bindings needed.

**Supabase URL:** `https://wkevmsedchftztoolkmi.supabase.co`

---

## Props from Parent (WeWeb)

| Prop | Type | Description |
|------|------|-------------|
| `supabaseUrl` | string | Supabase project URL |
| `supabaseAnonKey` | string | Supabase publishable/anon key |
| `authToken` | string | Current admin user's JWT |
| `workflowId` | string (UUID) | Current workflow ID (null for new workflows) |

All backend functions use `get_current_merchant_id()` from the JWT to scope data to the admin's merchant. No merchant ID needs to be passed explicitly.

---

## Node Types

The workflow canvas supports these node types:

| Node Type | Purpose | Has branching? |
|-----------|---------|---------------|
| **Condition** | Evaluate rules, branch true/false | Yes (true/false handles) |
| **Action** | Execute loyalty actions, send messages, call APIs | No |
| **Wait** | Pause for a duration | No |
| **Agent** | AI-powered decision | Yes (true/false handles) |

**Note:** Trigger node is NOT in the palette. The first node (no incoming edges) is the entry point. The backend auto-detects which CRM events should start the workflow based on condition node collections.

---

## Backend API Reference

### Workflow CRUD

**Save workflow (create or update):**
```
POST /rest/v1/rpc/bff_upsert_amp_workflow_with_graph
Body: {
  "p_workflow": { "id": "uuid or null", "name": "...", "description": "...", "is_active": true },
  "p_nodes": [ { "id": "uuid", "node_type": "condition", "node_name": "...", "node_config": {...}, "position_x": 300, "position_y": 200 } ],
  "p_edges": [ { "id": "uuid", "from_node_id": "uuid", "to_node_id": "uuid", "source_handle": "output-true" } ],
  "p_triggers": []
}

Returns: { "success": true, "workflow_id": "uuid", "code": "CREATED" | "UPDATED" }
```

When `p_triggers` is empty, the backend auto-generates triggers from condition node collections.

**Load workflow:**
```
POST /rest/v1/rpc/bff_get_amp_workflow_full
Body: { "p_workflow_id": "uuid" }

Returns: {
  "success": true,
  "workflow": { "id", "name", "description", "is_active", ... },
  "nodes": [ { "id", "node_type", "node_name", "node_config", "position_x", "position_y" } ],
  "edges": [ { "id", "from_node_id", "to_node_id", "source_handle", "edge_label" } ],
  "triggers": [ { "id", "trigger_type", "trigger_table", "trigger_operation", "trigger_conditions", "is_active" } ]
}
```

**Duplicate workflow:**
```
POST /rest/v1/rpc/bff_duplicate_amp_workflow
Body: { "p_workflow_id": "uuid", "p_new_name": "Copy of My Workflow" }

Returns: { "success": true, "new_workflow_id": "uuid" }
```

---

## Condition Node

### Condition Builder UI

The condition node config panel shows a **Condition Builder** with groups:

- **All (AND)** / **Any (OR)** toggle at top level (`groups_operator`)
- Each group has:
  - **AND** / **OR** toggle within the group
  - **Collection** dropdown (data source)
  - **Check single record** / **Check aggregate** toggle (if collection supports it)
  - Conditions or aggregate config

### Data: Collections

```
POST /rest/v1/rpc/bff_get_workflow_collections
Body: {}

Returns: [
  {
    "name": "wallet_ledger",
    "label": "Points / Wallet",
    "supports_aggregate": true,
    "aggregate_fields": [
      { "name": "amount", "type": "number", "label": "Amount", "aggregates": ["sum", "avg", "min", "max", "count"] },
      { "name": "signed_amount", "type": "number", "label": "Signed Amount", "aggregates": ["sum", "avg", "min", "max", "count"] }
    ],
    "fields": [ { "name": "amount", "type": "number", "label": "Amount" }, ... ]
  },
  {
    "name": "purchase_items_ledger",
    "label": "Purchase Items",
    "supports_aggregate": true,
    "aggregate_fields": [ { "name": "line_total", ... }, { "name": "quantity", ... } ],
    "joinable_to": {
      "table": "purchase_ledger",
      "on": { "local": "transaction_id", "foreign": "id" },
      "time_field": "created_at"
    },
    "fields": [ ... ]
  },
  { "name": "user_accounts", "label": "Users", "supports_aggregate": false, "fields": [ ... ] },
  { "name": "purchase_ledger", "label": "Purchases", "supports_aggregate": true, ... }
]
```

### Simple Condition Mode (Check single record)

Check if any row exists matching field conditions.

**UI:** Field dropdown → Operator dropdown → Value input. Can add multiple conditions (AND within group).

**Operators:** equals, not_equals, greater_than, greater_or_equal (shown as ≥), less_than, less_or_equal (shown as ≤), contains

**Saved config:**
```json
{
  "groups_operator": "AND",
  "groups": [{
    "type": "simple",
    "collection": "wallet_ledger",
    "operator": "AND",
    "conditions": [
      { "field": "amount", "operator": "greater_than_or_equals", "value": "10" }
    ]
  }]
}
```

### Aggregate Condition Mode (Check aggregate)

Shown when collection has `supports_aggregate: true`. Checks SUM/COUNT/AVG across multiple rows.

**UI:**
1. **Function** dropdown: Sum, Count, Average, Min, Max
2. **Field** dropdown: from `aggregate_fields` (e.g., Line Total, Quantity)
3. **Filters** (optional): field + operator + value rows to narrow which rows are aggregated
4. **Time range** dropdown: Past 1 month, 3 months, 6 months, 12 months, 24 months, All time
5. **Threshold**: operator (≥, >, =, <, ≤) + value input

**Saved config:**
```json
{
  "groups_operator": "AND",
  "groups": [{
    "type": "aggregate",
    "collection": "purchase_items_ledger",
    "join": {
      "table": "purchase_ledger",
      "on": { "local": "transaction_id", "foreign": "id" }
    },
    "aggregate": "sum",
    "field": "line_total",
    "time_field": "created_at",
    "time_range": "12 months",
    "filters": [
      { "field": "sku_code", "operator": "equals", "value": "SKU-TSH-001-L" }
    ],
    "operator": "gte",
    "value": 10000
  }]
}
```

The `join` and `time_field` values come from the collection's `joinable_to` metadata — pass them through as-is.

### Edge Handles

Condition nodes have two output handles:
- `output-true` → connects to the "yes" path
- `output-false` → connects to the "no" path

If only one path is connected (e.g., only true), the workflow ends when the other path is taken.

---

## Action Node

### Data: Action Options

Called once on action panel mount. Cached.

```
POST /rest/v1/rpc/bff_get_amp_action_options
Body: {}

Returns: {
  "success": true,
  "ticket_types": [ { "id": "uuid", "name": "Test Raffle Tickets 2025", "ticket_code": "RAFFLE-2025", "description": "..." } ],
  "tags": [ { "id": "uuid", "tag_name": "VIP" }, { "id": "uuid", "tag_name": "Frequent Buyer" } ],
  "persona_groups": [
    {
      "id": "uuid", "group_name": "Lifestyle Segment",
      "personas": [ { "id": "uuid", "persona_name": "Health Conscious" }, { "id": "uuid", "persona_name": "Budget Shopper" } ]
    }
  ],
  "forms": [ { "id": "uuid", "name": "User Profile", "code": "USER_PROFILE", "form_category": "profile" } ],
  "private_earn_factors": [
    {
      "id": "uuid", "earn_factor_type": "multiplier", "earn_factor_amount": 3, "target_currency": "points",
      "target_entity_id": null, "window_start": "...", "window_end": "...", "group_id": "uuid", "group_name": "Birthday Bonus Program"
    }
  ]
}
```

### Data: Form Fields (on form select)

```
POST /rest/v1/rpc/bff_get_amp_form_fields
Body: { "p_form_id": "uuid" }

Returns: {
  "success": true,
  "form_id": "uuid",
  "fields": [{
    "id": "uuid", "field_key": "favorite_color", "label": "Favorite Color", "field_type": "select",
    "text_format": null, "is_required": true, "placeholder": "Choose a color", "help_text": "...",
    "min_value": null, "max_value": null, "min_selections": null, "max_selections": null,
    "options": [ { "value": "red", "label": "Red", "is_default": false }, { "value": "blue", "label": "Blue", "is_default": true } ]
  }]
}
```

### Action Type Selector

Show grouped categories:

**Loyalty Actions**
- Award Currency — Give points or tickets
- Assign Tag — Add a tag to user
- Remove Tag — Remove a tag from user
- Assign Persona — Change user's persona segment
- Assign Earn Factor — Give temporary earning boost
- Submit Form — Create a form submission

**Messaging**
- Send LINE Message — Push message via LINE
- Send SMS — Send SMS message

**Integration**
- API Call — HTTP request to external URL

### Per-Action Config Panels

#### Award Currency

1. Toggle: **Points** / **Ticket**
2. If Points: number input "Amount" (required, > 0)
3. If Ticket: dropdown "Ticket Type" (from `ticket_types`, display `name`, store `id`) + number input "Amount"
4. Text input: "Description" (optional, supports `{{variables}}`)

```json
{ "action_type": "award_currency", "currency": "points", "amount": 100, "description": "Welcome bonus" }
{ "action_type": "award_currency", "currency": "ticket", "ticket_type_id": "uuid", "amount": 5 }
```

#### Assign Tag

1. Dropdown of tags (from `tags`, display `tag_name`, store `id`)

```json
{ "action_type": "assign_tag", "tag_id": "uuid" }
```

#### Remove Tag

1. Same dropdown as Assign Tag

```json
{ "action_type": "remove_tag", "tag_id": "uuid" }
```

#### Assign Persona

1. Dropdown grouped by persona group: `group_name` as section header, `persona_name` as options

```
── Lifestyle Segment ──
   Health Conscious
   Budget Shopper
── Purchase Behavior ──
   Impulse Buyer
   Bargain Hunter
```

```json
{ "action_type": "assign_persona", "persona_id": "uuid" }
```

#### Assign Private Earn Factor

1. Dropdown grouped by `group_name`. Label each factor:
   - Rate: `"Earn {amount} {currency} per unit"`
   - Multiplier: `"{amount}x {currency} multiplier"`
   - If ticket with target_entity_id: append ticket type name from `ticket_types`

```
── Birthday Bonus Program ──
   3x points multiplier
   Earn 2 points per unit
── VIP Retention ──
   2x ticket multiplier — Raffle Tickets
```

2. Number input: "Duration (days)" (default 30, > 0)
   - Help text: "Starts from the moment the workflow runs for each user"

```json
{ "action_type": "assign_earn_factor", "earn_factor_id": "uuid", "window_end_days": 30 }
```

#### Submit Form

1. Dropdown: "Form Template" (from `forms`, display `name`)
2. On select: call `bff_get_amp_form_fields(form_id)`, show spinner while loading
3. Render each field based on `field_type`:

| field_type | Input component | Notes |
|-----------|----------------|-------|
| `text` | Text input | Respect `text_format` (email/phone/url) |
| `number` | Number input | Respect `min_value`, `max_value` |
| `date` | Date picker | |
| `select` | Single-select dropdown | Options from `options` array. Display `label`, store `value`. Pre-select `is_default` |
| `multiselect` | Multi-select checkboxes | Respect `min_selections`, `max_selections` |
| `checkbox` | Toggle | Stores `"true"` / `"false"` |
| `textarea` | Multi-line text | |
| `radio` | Radio group | Options from `options` array |

4. Show `label` as field label, `placeholder` as placeholder, `help_text` below input
5. Mark required fields with asterisk (`is_required`)
6. All text fields support `{{variable}}` syntax

```json
{
  "action_type": "submit_form", "form_id": "uuid",
  "field_values": { "favorite_color": "blue", "age": 28, "interests": ["sports", "cooking"] }
}
```

Note: `field_values` uses `field_key` as key (not field_id).

#### Send LINE Message

1. Text area: message content (supports `{{variables}}`)
2. Optional: JSON editor for flex messages

```json
{ "channel": "line", "content": "Hello {{user.firstname}}!" }
{ "channel": "line", "json_content": { "type": "flex", "altText": "Reward", "contents": { ... } } }
```

#### Send SMS

1. Text area: message (supports `{{variables}}`)

```json
{ "channel": "sms", "message": "Hi {{user.firstname}}, your code is {{trigger.code}}" }
```

#### API Call

1. Method dropdown: GET, POST, PUT, DELETE
2. URL text input (supports `{{variables}}`)
3. Headers key-value editor (optional)
4. Body JSON editor (optional, supports `{{variables}}`)

```json
{ "action_type": "api_call", "url": "https://api.example.com/notify", "method": "POST", "body": { "user_id": "{{user.id}}" } }
```

### Validation Before Save

| Action | Required |
|--------|----------|
| award_currency (points) | `amount` > 0 |
| award_currency (ticket) | `ticket_type_id` selected, `amount` > 0 |
| assign_tag | `tag_id` selected |
| remove_tag | `tag_id` selected |
| assign_persona | `persona_id` selected |
| assign_earn_factor | `earn_factor_id` selected, `window_end_days` > 0 |
| submit_form | `form_id` selected, all `is_required` fields filled |
| LINE | `content` or `json_content` not empty |
| SMS | `message` not empty |
| api_call | `url` not empty |

---

## Wait Node

### Config

1. Number input: duration value (required, > 0)
2. Dropdown: unit — Seconds, Minutes, Hours, Days, Weeks

```json
{ "duration": 10, "unit": "days" }
```

---

## Agent Node

### Config

1. Text input: "Campaign Objective" (e.g., "drive engagement", "reduce churn")
2. Toggle: "Use Groq AI" (default on)

```json
{ "campaign_objective": "drive engagement", "use_groq": true }
```

### Edge Handles

Same as condition: `output-true` (AI recommends action) / `output-false` (no action).

---

## Template Variables

Show a helper panel or insert button for text fields:

**User data**
- `{{user.firstname}}`, `{{user.lastname}}`, `{{user.fullname}}`
- `{{user.email}}`, `{{user.tel}}`
- `{{user.points_balance}}`
- `{{user.tier_id}}`, `{{user.persona_id}}`
- `{{user.line_id}}`

**Trigger data**
- `{{trigger.source}}` — wallet_ledger or purchase_ledger
- `{{trigger.amount}}`, `{{trigger.currency}}`, `{{trigger.transaction_type}}`
- `{{trigger.total_amount}}`, `{{trigger.final_amount}}`, `{{trigger.status}}`

**Agent data** (only after an agent node)
- `{{agent.message}}`, `{{agent.selected_asset_name}}`
- `{{agent.action}}`, `{{agent.urgency}}`, `{{agent.reasoning}}`

---

## Node Stats & User List

### Node Badge (bottom of each node on canvas)

Each node shows a clickable badge at the bottom:

```
┌─────────────────────┐
│  Check Balance       │
│  (condition node)    │
├─────────────────────┤
│  👤 247   ⏳ 12      │  ← clickable
└─────────────────────┘
```

- `👤 247` = unique users that passed this node (always shown)
- `⏳ 12` = currently waiting (only on wait nodes, only when > 0)

### Data: Node Stats

Called on workflow load. Optionally poll every 30-60 seconds.

```
POST /rest/v1/rpc/bff_get_amp_workflow_node_stats
Body: { "p_workflow_id": "uuid" }

Returns: {
  "success": true,
  "workflow_id": "uuid",
  "nodes": [
    { "node_id": "uuid-1", "node_type": "condition", "node_name": "Check Balance", "unique_passed": 247, "currently_waiting": 0 },
    { "node_id": "uuid-2", "node_type": "wait", "node_name": "Wait 10 days", "unique_passed": 195, "currently_waiting": 12 },
    { "node_id": "uuid-3", "node_type": "action", "node_name": "Send LINE", "unique_passed": 183, "currently_waiting": 0 }
  ]
}
```

Map `node_id` from the response to each node on the canvas and display the counts.

### User List Popup

Opened when clicking the node badge. Shows paginated list.

```
┌──────────────────────────────────────────────────────┐
│  Users at: Check Balance                  [Export ⬇]  │
│  247 total users                                      │
├──────────────────────────────────────────────────────┤
│  Name        │ User ID    │ Email       │ Entry Date  │
│  ────────────┼────────────┼─────────────┼──────────── │
│  Rangwan     │ f9fe89...  │ rang@...    │ 21 Feb 2026 │
│  Yuranan     │ 6e32...    │ yura@...    │ 20 Feb 2026 │
│  VoranunBun  │ b993...    │ vora@...    │ 20 Feb 2026 │
├──────────────────────────────────────────────────────┤
│  ← Page 1 of 5 →                                     │
└──────────────────────────────────────────────────────┘
```

**Columns:** Name, User ID, Email, Phone, Entry Date, Status, Execution Count

**Status badge colors:** `executed` = green, `sent` = green, `waiting` = blue, `failed` = red

```
POST /rest/v1/rpc/bff_get_amp_node_users
Body: { "p_workflow_id": "uuid", "p_node_id": "uuid", "p_page": 1, "p_page_size": 50 }

Returns: {
  "success": true,
  "total_count": 247,
  "page": 1,
  "page_size": 50,
  "total_pages": 5,
  "users": [
    {
      "user_id": "uuid",
      "fullname": "Rangwan",
      "email": "rangwan@...",
      "tel": "+6696...",
      "line_id": "U46fa...",
      "node_entry_date": "2026-02-21T09:36:48Z",
      "status": "executed",
      "execution_count": 3
    }
  ]
}
```

Pagination: increment `p_page` on next/prev. `total_pages` tells you when to stop.

### CSV Export

The "Export" button triggers a CSV file download. Open the URL via `window.open()` or a hidden `<a>` tag:

```
{supabaseUrl}/functions/v1/amp-export-node-users?workflow_id={wfId}&node_id={nodeId}&token={authToken}
```

This returns a CSV file directly (Content-Type: text/csv). The browser will prompt a file save dialog.

**CSV columns:** Name, User ID, Email, Phone, Node Entry Date, Status, Execution Count

---

## Edit Mode (Loading Existing Config)

When editing an existing node, `node_config` is passed. The component should:

1. **Condition:** Read `groups`, `groups_operator`. For each group, check `type` (simple/aggregate). Pre-populate collection, conditions/aggregate config.
2. **Action:** Read `action_type` or `channel` to determine panel. Pre-populate all fields. For `submit_form`: read `form_id`, call `bff_get_amp_form_fields`, populate field inputs from `field_values`.
3. **Wait:** Read `duration` and `unit`, populate inputs.
4. **Agent:** Read `campaign_objective` and `use_groq`.
