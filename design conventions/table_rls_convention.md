# Table RLS Convention

## Overview

This document defines the standard patterns for Row Level Security (RLS) policies in the CRM project to ensure security, consistency, and avoid common pitfalls.

---

## Core Principle

**All RLS policies must use `get_current_merchant_id()` for merchant filtering.** Never directly query lookup tables like `admin_users` or `user_accounts` within policy definitions.

---

## The Recursion Problem

### What Causes It

When an RLS policy on Table A directly queries Table B, and Table B has its own RLS policy, PostgreSQL evaluates both policies. If Table B's policy queries itself (or queries back to Table A), you get infinite recursion.

**Example of problematic pattern:**

```sql
-- BAD: Policy on purchase_receipt_upload
CREATE POLICY "Admins can manage"
ON purchase_receipt_upload
FOR ALL
USING (
  merchant_id = get_current_merchant_id() 
  AND EXISTS (
    SELECT 1 FROM admin_users  -- ← Direct query triggers admin_users RLS
    WHERE admin_users.auth_user_id = auth.uid()
  )
);
```

When this policy runs:
1. Query hits `purchase_receipt_upload`
2. Policy queries `admin_users` directly
3. `admin_users` has RLS that queries itself
4. Recursion → Error 42P17

### The Solution

Use `get_current_merchant_id()` which is `SECURITY DEFINER`. It internally queries `admin_users` but **bypasses RLS** when doing so, breaking the recursion chain.

**Correct pattern:**

```sql
-- GOOD: Simple policy using SECURITY DEFINER function
CREATE POLICY "Admins can manage"
ON purchase_receipt_upload
FOR ALL
TO authenticated
USING (merchant_id = get_current_merchant_id())
WITH CHECK (merchant_id = get_current_merchant_id());
```

---

## Standard Policy Templates

### 1. Basic Merchant Isolation (Most Tables)

For tables where all authenticated users with merchant context can read:

```sql
-- Enable RLS
ALTER TABLE {table_name} ENABLE ROW LEVEL SECURITY;

-- Authenticated users (admins and end-users with merchant context)
CREATE POLICY "Authenticated users can view merchant data"
ON {table_name}
FOR SELECT
TO authenticated
USING (merchant_id = get_current_merchant_id());

-- Service role bypass for internal operations
CREATE POLICY "Service role has full access"
ON {table_name}
FOR ALL
TO service_role
USING (true);
```

### 2. Admin-Only Write Access

For tables where only admins can modify but all can read:

```sql
-- Read: all authenticated with merchant context
CREATE POLICY "Authenticated can view"
ON {table_name}
FOR SELECT
TO authenticated
USING (merchant_id = get_current_merchant_id());

-- Write: only authenticated (admin check happens in get_current_merchant_id)
CREATE POLICY "Admins can manage"
ON {table_name}
FOR ALL
TO authenticated
USING (merchant_id = get_current_merchant_id())
WITH CHECK (merchant_id = get_current_merchant_id());
```

### 3. User-Owned Data (e.g., user submissions, uploads)

For tables where users can only see their own records:

```sql
-- Users see only their own records
CREATE POLICY "Users can view own records"
ON {table_name}
FOR SELECT
TO authenticated
USING (user_id = auth.uid());

-- Admins can view all in their merchant
CREATE POLICY "Admins can view merchant records"
ON {table_name}
FOR SELECT
TO authenticated
USING (merchant_id = get_current_merchant_id());

-- Service role for backend operations
CREATE POLICY "Service role has full access"
ON {table_name}
FOR ALL
TO service_role
USING (true);
```

### 4. Anon Access (WeWeb Integration)

For tables that need anonymous access with merchant context from headers:

```sql
-- Anon with merchant context (via x-merchant-id header)
CREATE POLICY "Anon with merchant context can view"
ON {table_name}
FOR SELECT
TO anon
USING (
  merchant_id = get_current_merchant_id() 
  AND get_current_merchant_id() IS NOT NULL
);
```

---

## How `get_current_merchant_id()` Works

This function is `SECURITY DEFINER`, meaning it runs with elevated privileges and bypasses RLS on tables it queries internally.

**Resolution order:**
1. `x-merchant-id` header (for WeWeb/anon requests)
2. JWT `merchant_id` claim (for direct merchant tokens)
3. `admin_users` lookup via `auth.uid()` (for admin authentication)
4. `user_accounts` lookup via `auth.uid()` (for end-user authentication)

Because it's SECURITY DEFINER, it can safely query `admin_users` and `user_accounts` without triggering their RLS policies.

---

## Rules Summary

| ✅ DO | ❌ DON'T |
|-------|----------|
| Use `get_current_merchant_id()` for merchant filtering | Directly query `admin_users` in policies |
| Use `auth.uid()` for user-owned data | Use `EXISTS (SELECT FROM admin_users)` |
| Keep policies simple (single condition when possible) | Chain multiple table lookups in policies |
| Use SECURITY DEFINER functions for complex lookups | Assume RLS won't cause recursion |

---

## Debugging RLS Issues

### Error: `42P17 - infinite recursion detected`

1. Check if the policy directly queries another RLS-protected table
2. Replace direct queries with appropriate SECURITY DEFINER helper functions
3. Test with a simple `SELECT * FROM {table} LIMIT 1` as the affected role

### Testing Policies

```sql
-- Test as authenticated user
SET ROLE authenticated;
SET request.jwt.claims = '{"sub": "user-uuid-here"}';
SELECT * FROM {table_name} LIMIT 5;
RESET ROLE;
```

---

## Migration Checklist

When creating new tables:

- [ ] Enable RLS: `ALTER TABLE {name} ENABLE ROW LEVEL SECURITY;`
- [ ] Add merchant filtering policy using `get_current_merchant_id()`
- [ ] Add service_role bypass policy
- [ ] Add anon policy if WeWeb needs access
- [ ] Test from WeWeb to confirm no recursion errors





