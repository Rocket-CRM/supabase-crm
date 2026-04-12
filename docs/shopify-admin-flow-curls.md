# Shopify Admin Flow - cURL Examples

## Function 1: Upsert Merchant with Credentials

**Purpose:** Check if merchant exists, create if not

**Endpoint:** Database RPC function

### cURL Example

```bash
curl -X POST 'https://wkevmsedchftztoolkmi.supabase.co/rest/v1/rpc/shopify_upsert_merchant_with_credentials' \
  -H "apikey: YOUR_SUPABASE_ANON_KEY" \
  -H "Authorization: Bearer YOUR_SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "p_merchant_code": "quickstart-ef112207.myshopify.com",
    "p_merchant_name": "QuickStart Store",
    "p_shopify_credentials": {
      "api_key": "c1d554532c476865b0ec50a97fce37f0",
      "api_secret": "shpss_REDACTED",
      "shop_domain": "quickstart-ef112207.myshopify.com",
      "access_token": "shpua_REDACTED"
    }
  }'
```

### Success Response (New Merchant)

```json
{
  "success": true,
  "is_new": true,
  "merchant_id": "550e8400-e29b-41d4-a716-446655440000",
  "merchant_code": "quickstart-ef112207.myshopify.com",
  "merchant_name": "QuickStart Store",
  "credentials_exist": true,
  "message": "Merchant created with Shopify credentials"
}
```

### Success Response (Existing Merchant)

```json
{
  "success": true,
  "is_new": false,
  "merchant_id": "550e8400-e29b-41d4-a716-446655440000",
  "merchant_code": "quickstart-ef112207.myshopify.com",
  "merchant_name": "QuickStart Store",
  "credentials_exist": true,
  "message": "Merchant found, credentials updated"
}
```

---

## Function 2: Authenticate Shopify Admin

**Purpose:** Verify Shopify admin token, find/create admin, return CRM token

**Endpoint:** Edge Function

### cURL Example

```bash
curl -X POST 'https://wkevmsedchftztoolkmi.supabase.co/functions/v1/auth-shopify-admin' \
  -H "Content-Type: application/json" \
  -d '{
    "shopify_admin_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "merchant_code": "quickstart-ef112207.myshopify.com"
  }'
```

### Success Response (New Admin)

```json
{
  "success": true,
  "admin_user": {
    "id": "650e8400-e29b-41d4-a716-446655440001",
    "email": "admin@quickstart.com",
    "name": "John Smith",
    "merchant_code": "quickstart-ef112207.myshopify.com"
  },
  "crm_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJhdWQiOiJhdXRoZW50aWNhdGVkIiwicm9sZSI6ImF1dGhlbnRpY2F0ZWQiLCJleHAiOjE3MDU1MzI0MDAsInN1YiI6IjY1MGU4NDAwLWUyOWItNDFkNC1hNzE2LTQ0NjY1NTQ0MDAwMSIsImVtYWlsIjoiYWRtaW5AcXVpY2tzdGFydC5jb20iLCJtZXJjaGFudF9pZCI6IjU1MGU4NDAwLWUyOWItNDFkNC1hNzE2LTQ0NjY1NTQ0MDAwMCIsIm1lcmNoYW50X2NvZGUiOiJxdWlja3N0YXJ0LWVmMTEyMjA3Lm15c2hvcGlmeS5jb20iLCJ1c2VyX21ldGFkYXRhIjp7InJvbGUiOiJhZG1pbiIsInNvdXJjZSI6InNob3BpZnlfYWRtaW4ifX0.abc123...",
  "is_new_admin": true
}
```

### Success Response (Existing Admin)

```json
{
  "success": true,
  "admin_user": {
    "id": "650e8400-e29b-41d4-a716-446655440001",
    "email": "admin@quickstart.com",
    "name": "John Smith",
    "merchant_code": "quickstart-ef112207.myshopify.com"
  },
  "crm_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "is_new_admin": false
}
```

### Error Responses

**Invalid Token:**
```json
{
  "success": false,
  "error": "Invalid token signature"
}
```

**Token Expired:**
```json
{
  "success": false,
  "error": "Token expired"
}
```

**Merchant Not Found:**
```json
{
  "success": false,
  "error": "Merchant not found"
}
```

---

## Complete Flow Example

### Step 1: Create/Check Merchant

```bash
# First call - creates merchant
curl -X POST 'https://wkevmsedchftztoolkmi.supabase.co/rest/v1/rpc/shopify_upsert_merchant_with_credentials' \
  -H "apikey: YOUR_ANON_KEY" \
  -H "Authorization: Bearer YOUR_SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "p_merchant_code": "quickstart-ef112207.myshopify.com",
    "p_merchant_name": "QuickStart Store",
    "p_shopify_credentials": {
      "api_key": "c1d554532c476865b0ec50a97fce37f0",
      "api_secret": "shpss_REDACTED",
      "shop_domain": "quickstart-ef112207.myshopify.com",
      "access_token": "shpua_REDACTED"
    }
  }'
```

Response:
```json
{
  "success": true,
  "is_new": true,
  "merchant_id": "550e8400-e29b-41d4-a716-446655440000",
  "merchant_code": "quickstart-ef112207.myshopify.com"
}
```

### Step 2: Authenticate Admin

```bash
# Shopify provides admin token to your app
# Your frontend sends it to verify and get CRM token
curl -X POST 'https://wkevmsedchftztoolkmi.supabase.co/functions/v1/auth-shopify-admin' \
  -H "Content-Type: application/json" \
  -d '{
    "shopify_admin_token": "eyJ...",
    "merchant_code": "quickstart-ef112207.myshopify.com"
  }'
```

Response:
```json
{
  "success": true,
  "admin_user": {
    "id": "650e8400-e29b-41d4-a716-446655440001",
    "email": "admin@quickstart.com"
  },
  "crm_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "is_new_admin": true
}
```

### Step 3: Use CRM Token

```bash
# Use the CRM token for all subsequent API calls
curl -X POST 'https://wkevmsedchftztoolkmi.supabase.co/rest/v1/rpc/some_crm_function' \
  -H "apikey: YOUR_ANON_KEY" \
  -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..." \
  -H "Content-Type: application/json" \
  -d '{
    "param": "value"
  }'
```

---

## Notes

1. **Merchant Code**: Use full Shopify domain (e.g., `quickstart-ef112207.myshopify.com`)

2. **Shopify Admin Token**: Your Shopify app generates this JWT signed with the shop's API secret

3. **CRM Token**: The token returned by `auth-shopify-admin` is what you use for all CRM operations

4. **Token Expiration**: CRM tokens expire after 24 hours (86400 seconds)

5. **Security**: 
   - Function 1 requires service role key
   - Function 2 is publicly accessible (verifies Shopify signature)

6. **Idempotency**: 
   - Calling Function 1 multiple times is safe (upsert)
   - Calling Function 2 multiple times creates new tokens but doesn't duplicate admins
