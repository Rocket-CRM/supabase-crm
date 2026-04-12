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
      "args": ["/Users/rangwan/Documents/Supabase CRM/mcp-crm-server/dist/index.js"],
      "env": {
        "SUPABASE_URL": "https://wkevmsedchftztoolkmi.supabase.co",
        "SUPABASE_ANON_KEY": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndrZXZtc2VkY2hmdHp0b29sa21pIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTA1MTM2OTgsImV4cCI6MjA2NjA4OTY5OH0.bd8ELGtX8ACmk_WCxR_tIFljwyHgD3YD4PdBDpD-kSM",
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
      "args": ["/Users/rangwan/Documents/Supabase CRM/mcp-crm-server/dist/index.js"],
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
