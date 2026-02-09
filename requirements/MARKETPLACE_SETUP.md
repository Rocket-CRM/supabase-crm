# Marketplace Integration v2.0 - Setup Guide

## Implementation Summary

**Architecture:** Hookdeck → Kafka → Render Consumer → Inngest → Database

**Key Feature:** All flow control via Inngest native batching (no manual state management)

---

## Phase 1: Kafka Topic Setup

### Step 1: Create Topic in Confluent Cloud

1. Go to: https://confluent.cloud
2. Navigate to: Environments → Your environment → Cluster `lkc-6r72k2`
3. Click: **Topics** → **Create topic**

**Topic Configuration:**
```yaml
Topic name: marketplace.orders
Partitions: 100
Partition strategy: By key (shop_id)
Retention time: 7 days (168 hours)
Cleanup policy: Delete
Replication factor: 3 (default)
```

4. Click **Create with defaults**

### Step 2: Create API Keys

**Key 1: Write Access (for Hookdeck)**

1. Navigate to: **API Keys** → **Add key**
2. Scope: **Granular access**
3. Resource type: **Topic**
4. Topic name: `marketplace.orders`
5. Operations: **Write**
6. Click **Create**
7. **Save both API Key and Secret immediately** (secret shown once only)

```
Write Key: ___________________
Write Secret: ___________________
```

**Key 2: Read Access (for Render Consumer)**

1. Navigate to: **API Keys** → **Add key**
2. Scope: **Granular access**
3. Resource type: **Topic**
4. Topic name: `marketplace.orders`
5. Operations: **Read**
6. Click **Create**
7. **Save both API Key and Secret**

```
Read Key: ___________________
Read Secret: ___________________
```

### Step 3: Test Topic

```bash
# Replace with your actual credentials
KAFKA_REST_ENDPOINT="https://pkc-ox31np.ap-southeast-7.aws.confluent.cloud:443"
CLUSTER_ID="lkc-6r72k2"
WRITE_KEY="your-write-key"
WRITE_SECRET="your-write-secret"

# Encode credentials
AUTH=$(echo -n "$WRITE_KEY:$WRITE_SECRET" | base64)

# Test publish
curl -X POST \
  "$KAFKA_REST_ENDPOINT/kafka/v3/clusters/$CLUSTER_ID/topics/marketplace.orders/records" \
  -H "Content-Type: application/json" \
  -H "Authorization: Basic $AUTH" \
  -d '{
    "key": {
      "type": "STRING",
      "data": "shop-test123"
    },
    "value": {
      "type": "JSON",
      "data": {
        "platform": "shopee",
        "shop_id": "test123",
        "order_sn": "TEST001",
        "order_status": "READY_TO_SHIP",
        "timestamp": 1735689600000
      }
    }
  }'
```

**Expected Response:**
```json
{
  "cluster_id": "lkc-6r72k2",
  "topic_name": "marketplace.orders",
  "partition_id": 42,
  "offset": 0
}
```

**Verify in Confluent Console:**
- Go to Topics → marketplace.orders → Messages
- You should see your test message

---

## Phase 2: Hookdeck Configuration

### Step 1: Create Destination

1. Go to: https://dashboard.hookdeck.com
2. Navigate to: **Destinations** → **Add Destination**

**Destination Configuration:**

```yaml
Name: Confluent Kafka - Marketplace Orders

URL: https://pkc-ox31np.ap-southeast-7.aws.confluent.cloud:443/kafka/v3/clusters/lkc-6r72k2/topics/marketplace.orders/records

HTTP Method: POST

Headers:
  - Name: Content-Type
    Value: application/json
  
  - Name: Authorization
    Value: Basic [base64 of WRITE_KEY:WRITE_SECRET]
```

**To encode Authorization header:**
```bash
echo -n "WRITE_KEY:WRITE_SECRET" | base64
# Copy output and use: Basic {output}
```

### Step 2: Create Transformation

In Hookdeck, create transformation:

**Name:** Shopee to Kafka Format

**Code:**
```javascript
function transform(request) {
  const webhook = request.body;
  
  // Filter 1: Skip UNPAID orders (not eligible for points)
  if (webhook.order_status === 'UNPAID') {
    console.log('Filtered: UNPAID order');
    return { skip: true };
  }
  
  // Filter 2: Validate required fields
  if (!webhook.shop_id || !webhook.order_sn) {
    console.error('Invalid webhook: missing shop_id or order_sn');
    return { skip: true };
  }
  
  // Transform to Kafka REST API format
  return {
    body: {
      key: {
        type: 'STRING',
        data: `shop-${webhook.shop_id}`
      },
      value: {
        type: 'JSON',
        data: {
          platform: 'shopee',
          shop_id: webhook.shop_id,
          order_sn: webhook.order_sn,
          order_status: webhook.order_status,
          timestamp: Date.now()
        }
      }
    }
  };
}
```

### Step 3: Create Connection

1. Navigate to: **Connections** → **Add Connection**

**Connection Configuration:**

```yaml
Name: Shopee Orders to Kafka

Source: 
  - Create new or select existing Shopee webhook source
  - URL will be: https://events.hookdeck.com/e/src_xxxxx

Transformation:
  - Select: "Shopee to Kafka Format" (created above)

Destination:
  - Select: "Confluent Kafka - Marketplace Orders" (created above)

Rules:
  - Retry strategy: Exponential backoff
  - Max attempts: 3
```

2. Click **Create Connection**

### Step 4: Test Hookdeck → Kafka

**Send test webhook:**

```bash
# Get your Hookdeck source URL from the connection
HOOKDECK_URL="https://events.hookdeck.com/e/src_xxxxx"

curl -X POST "$HOOKDECK_URL" \
  -H "Content-Type: application/json" \
  -d '{
    "shop_id": "123456",
    "order_sn": "TEST002",
    "order_status": "READY_TO_SHIP",
    "update_time": 1735689600
  }'
```

**Verify:**
1. Hookdeck dashboard: Request should show "Success" status
2. Confluent console: Message should appear in `marketplace.orders` topic

---

## Phase 3: Deploy Inngest Workflow

### Step 1: Deploy Edge Function

```bash
cd /Users/rangwan/Documents/Supabase\ CRM

supabase functions deploy inngest-marketplace-serve --no-verify-jwt
```

**Expected output:**
```
Deploying Function inngest-marketplace-serve (project ref: wkevmsedchftztoolkmi)
✓ Function deployed successfully
Function URL: https://wkevmsedchftztoolkmi.supabase.co/functions/v1/inngest-marketplace-serve
```

### Step 2: Configure Inngest App

1. Go to: https://app.inngest.com
2. Navigate to: **Apps** → Find or create app `marketplace-serve`
3. Click: **Sync** → **Add App URL**

**App Configuration:**

```yaml
App ID: marketplace-serve

Endpoint URL: https://wkevmsedchftztoolkmi.supabase.co/functions/v1/inngest-marketplace-serve

Signing Key: (copy from Inngest dashboard)
```

4. Click **Sync** to register the workflow

**Verify:**
- You should see function `process-shop-orders` appear in Inngest dashboard
- Check that batching config is visible:
  - Batch size: 50
  - Timeout: 2m
  - Rate limit: 30/1m

### Step 3: Set Environment Variables (Supabase)

```bash
# Set Inngest signing key
supabase secrets set INNGEST_SIGNING_KEY=your-signing-key-from-inngest-dashboard

# Verify Supabase credentials already set
supabase secrets list
# Should show: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
```

---

## Phase 4: Update Render Consumer

### Step 1: Update Environment Variables

In Render dashboard for `crm-event-processors` service:

**Add:**
```bash
KAFKA_TOPIC_MARKETPLACE_ORDERS=marketplace.orders
```

**Verify existing:**
```bash
KAFKA_BOOTSTRAP_SERVERS=pkc-ox31np.ap-southeast-7.aws.confluent.cloud:9092
KAFKA_API_KEY={read-key-from-step-2-above}
KAFKA_API_SECRET={read-secret-from-step-2-above}
INNGEST_EVENT_KEY={your-inngest-event-key}
```

### Step 2: Deploy Updated Consumer

```bash
cd crm-event-processors

# Commit changes
git add .
git commit -m "Add MarketplaceConsumer for event-driven order processing"
git push origin main
```

**Render will auto-deploy**

**Verify in Render logs:**
```
[MarketplaceConsumer] Starting...
[MarketplaceConsumer] Running
```

---

## Phase 5: Integration Testing

### Test 1: Single Order Flow

**Send test webhook via Hookdeck:**

```bash
curl -X POST "https://events.hookdeck.com/e/src_xxxxx" \
  -H "Content-Type: application/json" \
  -d '{
    "shop_id": "123456",
    "order_sn": "TEST_SINGLE_001",
    "order_status": "READY_TO_SHIP",
    "update_time": 1735689600
  }'
```

**Expected behavior:**
1. Hookdeck filters (UNPAID check passes)
2. Hookdeck posts to Kafka ✓
3. Consumer receives message ✓
4. Consumer forwards to Inngest ✓
5. Inngest queues event (waiting for batch or timeout) ✓

**Check Inngest Dashboard:**
- Event should appear in Events tab
- Workflow should NOT run yet (waiting for 49 more or 2-minute timeout)

### Test 2: Batch Trigger (50 Orders)

**Send 50 orders:**

```bash
for i in {1..50}; do
  curl -X POST "https://events.hookdeck.com/e/src_xxxxx" \
    -H "Content-Type: application/json" \
    -d "{
      \"shop_id\": \"123456\",
      \"order_sn\": \"TEST_BATCH_$(printf %03d $i)\",
      \"order_status\": \"READY_TO_SHIP\",
      \"update_time\": $(date +%s)
    }"
  sleep 0.1
done
```

**Expected behavior:**
1. All 50 messages arrive in Kafka ✓
2. Consumer forwards all 50 to Inngest ✓
3. Inngest batches them (shop_id matches) ✓
4. After 50th event: Workflow triggers immediately ✓
5. Workflow receives `events` array with 50 items ✓
6. Step 1: Get credentials (should fail if no test credentials) ✓

**Check Inngest Dashboard:**
- Function Runs tab should show 1 run
- Click into run to see workflow trace
- Should see all 50 events in batch

### Test 3: Timeout Trigger (Partial Batch)

**Send 15 orders and wait:**

```bash
for i in {1..15}; do
  curl -X POST "https://events.hookdeck.com/e/src_xxxxx" \
    -H "Content-Type: application/json" \
    -d "{
      \"shop_id\": \"789012\",
      \"order_sn\": \"TEST_TIMEOUT_$(printf %03d $i)\",
      \"order_status\": \"SHIPPED\",
      \"update_time\": $(date +%s)
    }"
done
```

**Expected behavior:**
1. 15 events accumulated in Inngest ✓
2. Wait 2 minutes... ✓
3. Workflow triggers with 15-event batch ✓
4. Workflow processes partial batch ✓

### Test 4: UNPAID Filtering

**Send UNPAID order:**

```bash
curl -X POST "https://events.hookdeck.com/e/src_xxxxx" \
  -H "Content-Type: application/json" \
  -d '{
    "shop_id": "123456",
    "order_sn": "TEST_UNPAID_001",
    "order_status": "UNPAID",
    "update_time": 1735689600
  }'
```

**Expected behavior:**
1. Hookdeck receives webhook ✓
2. Transformation filters it (skip: true) ✓
3. Not forwarded to Kafka ✓
4. Consumer never sees it ✓

**Verify:**
- Hookdeck dashboard shows request with "Filtered" status
- Kafka topic does NOT contain this message

---

## Phase 6: Production Setup

### Prerequisites

Before going live, ensure you have:

1. **Valid Shop Credentials** in `merchant_shopee_config`:
```sql
INSERT INTO merchant_shopee_config (
  merchant_id,
  shop_id,
  partner_id,
  access_token,
  refresh_token,
  is_active
) VALUES (
  'your-merchant-uuid',
  'your-actual-shop-id',
  'your-partner-id',
  'your-access-token',
  'your-refresh-token',
  true
);
```

2. **Shopee Webhook URL** pointing to Hookdeck

### Cutover Steps

1. **Shadow Mode (4 hours):**
   - Keep old webhook receiver active
   - Add Hookdeck connection (new path)
   - Monitor both paths
   - Compare order counts

2. **Switch to New (2 hours):**
   - Update Shopee webhook URL to Hookdeck only
   - Monitor Inngest dashboard
   - Verify orders processing

3. **Verify (24 hours):**
   - Check database for new orders
   - Monitor workflow success rate
   - Check for any errors

### Rollback Plan

If issues occur:
```
1. Revert Shopee webhook URL to old receiver
2. Old Edge Functions still deployed (don't delete yet)
3. Old cron job can be re-enabled if needed
```

---

## Phase 7: Cleanup (After 1 Week Stable)

### Remove Old Components

**1. Delete Cron Job:**
```sql
SELECT cron.unschedule('shopee-batch-checker');
```

**2. Delete Old Edge Functions:**
```bash
supabase functions delete shopee-webhook-receiver
supabase functions delete shopee-batch-checker
supabase functions delete shopee-process-orders
```

**3. Archive Old Code:**
```bash
mkdir -p archive/marketplace-v1
mv supabase/functions/shopee-* archive/marketplace-v1/
```

---

## Monitoring & Operations

### Inngest Dashboard

**URL:** https://app.inngest.com

**Key Metrics:**
- **Function Runs**: Total workflow executions
- **Success Rate**: Should be >99%
- **Average Duration**: Typically 2-5 seconds per batch
- **Batched Events**: Shows how many orders per batch (avg should be ~50)

**Debugging Failed Workflows:**
1. Go to: Functions → `process-shop-orders` → Filter by "Failed"
2. Click into failed run
3. See which step failed (Step 1, 2, or 3)
4. Check error message
5. Retry from failed step if transient error

### Confluent Dashboard

**Monitor:**
- **Consumer Lag**: Should stay under 100 messages
- **Throughput**: Messages/second published
- **Partition Distribution**: Should be balanced across 100 partitions

### Supabase Database

**Monitor:**
```sql
-- Orders processed per hour
SELECT 
  DATE_TRUNC('hour', processed_at) as hour,
  COUNT(*) as orders_processed,
  COUNT(DISTINCT shop_id) as shops_processed
FROM shopee_orders_raw
WHERE processed_at >= NOW() - INTERVAL '24 hours'
GROUP BY 1
ORDER BY 1 DESC;

-- Recent processing status
SELECT 
  shop_id,
  COUNT(*) as orders,
  MAX(processed_at) as last_processed
FROM shopee_orders_raw
WHERE processed_at >= NOW() - INTERVAL '1 hour'
GROUP BY shop_id
ORDER BY last_processed DESC;
```

---

## Troubleshooting

### Orders Not Processing

**Check 1: Kafka Topic**
- Confluent console → Topics → marketplace.orders → Messages
- Are messages arriving?

**Check 2: Consumer**
- Render logs for `crm-event-processors`
- Should see: `[MarketplaceConsumer] Forwarded to Inngest`

**Check 3: Inngest**
- Inngest dashboard → Events
- Are `marketplace/order-received` events arriving?
- Check batching status

**Check 4: Workflow**
- Inngest dashboard → Functions → `process-shop-orders`
- Are workflows being triggered?
- Check for failed runs

### High Failure Rate

**Check Step Failures:**

**Step 1 (get-credentials) fails:**
- Verify shop_id exists in `merchant_shopee_config`
- Check `is_active = true`
- Verify credentials not expired

**Step 2 (call-shopee-api) fails:**
- Check Shopee API status
- Verify access_token is valid
- Check if rate limited (should be prevented by Inngest)
- Review retry attempts (should be 3x)

**Step 3 (save-orders) fails:**
- Check database connection
- Verify `shopee_orders_raw` table exists
- Check for unique constraint violations (expected, handled by upsert)

### Rate Limiting Issues

If getting 429 errors from Shopee despite rate limiting:

**Adjust Inngest config:**
```typescript
rateLimit: {
  limit: 20,    // Reduce from 30 to 20
  period: '1m',
  key: 'data.shop_id'
}
```

---

## Configuration Reference

### Kafka Topic
```
Topic: marketplace.orders
Cluster: lkc-6r72k2
Endpoint: https://pkc-ox31np.ap-southeast-7.aws.confluent.cloud:443
Partitions: 100
Retention: 7 days
```

### Inngest Flow Control
```typescript
batchEvents: {
  maxSize: 50,        // Shopee API limit
  timeout: '2m',      // Cooldown period
  key: 'data.shop_id' // Per-shop batching
}

rateLimit: {
  limit: 30,          // API calls per minute
  period: '1m',
  key: 'data.shop_id'
}

concurrency: {
  limit: 10,          // Parallel shops
  key: 'data.shop_id'
}
```

### Database Tables
```
Credentials: merchant_shopee_config
Orders: shopee_orders_raw
```

---

## Success Criteria

**Technical:**
- [ ] Kafka topic created and accessible
- [ ] Hookdeck filters UNPAID orders
- [ ] Consumer forwards events to Inngest
- [ ] Inngest batches 50 orders per shop
- [ ] Workflow calls Shopee API successfully
- [ ] Orders saved to database

**Operational:**
- [ ] Zero manual intervention required
- [ ] All monitoring via Inngest dashboard
- [ ] Rollback plan tested

**Business:**
- [ ] Orders processed within 5 minutes
- [ ] No 429 rate limit errors
- [ ] Zero duplicate orders in database
