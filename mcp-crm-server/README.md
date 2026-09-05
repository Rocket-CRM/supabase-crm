# CRM MCP Server

Role-aware MCP server for CRM Supabase access. Designed for use with Cursor IDE.

## How it works

1. Authenticates as a named Supabase Auth user (tester, store_admin, store_owner)
2. Loads permissions from `system_mcp_role_permissions` for that role
3. Exposes scoped tools — only operations the role is allowed to perform
4. All DB queries use the user's JWT, so RLS auto-scopes to their merchant
5. Schema operations (CREATE TABLE, ALTER, DROP, functions) are hardcoded out

## Setup

### Step 1: Create a Supabase Auth user for the role

In Supabase Dashboard → Authentication → Users, create a new user:
- Email: e.g. `tester-ajinomoto@internal.com`
- Password: a secure password

### Step 2: Add them to admin_users

```sql
INSERT INTO admin_users (auth_user_id, merchant_id, email, active_status, role_id)
VALUES (
  '<auth_user_id from step 1>',
  '<merchant_uuid>',
  'tester-ajinomoto@internal.com',
  true,
  (SELECT id FROM admin_roles WHERE role_code = 'tester' LIMIT 1)
);
```

If no `tester` role exists in `admin_roles` yet, create it:
```sql
INSERT INTO admin_roles (role_code, role_name, is_system_role, active_status)
VALUES ('tester', 'Tester', true, true);
```

Repeat for `store_admin` and `store_owner` as needed.

### Step 3: Configure your environment

Copy `.env.example` to `.env` and fill in:

```
SUPABASE_URL=https://wkevmsedchftztoolkmi.supabase.co
SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndrZXZtc2VkY2hmdHp0b29sa21pIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTA1MTM2OTgsImV4cCI6MjA2NjA4OTY5OH0.bd8ELGtX8ACmk_WCxR_tIFljwyHgD3YD4PdBDpD-kSM
# Optional: only for trusted upstream authoring servers. Omit for downstream read-only consumers.
SUPABASE_SERVICE_ROLE_KEY=your_service_role_key_here
CRM_EMAIL=tester-ajinomoto@internal.com
CRM_PASSWORD=your_password_here
```

### Step 4: Build

```bash
npm install
npm run build
```

### Step 5: Configure Cursor

Add to your Cursor MCP settings (`~/.cursor/mcp.json` or the workspace `.cursor/mcp.json`):

```json
{
  "mcpServers": {
    "crm-tester": {
      "command": "node",
      "args": ["~/Documents/rocket/supabase-crm/mcp-crm-server/dist/index.js"],
      "env": {
        "SUPABASE_URL": "https://wkevmsedchftztoolkmi.supabase.co",
        "SUPABASE_ANON_KEY": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndrZXZtc2VkY2hmdHp0b29sa21pIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTA1MTM2OTgsImV4cCI6MjA2NjA4OTY5OH0.bd8ELGtX8ACmk_WCxR_tIFljwyHgD3YD4PdBDpD-kSM",
        "SUPABASE_SERVICE_ROLE_KEY": "omit_for_downstream_read_only_or_set_for_trusted_authoring",
        "CRM_EMAIL": "tester-ajinomoto@internal.com",
        "CRM_PASSWORD": "your_password_here"
      }
    }
  }
}
```

For multiple roles, add multiple entries:

```json
{
  "mcpServers": {
    "crm-tester": { ... },
    "crm-store-admin": {
      "command": "node",
      "args": ["~/Documents/rocket/supabase-crm/mcp-crm-server/dist/index.js"],
      "env": {
        "CRM_EMAIL": "admin-ajinomoto@internal.com",
        "CRM_PASSWORD": "..."
      }
    }
  }
}
```

## Available Tools

| Tool | Description |
|------|-------------|
| `get_my_context` | Shows your role, allowed operations, and guardrails |
| `list_tables` | Lists all tables your role can access with permitted operations |
| `get_table_context` | Returns detailed domain docs for a table (purpose, columns, relationships, scenarios) |
| `query_table` | SELECT rows with optional filters. RLS auto-scopes to your merchant |
| `insert_row` | INSERT a new row. merchant_id auto-injected by RLS |
| `update_row` | UPDATE a row by id |
| `delete_row` | DELETE a row by id (tester role only for most tables) |

## Knowledge MCP Tools

The server also exposes the `internal_knowledge` feature knowledge database as first-class MCP tools. These tools are for upstream authoring agents and downstream project agents that need accurate feature context before producing code, QA cases, proposals, decks, help docs, or frontend journey notes.

### Read Tools

These use the authenticated CRM user and the public `internal_knowledge_*` read RPCs.

| Tool | Purpose |
|------|---------|
| `get_feature_tree` | Return the active product hierarchy. Use this to discover feature slugs. |
| `search_feature_knowledge` | Full-text search over feature knowledge blocks. Use this first when the user gives a topic. |
| `get_feature_context` | Return typed blocks for one feature, optionally including child feature blocks and filters. |
| `get_related_features` | Return hierarchy and related-feature blocks for a feature. |
| `list_knowledge_type_templates` | Return expected content and quality rules for every knowledge type. |

### Upstream Authoring Tools

These require `SUPABASE_SERVICE_ROLE_KEY`. Do not set that key in normal downstream read-only project MCP configs.

| Tool | Purpose |
|------|---------|
| `suggest_block_metadata` | Recommend scopes and quality rules for a knowledge type. |
| `validate_knowledge_block` | Validate proposed title/content/type/perspectives/output uses/scope before writing. |
| `create_feature_item` | Create a domain, feature, or sub-feature item. |
| `update_feature_item` | Update or deactivate an existing feature item. |
| `create_knowledge_block` | Create a typed reusable knowledge block. |
| `update_knowledge_block` | Update or deactivate an existing knowledge block. |

### Downstream Retrieval Protocol

Every downstream project should follow this sequence before creating feature-specific output:

1. Call `search_feature_knowledge` with the user's feature/topic.
2. Pick the best matching `feature_slug`.
3. Call `get_feature_context` with filters for the output type.
4. Use the returned blocks as orientation and constraints.
5. For implementation work, verify exact tables, RPC signatures, functions, routes, and source files from live project tools before coding.

Recommended filters:

| Project type | `knowledge_types` | `perspectives` | `output_uses` / `scopes` |
|--------------|-------------------|----------------|---------------------------|
| Marketing / decks / proposals | `overview`, `value_proposition`, `related_features` | `marketing`, `sales`, `product` | `slide_generation`, `proposal_content`, `marketing_content` |
| Frontend | `configuration_reference`, `admin_journey`, `user_experience`, `business_rules`, `testing_guidance` | `frontend`, `testing`, `customer_success` | `frontend_context`; scopes `admin_fe`, `user_fe`, `general` |
| Backend / implementation | `technical_overview`, `implementation_objects`, `technical_flow`, `implementation_constraints`, `business_rules` | `technical`, `implementation`, `testing` | `implementation_brief`, `technical_docs`; scopes `be`, `integration`, `general` |
| QA / testing | `testing_guidance`, `business_rules`, `limitations` | `testing` | `qa_testing`; all relevant scopes |

Suggested downstream project rule:

```md
Before creating feature-specific output, query the CRM Knowledge MCP. Start with `search_feature_knowledge`, then call `get_feature_context` for the selected feature slug using filters for the output type. Treat `implementation_objects` and `technical_flow` blocks as pointers, then verify exact schemas, function signatures, routes, and code from live tools before coding.
```

Example frontend context call:

```json
{
  "feature_slug": "rewards",
  "knowledge_types": ["configuration_reference", "admin_journey", "user_experience", "business_rules", "testing_guidance"],
  "perspectives": ["frontend", "testing"],
  "output_uses": ["frontend_context", "qa_testing"],
  "scopes": ["admin_fe", "user_fe", "general"],
  "include_children": true
}
```

Example backend context call:

```json
{
  "feature_slug": "purchase-transactions",
  "knowledge_types": ["technical_overview", "implementation_objects", "technical_flow", "implementation_constraints", "business_rules"],
  "perspectives": ["technical", "implementation", "testing"],
  "output_uses": ["implementation_brief", "technical_docs", "agent_context"],
  "scopes": ["be", "integration", "general"],
  "include_children": true
}
```

## Permissions Summary

| Role | Read | Insert | Update | Delete |
|------|------|--------|--------|--------|
| `store_admin` | All 23 tables | — | — | — |
| `store_owner` | All 23 tables | 4 tables | 4 tables | — |
| `tester` | All 27 tables | 15 tables | 5 tables | 13 tables |

Permissions are stored in `system_mcp_role_permissions` and can be updated without redeploying the server.

## Adding New Tables to Permissions

```sql
INSERT INTO system_mcp_role_permissions
  (role_code, table_name, allow_select, allow_insert, allow_update, allow_delete, notes)
VALUES
  ('tester', 'new_table', true, true, false, false, 'New table for X feature');
```

## Adding Table Documentation

```sql
INSERT INTO system_mcp_table_context
  (table_name, purpose, key_columns, relationships, insert_notes, common_scenarios)
VALUES (
  'new_table',
  'What this table does in one paragraph.',
  '{"id": "UUID PK", "merchant_id": "Auto-scoped."}',
  '{"user_accounts": "References via user_id."}',
  'Do not pass merchant_id. Requires x and y fields.',
  '["Create a basic row: {field1, field2}"]'
);
```
