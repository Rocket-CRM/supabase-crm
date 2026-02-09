# Bulk Import System - Deployment Checklist

Use this checklist to deploy the bulk import system step by step.

---

## Pre-Deployment Verification

- [ ] Ensure you have access to:
  - [ ] Supabase Dashboard (SQL Editor + Edge Functions)
  - [ ] Inngest Dashboard
  - [ ] Render Dashboard
  - [ ] GitHub account

---

## Step 1: Database Schema Deployment

**Location:** Supabase Dashboard → SQL Editor

- [ ] Open `sql/bulk_import_schema.sql` file
- [ ] Copy entire contents
- [ ] Paste into Supabase SQL Editor
- [ ] Click "Run" to execute
- [ ] Verify success (should see "Success. No rows returned")
- [ ] Test table creation:
  ```sql
  SELECT * FROM bulk_import_batches LIMIT 1;
  ```
- [ ] Should return empty result (no error)
- [ ] Test function exists:
  ```sql
  SELECT proname FROM pg_proc WHERE proname = 'bulk_insert_purchases_with_items';
  ```
- [ ] Should return 1 row with function name

**Status:** ⬜ Not Started | ⬜ In Progress | ⬜ Completed | ⬜ Failed

---

## Step 2: Inngest Configuration

**Location:** Inngest Dashboard (https://www.inngest.com)

- [ ] Log in to Inngest dashboard
- [ ] Go to Settings → Keys
- [ ] Copy **Signing Key** (starts with `signkey_`)
- [ ] Copy **Event Key** (starts with `key_`)
- [ ] Save both keys securely (you'll need them in next steps)

**Keys saved:**
- Signing Key: `signkey_...` ⬜
- Event Key: `key_...` ⬜

**Status:** ⬜ Not Started | ⬜ In Progress | ⬜ Completed | ⬜ Failed

---

## Step 3: Supabase Edge Function Deployment

**Location:** Supabase Dashboard → Edge Functions

### Option A: Via Dashboard (Recommended for first deployment)

- [ ] Go to Supabase Dashboard → Edge Functions
- [ ] Click "Create a new function"
- [ ] Set name: `inngest-bulk-import-serve`
- [ ] Open `supabase-functions/inngest-bulk-import-serve/index.ts`
- [ ] Copy entire contents
- [ ] Paste into function editor
- [ ] Click "Deploy function"
- [ ] Wait for deployment to complete

### Configure Environment Variables

- [ ] In Edge Functions, click on `inngest-bulk-import-serve`
- [ ] Go to "Settings" tab
- [ ] Add environment variable:
  - Key: `INNGEST_SIGNING_KEY`
  - Value: [Paste signing key from Step 2]
- [ ] Click "Save"

### Test Deployment

- [ ] Get function URL (should be like: `https://PROJECT.supabase.co/functions/v1/inngest-bulk-import-serve`)
- [ ] Test with curl:
  ```bash
  curl -X GET https://YOUR-PROJECT.supabase.co/functions/v1/inngest-bulk-import-serve
  ```
- [ ] Should return Inngest registration response

**Function URL:** `https://_________________________.supabase.co/functions/v1/inngest-bulk-import-serve`

**Status:** ⬜ Not Started | ⬜ In Progress | ⬜ Completed | ⬜ Failed

---

## Step 4: Configure Inngest Webhook

**Location:** Inngest Dashboard → Apps → Webhooks

- [ ] Go to Inngest Dashboard
- [ ] Select your app (or create new: `crm-bulk-import-system`)
- [ ] Go to "Serve API/SDK" tab
- [ ] Click "Manage" for your environment (Production)
- [ ] Add new serve endpoint:
  - URL: [Function URL from Step 3]
  - Signing key: [Already configured]
- [ ] Click "Sync"
- [ ] Verify function discovered: `bulk-import-purchases`
- [ ] Should show status as "Active"

**Status:** ⬜ Not Started | ⬜ In Progress | ⬜ Completed | ⬜ Failed

---

## Step 5: Render Web Service Deployment

**Location:** Render Dashboard + GitHub

### 5.1 Push to GitHub

- [ ] Open terminal
- [ ] Navigate to crm-bulk-import folder:
  ```bash
  cd "/Users/rangwan/Documents/Supabase CRM/crm-bulk-import"
  ```
- [ ] Initialize git:
  ```bash
  git init
  git add .
  git commit -m "Initial commit: Bulk import service"
  ```
- [ ] Create new repository on GitHub:
  - Repository name: `crm-bulk-import`
  - Visibility: Private
  - Do NOT initialize with README (we have files already)
- [ ] Copy the remote URL from GitHub
- [ ] Add remote and push:
  ```bash
  git remote add origin https://github.com/YOUR-ORG/crm-bulk-import.git
  git branch -M main
  git push -u origin main
  ```

**GitHub Repository:** `https://github.com/________________________/crm-bulk-import`

### 5.2 Deploy to Render

- [ ] Go to Render Dashboard
- [ ] Click "New +" → "Web Service"
- [ ] Connect to GitHub repository
- [ ] Select `crm-bulk-import` repository
- [ ] Configure settings:
  - **Name:** `crm-bulk-import`
  - **Environment:** `Node`
  - **Region:** Choose closest to your users
  - **Branch:** `main`
  - **Build Command:** `npm install && npm run build`
  - **Start Command:** `npm start`
  - **Instance Type:** `Starter` (for testing) or `Standard` (for production)
  - **Auto-Deploy:** `Yes`

### 5.3 Configure Environment Variables

- [ ] In Render dashboard, go to "Environment" tab
- [ ] Add variables:

| Key | Value | Source |
|-----|-------|--------|
| `SUPABASE_URL` | `https://YOUR-PROJECT.supabase.co` | Supabase Dashboard |
| `SUPABASE_SERVICE_ROLE_KEY` | `eyJhbGc...` | Supabase Dashboard → Settings → API |
| `INNGEST_EVENT_KEY` | `key_...` | From Step 2 |
| `PORT` | `3000` | Default |

- [ ] Click "Save Changes"

### 5.4 Deploy and Verify

- [ ] Click "Manual Deploy" → "Deploy latest commit"
- [ ] Wait for build to complete (~2-5 minutes)
- [ ] Check logs for errors
- [ ] Once deployed, test health endpoint:
  ```bash
  curl https://crm-bulk-import.onrender.com/health
  ```
- [ ] Should return:
  ```json
  {"status": "healthy", "service": "crm-bulk-import"}
  ```

**Render Service URL:** `https://________________________________.onrender.com`

**Status:** ⬜ Not Started | ⬜ In Progress | ⬜ Completed | ⬜ Failed

---

## Step 6: End-to-End Testing

### 6.1 Prepare Test Data

- [ ] Open `crm-bulk-import/sample-purchases.csv`
- [ ] Replace placeholder values:
  - Get a real `user_id` from your database:
    ```sql
    SELECT id FROM user_accounts WHERE merchant_id = 'YOUR-MERCHANT-ID' LIMIT 1;
    ```
  - Get real `sku_id` values:
    ```sql
    SELECT id FROM product_sku_master LIMIT 3;
    ```
  - Replace all instances in CSV file
- [ ] Save the updated CSV

### 6.2 Test Upload

- [ ] Upload CSV via curl:
  ```bash
  curl -X POST https://crm-bulk-import.onrender.com/api/import/purchases \
    -F "file=@sample-purchases.csv" \
    -F "merchant_id=YOUR-MERCHANT-ID" \
    -F "batch_name=Test Import $(date)"
  ```
- [ ] Should receive response:
  ```json
  {
    "success": true,
    "batch_id": "uuid-here",
    "message": "Import started..."
  }
  ```
- [ ] Copy the `batch_id` for next step

**Batch ID:** `_________________________________________`

### 6.3 Monitor Progress

- [ ] Check status immediately:
  ```bash
  curl https://crm-bulk-import.onrender.com/api/import/status/BATCH-ID
  ```
- [ ] Should show `status: "pending"` or `"processing"`
- [ ] Go to Inngest Dashboard → Runs
- [ ] Find the `import/bulk-purchases` event
- [ ] Click to see step-by-step execution
- [ ] Verify all steps complete successfully
- [ ] Check status again:
  ```bash
  curl https://crm-bulk-import.onrender.com/api/import/status/BATCH-ID
  ```
- [ ] Should show `status: "completed"`
- [ ] Note: `imported_purchases` and `imported_items` counts

**Results:**
- Imported purchases: `______`
- Imported items: `______`
- Duration: `______ seconds`

### 6.4 Verify Database

- [ ] Check batch record:
  ```sql
  SELECT * FROM bulk_import_batches ORDER BY created_at DESC LIMIT 1;
  ```
- [ ] Check purchases:
  ```sql
  SELECT * FROM purchase_ledger 
  WHERE transaction_number LIKE 'TXN2024%' 
  ORDER BY created_at DESC LIMIT 10;
  ```
- [ ] Check items:
  ```sql
  SELECT pil.* 
  FROM purchase_items_ledger pil
  JOIN purchase_ledger pl ON pil.transaction_id = pl.id
  WHERE pl.transaction_number LIKE 'TXN2024%'
  ORDER BY pil.created_at DESC LIMIT 10;
  ```

### 6.5 Verify CDC Processing

- [ ] Wait 1-2 minutes for CDC to process
- [ ] Check if CDC picked up inserts:
  - [ ] Go to Confluent dashboard
  - [ ] Check `purchase.public.purchase_ledger` topic
  - [ ] Should see new messages
- [ ] Check Render consumer logs:
  - [ ] Currency consumer should show batch processing
  - [ ] Tier consumer should process tier evaluations
  - [ ] Mission consumer should check mission progress
- [ ] Verify currency awarded:
  ```sql
  SELECT * FROM wallet_ledger 
  WHERE source_type = 'purchase' 
  AND source_id IN (
    SELECT id FROM purchase_ledger WHERE transaction_number LIKE 'TXN2024%'
  );
  ```

**Status:** ⬜ Not Started | ⬜ In Progress | ⬜ Completed | ⬜ Failed

---

## Step 7: Performance Testing (Optional)

### Test with Larger Dataset

- [ ] Generate CSV with 1,000 rows (duplicate sample data)
- [ ] Upload and measure time
- [ ] Expected: ~10-30 seconds
- [ ] Check database load during import
- [ ] Verify all rows inserted successfully

**Results:**
- Rows: `1,000`
- Duration: `______ seconds`
- Success rate: `100%` ⬜

**Status:** ⬜ Not Started | ⬜ In Progress | ⬜ Completed | ⬜ Failed

---

## Troubleshooting

### Issue: Edge function deployment fails

**Check:**
- [ ] Supabase project has edge functions enabled
- [ ] Function code has no syntax errors
- [ ] Import statements use correct ESM URLs

### Issue: Inngest webhook not syncing

**Check:**
- [ ] Function URL is correct and accessible
- [ ] INNGEST_SIGNING_KEY is set in Supabase
- [ ] Function returns proper Inngest registration response

### Issue: Render deployment fails

**Check:**
- [ ] package.json has all dependencies
- [ ] tsconfig.json is valid
- [ ] Build command completes successfully
- [ ] Environment variables are set

### Issue: Upload fails with validation error

**Check:**
- [ ] CSV has correct column headers
- [ ] user_id and sku_id values are valid UUIDs
- [ ] user_id exists in user_accounts table
- [ ] sku_id exists in product_sku_master table
- [ ] merchant_id is correct

### Issue: CDC not processing purchases

**Check:**
- [ ] CDC connector is running (check Confluent dashboard)
- [ ] Kafka topics are receiving messages
- [ ] Render consumers are running
- [ ] Check consumer logs for errors

---

## Post-Deployment Tasks

- [ ] Document service URLs in team wiki
- [ ] Set up monitoring alerts (Render + Inngest)
- [ ] Schedule periodic cleanup of old batch records
- [ ] Train admin team on using the import API
- [ ] Create admin UI (future enhancement)
- [ ] Set up email notifications (future enhancement)

---

## Rollback Plan

If critical issues arise:

1. **Disable Render service:**
   - [ ] Go to Render dashboard
   - [ ] Click "Suspend" on the service

2. **Disable Inngest webhook:**
   - [ ] Go to Inngest dashboard
   - [ ] Remove serve endpoint

3. **Clean up test data (if needed):**
   ```sql
   -- Delete test batches
   DELETE FROM bulk_import_batches WHERE batch_name LIKE '%Test%';
   
   -- Delete test purchases (BE CAREFUL!)
   DELETE FROM purchase_items_ledger WHERE transaction_id IN (
     SELECT id FROM purchase_ledger WHERE transaction_number LIKE 'TXN2024%'
   );
   DELETE FROM purchase_ledger WHERE transaction_number LIKE 'TXN2024%';
   ```

---

## Success Criteria

Deployment is successful when:

- ✅ All database objects created without errors
- ✅ Edge function deploys and syncs with Inngest
- ✅ Render service deploys and health check passes
- ✅ Test CSV upload completes successfully
- ✅ Purchases and items appear in database
- ✅ CDC processes new records
- ✅ Currency/Tier/Mission workflows trigger

---

## Completion

**Deployment completed on:** `__________________`

**Deployed by:** `__________________`

**Production URL:** `https://________________________________.onrender.com`

**Notes:**

```
[Add any notes about deployment issues, workarounds, or special configurations]




```

---

*This checklist is complete once all checkboxes are marked and success criteria are met.*
