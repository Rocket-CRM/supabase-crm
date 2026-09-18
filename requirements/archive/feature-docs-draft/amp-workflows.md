# Feature Guide: AMP Workflows (Rule-Based)

## 1. Overview

AMP Workflows is the marketing automation engine of the CX Platform. Merchants design automated journeys that respond to customer behavior — when a member earns points, completes a purchase, or enters an audience segment, workflows trigger and execute a chain of actions: send a LINE message, award bonus points, assign a tag, wait three days, check a condition, then branch.

The builder is a visual drag-and-drop canvas where marketing teams construct these workflows without code. Each workflow is a directed graph of nodes (conditions, actions, waits, messages) connected by edges. The system watches for database events via a CDC pipeline (Debezium → Kafka → consumer → dispatcher), matches them to active workflow triggers, and hands execution to Inngest for durable orchestration. Inngest handles retries, long waits, and state persistence — a workflow that sleeps for 7 days resumes reliably.

Workflows operate entirely in the background. Members never interact with a "workflow" directly — they receive its effects: a welcome LINE message, bonus points in their wallet, a tag that changes their eligibility, or a persona reassignment. The admin sees these effects tracked as an execution log with funnel analytics.

## 2. Key Concepts

**Workflow** — An automated sequence of steps stored as a directed graph (nodes + edges). Has a name, code, active/inactive status, and a run mode (`event` for CDC-triggered, `batch` for manual). Example: "Welcome Series" triggers on new user signup, sends greeting, waits 2 days, checks purchase history, branches.

**Node** — A single step in the workflow. Six types exist: condition, action, wait, message (deprecated — now action sub-types), agent, and API call. Each node has a type, configuration, and canvas position.

**Edge** — A directional connection between two nodes. Carries a `source_handle` that determines branching: `default` (linear flow), `true` (condition passed), or `false` (condition failed).

**Entry Node** — The first condition node with no incoming edges. This is where execution begins. Triggers are auto-derived from which database tables the entry condition references.

**Trigger** — A mapping from a CDC event (table + operation) to a workflow. Auto-generated when the workflow is saved. Example: entry condition checks `wallet_ledger` → trigger created for `wallet_ledger INSERT`. Stored in `amp_workflow_trigger`.

**Execution** — A single user's run through a workflow, tracked by a unique `inngest_run_id`. Statuses: `active` (in progress), `completed`, `failed`, `exited`.

**Audience** — A saved segment backed by a system workflow. When activated, a 2-node workflow (condition → add-to-audience action) evaluates in real-time via the same CDC pipeline. See Audience Builder feature guide.

**Variable Substitution** — Template syntax (`{{user.firstname}}`, `{{trigger.amount}}`) that personalizes message content and API payloads at execution time.

**Node Stats** — Per-node execution counters (entered, completed, errors) displayed as overlays on the canvas. Sourced from `amp_workflow_log`.

## 3. Configuration Reference

### Workflow Settings

| Setting | What it controls | Options | Default |
|---|---|---|---|
| Name | Display name in workflow list | Free text | "New Workflow" |
| Code | Unique identifier per merchant | Auto-generated `wf_{timestamp}` | Auto |
| Description | Optional notes | Free text | Empty |
| Status | Whether the workflow processes events | Active / Inactive | Inactive |
| Run Mode | How the workflow is triggered | `event` (CDC-driven), `batch` (manual) | `event` |
| Scope | Visibility classification | `user` (marketer-facing), `system` (infrastructure) | `user` |
| Domain | What the workflow automates | `campaign`, `audience` | `campaign` |

### Node Types and Configuration

**Condition Node**

| Setting | What it controls | Example |
|---|---|---|
| Match mode | How groups combine | `all` (AND) / `any` (OR) |
| Collection (table) | Which data table to query | `wallet_ledger`, `purchase_ledger`, `user_accounts` |
| Field | Column to evaluate | `amount`, `transaction_type`, `tier_id` |
| Operator | Comparison type | `=`, `>`, `<`, `contains`, `SUM >`, `COUNT >=` |
| Value | Target value | `100`, `earn`, specific UUID |

**Action Node** — sub-types grouped by category:

| Category | Action | Key settings |
|---|---|---|
| Messages | LINE Message | `content` (text), `json_content` (Flex message) |
| Messages | SMS | `message` (text with variables) |
| Loyalty | Award Currency | `currency` (points/ticket), `amount`, `ticket_type_id` |
| Loyalty | Assign Tag | `tag_id` |
| Loyalty | Remove Tag | `tag_id` |
| Loyalty | Assign Persona | `persona_id` |
| Loyalty | Earn Factor | `earn_factor_id`, `window_end_days` |
| Loyalty | Submit Form | `form_id`, `field_values` |
| Audience | Add to Audience | `audience_id` |
| Audience | Remove from Audience | `audience_id` |
| Integration | Webhook | `method`, `url`, `headers`, `body`, `timeout_seconds` |

**Wait Node**

| Setting | Options | Example |
|---|---|---|
| Duration | Numeric value | `3` |
| Unit | minutes, hours, days, weeks, months | `days` |

**Agent Node** — Select a pre-configured AI agent by ID. See AMP AI Decisioning guide.

## 4. Admin Journey

**Repo:** `Rocket-CRM/loyalty-admin`

**Route map:**

| Page Name | Current Route | BFF / Data Source |
|---|---|---|
| Workflow List | `/workflow-list` | `amp_workflow` table (direct query, `scope='user'`) |
| Workflow Builder | `/workflow-list` (inline canvas view) | `bff_get_amp_workflow_full`, `bff_get_workflow_collections`, `bff_get_amp_action_options` |
| Audience Builder | `/audience-builder` | `bff_list_audiences`, `bff_create_audience`, `bff_activate_audience` |
| AMP Analytics | `/amp-analytics` | `bff_amp_analytics_overview`, `bff_amp_analytics_workflow` |

### 4a. Create a New Workflow

1. From **Workflow List**, click **"Create workflow"** button
2. **Workflow Builder** opens with a single Entry Condition node on the canvas and the node palette sidebar
3. Configure the entry condition: select collection (table), field, operator, value — this defines what triggers the workflow
4. Drag nodes from the **Node Palette** (left sidebar) onto the canvas — grouped as Messages, Loyalty, Audience, Integration, Logic
5. Connect nodes by dragging from output handles to input handles. Condition and Agent nodes have two outputs: true (green) and false (red)
6. Click any node to open its **Config Panel** (right sidebar) and configure settings
7. Set workflow name and description in the **Settings** panel
8. Click **"Save"** — saves as inactive. Toggle **"Active"** switch to activate (starts processing events)

### 4b. Edit an Existing Workflow

1. From **Workflow List**, click any workflow row
2. **Workflow Builder** opens with the existing graph loaded (nodes, edges, triggers)
3. Modify nodes, edges, or settings. Save when done.

### 4c. Manage the Workflow List

1. **Workflow List** displays all `scope='user'` workflows with columns: Name, Status (badge), Run Mode, Domain, Last Updated
2. **Toggle status**: activate/deactivate directly from the list via toggle switch
3. **Duplicate**: creates a copy with "(Copy)" suffix, set to inactive
4. **Batch Run**: manually trigger evaluation for all qualifying users (when `run_mode='batch'`)

### 4d. View Analytics

1. From **AMP Analytics**, the **Overview Dashboard** shows: total workflows, executions, users reached, actions performed
2. Click a workflow row → **Workflow Detail** with per-workflow stats, daily volume charts, action funnel, recent executions
3. Click a user row → **User Timeline** showing the full execution path with color-coded event dots
4. Time range filter: 7D / 30D / 90D / All / Custom date range

### 4e. Common Admin Mistakes

- Saving a workflow with no entry condition configured → workflow has no trigger, never fires
- Activating a workflow before finishing node configuration → incomplete actions fail at execution
- Creating a condition that references a table not yet on the CDC pipeline → trigger never arrives
- Setting wait duration too short for the use case (e.g., 5 minutes for a "re-engagement" flow)
- Forgetting to activate after saving — workflows default to inactive

## 5. Member Experience

**Repo:** `Rocket-CRM/loyalty-user`

Members do not interact with workflows directly. There is no workflow-specific UI in the member app. Workflows are background automation — members experience the effects.

**Route map:** N/A — no member-facing routes for workflows.

### Member-Visible Outcomes

| Workflow Action | What the Member Sees |
|---|---|
| LINE Message | Push notification and message in LINE chat |
| SMS | Text message on phone |
| Award Currency (points) | Points balance increases, transaction appears in history |
| Award Currency (tickets) | Ticket balance increases |
| Assign Tag | No direct visibility (affects eligibility for rewards, missions, etc.) |
| Assign Persona | May change visible tier benefits, reward pricing, or content |
| Assign Earn Factor | Temporary earning boost — member sees higher points per transaction |
| Submit Form | Form data populated on their profile |
| Add/Remove from Audience | No direct visibility (affects future workflow targeting) |

### Timing

- CDC pipeline latency: ~200-500ms from database write to workflow trigger
- Execution is durable: wait nodes pause for the configured duration, then resume
- Message delivery depends on the channel provider (LINE: near-instant, SMS: seconds)
- Members may receive workflow effects minutes, hours, or days after the triggering event

## 6. Perspectives

### 6a. For Customer Success / Support

**Elevator pitch:** "Workflows automate your marketing actions. When a customer does something — earns points, makes a purchase, joins a segment — the system automatically sends messages, awards bonuses, or updates their profile based on rules you set up."

**Top support questions:**

| Question | Answer |
|---|---|
| "Customer says they got a random LINE message" | Check active workflows — find which one targets that user's trigger event. The message came from an action node. |
| "Customer didn't receive the welcome bonus" | Check if the welcome workflow is active, if the user met the entry condition, and if the execution completed (check AMP Analytics → User Timeline). |
| "Customer got the same message twice" | Check if there are duplicate workflows targeting the same trigger. Or the user may have triggered the workflow twice (two qualifying events). |
| "Points were awarded but no message sent" | The workflow may have failed after the award action but before the message node. Check execution logs for errors. |
| "How do I stop a workflow for one customer?" | Workflows don't have per-user opt-out. Deactivate the workflow to stop it for everyone, or adjust the entry condition to exclude specific segments. |

### 6b. For Marketing

**Value proposition:** AMP replaces manual campaign sends with automated, behavior-triggered journeys. Instead of batch-blasting a segment, workflows react to individual customer moments — a purchase, a tier upgrade, a lapsed period — and deliver the right message at the right time.

**Campaign patterns:**
1. **Welcome series** — Signup triggers: greeting → wait 2 days → check first purchase → send discount or tips
2. **Post-purchase nurture** — Purchase triggers: thank you → wait 7 days → request review → award bonus points
3. **Win-back** — Lapsed audience triggers: "we miss you" → wait 3 days → send offer → check redemption
4. **Tier celebration** — Tier upgrade triggers: congratulations message → award bonus points → exclusive offer
5. **Birthday campaign** — Birthday date match: greeting → birthday points → special reward offer

**Metrics available in AMP Analytics:** Total triggers, unique users reached, completion rate, failure rate, in-flight count, action funnel (executed → sent → delivered → opened), daily volume trends.

### 6c. For Testers

**Config → expected behavior:**

| Config | Expected Behavior |
|---|---|
| Workflow `is_active = false` | No events processed, triggers ignored |
| Entry condition on `wallet_ledger` with `transaction_type = 'earn'` | Only point-earning events trigger (not deductions) |
| Condition node evaluates to false, no false-branch edge | Execution ends at that node (`execution_completed`) |
| Wait node: 3 days | Inngest sleeps for 72 hours, then resumes at the next node |
| Action node: award 100 points | `wallet_ledger` INSERT with `source_type='amp'`, `amount=100` |
| Action node: assign tag | `user_tags` upsert with `source_type='amp'`, `source_id=workflow_id` |

**Execution log assertions:**

- ASSERT: Every execution starts with `execution_started` event (no `node_id`)
- ASSERT: Each node produces a `node_executed` event with correct `node_id` and `node_type`
- ASSERT: Message actions produce both `node_executed` (status: `executed`) and `action_sent` (status: `sent`)
- ASSERT: Execution ends with `execution_completed`, `execution_failed`, or `execution_exited`
- ASSERT: All log entries share the same `inngest_run_id` for one execution
- ASSERT: `source_type='amp'` on all CRM records created by workflow actions

**Status model (event sourcing — all statuses are INSERT, not UPDATE):**

| Event Type | When | Node Context |
|---|---|---|
| `execution_started` | Workflow begins for a user | No |
| `node_executed` | A node runs | Yes |
| `action_sent` | Message accepted by provider | Yes, with `external_message_id` |
| `action_delivered` | Provider confirms delivery | Yes |
| `action_failed` | Node execution error | Yes, with `error_message` |
| `execution_completed` | All nodes finished | No |
| `execution_failed` | Unrecoverable error | No |

**Error scenarios to test:**
- Network failure on message send → Inngest retries 3 times with exponential backoff
- Invalid tag_id in action config → `action_failed` logged, execution may continue or fail depending on error handling
- CDC event for a table not in the trigger registry → event ignored, no workflow fires
- Two workflows trigger on the same event → both execute independently
- User triggers same workflow while a previous execution is still in-flight → new execution starts (parallel runs allowed)

## 7. Business Rules

**Rule:** Triggers are auto-derived from entry condition fields. When a workflow is saved, `bff_upsert_amp_workflow_with_graph` scans condition nodes for their `collection` (table name) and creates/updates `amp_workflow_trigger` records.
**Example:** Entry condition queries `wallet_ledger.transaction_type = 'earn'` → trigger created for `wallet_ledger INSERT`.

**Rule:** The entry node is the first node with no incoming edges. There is no explicit "trigger" node type.
**Example:** A workflow with nodes A→B→C where A has no incoming edges → A is the entry node.

**Rule:** Condition nodes branch via `source_handle`. True path follows the `true` handle edge; false path follows the `false` handle. If no edge exists for a branch, execution stops on that path.
**Example:** Condition "points > 500" evaluates to false, no false-edge → execution completes without running further nodes.

**Rule:** Wait nodes use Inngest's `step.sleep()`. The workflow pauses for the exact duration, then resumes. Inngest persists state across server restarts.
**Example:** Wait 7 days → execution pauses, Inngest scheduler resumes after 7 days.

**Rule:** Workflows default to `is_active = false`. They must be explicitly activated to process events. Deactivating stops new executions but does not cancel in-flight ones.
**Example:** Admin saves workflow → inactive. Toggles active → starts processing CDC events.

**Rule:** All action side-effects are tracked with `source_type='amp'` and `source_id=workflow_id`, enabling audit trail back to the originating workflow.
**Example:** Points awarded by workflow → `wallet_ledger` row has `source_type='amp'`.

**Rule:** Inngest retries failed steps 3 times with exponential backoff (1s → 2s → 4s). 4xx errors do not retry. 5xx and network errors do.
**Example:** LINE API returns 500 → retried 3 times. LINE API returns 400 (bad request) → fails immediately.

**Rule:** CDC pipeline filters inserts only (`op = 'c'`) and applies table-specific business filters (wallet: `earn` transactions only; purchase: `completed` only). Deduplication via Redis with a 5-minute window.
**Example:** Points deduction (not `earn`) → AmpConsumer filters it out, no workflow triggered.

## 8. Related Features

| Feature | Connection to AMP Workflows |
|---|---|
| Currency | Award points/tickets action writes to `wallet_ledger` via `chokepoint_post_wallet_transaction`. Point earning events trigger workflows via CDC. See `Currency.md`. |
| Tags & Personas | Assign/remove tag and assign persona actions modify user profile data. Tag/persona changes can be entry conditions. See `Tag_and_Persona.md`. |
| Tier | Tier-related conditions can gate workflow branches. Tier upgrades (future CDC source) can trigger workflows. See `Tier.md`. |
| Rewards | Workflows do not directly issue rewards, but can trigger conditions or tag members for reward eligibility. See `Reward.md`. |
| Forms | Submit form action populates form responses. Form submissions (future CDC source) can trigger workflows. See `Forms.md`. |
| AMP AI Decisioning | Agent nodes invoke AI-powered decision engines within the workflow graph. See `AMP - AI Decisioning.md`. |
| AMP Audiences | Audiences are system workflows using the same engine. Audience membership changes can trigger marketing workflows. See Audience Builder. |
| Activity/Earning | Purchase and earning events are the primary CDC sources that trigger workflows. See `Activity_Based_Earning.md`. |
