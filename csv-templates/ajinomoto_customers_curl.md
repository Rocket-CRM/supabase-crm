# Ajinomoto customer import – curl and sample CSV

## Sample CSV

Use **10 users**: [ajinomoto_customers_sample_10.csv](ajinomoto_customers_sample_10.csv)

Columns (aligned with your source): `firstname`, `lastname`, `fullname`, `tel`, `birth_date`, `email`, `gender`, `addressline_1`, `subdistrict`, `district`, `city`, `postcode`, `total_points`, `created_at`, `branch`, `store_code`, `store_name`, `salesman_code`, `salesman_name`. Empty values use `-`. `birth_date` is DD-MM-YYYY; `created_at` is date (DD-MM-YYYY). `amount` and last-active fields are omitted per plan.

## Curl – customer import

Replace `YOUR_RENDER_URL` and `YOUR_AJINOMOTO_MERCHANT_ID` (UUID from `merchant_master` for Ajinomoto).

**Import and also create `wallet_ledger` rows for points:**

```bash
curl -X POST "YOUR_RENDER_URL/api/import/customers" \
  -F "file=@csv-templates/ajinomoto_customers_sample_10.csv" \
  -F "merchant_id=YOUR_AJINOMOTO_MERCHANT_ID" \
  -F "batch_name=Ajinomoto customers 10" \
  -F "create_wallet_ledger_entry=true"
```

**Import and only update `user_wallet` (no ledger rows):**

```bash
curl -X POST "YOUR_RENDER_URL/api/import/customers" \
  -F "file=@csv-templates/ajinomoto_customers_sample_10.csv" \
  -F "merchant_id=YOUR_AJINOMOTO_MERCHANT_ID" \
  -F "batch_name=Ajinomoto customers 10" \
  -F "create_wallet_ledger_entry=false"
```

**Check status:**

```bash
curl "YOUR_RENDER_URL/api/import/status/BATCH_ID_FROM_RESPONSE"
```

**List recent imports for merchant:**

```bash
curl "YOUR_RENDER_URL/api/import/list/YOUR_AJINOMOTO_MERCHANT_ID"
```

## Get Ajinomoto merchant_id

In Supabase SQL (or via MCP):

```sql
SELECT id, name FROM merchant_master WHERE name ILIKE '%ajinomoto%' LIMIT 1;
```

Use the returned `id` as `YOUR_AJINOMOTO_MERCHANT_ID`.
