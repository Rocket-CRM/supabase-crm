# Custom Reward Scripts System

## Overview

Custom reward scripts are merchant-specific, one-off reward logic that is too complex or specialized to fit into the standard `earn_factor` rule engine. These scripts handle unique business requirements that vary significantly between merchants and cannot be standardized into configurable rules.

## Purpose

**Standard System (`earn_factor`):**
- Handles common, repeatable reward patterns
- Configurable through UI/database
- Examples: "100 THB = 1 point", "5x multiplier on SKU X"

**Custom Scripts:**
- Handles merchant-specific, complex requirements
- Implemented as custom code (SQL functions or Edge Functions)
- Examples: 
  - Quarterly purchase volume bonuses with multiple conditions
  - POSM display verification + monthly purchase threshold
  - Complex multi-criteria seasonal promotions
  - Third-party API integrations for validation

## Key Principles

1. **Not a Duplicate System**: Custom scripts are for truly unique requirements that cannot be expressed through the standard earn_factor configuration
2. **Execution Management Only**: If using a registry table, it only manages when/how to run scripts, not the business logic itself
3. **Proper Integration**: Scripts must write to `currency_earned_ledger` to integrate with the existing event-driven system
4. **Merchant Isolation**: Each merchant's scripts are independent and cannot affect other merchants

---

## Architecture

### Storage Pattern

**Schema:** `custom_function`

**Naming Convention:** `custom_function.{merchant_slug}_{purpose}`

**Examples:**
```sql
custom_function.ajinomoto_quarterly_bonus
custom_function.ajinomoto_posm_activity
custom_function.unilever_monthly_volume
custom_function.nestle_referral_bonus
```

### Implementation Options

#### Option 1: Functions Only (Recommended for Simple Needs)

**When to use:**
- Manual execution is acceptable
- Config rarely changes
- No need for execution history
- No need for UI management

**Implementation:**
```sql
-- Just create the function
CREATE FUNCTION custom_function.ajinomoto_quarterly_bonus(
  p_merchant_id UUID,
  p_execution_id UUID,
  p_config JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Custom logic here
  -- Writes to currency_earned_ledger
  -- Returns summary
END;
$$;

-- Execute manually when needed
SELECT custom_function.ajinomoto_quarterly_bonus(
  '99e456a2-107c-48c5-a12d-2b8b8b85aa2d',
  gen_random_uuid(),
  '{"threshold": 50000, "bonus_rate": 0.01}'::jsonb
);
```

#### Option 2: Registry + Functions (For Automation)

**When to use:**
- Automatic scheduling needed (cron-based execution)
- Enable/disable without code changes
- Execution audit trail required
- UI for script management
- Dynamic configuration changes

**Schema:**
```sql
CREATE TABLE custom_reward_scripts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id UUID REFERENCES merchant_master(id),
  
  -- Script identification
  script_name TEXT NOT NULL,
  description TEXT,
  
  -- Execution management
  script_type TEXT CHECK (script_type IN ('scheduled', 'manual')),
  schedule_cron TEXT, -- e.g., '0 0 1 */3 *' for quarterly
  active_status BOOLEAN DEFAULT true,
  
  -- Script location
  function_name TEXT, -- e.g., 'custom_function.ajinomoto_quarterly_bonus'
  edge_function_path TEXT, -- Alternative: path to Edge Function
  
  -- Flexible configuration (opaque to system, used by script)
  config JSONB,
  
  -- Execution tracking
  last_run_at TIMESTAMPTZ,
  last_run_status TEXT,
  next_run_at TIMESTAMPTZ,
  
  -- Audit
  created_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID,
  
  CONSTRAINT check_script_location CHECK (
    (function_name IS NOT NULL AND edge_function_path IS NULL) OR
    (function_name IS NULL AND edge_function_path IS NOT NULL)
  )
);

CREATE TABLE custom_reward_executions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  script_id UUID REFERENCES custom_reward_scripts(id),
  started_at TIMESTAMPTZ DEFAULT NOW(),
  completed_at TIMESTAMPTZ,
  status TEXT CHECK (status IN ('running', 'completed', 'failed')),
  result_summary JSONB,
  error_message TEXT
);
```

---

## Integration with Currency System

### Required Flow

All custom scripts **must** follow this pattern to integrate properly:

```sql
CREATE FUNCTION custom_function.merchant_script(...)
RETURNS JSONB AS $$
DECLARE
  v_execution_id UUID := p_execution_id;
BEGIN
  -- 1. Query/calculate who qualifies
  FOR v_user IN 
    SELECT user_id, calculated_amount
    FROM ...
    WHERE ... -- Custom conditions
  LOOP
    -- 2. Write to currency_earned_ledger (NOT direct to balance!)
    INSERT INTO currency_earned_ledger (
      user_id,
      merchant_id,
      currency_type,
      amount,
      source_type,
      source_id,
      metadata
    ) VALUES (
      v_user.user_id,
      p_merchant_id,
      'points', -- or 'tickets', etc.
      v_user.calculated_amount,
      'custom_script',
      v_execution_id,
      jsonb_build_object(
        'script_name', 'merchant_script',
        'execution_date', NOW(),
        'criteria_met', v_user.criteria_details
      )
    );
  END LOOP;
  
  -- 3. Return execution summary
  RETURN jsonb_build_object(
    'status', 'completed',
    'users_processed', ...,
    'points_awarded', ...
  );
END;
$$;
```

**Why this matters:**
- ✅ Existing triggers/events handle balance updates
- ✅ Full audit trail in ledgers
- ✅ Expiry rules apply automatically
- ✅ Notifications sent through standard system
- ✅ Can be reversed if needed

### DO NOT:
```sql
-- ❌ WRONG: Direct balance manipulation
UPDATE user_currency_balance 
SET balance = balance + 1000 
WHERE user_id = '...';

-- ✅ CORRECT: Write to ledger
INSERT INTO currency_earned_ledger (...) VALUES (...);
```

---

## Use Cases

### Case 1: Quarterly Volume Bonus (Ajinomoto)

**Requirement:**
- At end of each calendar quarter
- Users who purchased ≥50,000 THB in the quarter
- Must have ≥10 separate purchase transactions
- Award 1% of total quarterly spend as bonus points
- Cap at 5,000 bonus points per user

**Implementation:**
```sql
CREATE FUNCTION custom_function.ajinomoto_quarterly_bonus(
  p_merchant_id UUID,
  p_execution_id UUID,
  p_config JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_quarter_start DATE;
  v_quarter_end DATE;
  v_threshold NUMERIC;
  v_min_visits INT;
  v_bonus_rate NUMERIC;
  v_max_bonus INT;
  v_user RECORD;
  v_bonus_points INT;
  v_users_awarded INT := 0;
  v_total_points INT := 0;
BEGIN
  -- Extract config
  v_quarter_start := (p_config->>'quarter_start')::date;
  v_quarter_end := (p_config->>'quarter_end')::date;
  v_threshold := (p_config->>'threshold')::numeric;
  v_min_visits := (p_config->>'min_visits')::int;
  v_bonus_rate := (p_config->>'bonus_rate')::numeric;
  v_max_bonus := (p_config->>'max_bonus_per_user')::int;
  
  -- Find qualified users
  FOR v_user IN
    SELECT 
      user_id,
      SUM(final_amount) as total_spent,
      COUNT(DISTINCT id) as visit_count
    FROM public.purchase_ledger
    WHERE merchant_id = p_merchant_id
      AND created_at >= v_quarter_start
      AND created_at < v_quarter_end + INTERVAL '1 day'
    GROUP BY user_id
    HAVING SUM(final_amount) >= v_threshold
       AND COUNT(DISTINCT id) >= v_min_visits
  LOOP
    -- Calculate bonus (1% of spend, capped)
    v_bonus_points := LEAST(
      FLOOR(v_user.total_spent * v_bonus_rate)::INT,
      v_max_bonus
    );
    
    -- Award via ledger
    INSERT INTO public.currency_earned_ledger (
      user_id,
      merchant_id,
      currency_type,
      amount,
      source_type,
      source_id,
      metadata
    ) VALUES (
      v_user.user_id,
      p_merchant_id,
      'points',
      v_bonus_points,
      'custom_script',
      p_execution_id,
      jsonb_build_object(
        'script_name', 'ajinomoto_quarterly_bonus',
        'quarter_start', v_quarter_start,
        'quarter_end', v_quarter_end,
        'total_spent', v_user.total_spent,
        'visit_count', v_user.visit_count,
        'bonus_rate', v_bonus_rate
      )
    );
    
    v_users_awarded := v_users_awarded + 1;
    v_total_points := v_total_points + v_bonus_points;
  END LOOP;
  
  RETURN jsonb_build_object(
    'status', 'completed',
    'quarter', v_quarter_start::text,
    'users_qualified', v_users_awarded,
    'total_points_awarded', v_total_points,
    'execution_date', NOW()
  );
END;
$$;
```

**Execution:**
```sql
-- Manual execution at end of Q1 2024
SELECT custom_function.ajinomoto_quarterly_bonus(
  '99e456a2-107c-48c5-a12d-2b8b8b85aa2d', -- merchant_id
  gen_random_uuid(), -- execution_id
  '{
    "quarter_start": "2024-01-01",
    "quarter_end": "2024-03-31",
    "threshold": 50000,
    "min_visits": 10,
    "bonus_rate": 0.01,
    "max_bonus_per_user": 5000
  }'::jsonb
);
```

---

### Case 2: POSM Activity + Monthly Purchase (Ajinomoto)

**Requirement:**
- Check if user uploaded POSM display photo in current month
- Verify `display_size` parameter in upload metadata
- User must have ≥20,000 THB purchases in same month
- Award 500 tickets (not points)

**Implementation:**
```sql
CREATE FUNCTION custom_function.ajinomoto_posm_activity(
  p_merchant_id UUID,
  p_execution_id UUID,
  p_config JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_month_start DATE;
  v_month_end DATE;
  v_min_purchase NUMERIC;
  v_required_display_size TEXT;
  v_ticket_award INT;
  v_user RECORD;
  v_users_awarded INT := 0;
BEGIN
  -- Extract config
  v_month_start := (p_config->>'month_start')::date;
  v_month_end := (p_config->>'month_end')::date;
  v_min_purchase := (p_config->>'min_purchase')::numeric;
  v_required_display_size := p_config->>'required_display_size';
  v_ticket_award := (p_config->>'ticket_award')::int;
  
  -- Find users who meet both criteria
  FOR v_user IN
    WITH posm_uploads AS (
      SELECT DISTINCT user_id
      FROM public.upload_activity_ledger -- Assume this table exists
      WHERE merchant_id = p_merchant_id
        AND upload_type = 'posm_display'
        AND created_at >= v_month_start
        AND created_at < v_month_end + INTERVAL '1 day'
        AND metadata->>'display_size' = v_required_display_size
    ),
    monthly_purchases AS (
      SELECT 
        user_id,
        SUM(final_amount) as total_spent
      FROM public.purchase_ledger
      WHERE merchant_id = p_merchant_id
        AND created_at >= v_month_start
        AND created_at < v_month_end + INTERVAL '1 day'
      GROUP BY user_id
      HAVING SUM(final_amount) >= v_min_purchase
    )
    SELECT 
      mp.user_id,
      mp.total_spent
    FROM monthly_purchases mp
    INNER JOIN posm_uploads pu ON mp.user_id = pu.user_id
  LOOP
    -- Award tickets
    INSERT INTO public.currency_earned_ledger (
      user_id,
      merchant_id,
      currency_type,
      amount,
      source_type,
      source_id,
      metadata
    ) VALUES (
      v_user.user_id,
      p_merchant_id,
      'tickets',
      v_ticket_award,
      'custom_script',
      p_execution_id,
      jsonb_build_object(
        'script_name', 'ajinomoto_posm_activity',
        'month', v_month_start,
        'display_size', v_required_display_size,
        'monthly_spent', v_user.total_spent
      )
    );
    
    v_users_awarded := v_users_awarded + 1;
  END LOOP;
  
  RETURN jsonb_build_object(
    'status', 'completed',
    'month', v_month_start::text,
    'users_qualified', v_users_awarded,
    'total_tickets_awarded', v_users_awarded * v_ticket_award
  );
END;
$$;
```

---

## Function Signature Standard

All custom reward functions should follow this signature:

```sql
CREATE FUNCTION custom_function.{merchant}_{purpose}(
  p_merchant_id UUID,      -- Required: Which merchant
  p_execution_id UUID,     -- Required: Unique ID for this run
  p_config JSONB           -- Required: Script-specific parameters
)
RETURNS JSONB              -- Required: Execution summary
LANGUAGE plpgsql
SECURITY DEFINER           -- Recommended: Bypass RLS
AS $$
BEGIN
  -- Script logic
  RETURN jsonb_build_object(
    'status', 'completed',
    'users_processed', ...,
    'points_awarded', ...
  );
END;
$$;
```

**Standard return fields:**
- `status`: 'completed' | 'failed' | 'partial'
- `users_processed`: Integer count
- `points_awarded` / `tickets_awarded`: Total currency awarded
- Additional context as needed

---

## Shared Helper Functions

Create reusable utilities for common operations:

```sql
-- Schema for shared helpers
CREATE SCHEMA IF NOT EXISTS custom_function_helpers;

-- Award currency helper
CREATE FUNCTION custom_function_helpers.award_currency(
  p_user_id UUID,
  p_merchant_id UUID,
  p_currency_type currency,
  p_amount INT,
  p_execution_id UUID,
  p_metadata JSONB
)
RETURNS VOID
LANGUAGE sql
AS $$
  INSERT INTO public.currency_earned_ledger (
    user_id, merchant_id, currency_type, amount,
    source_type, source_id, metadata
  ) VALUES (
    p_user_id, p_merchant_id, p_currency_type, p_amount,
    'custom_script', p_execution_id, p_metadata
  );
$$;

-- Get period purchases helper
CREATE FUNCTION custom_function_helpers.get_period_purchases(
  p_merchant_id UUID,
  p_start_date DATE,
  p_end_date DATE
)
RETURNS TABLE(
  user_id UUID,
  total_spent NUMERIC,
  transaction_count INT
)
LANGUAGE sql
AS $$
  SELECT 
    user_id,
    SUM(final_amount) as total_spent,
    COUNT(*) as transaction_count
  FROM public.purchase_ledger
  WHERE merchant_id = p_merchant_id
    AND created_at >= p_start_date
    AND created_at < p_end_date + INTERVAL '1 day'
  GROUP BY user_id;
$$;
```

**Usage in custom functions:**
```sql
-- Use helpers to simplify logic
SELECT custom_function_helpers.award_currency(
  v_user.id, p_merchant_id, 'points', v_bonus, p_execution_id, v_metadata
);
```

---

## Best Practices

### 1. Idempotency
Prevent double-awarding by checking execution history:
```sql
-- Check if already executed for this period
IF EXISTS (
  SELECT 1 FROM custom_reward_executions
  WHERE script_id = ...
    AND status = 'completed'
    AND result_summary->>'quarter' = v_quarter
) THEN
  RAISE EXCEPTION 'Script already executed for this period';
END IF;
```

### 2. Dry Run Mode
Support testing without actually awarding:
```sql
v_dry_run := COALESCE((p_config->>'dry_run')::boolean, false);

IF NOT v_dry_run THEN
  INSERT INTO currency_earned_ledger (...) VALUES (...);
END IF;
```

### 3. Error Handling
Wrap in transaction and log errors:
```sql
BEGIN
  -- Script logic
EXCEPTION WHEN OTHERS THEN
  -- Log error
  INSERT INTO custom_reward_executions (
    script_id, status, error_message
  ) VALUES (
    ..., 'failed', SQLERRM
  );
  RAISE;
END;
```

### 4. Performance
For large datasets, batch process:
```sql
-- Process in batches of 1000
FOR v_batch IN
  SELECT array_agg(user_id) as user_ids
  FROM (
    SELECT user_id, ROW_NUMBER() OVER () as rn
    FROM qualified_users
  ) sub
  GROUP BY FLOOR((rn - 1) / 1000)
LOOP
  -- Process batch
END LOOP;
```

### 5. Documentation
Always comment functions:
```sql
COMMENT ON FUNCTION custom_function.ajinomoto_quarterly_bonus IS 
'Ajinomoto Quarterly Volume Bonus
Awards 1% of quarterly spend as bonus points to users who:
- Spent ≥50,000 THB in the quarter
- Made ≥10 separate purchases
- Cap: 5,000 points per user

Run at end of each quarter.
Merchant: Ajinomoto (99e456a2-107c-48c5-a12d-2b8b8b85aa2d)';
```

---

## Testing Custom Scripts

### Test Execution
```sql
-- Test with small config
SELECT custom_function.ajinomoto_quarterly_bonus(
  '99e456a2-107c-48c5-a12d-2b8b8b85aa2d',
  gen_random_uuid(),
  '{
    "quarter_start": "2024-01-01",
    "quarter_end": "2024-03-31",
    "threshold": 1000,
    "min_visits": 1,
    "bonus_rate": 0.01,
    "max_bonus_per_user": 100,
    "dry_run": true
  }'::jsonb
);
```

### Verify Results
```sql
-- Check ledger entries
SELECT 
  user_id,
  amount,
  metadata
FROM currency_earned_ledger
WHERE source_id = '{execution_id}'
  AND source_type = 'custom_script';
```

---

## Security Considerations

1. **`SECURITY DEFINER`**: Functions run with creator's permissions, bypassing RLS
2. **Validate merchant_id**: Always verify merchant_id parameter matches expected merchant
3. **Input validation**: Validate all config parameters before use
4. **Audit trail**: Always include detailed metadata for audit purposes
5. **Permissions**: Grant execute permission only to authorized roles

```sql
-- Restrict execution
REVOKE ALL ON FUNCTION custom_function.ajinomoto_quarterly_bonus FROM PUBLIC;
GRANT EXECUTE ON FUNCTION custom_function.ajinomoto_quarterly_bonus TO admin_role;
```

---

## Migration Template

```sql
-- Migration: {date}_custom_function_{merchant}_{purpose}.sql

-- Create schema (if first custom function)
CREATE SCHEMA IF NOT EXISTS custom_function;

-- Create the custom function
CREATE OR REPLACE FUNCTION custom_function.{merchant}_{purpose}(
  p_merchant_id UUID,
  p_execution_id UUID,
  p_config JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Implementation
END;
$$;

-- Add comment
COMMENT ON FUNCTION custom_function.{merchant}_{purpose} IS 
'{Description of what this script does and when to run it}';

-- Optional: Create registry entry
INSERT INTO custom_reward_scripts (
  merchant_id,
  script_name,
  function_name,
  config,
  script_type
) VALUES (
  '{merchant_id}',
  '{Script Display Name}',
  'custom_function.{merchant}_{purpose}',
  '{default_config}'::jsonb,
  'manual'
);
```

---

## Future Enhancements

### Phase 1 (Current)
- ✅ Manual execution of custom functions
- ✅ Integration with currency_earned_ledger

### Phase 2 (If Needed)
- Registry table for execution management
- Automatic scheduling via cron
- Admin UI for script management
- Execution history dashboard

### Phase 3 (Advanced)
- Edge Function support for external API calls
- Multi-merchant script templates
- A/B testing framework for reward experiments
- Real-time execution monitoring

---

## Decision Log

### Why Not Extend earn_factor?
- Merchant requirements are too diverse and change frequently
- Would make earn_factor table/logic overly complex
- Custom scripts need full programming flexibility (loops, external APIs, complex calculations)
- Separation of concerns: Standard vs. Custom

### Why custom_function Schema?
- Clear namespace separation from standard system
- Easy to identify custom merchant logic
- Can apply different permissions/access controls

### Why JSONB Config?
- Each script has unique parameters
- Avoid rigid schema that limits flexibility
- Easy to version config changes
- Scripts self-document required parameters

### Why Integrate via Ledger?
- Maintains audit trail
- Triggers existing event processing
- Enables rollback if needed
- Consistent with standard reward flow

---

## Contact & Governance

**Before Creating Custom Script:**
1. Confirm requirement cannot be met with standard system
2. Document business logic and acceptance criteria
3. Get merchant approval on behavior and frequency
4. Code review by senior developer
5. Test with dry-run mode
6. Monitor first execution closely

**Ownership:**
- Merchant requests custom script
- Development team implements and maintains
- Scripts are merchant-specific (not shared between merchants)
