# Project Overview

This is the **CRM** project.

## Feature-Scoped Study Map

When the user's prompt specifies a particular feature (e.g., "for missions and rewards feature"), **ONLY** study the relevant components for that feature. Use this mapping:

### Missions Feature
- **Requirement Docs**: `Mission.md`
- **Database Patterns**: Tables/functions/views starting with `mission_*`, `fn_*mission*`, `trigger_mission*`, `queue_mission*`, `process_mission*`
- **Related Features**: Currency (for rewards), Forms (for condition triggers), Referral (for condition triggers)

### Rewards Feature
- **Requirement Docs**: `Reward.md`, `MCA.md` (Multi-Channel Attribution)
- **Database Patterns**: Tables/functions/views starting with `reward_*`, `redemption_*`, `promo_code_*`, `fn_*reward*`, `fn_*redemption*`
- **Related Features**: Currency (for costs), Tier (for eligibility), Tag/Persona (for targeting)

### Currency Feature
- **Requirement Docs**: `Currency.md`
- **Database Patterns**: Tables/functions/views: `wallet_ledger`, `wallet_transaction_queue`, `fn_*wallet*`, `fn_process_wallet*`, `points_*`, `tickets_*`
- **Related Features**: Missions (earn), Rewards (spend), Checkin (earn)

### Tier Feature
- **Requirement Docs**: `Tier.md`, `Tier diagram - detailed.md`
- **Database Patterns**: Tables/functions/views: `tier_master`, `tier_*`, `fn_*tier*`, `user_tier_*`
- **Related Features**: Currency (tier progress), Rewards (tier-gated), Tag/Persona (tier personas)

### Tag and Persona Feature
- **Requirement Docs**: `Tag_and_Persona.md`
- **Database Patterns**: Tables/functions/views: `persona_*`, `tag_*`, `fn_assign_persona`, `fn_assign_tag`, `user_personas`, `user_tags`
- **Related Features**: Rewards (targeting), Missions (targeting)

### Referral Feature
- **Requirement Docs**: `Referral.md`
- **Database Patterns**: Tables/functions/views: `referral_*`, `fn_*referral*`
- **Related Features**: Missions (referral conditions), Currency (referral rewards)

### Forms Feature
- **Requirement Docs**: `Forms.md`
- **Database Patterns**: Tables/functions/views: `form_*`, `fn_*form*`, `form_submissions`
- **Related Features**: Missions (form completion conditions)

### Checkin Feature
- **Requirement Docs**: `Checkin.md`
- **Database Patterns**: Tables/functions/views: `checkin_*`, `fn_*checkin*`
- **Related Features**: Currency (earn rewards), Missions (checkin conditions)

### Stored Value Card Feature
- **Requirement Docs**: `Stored_Value_Card.md`
- **Database Patterns**: Tables/functions/views: `svc_*`, `stored_value_*`, `fn_*svc*`

### Store Classification Feature
- **Requirement Docs**: `Store_Attribute_Classification.md`
- **Database Patterns**: Tables/functions/views: `store_*`, `location_*`, `partner_*`

### Consent and Communication Feature
- **Requirement Docs**: `Consent_and_Communication.md`
- **Database Patterns**: Tables/functions/views: `consent_*`, `communication_*`, `notification_*`

## Assistant Startup Instructions

**IMPORTANT**: If the user's prompt specifies a particular feature (e.g., "for missions and rewards feature"), use the Feature-Scoped Study Map above to determine which requirement docs and database patterns to study. DO NOT study all features - only study what's specified.

### When Feature is Specified (e.g., "for missions feature"):
1. Study **ONLY the Supabase database objects for that feature** via MCP:
   - Use the database patterns from the Feature-Scoped Study Map
   - Load only relevant tables, functions, views, queues, crons
   - Understand relationships only within scope (and minimal related features if needed)

2. Study **ONLY the requirement docs for that feature**:
   - Use the requirement doc list from the Feature-Scoped Study Map
   - Tie requirements back to the specific database objects

### When NO Feature is Specified (full project analysis):
1. Study the **entire Supabase database** CRM project via MCP:
   - Load all tables, schema definitions, and functions
   - Study all edge functions, queues, crons
   - Understand how all tables relate (FKs, ledgers, masters)

2. Study **all business requirement docs** in `/requirements/` folder:
   - Tie requirements back to actual database tables and functions

### Safety Rule (Always Apply):
- You may automatically run **read-only queries** (SELECT).
- For any CREATE, ALTER, UPDATE, DELETE, or function modifications:
  - **Do not run automatically.**
  - Present changes **in chat** with descriptive explanation of what will change and why.
  - Only show raw SQL/code if you need it for actual implementation steps.
  - Only create migration files if they're useful for your implementation workflow.
  - Await explicit approval before executing.  

## Goal
Maintain a clear mapping between business requirements and the actual Supabase implementation in order to perform coding and architectural design tasks that need the complete context of the project.

## Response Style

- Always respond as if you are a **seasoned Principal Engineer** explaining to a **non-technical stakeholder** who needs to understand the logic and reasoning.
- **FOCUS ON LOGIC DESCRIPTIONS**: Explain the detailed logic, data flow, and algorithmic reasoning - not business fluff or marketing language.
- **Code is for AI execution only**: 
  1. **Default to NO code**: Don't include code/SQL unless you (the AI) need it for later execution via MCP tools.
  2. **User is not a developer**: The user will NOT be reading or implementing code themselves.
  3. **When code is needed**: Only include it when YOU need to execute it later (e.g., queries to analyze data, functions to call).
  4. **Explain the logic instead**: Describe what the system would do step-by-step, like explaining an algorithm or flowchart in words.
- **Logic-focused explanations should include**:
  - How data flows through the system
  - What conditions trigger what actions  
  - How different components interact
  - What calculations or transformations occur
  - Decision trees and branching logic
  - Specific examples with real data scenarios
- **Avoid both extremes**: Not too technical (no code dumps), but not too high-level (no fluffy business speak).
- Think of it as **explaining a complex flowchart or algorithm in detailed prose** - precise, logical, but accessible.

## Primary Purpose and Workflow

- The assistant's **primary purpose** is to study and analyze this project.  
- Default mode = **analysis, explanation, and ideas**, not code generation.  
- Only proceed to code creation, migrations, or structural changes if I give **explicit go-ahead**.  
- Never assume I want new project scaffolding or setup tasks.  
- Always start by:
  1. Reading rules and requirements.
  2. Analyzing Supabase schema/functions via MCP.
  3. Producing insights, mappings, and design ideas.
- Creation work (SQL migrations, app code, etc.) should follow only after explicit human approval.

## Production Environment Rule

- This is a **production project**.  
- Do **not** make schema changes, create or edit functions, or run any modifying queries unless I explicitly instruct you.  
- All actions should be treated as read-only, analytical, or advisory by default.  
- Be extremely careful in recommendations: always explain risks, trade-offs, and safety considerations.  
- Any code or SQL you generate must be presented as **review-only output**, not executed automatically.  
- For any proposed change (e.g., new tables, RLS policies, migrations):
  - **Present in chat** describing what will change and business impact.
  - Show raw code only if needed for implementation.
  - Create files only if useful for implementation workflow.
  - Await explicit approval before considering execution.

## Database Object Naming Conventions

All database views and materialized views must follow strict naming conventions for clarity:

### Views (Real-time data):
- **`v_`** prefix for regular views - Always current, computed on-demand
  - Example: `v_reward_promo_code_list` (shows individual promo codes)
  - Example: `v_wallet_queue_status` (monitors queue status)

### Materialized Views (Pre-computed data):  
- **`mv_`** prefix for materialized views - Cached data, requires refresh
  - Example: `mv_reward_promo_code_summary_internal` (aggregated summaries)
  - Example: `mv_earn_factors_complete` (pre-computed earn factors)

### Special Backend-for-Frontend Views:
- **`bff_`** prefix for API-oriented views that enrich data for frontend consumption
  - Example: `bff_earn_conditions` (enriches conditions with entity names)

### When to Use Each Type:

**Use Regular Views (`v_`)** when:
- Need real-time, always current data
- Performing simple JOINs and lookups
- Data changes frequently (e.g., redemption status)
- No heavy aggregations needed

**Use Materialized Views (`mv_`)** when:
- Heavy aggregations (COUNT, SUM, GROUP BY)
- Complex calculations across large datasets
- Data changes infrequently
- Slight staleness is acceptable
- Performance is critical

### Security Note:
All views inherit Row Level Security (RLS) from their underlying tables. Views that access sensitive data must either:
1. Query tables with proper RLS policies that use `get_current_merchant_id()`
2. Use SECURITY DEFINER functions that extract merchant context from auth tokens

Never create views that bypass merchant isolation unless explicitly required for cross-merchant analytics.

## Row Level Security (RLS) Methodology

### Core Principle
**Every table MUST have RLS policies that filter data by merchant_id extracted from the access token**, ensuring complete merchant isolation.

### Standard RLS Implementation Pattern

For any table containing merchant-specific data, implement these policies:

```sql
-- 1. Enable RLS on the table
ALTER TABLE table_name ENABLE ROW LEVEL SECURITY;

-- 2. Policy for anon users with merchant context (WeWeb integration)
CREATE POLICY "Anon with merchant context can view"
    ON table_name
    FOR SELECT
    TO anon
    USING (
        merchant_id = get_current_merchant_id() 
        AND get_current_merchant_id() IS NOT NULL
    );

-- 3. Policy for authenticated users
CREATE POLICY "Authenticated users can view their merchant data"
    ON table_name
    FOR SELECT
    TO public
    USING (merchant_id = get_current_merchant_id());

-- 4. Service role bypass (for internal operations)
CREATE POLICY "Service role has full access"
    ON table_name
    FOR ALL
    TO public
    USING (auth.role() = 'service_role'::text);
```

### The `get_current_merchant_id()` Function
This critical function extracts merchant_id from multiple sources in priority order:
1. **Custom header** `x-merchant-id` (for WeWeb)
2. **JWT claims** `merchant_id` field
3. **Admin lookup** via `admin_users` table using `auth.uid()`
4. **User lookup** via `user_accounts` table using `auth.uid()`

### Implementation Requirements
- **All tables** with `merchant_id` column MUST have RLS enabled
- **All policies** MUST use `get_current_merchant_id()` for merchant filtering
- **Views** automatically inherit RLS from underlying tables
- **Materialized views** cannot have RLS directly - use SECURITY DEFINER wrapper functions
- **Test with WeWeb** to ensure policies work with their auth token integration

### Examples of Tables with Proper RLS
- `tier_master` - Successfully filters tiers by merchant
- `persona_group_master` - Filters persona groups by merchant
- `reward_master` - Filters rewards by merchant
- `reward_promo_code` - Filters promo codes by merchant
- `partner_merchant` - Filters partners by merchant
- `reward_redemptions_ledger` - Filters redemptions by merchant

### Never Allow
- Public read policies without merchant filtering
- Hardcoded merchant_id values in policies
- Views that bypass merchant isolation
- Direct table access without RLS






























