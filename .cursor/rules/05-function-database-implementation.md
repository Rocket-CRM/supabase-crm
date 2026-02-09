# Supabase CRM - Function & Database Implementation Rules

## Function Creation Guidelines

### Merchant Context Pattern
**CRITICAL**: All public API functions must automatically determine merchant context from authentication, never require explicit merchant_id parameter.

**Standard Pattern:**
```sql
CREATE OR REPLACE FUNCTION your_function_name()
RETURNS JSON
SECURITY DEFINER
LANGUAGE plpgsql
AS $$
DECLARE
    v_merchant_id UUID;
    v_result JSON;
BEGIN
    -- Get merchant_id using standard helper (same as all other functions)
    v_merchant_id := get_current_merchant_id();
    
    -- Return empty result if no merchant context
    IF v_merchant_id IS NULL THEN
        RETURN '[]'::json;
    END IF;

    -- Your business logic here using v_merchant_id
    SELECT json_agg(...) INTO v_result
    FROM your_tables
    WHERE merchant_id = v_merchant_id;

    RETURN COALESCE(v_result, '[]'::json);
END;
$$;
```

**DO NOT:**
- Create functions requiring explicit `merchant_id` parameters
- Create multiple wrapper functions with different parameter combinations
- Bypass the standard `get_current_merchant_id()` pattern

### Function Creation Philosophy

**Single Function Focus:**
- Create **ONE function** that addresses the specific requirement
- Do NOT create multiple convenience wrappers unless explicitly requested
- Avoid redundant functions that create maintenance overhead

### Authentication Hierarchy

The `get_current_merchant_id()` function checks sources in this order:
1. **Custom Header** (`x-merchant-id`) - for WeWeb integration
2. **JWT Claims** (`merchant_id` claim) - direct merchant tokens  
3. **Admin Users** (`admin_users.auth_user_id = auth.uid()`) - admin authentication
4. **End Users** (`user_accounts.id = auth.uid()`) - regular user authentication

This pattern ensures compatibility with all authentication methods in the system.

## Database Naming Conventions

### Core Table Naming Pattern

**Pattern**: `<domain>_<type>_<description>`

Tables of the same type should have the type category early in the name, followed by their specific description. This ensures related tables group together alphabetically.

### Table Type Categories

Common type categories that should appear after the domain:

- **`conditions`** - Rules, requirements, criteria
- **`log`** - Audit trails, historical records  
- **`limit`** - Restrictions, caps, boundaries
- **`progress`** - State tracking, user progress
- **`queue`** - Processing queues, batch jobs
- **`outcomes`** - Results, rewards, consequences
- **`config`** - Configuration, settings

### Examples Across Domains

#### Mission Domain
- `mission` - Primary entity
- `mission_conditions` - What users must do
- `mission_limit_progress` - Completion restrictions
- `mission_limit_claim` - Claim restrictions
- `mission_log_completion` - Completion audit
- `mission_log_outcome_distribution` - Distribution audit
- `mission_progress` - User state tracking

#### Wallet Domain
- `wallet` - Primary entity
- `wallet_ledger` - Core transactions
- `wallet_limit_daily` - Daily transaction limits
- `wallet_limit_withdrawal` - Withdrawal restrictions
- `wallet_log_transaction` - Transaction audit
- `wallet_log_adjustment` - Manual adjustment audit

#### Reward Domain
- `reward` - Primary entity
- `reward_conditions` - Eligibility rules
- `reward_limit_redemption` - Redemption caps
- `reward_log_redemption` - Redemption history
- `reward_queue_distribution` - Pending distributions

### Materialized Views
- **Pattern**: `mv_<domain>_<purpose>`
- Example: `mv_mission_conditions_expanded`

### Benefits of This Convention

1. **Alphabetical Grouping**: All `mission_log_*` tables appear together, all `mission_limit_*` tables appear together
2. **Clear Purpose**: The type category immediately indicates the table's role
3. **Consistent Pattern**: Easy to predict table names across all domains
4. **Scalability**: New domains follow the same pattern

### Index Naming Convention

- Primary keys: `<table_name>_pkey`
- Foreign keys: `<table_name>_<column_name>_fkey`
- Unique constraints: `<table_name>_<columns>_key`
- Regular indexes: `idx_<table_name>_<column(s)>`

### Constraint Naming Convention

- Foreign key constraints: `fk_<table_name>_<referenced_table>`
- Check constraints: `chk_<table_name>_<constraint_purpose>`
- Unique constraints: `uq_<table_name>_<columns>`

## Function Naming Conventions

### Patterns

- **Public API functions**: Simple action verbs (e.g., `accept_mission`, `claim_rewards`)
- **Internal functions**: Prefix with `fn_` (e.g., `fn_evaluate_mission_conditions`)
- **Trigger functions**: Prefix with `trigger_` (e.g., `trigger_mission_evaluation_realtime`)
- **Batch processing**: Include `batch` or `queue` (e.g., `process_mission_evaluation_batch`)

## Column Naming Conventions

- Use `snake_case` for all column names
- Boolean columns: Prefix with `is_`, `has_`, or `can_` (e.g., `is_active`, `has_claimed`)
- Timestamps: Suffix with `_at` (e.g., `created_at`, `completed_at`)
- Foreign keys: Suffix with `_id` (e.g., `user_id`, `mission_id`)
- Counts/amounts: Clear descriptive names (e.g., `lifetime_completions`, `period_claims`)

## Enum Naming Conventions

- Use `snake_case` for enum types
- Prefix with the domain (e.g., `mission_type`, `mission_condition_type`)
- Values in lowercase with underscores (e.g., `'standard'`, `'all_time'`)

## Migration File Naming

- Format: `XX_<action>_<target>.sql`
- Examples:
  - `01_create_mission_tables.sql`
  - `02_add_reset_mode_to_missions.sql`
  - `03_rename_limit_tables.sql`

## General Principles

1. **Consistency Over Creativity**: Follow established patterns
2. **Clarity Over Brevity**: Full words preferred over abbreviations
3. **Grouping Over Isolation**: Related items should be grouped by naming
4. **Simplicity Over Complexity**: Avoid over-engineering schemas
5. **Documentation**: Comment complex logic and business rules in the database

## Security Patterns

### Row Level Security (RLS)
- All merchant data tables must have RLS enabled
- Use merchant_id filtering in policies
- Support both authenticated and anon roles where appropriate

### Function Security
- All public functions use `SECURITY DEFINER`
- Internal helper functions use `SECURITY INVOKER`
- Grant appropriate permissions to authenticated/anon roles

## References

- For detailed mission system architecture, see `/requirements/Mission.md`
- For tier system design, see `/requirements/Tier.md`
- For currency system, see `/requirements/Currency.md`






























