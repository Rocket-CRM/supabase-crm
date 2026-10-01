# CS Teams & Agent Profiles

> Per-domain reference. Read ONLY when working on this domain. For the keyword → file map, see `_index.md`.

**Keywords:** team, agent, agent_profile, online, away, offline, max_concurrent, skills, routing, round_robin, least_busy, cs_teams, cs_agent_profiles

**Source:** `CS_Feature_Spec.md` (sections 4.8, 4.9)

**Tables:** `cs_agent_profiles`, `cs_teams`

**Functions (planned):**

| Function | Type | Purpose |
|---|---|---|
| `cs_bff_get_teams` | BFF | List teams for a merchant |
| `cs_bff_upsert_team` | BFF | Create or update team |
| `cs_bff_get_agent_profiles` | BFF | List agent profiles with online status |
| `cs_fn_update_agent_status` | Backend | Update agent online/away/offline status |
| `cs_fn_route_conversation` | Backend | Route conversation to best available agent |

**Key Business Rules (summary):**
- Agent profiles auto-provisioned on first CS inbox access
- Identity from `admin_users` via JOIN; `cs_agent_profiles` only stores operational state
- Teams reference `admin_users.id` in `member_admin_user_ids` array
- Routing methods: round-robin, least-busy, manual, skill-based

---
