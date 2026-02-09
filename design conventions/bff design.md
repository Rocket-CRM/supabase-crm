# Backend-for-Frontend (BFF) Design Conventions

This document outlines the design patterns and conventions for creating backend functions and views that serve frontend applications.

## BFF Upsert Functions

Backend-for-frontend upsert functions are designed to handle complex create/update operations for parent entities with nested children in a single atomic transaction.

### Function Signature Pattern

Use **individual parameters** for clarity and ease of use, not a single JSONB parameter. Each parameter should have a `p_` prefix to distinguish it as a parameter.

**Parameter structure:**
- Parent ID (uuid) - null for create, UUID for update
- Required parent fields (text, enums, etc.)
- Optional parent fields
- Children array (jsonb)

**Rationale:**
- Individual parameters are more explicit and match common codebase patterns
- Easier to use from WeWeb and other frontends (no need to wrap in single object)
- Parameters must match exactly (including `p_` prefix) when calling from frontend
- Consistent with other functions in the codebase

### Parent Entity Handling

The function determines whether to create or update the parent entity based on whether the parent ID parameter is null or provided:

**Create flow (when ID is null):**
- Generate new UUID for parent
- Insert parent record with merchant context
- Set created flag

**Update flow (when ID is provided):**
- Update existing parent record
- Filter by both ID and merchant_id for security
- Verify record exists and belongs to merchant
- Return error if not found
- Set updated flag

### Child Entity Handling (CRITICAL PATTERN)

**Always use update-by-ID pattern, NEVER delete-and-recreate.**

The function processes each child in the array and determines whether to update existing or create new based on the presence of an `id` field in the child object.

**Processing steps:**
1. Initialize tracking array to store IDs of children we want to keep
2. Loop through each child in the jsonb array
3. Extract only needed fields (ignore redundant fields from frontend)
4. Validate required fields, skip invalid children
5. Check if child has `id` field:
   - **If ID exists:** Update the existing child record, preserve the ID, add to tracking array
   - **If no ID:** Create new child with generated UUID, add to tracking array
6. After processing all children, delete any children belonging to parent that are NOT in tracking array
7. Track counts: created, updated, deleted, skipped

**Why this pattern is critical:**
- Preserves child IDs when updating (prevents breaking references)
- Other entities may reference these child IDs (e.g., users assigned to personas, stores linked to set members)
- UI state may track these IDs for selection, display, or navigation
- Audit logs and history depend on stable IDs
- Delete-and-recreate breaks all existing relationships and assignments

**BAD PATTERN (Never use):**
- Deleting all children first, then recreating from payload
- This breaks all references and changes all IDs
- User assignments, store links, and other relationships will be lost

### Response Format

Return comprehensive JSONB response with operation details:

**Response structure:**
- `success` (boolean) - operation succeeded or failed
- `parent_id` (uuid) - ID of created/updated parent
- `parent_created` (boolean) - whether parent was created
- `parent_updated` (boolean) - whether parent was updated
- `children_created` (integer) - count of new children
- `children_updated` (integer) - count of updated children
- `children_deleted` (integer) - count of deleted children
- `children_skipped` (integer) - count of invalid/skipped children
- `message` (text) - human-readable summary
- `error` (text) - error message if failed

This comprehensive response allows the frontend to show detailed feedback to users and handle different scenarios appropriately.

### Security and Merchant Context

**Merchant isolation:**
- Always extract merchant_id from context using `get_current_merchant_id()` function
- Validate merchant context exists before proceeding
- Filter all queries by merchant_id to ensure data isolation
- Return error if no merchant context found

**Function security:**
- Use `SECURITY DEFINER` to allow RLS bypass
- All merchant filtering must be explicit in function logic
- Never trust merchant_id from parameters - always use context
- Validate parent entity belongs to merchant before updating

### Frontend Integration Patterns

**Parameter naming:**
- Frontend must use exact parameter names including `p_` prefix
- WeWeb "Call a Postgres function" requires matching keys

**Handling undefined/null values:**
- Convert JavaScript `undefined` to `null` explicitly
- Use `value || null` or ternary operator for optional fields
- Empty strings may need conversion to null depending on validation

**Sending child arrays:**
- Can send full objects with redundant fields (merchant_id, created_at, etc.)
- Function extracts only needed fields and ignores the rest
- No need to transform objects before sending
- Include `id` field for updates, omit for creates

**Example WeWeb binding pattern:**
- Parent ID: `selected_item?.id || null` (null triggers create)
- Required fields: Direct bindings from form inputs
- Optional fields: `form.field || null`
- Children array: Direct binding to array variable

---

## Views with Proper RLS Enforcement

Views inherit RLS from underlying tables, but this inheritance can fail in certain scenarios, particularly with JOINs. This section documents how to create views that properly enforce merchant isolation.

### The Problem: RLS Inheritance Failures

When creating views with JOINs between multiple tables, the RLS policies on base tables may not be properly enforced through the view. The query planner may not correctly apply underlying RLS policies, resulting in views that show data from all merchants instead of filtering to the current merchant.

**Symptoms:**
- View shows thousands of records when base table shows only a few
- WeWeb displays data from multiple merchants
- Direct table queries work correctly but view queries don't

**Root cause:**
- Views don't have direct RLS policies
- RLS inheritance is inconsistent with complex JOINs
- Query planner optimization may bypass RLS checks

### The Solution: Explicit Merchant Filtering

Add **explicit merchant filtering** directly in the view definition using the `get_current_merchant_id()` function in a WHERE clause.

**Key principles:**
1. View must have explicit WHERE clause filtering by merchant
2. Use `get_current_merchant_id()` function for dynamic context
3. JOIN conditions should match merchant IDs between tables
4. All base tables must have proper RLS policies

### Base Table RLS Requirements

Before creating the view, ensure all underlying tables have:

**RLS enabled:**
- Row Level Security must be enabled on each table

**Anon policies (for WeWeb integration):**
- Policy for `anon` role using `get_current_merchant_id()`
- Must check that merchant_id matches AND is not null
- These policies enable WeWeb to query with custom headers

**Authenticated policies:**
- Policy for `public` or `authenticated` role
- Filter by `get_current_merchant_id()`
- Standard policy for direct Supabase auth users

### View Construction Pattern

**Explicit WHERE clause:**
- Add `WHERE parent_table.merchant_id = get_current_merchant_id()`
- This must be in view definition, not just relied on RLS inheritance
- Ensures merchant filtering happens at query planning time

**Merchant-aware JOINs:**
- When joining tables, add merchant_id equality to join condition
- Example: `ON table1.id = table2.parent_id AND table1.merchant_id = table2.merchant_id`
- Ensures both sides of join belong to same merchant

**Select all needed columns explicitly:**
- Don't use `SELECT *` in views
- List each column explicitly
- Rename conflicting columns with aliases
- Makes view schema clear and maintainable

### The get_current_merchant_id() Function

This critical function extracts merchant context from multiple sources in priority order:

1. **Custom header** `x-merchant-id` - Used by WeWeb
2. **JWT claims** `merchant_id` field - For direct auth
3. **Admin lookup** - Queries `admin_users` table using `auth.uid()`
4. **User lookup** - Queries `user_accounts` table using `auth.uid()`

The function works with:
- WeWeb (sends merchant context via header)
- Direct Supabase Auth (JWT contains merchant_id)
- Admin user sessions (lookup from admin_users table)
- End user sessions (lookup from user_accounts table)

Returns NULL if no merchant context found, which combined with proper policies, denies access.

### View Naming Conventions

Follow consistent naming prefixes based on view type:

**Regular views (`v_` prefix):**
- Real-time data, computed on-demand
- Use when: Need always-current data, simple JOINs, data changes frequently
- Example: `v_reward_promo_code_list`

**Materialized views (`mv_` prefix):**
- Pre-computed, cached data, requires refresh
- Use when: Heavy aggregations, complex calculations, slight staleness acceptable
- Example: `mv_reward_promo_code_summary_internal`

**Backend-for-frontend views (`bff_` prefix):**
- API-oriented enrichment views
- Combine data from multiple tables for frontend consumption
- Add computed fields, format data for display
- Example: `bff_earn_conditions`

### Testing View RLS Enforcement

Always test views with actual user context to verify merchant filtering:

**Create test function:**
- SECURITY DEFINER function that queries the view
- Returns merchant context and row count
- Call from WeWeb with real auth token

**Verification steps:**
1. Query base table directly - note row count
2. Query view - should match base table count
3. If counts differ, RLS enforcement is broken
4. Check each requirement: RLS enabled, anon policies, WHERE clause

### Troubleshooting Guide

**Symptom:** View shows all merchants' data instead of filtering

**Diagnosis checklist:**
1. Are base tables RLS enabled?
2. Do base tables have anon policies (for WeWeb)?
3. Does view have explicit WHERE clause with `get_current_merchant_id()`?
4. Does `get_current_merchant_id()` return correct merchant ID?
5. Are JOINs matching merchant IDs?

**Resolution steps:**
1. Add missing anon policies to base tables
2. Add explicit WHERE filter to view definition
3. Use CREATE OR REPLACE VIEW to update
4. Add merchant_id matching to JOIN conditions
5. Test with actual WeWeb user context

---

## Edge Functions vs Database RPC Functions

Edge functions (Supabase Functions) and database RPC functions handle merchant context differently due to their execution environments.

### Database RPC Functions

Database RPC functions run **inside PostgreSQL** where they have full access to the auth context:

- `get_current_merchant_id()` works correctly
- Can access `auth.uid()` for user lookups
- Can read custom headers like `x-merchant-id`
- Can query `admin_users` and `user_accounts` tables for merchant resolution

**Use `get_current_merchant_id()` for all database functions.**

### Edge Functions (Supabase Functions)

Edge functions run in **Deno** (outside the database). They cannot directly use `get_current_merchant_id()` because:

1. Edge functions don't have direct access to the PostgreSQL auth context
2. Custom tokens (non-Supabase auth) are not recognized by Supabase client
3. Calling `supabase.rpc('get_current_merchant_id')` with a custom token will hang or fail

**For edge functions with custom tokens, use one of these patterns:**

**Pattern 1: Merchant Registry (Recommended for known merchants)**
```javascript
const MERCHANT_REGISTRY = {
  'nbdreward': '7faab812-e179-48c2-9707-0d8a9b2f84ea',
  'duluxreward': '71a1b38e-ae10-42e1-ba12-63cbb4c0c4ba',
  'newcrm': '09b45463-3812-42fb-9c7f-9d43b6fd3eb9',
};

// Accept merchant_code in request body
const { merchant_code } = await req.json();
const merchantId = MERCHANT_REGISTRY[merchant_code.toLowerCase()];
```

**Pattern 2: Database Lookup (For dynamic merchants)**
```javascript
// Accept merchant_code in request body, look up in database
const { merchant_code } = await req.json();
const { data } = await supabase
  .from('merchant_master')
  .select('id')
  .eq('merchant_code', merchant_code)
  .single();
const merchantId = data?.id;
```

**Pattern 3: Accept merchant_id directly (For trusted internal calls)**
```javascript
// Only use when caller is trusted (e.g., other backend services)
const { merchant_id } = await req.json();
```

### When to Use Each

| Scenario | Use |
|----------|-----|
| Database function called from WeWeb | `get_current_merchant_id()` |
| Database function called from edge function | Pass `merchant_id` as parameter |
| Edge function with custom tokens | Merchant registry or database lookup |
| Edge function with Supabase auth | Can use `get_current_merchant_id()` via RPC |

### Example: Edge Function with Merchant Registry

```javascript
// Used by: claim-codes, validate-codes, upload-receipts-auto
const supabase = createClient(supabaseUrl, supabaseServiceKey);

const { merchant_code, ...otherParams } = await req.json();
const merchantId = MERCHANT_REGISTRY[merchant_code?.toLowerCase()];

if (!merchantId) {
  return new Response(JSON.stringify({ error: 'Invalid merchant_code' }), { status: 400 });
}

// Use service role client with resolved merchantId
const { data } = await supabase.rpc('some_function', {
  p_merchant_id: merchantId,
  ...otherParams
});
```

### Key Differences Summary

| Aspect | Database RPC | Edge Function |
|--------|--------------|---------------|
| Execution environment | PostgreSQL | Deno |
| Auth context access | Full (auth.uid(), headers) | None |
| `get_current_merchant_id()` | ✅ Works | ❌ Doesn't work with custom tokens |
| Merchant resolution | Automatic from context | Must be passed explicitly |
| Custom token support | Via header/lookup | Must use registry or lookup |

---

## Standardized Response Format

All BFF functions that return operation results (not data queries) must use a standardized response format. This enables consistent frontend handling, especially for alerts and notifications.

### Response Structure

Every response must contain exactly these 4 fields:

```json
{
  "success": true | false,
  "title": "Main message",
  "description": "Optional detail" | null,
  "data": { ... } | null
}
```

| Field | Type | Required | Purpose |
|-------|------|----------|---------|
| `success` | boolean | ✅ | Operation succeeded or failed |
| `title` | string | ✅ | Primary message for user (toast title) |
| `description` | string \| null | ✅ | Secondary detail (toast body) |
| `data` | object \| null | ✅ | Context-specific payload |

### Success Response Example

```sql
RETURN jsonb_build_object(
    'success', true,
    'title', 'Reward redeemed successfully',
    'description', null,
    'data', jsonb_build_object(
        'redemption_id', v_redemption.id,
        'points_deducted', v_points,
        'new_balance', v_balance
    )
);
```

### Error Response Example

```sql
RETURN jsonb_build_object(
    'success', false,
    'title', 'Insufficient points',
    'description', format('You need %s more points', v_shortage),
    'data', jsonb_build_object(
        'required', v_required,
        'available', v_available,
        'shortage', v_shortage
    )
);
```

### Frontend Binding

With standardized fields, frontend can bind directly without conditional logic:

| UI Element | Bind To |
|------------|---------|
| Toast title | `response.title` |
| Toast body | `response.description` |
| Toast type/color | `response.success ? 'success' : 'error'` |
| Show toast | `response != null` |

### Functions Using This Format

| Function | Purpose |
|----------|---------|
| `redeem_reward_with_points` | Redeem rewards using points |
| `api_mark_redemption_used` | Mark redemption as used |

### Migration Guide

When updating existing functions:

1. Replace `'error', '...'` with `'title', '...'`
2. Replace `'reason', '...'` with `'description', '...'`
3. Replace `'message', '...'` with `'title', '...'`
4. Wrap additional fields in `'data', jsonb_build_object(...)`
5. Ensure all 4 fields are present in every return path

---

## User ID Resolution Pattern

For user-facing BFF functions (missions, rewards, wallet, profile, etc.), use a consistent pattern that allows:
- **End users** to access their own data without providing their ID
- **Admins** to view any user's data by providing an explicit user ID

### Parameter Convention

```sql
CREATE OR REPLACE FUNCTION bff_get_user_something(
  p_user_id UUID DEFAULT NULL,  -- NULL = own data, UUID = admin override
  p_other_param TEXT
)
```

| Caller | `p_user_id` | Behavior |
|--------|-------------|----------|
| User with JWT | `NULL` (omit) | Auto-resolves from `auth.uid()` → views own data |
| Admin with JWT | `NULL` (omit) | Auto-resolves from `auth.uid()` → views own data |
| Admin with JWT | `<some-uuid>` | Validates admin role → views that user's data |
| User with JWT | `<some-uuid>` | ❌ Permission denied (non-admins can't view others) |
| No JWT | any | ❌ Authentication required |

### Implementation Pattern

```sql
DECLARE
  v_user_id UUID;
  v_is_admin BOOLEAN := FALSE;
BEGIN
  -- Determine user_id: provided or from auth
  IF p_user_id IS NOT NULL THEN
    -- Admin providing explicit user_id - verify caller is admin
    SELECT EXISTS (
      SELECT 1 FROM admin_users 
      WHERE auth_user_id = auth.uid() 
        AND role IN ('super_admin', 'admin', 'staff')
    ) INTO v_is_admin;
    
    IF NOT v_is_admin THEN
      RETURN jsonb_build_object(
        'success', false,
        'title', 'Permission denied',
        'description', 'Only admins can view other users'' data',
        'data', null
      );
    END IF;
    v_user_id := p_user_id;
  ELSE
    -- User viewing own data
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
      RETURN jsonb_build_object(
        'success', false,
        'title', 'Authentication required',
        'description', 'You must be logged in',
        'data', null
      );
    END IF;
  END IF;
  
  -- Continue with v_user_id...
END;
```

### Key Points

1. **Default to `auth.uid()`** - Users don't need to know or pass their own ID
2. **Admin check uses `admin_users` table** - Validates role is `super_admin`, `admin`, or `staff`
3. **Merchant context still required** - Use `get_current_merchant_id()` for merchant filtering
4. **Include `user_id` in response** - Helpful for admin views to confirm which user's data is shown

### Functions Using This Pattern

| Function | Purpose |
|----------|---------|
| `bff_get_user_missions` | List missions with progress |
| `bff_get_mission_detail` | Mission details + conditions + history |

### Frontend Integration

**User viewing own data (most common):**
```javascript
// No user_id needed - resolved from JWT
const { data } = await supabase.rpc('bff_get_user_missions', {
  p_include_inactive: false
});
```

**Admin viewing another user:**
```javascript
// Admin must provide explicit user_id
const { data } = await supabase.rpc('bff_get_user_missions', {
  p_user_id: selectedUserId,
  p_include_inactive: true
});
```

---

## Implementation Examples Reference

### Implemented Functions

**Persona groups with personas:**
- Function: `upsert_persona_group_with_personas`
- Parameters: group_id, group_name, user_type, active_status, personas array
- Updates personas by ID, preserves user assignments

**Store attribute sets with members:**
- Function: `upsert_store_attribute_set_with_members`
- Parameters: set_id, set_code, set_name, members array
- Updates members by ID, preserves store linkages

### Implemented Views

**Store master with attributes:**
- View: `store_master_attributes`
- Explicit WHERE: `sm.merchant_id = get_current_merchant_id()`
- Merchant-aware JOIN between store_master and store_attribute_assignments

---

## Summary Checklist

### For Upsert Functions:
- ✅ Use individual parameters with `p_` prefix, not single JSONB object
- ✅ Determine create vs update based on parent ID being null or provided
- ✅ Update children by ID (preserve IDs), never delete-and-recreate
- ✅ Track children to keep in array, delete only removed ones
- ✅ Extract only needed fields from child objects, ignore redundant fields
- ✅ Use merchant context from `get_current_merchant_id()`, never from parameters
- ✅ Return comprehensive JSONB response with operation counts
- ✅ Use SECURITY DEFINER for RLS bypass with explicit merchant filtering
- ✅ Validate parent belongs to merchant before updating

### For Views:
- ✅ Enable RLS on all underlying base tables first
- ✅ Create anon policies on base tables for WeWeb integration
- ✅ Add explicit WHERE clause with `get_current_merchant_id()` in view
- ✅ Match merchant IDs in JOIN conditions
- ✅ Follow naming conventions: v_ for regular, mv_ for materialized, bff_ for frontend
- ✅ Test with actual user context from WeWeb
- ✅ Select columns explicitly, avoid SELECT *
- ✅ Verify view row count matches base table when filtered

### For User-Facing Functions:
- ✅ Make `p_user_id` optional with `DEFAULT NULL`
- ✅ When `p_user_id` is NULL, resolve from `auth.uid()`
- ✅ When `p_user_id` is provided, validate caller is admin before using
- ✅ Return authentication error if no JWT and no user context
- ✅ Include resolved `user_id` in response data for clarity
- ✅ Still use `get_current_merchant_id()` for merchant filtering

### Never Do:
- ❌ Delete all children and recreate (breaks references)
- ❌ Use single JSONB parameter for function signature
- ❌ Rely only on RLS inheritance for views with JOINs
- ❌ Trust merchant_id from function parameters
- ❌ Create views without explicit merchant filtering
- ❌ Forget anon policies for WeWeb integration
- ❌ Require users to pass their own user_id (use `auth.uid()` default)
- ❌ Allow non-admins to query other users' data
- ❌ Skip admin role check when `p_user_id` is explicitly provided
