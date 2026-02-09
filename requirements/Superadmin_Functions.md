# Superadmin Functions

**Version:** 2.0  
**Last Updated:** January 2026  
**Project:** Supabase CRM

## Overview

Superadmin functions are `SECURITY DEFINER` functions that bypass Row Level Security (RLS) policies. These functions are designed for platform administrators to manage merchants, credentials, and admin users across all merchants.

## 🔒 Security

**All functions require Service Role Key authentication.**

These functions check `auth.role() = 'service_role'` and will return an `UNAUTHORIZED` error if called with regular user JWT tokens.

**Access Requirements**:
- ✅ Must use Supabase **Service Role Key**
- ❌ Regular user JWT tokens are **blocked**
- ⚠️ **Never expose service role key** to frontend
- ✅ Use only in **backend/server** operations

---

## Available Functions

### Create Functions
1. `admin_init_merchant_with_owner` - Create merchant + first owner (atomic)
2. `superadmin_create_merchant` - Create merchant only
3. `superadmin_create_merchant_credentials` - Create credentials for any merchant
4. `superadmin_create_admin_user` - Create admin user for any merchant

### Update Functions
5. `superadmin_update_merchant` - Update all merchant fields
6. `superadmin_update_admin_user` - Update admin user (role, name, email, phone, status)

---

## 1. admin_init_merchant_with_owner

**Purpose**: Create a new merchant with its first owner admin user in a single atomic operation.

**Use Case**: Quick merchant onboarding when you have the owner's details ready.

### Function Signature

```sql
admin_init_merchant_with_owner(
  p_merchant_name text,
  p_merchant_code text,
  p_owner_email text,
  p_owner_auth_user_id uuid,
  p_owner_name text DEFAULT NULL
) RETURNS jsonb
```

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `p_merchant_name` | text | ✅ | Display name of the merchant |
| `p_merchant_code` | text | ✅ | Unique merchant code (lowercase alphanumeric) |
| `p_owner_email` | text | ✅ | Owner's email address |
| `p_owner_auth_user_id` | uuid | ✅ | Supabase Auth user ID for the owner |
| `p_owner_name` | text | ❌ | Owner's display name (defaults to email prefix) |

### Returns

```json
{
  "success": true,
  "merchant_id": "uuid",
  "merchant_code": "newmerchant",
  "merchant_name": "New Merchant",
  "admin_user_id": "uuid",
  "owner_email": "owner@example.com",
  "owner_auth_user_id": "uuid"
}
```

### Error Codes

- `MERCHANT_CODE_EXISTS` - Merchant code already in use
- `SYSTEM_ERROR` - Owner role not found in system
- `UNEXPECTED_ERROR` - Database or other unexpected error

### cURL Example

```bash
curl -X POST 'https://wkevmsedchftztoolkmi.supabase.co/rest/v1/rpc/admin_init_merchant_with_owner' \
  -H "apikey: YOUR_SUPABASE_ANON_KEY" \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "p_merchant_name": "Acme Corporation",
    "p_merchant_code": "acme",
    "p_owner_email": "john@acme.com",
    "p_owner_auth_user_id": "550e8400-e29b-41d4-a716-446655440000",
    "p_owner_name": "John Smith"
  }'
```

### SQL Example

```sql
SELECT admin_init_merchant_with_owner(
  'Acme Corporation',
  'acme',
  'john@acme.com',
  '550e8400-e29b-41d4-a716-446655440000'::uuid,
  'John Smith'
);
```

---

## 2. superadmin_create_merchant

**Purpose**: Create a merchant without an owner. Owner and admin users can be added separately.

**Use Case**: When you want to set up the merchant first, then add multiple admins or configure settings before assigning ownership.

### Function Signature

```sql
superadmin_create_merchant(
  p_merchant_name text,
  p_merchant_code text,
  p_auth_methods text[] DEFAULT ARRAY['line', 'tel'],
  p_currency_award_delay_type text DEFAULT 'days',
  p_currency_award_delay_days integer DEFAULT 7,
  p_currency_award_timezone text DEFAULT 'Asia/Bangkok'
) RETURNS jsonb
```

### Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `p_merchant_name` | text | ✅ | - | Display name of the merchant |
| `p_merchant_code` | text | ✅ | - | Unique merchant code (lowercase, alphanumeric, hyphens/underscores) |
| `p_auth_methods` | text[] | ❌ | `['line', 'tel']` | Allowed authentication methods for end-users |
| `p_currency_award_delay_type` | text | ❌ | `'days'` | Delay type for currency awards |
| `p_currency_award_delay_days` | integer | ❌ | `7` | Number of days to delay currency awards |
| `p_currency_award_timezone` | text | ❌ | `'Asia/Bangkok'` | Timezone for currency award processing |

### Returns

```json
{
  "success": true,
  "merchant_id": "uuid",
  "merchant_code": "newmerchant",
  "merchant_name": "New Merchant",
  "message": "Merchant created successfully. Add owner user separately."
}
```

### Error Codes

- `MERCHANT_CODE_EXISTS` - Merchant code already in use
- `INVALID_MERCHANT_CODE` - Merchant code format invalid (must be lowercase alphanumeric)
- `UNEXPECTED_ERROR` - Database or other unexpected error

### cURL Example

```bash
curl -X POST 'https://wkevmsedchftztoolkmi.supabase.co/rest/v1/rpc/superadmin_create_merchant' \
  -H "apikey: YOUR_SUPABASE_ANON_KEY" \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "p_merchant_name": "Beta Store",
    "p_merchant_code": "betastore",
    "p_auth_methods": ["line", "tel"],
    "p_currency_award_delay_days": 14
  }'
```

### SQL Example

```sql
SELECT superadmin_create_merchant(
  'Beta Store',
  'betastore',
  ARRAY['line', 'tel'],
  'days',
  14,
  'Asia/Bangkok'
);
```

---

## 3. superadmin_create_merchant_credentials

**Purpose**: Create API credentials for any merchant service (LINE, SMS, payment gateways, etc.).

**Use Case**: Add integration credentials for merchants after setup or when credentials need to be rotated.

### Function Signature

```sql
superadmin_create_merchant_credentials(
  p_merchant_code text,
  p_service_name text,
  p_credentials jsonb,
  p_environment text DEFAULT 'production',
  p_is_active boolean DEFAULT true,
  p_expires_at timestamptz DEFAULT NULL,
  p_external_id text DEFAULT NULL
) RETURNS jsonb
```

### Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `p_merchant_code` | text | ✅ | - | Target merchant code |
| `p_service_name` | text | ✅ | - | Service identifier (e.g., 'line', '8x8', 'shopee', 'stripe') |
| `p_credentials` | jsonb | ✅ | - | Credentials object (structure varies by service) |
| `p_environment` | text | ❌ | `'production'` | Environment: `'production'`, `'staging'`, `'development'`, `'test'` |
| `p_is_active` | boolean | ❌ | `true` | Whether credentials are active |
| `p_expires_at` | timestamptz | ❌ | `null` | Optional expiration timestamp |
| `p_external_id` | text | ❌ | `null` | Optional external reference ID |

### Returns

```json
{
  "success": true,
  "credential_id": "uuid",
  "merchant_id": "uuid",
  "merchant_code": "acme",
  "merchant_name": "Acme Corporation",
  "service_name": "line",
  "environment": "production",
  "is_active": true,
  "message": "Credentials created for line"
}
```

### Error Codes

- `MERCHANT_NOT_FOUND` - Merchant code doesn't exist
- `INVALID_SERVICE_NAME` - Service name is empty
- `INVALID_CREDENTIALS` - Credentials object is empty
- `CREDENTIALS_EXIST` - Credentials already exist for this merchant + service + environment
- `UNEXPECTED_ERROR` - Database or other unexpected error

### Credential Formats by Service

#### LINE Login

```json
{
  "channel_id": "1234567890",
  "channel_secret": "abc123def456"
}
```

#### 8x8 SMS

```json
{
  "api_key": "your-8x8-api-key",
  "subaccount_id": "your-subaccount-id"
}
```

#### Shopee

```json
{
  "partner_id": "123456",
  "partner_key": "your-partner-key",
  "shop_id": "7890"
}
```

### cURL Example

```bash
curl -X POST 'https://wkevmsedchftztoolkmi.supabase.co/rest/v1/rpc/superadmin_create_merchant_credentials' \
  -H "apikey: YOUR_SUPABASE_ANON_KEY" \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "p_merchant_code": "acme",
    "p_service_name": "line",
    "p_credentials": {
      "channel_id": "1234567890",
      "channel_secret": "abc123def456"
    },
    "p_environment": "production",
    "p_is_active": true
  }'
```

### SQL Example

```sql
SELECT superadmin_create_merchant_credentials(
  'acme',
  'line',
  '{"channel_id": "1234567890", "channel_secret": "abc123def456"}'::jsonb,
  'production',
  true
);
```

---

## 4. superadmin_create_admin_user

**Purpose**: Create admin user for any merchant, bypassing the normal invitation flow.

**Use Case**: Quickly add admins to merchants, emergency access, or initial merchant setup.

### Function Signature

```sql
superadmin_create_admin_user(
  p_merchant_code text,
  p_email text,
  p_auth_user_id uuid,
  p_role_code text DEFAULT 'admin',
  p_name text DEFAULT NULL,
  p_phone text DEFAULT NULL
) RETURNS jsonb
```

### Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `p_merchant_code` | text | ✅ | - | Target merchant code |
| `p_email` | text | ✅ | - | Admin user's email address |
| `p_auth_user_id` | uuid | ✅ | - | Supabase Auth user ID |
| `p_role_code` | text | ❌ | `'admin'` | Role code: 'owner', 'admin', 'manager', 'viewer' |
| `p_name` | text | ❌ | `null` | Display name (defaults to email prefix) |
| `p_phone` | text | ❌ | `null` | Phone number |

### System Roles

| Role Code | Role Name | Description |
|-----------|-----------|-------------|
| `owner` | Owner | Full access, can manage all settings and team |
| `admin` | Admin | Full access except billing and dangerous settings |
| `manager` | Manager | Can manage users and content |
| `viewer` | Viewer | Read-only access |

### Returns

```json
{
  "success": true,
  "admin_user_id": "uuid",
  "merchant_id": "uuid",
  "merchant_code": "acme",
  "merchant_name": "Acme Corporation",
  "auth_user_id": "uuid",
  "email": "sarah@acme.com",
  "name": "Sarah Johnson",
  "role_code": "admin",
  "role_name": "Admin",
  "message": "Admin user created: sarah@acme.com as Admin"
}
```

### Error Codes

- `MERCHANT_NOT_FOUND` - Merchant code doesn't exist
- `INVALID_ROLE` - Role code is invalid or not a system role
- `INVALID_EMAIL` - Email format is invalid
- `USER_ALREADY_EXISTS` - Auth user already exists in this merchant
- `EMAIL_ALREADY_EXISTS` - Email already used by another user in this merchant
- `UNEXPECTED_ERROR` - Database or other unexpected error

### cURL Example

```bash
curl -X POST 'https://wkevmsedchftztoolkmi.supabase.co/rest/v1/rpc/superadmin_create_admin_user' \
  -H "apikey: YOUR_SUPABASE_ANON_KEY" \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "p_merchant_code": "acme",
    "p_email": "sarah@acme.com",
    "p_auth_user_id": "650e8400-e29b-41d4-a716-446655440001",
    "p_role_code": "admin",
    "p_name": "Sarah Johnson",
    "p_phone": "+66812345678"
  }'
```

### SQL Example

```sql
SELECT superadmin_create_admin_user(
  'acme',
  'sarah@acme.com',
  '650e8400-e29b-41d4-a716-446655440001'::uuid,
  'admin',
  'Sarah Johnson',
  '+66812345678'
);
```

---

## 5. superadmin_update_merchant

**Purpose**: Update any field in merchant_master for any merchant.

**Use Case**: Modify merchant settings, enable/disable features, update configurations without needing merchant admin access.

### Function Signature

```sql
superadmin_update_merchant(
    p_merchant_code text,
    p_name text DEFAULT NULL,
    p_auth_methods text[] DEFAULT NULL,
    p_earn_rate_entity_type text DEFAULT NULL,
    p_points_expiry_mode text DEFAULT NULL,
    p_points_ttl_months integer DEFAULT NULL,
    p_points_frequency text DEFAULT NULL,
    p_points_fiscal_year_end_month integer DEFAULT NULL,
    p_points_minimum_period_months integer DEFAULT NULL,
    p_points_expiry_active boolean DEFAULT NULL,
    p_referral_activation_trigger text DEFAULT NULL,
    p_referral_active boolean DEFAULT NULL,
    p_persona_attain text DEFAULT NULL,
    p_attain_persona text DEFAULT NULL,
    p_currency_award_delay_type text DEFAULT NULL,
    p_currency_award_delay_days integer DEFAULT NULL,
    p_currency_award_delay_minutes integer DEFAULT NULL,
    p_currency_award_time time DEFAULT NULL,
    p_currency_award_timezone text DEFAULT NULL,
    p_marketplace_claim_from_status jsonb DEFAULT NULL
) RETURNS jsonb
```

### Parameters

**Only non-null parameters are updated**. All parameters except `p_merchant_code` are optional.

| Category | Parameters | Valid Values |
|----------|-----------|--------------|
| **Basic** | `p_name`, `p_auth_methods` | name: text, auth_methods: array of 'line', 'tel' |
| **Points Expiry** | `p_points_expiry_active`, `p_points_ttl_months`, `p_points_expiry_mode`, `p_points_frequency`, `p_points_fiscal_year_end_month`, `p_points_minimum_period_months` | expiry_mode: 'none', 'rolling', 'fiscal' |
| **Earn Rate** | `p_earn_rate_entity_type` | 'tier', 'persona' |
| **Referral** | `p_referral_active`, `p_referral_activation_trigger` | trigger: 'first_purchase', 'registration' |
| **Persona** | `p_persona_attain`, `p_attain_persona` | 'highest_spend_per_period', 'total_spend', etc. |
| **Currency Award** | `p_currency_award_delay_type`, `p_currency_award_delay_days`, `p_currency_award_delay_minutes`, `p_currency_award_time`, `p_currency_award_timezone` | delay_type: 'immediate', 'rolling_minutes', 'rolling_days', 'scheduled' |
| **Marketplace** | `p_marketplace_claim_from_status` | JSONB object with platform statuses |

### Returns

```json
{
  "success": true,
  "merchant_id": "uuid",
  "merchant_code": "acme",
  "merchant_name": "Updated Name",
  "updated_fields": ["name", "auth_methods", "referral_active"],
  "message": "Merchant updated: 3 field(s) changed"
}
```

### Error Codes

- `MERCHANT_NOT_FOUND` - Merchant code doesn't exist
- `INVALID_DELAY_TYPE` - Invalid currency_award_delay_type value
- `UNEXPECTED_ERROR` - Database or constraint violation

### cURL Example

```bash
curl -X POST 'https://wkevmsedchftztoolkmi.supabase.co/rest/v1/rpc/superadmin_update_merchant' \
  -H "apikey: YOUR_SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer YOUR_SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "p_merchant_code": "acme",
    "p_name": "Acme Corporation Ltd",
    "p_auth_methods": ["line", "tel"],
    "p_referral_active": true,
    "p_points_expiry_active": true,
    "p_points_ttl_months": 12
  }'
```

### SQL Example

```sql
-- Update multiple fields at once
SELECT superadmin_update_merchant(
  'acme',
  p_name := 'Acme Corporation Ltd',
  p_auth_methods := ARRAY['line', 'tel'],
  p_referral_active := true,
  p_points_expiry_active := true,
  p_points_ttl_months := 12
);

-- Update single field
SELECT superadmin_update_merchant(
  'acme',
  p_currency_award_delay_type := 'rolling_days',
  p_currency_award_delay_days := 7
);
```

---

## 6. superadmin_update_admin_user

**Purpose**: Update admin user details including role, name, email, phone, and active status for any merchant.

**Use Case**: Change user roles, update contact info, activate/deactivate users without merchant admin access.

### Function Signature

```sql
superadmin_update_admin_user(
    p_merchant_code text,
    p_auth_user_id uuid,
    p_role_code text DEFAULT NULL,
    p_name text DEFAULT NULL,
    p_email text DEFAULT NULL,
    p_phone text DEFAULT NULL,
    p_active_status boolean DEFAULT NULL
) RETURNS jsonb
```

### Parameters

**Only non-null parameters are updated**.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `p_merchant_code` | text | ✅ | Target merchant code |
| `p_auth_user_id` | uuid | ✅ | Supabase Auth user ID to update |
| `p_role_code` | text | ❌ | New role: 'owner', 'admin', 'manager', 'viewer' |
| `p_name` | text | ❌ | New display name |
| `p_email` | text | ❌ | New email address |
| `p_phone` | text | ❌ | New phone number |
| `p_active_status` | boolean | ❌ | Enable (true) or disable (false) user |

### Returns

```json
{
  "success": true,
  "admin_user_id": "uuid",
  "merchant_id": "uuid",
  "merchant_code": "acme",
  "merchant_name": "Acme Corporation",
  "auth_user_id": "uuid",
  "email": "updated@acme.com",
  "role_code": "manager",
  "role_name": "Manager",
  "updated_fields": ["role", "email"],
  "message": "Admin user updated: 2 field(s) changed"
}
```

### Error Codes

- `MERCHANT_NOT_FOUND` - Merchant code doesn't exist
- `USER_NOT_FOUND` - Admin user not found in this merchant
- `INVALID_ROLE` - Role code is invalid
- `INVALID_EMAIL` - Email format is invalid
- `EMAIL_ALREADY_EXISTS` - Email already used by another user in this merchant
- `UNEXPECTED_ERROR` - Database error

### cURL Example

```bash
# Change user role
curl -X POST 'https://wkevmsedchftztoolkmi.supabase.co/rest/v1/rpc/superadmin_update_admin_user' \
  -H "apikey: YOUR_SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer YOUR_SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "p_merchant_code": "acme",
    "p_auth_user_id": "550e8400-e29b-41d4-a716-446655440000",
    "p_role_code": "manager"
  }'

# Update contact details
curl -X POST 'https://wkevmsedchftztoolkmi.supabase.co/rest/v1/rpc/superadmin_update_admin_user' \
  -H "apikey: YOUR_SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer YOUR_SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "p_merchant_code": "acme",
    "p_auth_user_id": "550e8400-e29b-41d4-a716-446655440000",
    "p_name": "John Updated",
    "p_email": "john.new@acme.com",
    "p_phone": "+66812345678"
  }'

# Deactivate user
curl -X POST 'https://wkevmsedchftztoolkmi.supabase.co/rest/v1/rpc/superadmin_update_admin_user' \
  -H "apikey: YOUR_SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer YOUR_SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "p_merchant_code": "acme",
    "p_auth_user_id": "550e8400-e29b-41d4-a716-446655440000",
    "p_active_status": false
  }'
```

### SQL Example

```sql
-- Promote user to admin
SELECT superadmin_update_admin_user(
  'acme',
  '550e8400-e29b-41d4-a716-446655440000'::uuid,
  p_role_code := 'admin'
);

-- Update multiple fields
SELECT superadmin_update_admin_user(
  'acme',
  '550e8400-e29b-41d4-a716-446655440000'::uuid,
  p_name := 'Jane Smith',
  p_email := 'jane.smith@acme.com',
  p_phone := '+66999888777'
);
```

---

## Common Workflows

### Workflow 1: Quick Merchant Setup (All-in-One)

Use when you have all merchant and owner details ready.

```sql
-- Single function call creates merchant + owner
SELECT admin_init_merchant_with_owner(
  'Acme Corporation',
  'acme',
  'john@acme.com',
  '550e8400-e29b-41d4-a716-446655440000'::uuid,
  'John Smith'
);
```

### Workflow 2: Staged Merchant Setup

Use when you want to configure the merchant before adding users.

```sql
-- Step 1: Create merchant
SELECT superadmin_create_merchant(
  'Beta Store',
  'betastore',
  ARRAY['line', 'tel'],
  'days',
  14
);

-- Step 2: Add LINE credentials
SELECT superadmin_create_merchant_credentials(
  'betastore',
  'line',
  '{"channel_id": "1234567890", "channel_secret": "abc123def456"}'::jsonb
);

-- Step 3: Add SMS credentials
SELECT superadmin_create_merchant_credentials(
  'betastore',
  '8x8',
  '{"api_key": "your-key", "subaccount_id": "your-id"}'::jsonb
);

-- Step 4: Add owner
SELECT superadmin_create_admin_user(
  'betastore',
  'owner@betastore.com',
  '750e8400-e29b-41d4-a716-446655440002'::uuid,
  'owner',
  'Store Owner'
);

-- Step 5: Add additional admins
SELECT superadmin_create_admin_user(
  'betastore',
  'manager@betastore.com',
  '850e8400-e29b-41d4-a716-446655440003'::uuid,
  'manager',
  'Store Manager'
);
```

### Workflow 3: Add Admin to Existing Merchant

```sql
-- Add admin user to existing merchant
SELECT superadmin_create_admin_user(
  'acme',
  'newadmin@acme.com',
  '950e8400-e29b-41d4-a716-446655440004'::uuid,
  'admin'
);
```

### Workflow 4: Update Credentials

```sql
-- Note: superadmin_create_merchant_credentials checks for duplicates
-- To update, you need to DELETE the old credentials first, or create with different environment

-- Option 1: Create sandbox credentials (different environment)
SELECT superadmin_create_merchant_credentials(
  'acme',
  'line',
  '{"channel_id": "sandbox123", "channel_secret": "sandboxsecret"}'::jsonb,
  'sandbox'
);

-- Option 2: Delete old credentials and create new ones (manual SQL)
DELETE FROM merchant_credentials 
WHERE merchant_code = 'acme' 
AND service_name = 'line' 
AND environment = 'production';

SELECT superadmin_create_merchant_credentials(
  'acme',
  'line',
  '{"channel_id": "new123", "channel_secret": "newsecret"}'::jsonb,
  'production'
);
```

---

## Security & Authentication

### Service Role Key Required

**All functions require service role key authentication.**

Each function checks:
```sql
IF auth.role() != 'service_role' THEN
    RETURN jsonb_build_object(
        'success', false,
        'error_code', 'UNAUTHORIZED',
        'error_message', 'This function requires service role key access'
    );
END IF;
```

### Where to Get Service Role Key

**Supabase Dashboard → Settings → API → `service_role` key**

⚠️ This is a **secret key** - never expose to frontend!

### Usage

```bash
curl -X POST 'https://wkevmsedchftztoolkmi.supabase.co/rest/v1/rpc/FUNCTION_NAME' \
  -H "apikey: YOUR_SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer YOUR_SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -d '{"param": "value"}'
```

### Security Best Practices

1. ✅ **Backend Only** - Use service role key only in backend/server code
2. ✅ **Environment Variables** - Store key in environment variables, never hardcode
3. ✅ **Never Expose** - Do not send to frontend or include in client code
4. ✅ **API Gateway** - Create backend API endpoints that validate admin access before calling these functions
5. ✅ **IP Whitelist** - Restrict access to specific IP addresses
6. ✅ **Audit Logging** - Log all operations for compliance
7. ✅ **Rate Limiting** - Implement rate limits to prevent abuse

### Audit Trail (Optional)

Log all superadmin operations:

```sql
CREATE TABLE IF NOT EXISTS superadmin_audit_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  function_name text NOT NULL,
  merchant_code text,
  operation text,
  parameters jsonb,
  result jsonb,
  ip_address text,
  created_at timestamptz DEFAULT NOW()
);

CREATE INDEX idx_superadmin_audit_merchant ON superadmin_audit_log(merchant_code);
CREATE INDEX idx_superadmin_audit_created_at ON superadmin_audit_log(created_at DESC);
```

---

## Error Handling

All functions return consistent error format:

```json
{
  "success": false,
  "error_code": "ERROR_CODE",
  "error_message": "Human-readable error message",
  "hint": "Optional hint for resolution"
}
```

### Common Error Codes

| Error Code | Description | Resolution |
|------------|-------------|------------|
| `UNAUTHORIZED` | Not using service role key | Use service role key instead of regular JWT |
| `MERCHANT_CODE_EXISTS` | Merchant code already taken | Use different code |
| `MERCHANT_NOT_FOUND` | Merchant doesn't exist | Check merchant_code spelling |
| `INVALID_MERCHANT_CODE` | Code format invalid | Use lowercase alphanumeric only |
| `INVALID_DELAY_TYPE` | Invalid currency_award_delay_type | Use: immediate, rolling_minutes, rolling_days, scheduled |
| `INVALID_ENVIRONMENT` | Invalid environment value | Use: production, staging, development, test |
| `INVALID_ROLE` | Role doesn't exist | Use: owner, admin, manager, viewer |
| `INVALID_EMAIL` | Email format wrong | Provide valid email |
| `USER_ALREADY_EXISTS` | User already in merchant | User already has access |
| `USER_NOT_FOUND` | User not found in merchant | Check auth_user_id and merchant_code |
| `EMAIL_ALREADY_EXISTS` | Email used by another user | Use different email |
| `CREDENTIALS_EXIST` | Credentials already exist | Delete old ones first or use different environment |
| `UNEXPECTED_ERROR` | Database error | Check logs for details |

---

## Testing

### Test Data

```sql
-- Test merchant creation
SELECT superadmin_create_merchant(
  'Test Merchant',
  'testmerchant',
  ARRAY['line']
);

-- Test credentials
SELECT superadmin_create_merchant_credentials(
  'testmerchant',
  'line',
  '{"channel_id": "test123", "channel_secret": "testsecret"}'::jsonb,
  'development'  -- Valid: production, staging, development, test
);

-- Test admin user
SELECT superadmin_create_admin_user(
  'testmerchant',
  'test@test.com',
  gen_random_uuid(),
  'admin',
  'Test Admin'
);
```

### Cleanup Test Data

```sql
-- Delete test admin users
DELETE FROM admin_users WHERE merchant_id IN (
  SELECT id FROM merchant_master WHERE merchant_code = 'testmerchant'
);

-- Delete test credentials
DELETE FROM merchant_credentials WHERE merchant_code = 'testmerchant';

-- Delete test merchant
DELETE FROM merchant_master WHERE merchant_code = 'testmerchant';
```

---

## Valid Constraint Values

### Environment (merchant_credentials)
- `'production'` - Live production credentials
- `'staging'` - Staging environment
- `'development'` - Development environment
- `'test'` - Testing environment

### Currency Award Delay Type (merchant_master)
- `'immediate'` - Award currency immediately
- `'rolling_minutes'` - Delay by minutes (rolling)
- `'rolling_days'` - Delay by days (rolling)
- `'scheduled'` - Award at specific time

### Points Expiry Mode (merchant_master)
- `'none'` - Points never expire
- `'rolling'` - Rolling expiry based on TTL
- `'fiscal'` - Fiscal year-end expiry

### Earn Rate Entity Type (merchant_master)
- `'tier'` - Earn rate based on tier
- `'persona'` - Earn rate based on persona

### Admin Roles (admin_roles)
- `'owner'` - Full access, merchant owner
- `'admin'` - Full access except critical settings
- `'manager'` - Can manage users and content
- `'viewer'` - Read-only access

### Auth Methods (merchant_master)
- `'line'` - LINE login
- `'tel'` - Phone OTP
- Both: `ARRAY['line', 'tel']`

### Referral Activation Trigger (merchant_master)
- `'first_purchase'` - Activated on first purchase
- `'registration'` - Activated on registration

---

## Best Practices

1. **Use Service Role Key**: Always use service role key for backend operations, never expose to frontend
2. **Validate merchant_code format**: Lowercase, alphanumeric, hyphens/underscores only
3. **Use staged setup for complex merchants**: Create merchant → Add credentials → Add users
4. **Store credentials securely**: Never log or expose credentials in plain text
5. **Set expiry dates**: For temporary or trial credentials
6. **Use environment tags**: Separate production/staging/development/test credentials
7. **Document credential structures**: Different services need different credential formats
8. **Audit all operations**: Implement audit logging for compliance
9. **Test in development first**: Always test with development environment before production
10. **Rotate credentials regularly**: Set expires_at and rotate before expiry
11. **Update only what's needed**: Functions only update non-null parameters
12. **Use transactions**: Batch related operations in database transactions

---

## Related Documentation

- [Authentication System](./Authentication.md) - End-user and admin authentication
- [Admin Roles & Permissions](./Admin_Roles.md) - Role-based access control
- [Merchant Configuration](./Merchant_Configuration.md) - Merchant settings and features

---

*Document Version: 2.0*  
*Last Updated: January 2026*  
*System: Supabase CRM - Superadmin Functions*
