# CS Teams & Agent Management — List + Config

## What This Is

Team and agent management for the CS module. Agents are the human support staff who handle conversations. Teams group agents by function, skill, or brand. This page manages:

- **Teams** — Create teams, assign members, set routing rules, link business hours
- **Agent profiles** — CS-specific settings like skills, max concurrent conversations, online status

The AI in this project should use its own judgment for what UI layout produces the best UX for **managing customer service teams and agent capacity**. Study how Zendesk, Freshdesk, or Intercom handle team management — then decide the best structure.

---

## FE Project Context

| Layer | Tech |
|---|---|
| Framework | Next.js 16 (App Router, React 19) |
| UI | Shopify Polaris v13 (the only component library) |
| Backend | All data via `supabase.rpc()` |
| Auth | Supabase Auth, JWT carries merchant context |
| Forms | `react-hook-form` + `zod` |

### Routes

```
src/app/(admin)/cs-teams/              → Teams list + agent overview
src/app/(admin)/cs-teams/[id]/         → Team config (create/edit team)
```

---

## Backend Connection — Tables & RPCs

### Core Tables

**`admin_teams`** — Shared team table (used by both Loyalty and CS modules)

| Column | Type | Notes |
|---|---|---|
| `id` | uuid PK | |
| `merchant_id` | uuid FK | |
| `name` | text | "VIP Support", "Refund Team", "Thai Language Team" |
| `description` | text | |
| `domain` | text | `loyalty`, `cs`, `both` |
| `business_hours_id` | uuid FK → cs_business_hours | Which business hours schedule this team follows |
| `is_active` | boolean | |
| `created_at` | timestamptz | |
| `updated_at` | timestamptz | |

**`admin_users`** — Shared admin user table with CS-specific columns added:

| Column | Type | Notes |
|---|---|---|
| (existing columns) | | name, email, role, merchant_id, etc. |
| `cs_online_status` | text (nullable) | `online`, `away`, `offline` — CS agent availability |
| `cs_max_concurrent` | int (nullable) | Max simultaneous conversations this agent can handle |
| `cs_skills` | jsonb (nullable) | `{languages: ["th","en"], platforms: ["shopee","line"], expertise: ["refunds","products"]}` |

**`admin_roles`** / **`admin_role_permissions`** — Existing RBAC tables. CS adds new roles and permission resources.

New CS roles: `cs_admin`, `cs_supervisor`, `cs_agent`, `cs_viewer`

New CS permission resources:

| Resource | Typical Actions |
|---|---|
| `cs_conversation` | `[read, reply, assign, resolve, close]` |
| `cs_knowledge` | `[read, create, update, delete]` |
| `cs_procedure` | `[read, create, update, activate]` |
| `cs_brand_config` | `[read, update]` |
| `cs_analytics` | `[read]` |
| `cs_team` | `[read, create, update]` |

### RPCs — Teams

| RPC | Purpose | Notes |
|---|---|---|
| `cs_bff_get_teams` | List all CS teams | Returns teams where domain='cs' or domain='both'. Includes member count, business hours name, active status. |
| `cs_bff_get_team` | Get team detail | Params: team_id. Returns team config + member list with their CS profiles (skills, capacity, status). |
| `cs_bff_upsert_team` | Create/update team | Params: name, description, business_hours_id, member_ids[], is_active |
| `cs_bff_delete_team` | Delete team | Params: team_id. Reassign or unassign conversations first. |
| `cs_bff_add_team_member` | Add agent to team | Params: team_id, user_id |
| `cs_bff_remove_team_member` | Remove agent from team | Params: team_id, user_id |

### RPCs — Agent CS Profiles

| RPC | Purpose | Notes |
|---|---|---|
| `cs_bff_get_agents` | List all agents with CS profiles | Returns admin_users who have CS roles, with their cs_online_status, cs_max_concurrent, cs_skills, current conversation count. |
| `cs_bff_update_agent_cs_profile` | Update CS-specific fields | Params: user_id, cs_max_concurrent, cs_skills. Only updates CS columns. |
| `cs_bff_update_agent_status` | Change online status | Params: user_id, cs_online_status (online/away/offline). Called by agents themselves or supervisors. |
| `cs_bff_get_agent_workload` | Current workload | Params: user_id. Returns: active conversation count, ticket count, avg response time today. |

---

## Key Domain Concepts the UI Must Support

### 1. Team Configuration

- **Team name and description** — Descriptive grouping: "VIP Support", "Refund Team", "After-Hours Team"
- **Members** — Add/remove agents. An agent can belong to multiple teams.
- **Business hours** — Each team is linked to a business hours schedule (from `cs_business_hours`). SLA timers use the assigned team's hours.
- **Domain** — Whether this team handles CS only, loyalty only, or both

### 2. Agent CS Profile

Each agent has CS-specific attributes:
- **Online status** — Online (available for assignment), Away (won't receive new conversations), Offline (not working)
- **Max concurrent conversations** — Capacity cap. Auto-assignment respects this limit.
- **Skills** — Languages spoken, platform expertise, topic expertise. Used for skills-based routing.

### 3. Auto-Assignment Rules

Teams define how conversations are routed to their members:
- **Round-robin** — Rotate through available agents
- **Least-busy** — Assign to agent with fewest open conversations
- **Skills-based** — Match conversation language/platform/topic to agent skills
- **Load balanced** — Respect max_concurrent limits

These rules are configured per team.

### 4. Real-Time Status Dashboard

A supervisor view showing:
- Who is online / away / offline
- Current conversation count per agent vs their max capacity
- Visual capacity indicators (green = under 50%, yellow = 50-80%, red = 80%+)

---

## Key UX Requirements

1. The team list should show team health at a glance — how many members, how many online, current capacity utilization.

2. Agent management should make it easy to see and adjust capacity across the team.

3. Skills configuration should be intuitive — tag-style input for languages, platforms, and expertise areas.

4. Status changes (online/away/offline) should be quick — agents change status frequently.

---

## What NOT to Build (Backend Handles These)

- Auto-assignment routing logic — backend determines which agent gets the next conversation
- Capacity enforcement — backend respects max_concurrent when assigning
- Agent idle detection — backend could auto-set "away" after inactivity (future)
- Role/permission CRUD — use existing admin role management pages (shared with loyalty)
