# CRM Bulk Import Service

Render Web Service for bulk importing purchase transactions via CSV upload.

## Overview

This service handles:
- CSV file uploads (up to 100MB)
- Batch job creation and tracking
- Triggering Inngest workflows for async processing
- Status checking and import history

## Architecture

```
User uploads CSV → Render API → Creates batch record → Triggers Inngest
                                                     ↓
                                      Supabase Edge Function processes import
                                                     ↓
                                      Atomic database insert (all or nothing)
                                                     ↓
                                      CDC → Kafka → Event processing
```

## Setup

### Prerequisites

- Node.js 20+
- Supabase project with bulk import schema deployed
- Inngest account with signing key

### Installation

```bash
npm install
```

### Environment Variables

Create `.env` file based on `.env.example`:

```env
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_ROLE_KEY=your-service-role-key
INNGEST_EVENT_KEY=your-inngest-event-key
PORT=3000
```

### Development

```bash
npm run dev
```

### Build

```bash
npm run build
npm start
```

## API Endpoints

### POST /api/import/purchases

Upload CSV file and start import.

**Request:**
```bash
curl -X POST http://localhost:3000/api/import/purchases \
  -F "file=@purchases.csv" \
  -F "merchant_id=uuid-here" \
  -F "batch_name=January 2024 Import"
```

**Response:**
```json
{
  "success": true,
  "batch_id": "uuid-here",
  "message": "Import started. Check status endpoint for progress."
}
```

### GET /api/import/status/:batch_id

Check import status.

**Response:**
```json
{
  "id": "uuid-here",
  "merchant_id": "uuid-here",
  "status": "completed",
  "imported_purchases": 1234,
  "imported_items": 5678,
  "started_at": "2024-01-15T10:00:00Z",
  "completed_at": "2024-01-15T10:03:42Z"
}
```

### GET /api/import/list/:merchant_id

List recent imports for merchant (last 50).

**Response:**
```json
[
  {
    "id": "uuid-here",
    "merchant_id": "uuid-here",
    "batch_name": "January 2024 Import",
    "status": "completed",
    "imported_purchases": 1234,
    "imported_items": 5678,
    "created_at": "2024-01-15T10:00:00Z"
  }
]
```

### GET /health

Health check endpoint.

**Response:**
```json
{
  "status": "healthy",
  "service": "crm-bulk-import"
}
```

## CSV Format

**Required columns:**
- `transaction_number` - Unique identifier (groups line items)
- `transaction_date` - ISO timestamp
- `user_id` - UUID of buyer
- `final_amount` - Total purchase amount
- `sku_id` - UUID of product SKU
- `quantity` - Item quantity
- `unit_price` - Price per unit
- `line_total` - Line item total

**Optional columns:**
- `store_id`, `discount_amount`, `tax_amount`, `status`, `payment_status`, `record_type`, `processing_method`, `earn_currency`, `transaction_source`, `external_ref`, `notes`, `item_discount_amount`, `item_tax_amount`

**Example:**
```csv
transaction_number,transaction_date,user_id,final_amount,sku_id,quantity,unit_price,line_total
TXN001,2024-01-15T10:00:00Z,uuid-user-1,350.00,uuid-sku-coffee,2,120.00,240.00
TXN001,2024-01-15T10:00:00Z,uuid-user-1,350.00,uuid-sku-tea,1,110.00,110.00
TXN002,2024-01-15T11:30:00Z,uuid-user-2,500.00,uuid-sku-lunch,1,500.00,500.00
```

**Note:** Purchase-level fields are duplicated across all line items with the same `transaction_number`.

## Deployment (Render)

1. Push code to GitHub
2. Create new Web Service in Render
3. Connect to GitHub repo
4. Set environment variables:
   - `SUPABASE_URL`
   - `SUPABASE_SERVICE_ROLE_KEY`
   - `INNGEST_EVENT_KEY`
5. Deploy

## Error Handling

- **Validation errors**: Batch marked as `failed`, no database changes
- **Database errors**: Automatic rollback, batch marked as `failed`
- **File errors**: Batch marked as `failed`, file deleted

All errors are logged and stored in `bulk_import_batches.error_message`.

## Performance

| Rows | Transactions | Estimated Time |
|------|--------------|----------------|
| 1,000 | ~300 | ~10 seconds |
| 10,000 | ~3,000 | ~1 minute |
| 50,000 | ~15,000 | ~5 minutes |
| 100,000 | ~30,000 | ~10 minutes |

## License

Proprietary - Rocket CRM
