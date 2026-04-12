# Rocket Loyalty x Euro Creations API v2.0

**REST API Specification — Asset, Maintenance Plan & User Integration**

> Rocket Innovation Co. Ltd — Strictly Private & Confidential
> Last Updated: March 2, 2026
> Configured for Merchant: Euro Creations (`bf5bc88c-5563-41b4-aa10-5510c9bce39c`)

---

## Table of Contents

1. [Authentication with API Key](#1-authentication-with-api-key)
2. [Create or Update User (Contact/Account)](#2-create-or-update-user)
3. [Update User Details](#3-update-user-details)
4. [Retrieve User Information](#4-retrieve-user-information)
5. [Create Asset](#5-create-asset)
6. [Update Existing Asset](#6-update-existing-asset)
7. [Create Maintenance Plan](#7-create-maintenance-plan)
8. [Update Existing Maintenance Plan](#8-update-existing-maintenance-plan)
9. [Retrieve Asset / Maintenance Plan by ID](#9-retrieve-asset--maintenance-plan-by-id)
10. [Create Third Party Bill (Purchase Transaction)](#10-create-third-party-bill-purchase-transaction)
11. [Error Codes](#error-codes)
12. [Field Mapping Reference (Old → New)](#field-mapping-reference)
13. [Data Formats](#data-formats)

---

## 1. Authentication with API Key

All API requests require authentication using the `x-api-key` header.

| Item | Value |
|------|-------|
| Base URL | `https://open-api.rocket-loyalty.com/functions/v1` |
| Auth Method | Custom API Key Header |
| Header | `x-api-key: {your-api-key}` |
| Expiration | None — API keys remain valid until revoked |

Generate API keys in the Rocket Loyalty admin dashboard under **Settings → API Keys**.

---

## 2. Create or Update User

Create new users or update existing users in the Rocket Loyalty system.

| Item | Value |
|------|-------|
| Method | `POST` |
| URI | `/api-users` |
| Content-Type | `application/json` |

### Request Data Model

#### Basic Information

| Field | Required | Type | Remark |
|-------|----------|------|--------|
| `tel` | Mandatory | String | Phone number. Accepts both `0812345678` and `+66812345678` format; system auto-normalizes to `+66` E.164. |
| `fullname` | Mandatory | String | Full name |
| `firstname` | Optional | String | First name |
| `lastname` | Optional | String | Last name |
| `email` | Optional | String | Email address |
| `line_id` | Optional | String | LINE messenger ID |
| `id_card` | Optional | String | National ID card number |
| `birth_date` | Optional | Date | Format: `YYYY-MM-DD` (e.g. `1990-01-15`) |

#### External Integration

| Field | Required | Type | Remark |
|-------|----------|------|--------|
| `external_user_id` | Optional | String | Salesforce Contact ID or external reference |

#### User Classification

| Field | Required | Type | Remark |
|-------|----------|------|--------|
| `user_type` | Optional | String | Default: `buyer`. Options: `buyer`, `seller` |
| `user_stage` | Optional | String | Customer lifecycle stage. Options: `lead`, `account`, `prospect`, `customer`, `churned` |

#### Communication Preferences

| Field | Required | Type | Remark |
|-------|----------|------|--------|
| `channel_email` | Optional | Boolean | Default: `true` |
| `channel_sms` | Optional | Boolean | Default: `false` |
| `channel_line` | Optional | Boolean | Default: `true` |
| `channel_push` | Optional | Boolean | Default: `true` |

#### Address & Custom Fields

| Field | Required | Type | Remark |
|-------|----------|------|--------|
| `addresses` | Optional | Array | User addresses (see structure below) |
| `address_mode` | Optional | String | Default: `replace`. Options: `replace`, `add` |
| `form_submissions` | Optional | Array | Custom profile fields like brand_interest (see structure below) |
| `upsert` | Optional | Boolean | Default: `false`. If `true`, updates existing user; if `false`, errors if user exists |

#### `addresses` Array Structure

| Field | Type |
|-------|------|
| `address_line_1` | String |
| `address_line_2` | String |
| `state` | String |
| `city` | String |
| `district` | String |
| `subdistrict` | String |
| `postcode` | String |

#### `form_submissions` Array Structure

| Field | Required | Type | Remark |
|-------|----------|------|--------|
| `form_template_code` | Mandatory | String | Must be `USER_PROFILE` for brand interest |
| `submission_mode` | Optional | String | Default: `create`. Options: `create`, `update` |
| `form_data` | Mandatory | Object | Field key-value pairs (see below) |

**Available `form_data` Fields:**

| Field Key | Type | Options | Remark |
|-----------|------|---------|--------|
| `brand_interest` | Array | `luxury`, `sports`, `electronics`, `fashion`, `home` | Multi-select brand preferences |

### Example Request — Create Lead with Brand Interest

```json
{
  "tel": "+66863210111",
  "fullname": "John Smith",
  "email": "john.smith@example.com",
  "external_user_id": "001BW00000B3Ait",
  "user_stage": "lead",
  "form_submissions": [
    {
      "form_template_code": "USER_PROFILE",
      "submission_mode": "create",
      "form_data": {
        "brand_interest": ["luxury", "fashion"]
      }
    }
  ]
}
```

### Example Request — Create Account Customer

```json
{
  "tel": "+66812345678",
  "fullname": "Jane Doe",
  "firstname": "Jane",
  "lastname": "Doe",
  "email": "jane.doe@eurocreations.com",
  "external_user_id": "SF_CONTACT_002",
  "birth_date": "1985-03-15",
  "user_stage": "account",
  "channel_email": true,
  "channel_sms": true,
  "addresses": [
    {
      "address_line_1": "123 Sukhumvit Road",
      "city": "Bangkok",
      "district": "Khlong Toei",
      "postcode": "10110"
    }
  ],
  "form_submissions": [
    {
      "form_template_code": "USER_PROFILE",
      "submission_mode": "create",
      "form_data": {
        "brand_interest": ["electronics", "sports", "home"]
      }
    }
  ],
  "upsert": true
}
```

### Example Response — 201 Created (or 200 if upsert updated)

```json
{
  "success": true,
  "data": {
    "success": true,
    "user_id": "0815c8fc-10f7-4181-8bf9-4db14e48598f",
    "external_user_id": "SF_CONTACT_002",
    "created": true,
    "updated": false,
    "addresses_added": 1,
    "addresses_deleted": 0,
    "form_submissions_created": 1,
    "form_submissions_updated": 0
  },
  "meta": {
    "request_id": "req_user001",
    "response_time_ms": 189
  }
}
```

### Example Response — 409 User Already Exists (when `upsert=false`)

```json
{
  "success": false,
  "error": "User already exists",
  "code": "USER_EXISTS",
  "details": "User with tel '+66812345678' already exists. Use upsert=true to update.",
  "request_id": "req_user002"
}
```

### POSTMAN curl

```bash
curl --location 'https://open-api.rocket-loyalty.com/functions/v1/api-users' \
--header 'Content-Type: application/json' \
--header 'x-api-key: YOUR_API_KEY_HERE' \
--data '{
  "tel": "+66812345678",
  "fullname": "Jane Doe",
  "firstname": "Jane",
  "lastname": "Doe",
  "email": "jane.doe@eurocreations.com",
  "external_user_id": "SF_CONTACT_002",
  "birth_date": "1985-03-15",
  "user_stage": "account",
  "addresses": [
    {
      "address_line_1": "123 Sukhumvit Road",
      "city": "Bangkok",
      "postcode": "10110"
    }
  ],
  "form_submissions": [
    {
      "form_template_code": "USER_PROFILE",
      "submission_mode": "create",
      "form_data": {
        "brand_interest": ["electronics", "sports", "home"]
      }
    }
  ],
  "upsert": true
}'
```

---

## 3. Update User Details

Update existing user information. All fields are **OPTIONAL** — only provide fields you want to update.

| Item | Value |
|------|-------|
| Method | `PATCH` |
| Content-Type | `application/json` |

**URI Options:**

| URI | Lookup by |
|-----|-----------|
| `/api-users/by-external-id/{external_user_id}` | Salesforce Contact ID |
| `/api-users/by-email/{email}` | Email address |
| `/api-users/by-tel/{phone}` | Phone number |
| `/api-users/by-line-id/{line_id}` | LINE ID |
| `/api-users/{user_id}` | UUID |

### Request Data Model

| Field | Type | Remark |
|-------|------|--------|
| `fullname` | String | Full name |
| `firstname` | String | First name |
| `lastname` | String | Last name |
| `email` | String | Email address |
| `tel` | String | Phone number |
| `line_id` | String | LINE messenger ID |
| `id_card` | String | National ID card |
| `birth_date` | Date | Format: `YYYY-MM-DD` |
| `user_stage` | String | Customer lifecycle stage |
| `channel_email` | Boolean | Email preference |
| `channel_sms` | Boolean | SMS preference |
| `channel_line` | Boolean | LINE preference |
| `channel_push` | Boolean | Push notification preference |
| `addresses` | Array | User addresses |
| `address_mode` | String | `replace` or `add` |
| `form_submissions` | Array | Update custom fields like brand_interest |

### Example — Update User Stage (Lead → Account)

```json
{
  "user_stage": "account"
}
```

### Example — Update Brand Interest

```json
{
  "form_submissions": [
    {
      "form_template_code": "USER_PROFILE",
      "submission_mode": "update",
      "form_data": {
        "brand_interest": ["luxury", "electronics"]
      }
    }
  ]
}
```

### Example — Update Multiple Fields

```json
{
  "email": "newemail@example.com",
  "user_stage": "account",
  "form_submissions": [
    {
      "form_template_code": "USER_PROFILE",
      "submission_mode": "update",
      "form_data": {
        "brand_interest": ["sports", "fashion"]
      }
    }
  ]
}
```

### Example Response — 200 Success

```json
{
  "success": true,
  "data": {
    "success": true,
    "user_id": "0815c8fc-10f7-4181-8bf9-4db14e48598f",
    "updated_fields": ["user_stage", "form_submissions"],
    "addresses_added": 0,
    "addresses_deleted": 0,
    "form_submissions_created": 0,
    "form_submissions_updated": 1
  },
  "meta": {
    "request_id": "req_update_user001",
    "response_time_ms": 145
  }
}
```

### Example Response — 404 User Not Found

```json
{
  "success": false,
  "error": "User not found",
  "code": "USER_NOT_FOUND",
  "details": "No user found with external_user_id 'SF_CONTACT_999'",
  "request_id": "req_update_user002"
}
```

### POSTMAN curl — Update by External ID

```bash
curl --location --request PATCH \
  'https://open-api.rocket-loyalty.com/functions/v1/api-users/by-external-id/SF_CONTACT_002' \
--header 'Content-Type: application/json' \
--header 'x-api-key: YOUR_API_KEY_HERE' \
--data '{
  "user_stage": "account",
  "form_submissions": [
    {
      "form_template_code": "USER_PROFILE",
      "submission_mode": "update",
      "form_data": {
        "brand_interest": ["luxury", "electronics"]
      }
    }
  ]
}'
```

### POSTMAN curl — Update by Phone

```bash
curl --location --request PATCH \
  'https://open-api.rocket-loyalty.com/functions/v1/api-users/by-tel/%2B66812345678' \
--header 'Content-Type: application/json' \
--header 'x-api-key: YOUR_API_KEY_HERE' \
--data '{
  "user_stage": "account"
}'
```

---

## 4. Retrieve User Information

Retrieve user profile details including custom fields.

| Item | Value |
|------|-------|
| Method | `GET` |

**URI Options:** (same as Update User)

| URI | Lookup by |
|-----|-----------|
| `/api-users/by-external-id/{external_user_id}` | Salesforce Contact ID |
| `/api-users/by-email/{email}` | Email address |
| `/api-users/by-tel/{phone}` | Phone number |
| `/api-users/by-line-id/{line_id}` | LINE ID |
| `/api-users/{user_id}` | UUID |

### Example Request

```
GET https://open-api.rocket-loyalty.com/functions/v1/api-users/by-external-id/SF_CONTACT_002
```

### Example Response

```json
{
  "success": true,
  "data": {
    "user": {
      "user_id": "0815c8fc-10f7-4181-8bf9-4db14e48598f",
      "external_user_id": "SF_CONTACT_002",
      "fullname": "Jane Doe",
      "firstname": "Jane",
      "lastname": "Doe",
      "email": "jane.doe@eurocreations.com",
      "tel": "+66812345678",
      "line_id": null,
      "birth_date": "1985-03-15",
      "user_type": "buyer",
      "user_stage": "account",
      "tier_id": "uuid",
      "persona_id": null,
      "points_balance": 500,
      "channel_email": true,
      "channel_sms": false,
      "channel_line": true,
      "channel_push": true,
      "addresses": [
        {
          "address_line_1": "123 Sukhumvit Road",
          "city": "Bangkok",
          "district": "Khlong Toei",
          "postcode": "10110"
        }
      ],
      "custom_fields": {
        "brand_interest": ["luxury", "fashion"]
      }
    }
  },
  "meta": {
    "request_id": "req_getuser001",
    "response_time_ms": 67
  }
}
```

### POSTMAN curl

```bash
curl --location \
  'https://open-api.rocket-loyalty.com/functions/v1/api-users/by-external-id/SF_CONTACT_002' \
--header 'x-api-key: YOUR_API_KEY_HERE'
```

---

## 5. Create Asset

Create new Assets in the Rocket Loyalty system.

| Item | Value |
|------|-------|
| Method | `POST` |
| URI | `/api-assets` |
| Content-Type | `application/json` |

### Request Data Model

#### Core Fields

| Field | Required | Type | Remark |
|-------|----------|------|--------|
| `asset_type_code` | Mandatory | String | Must be `ASSET` |
| `name` | Mandatory | String | Asset name |
| `external_id` | Optional | String | Salesforce Asset ID (unique) |
| `serial_number` | Optional | String | Equipment serial number |
| `status` | Optional | String | e.g. `Purchased`, `Installed` |
| `purchase_date` | Optional | Date | Format: `YYYY-MM-DD` |
| `install_date` | Optional | Date | Format: `YYYY-MM-DD` |
| `external_user_id` | Optional | String | Salesforce Contact ID or phone number |
| `user_id` | Optional | UUID | Internal user ID |
| `sku_code` | Optional | String | Product SKU code |
| `purchase_transaction_number` | Optional | String | Related purchase transaction |
| `upsert` | Optional | Boolean | If `true`, updates existing asset; if `false`, errors if exists |
| `custom_fields` | Optional | Object | All Euro-specific fields (see below) |

#### Custom Fields for ASSET Type (Euro Creations)

**Warranty & Usage:**

| Field | Type | Remark |
|-------|------|--------|
| `warrantyPeriodTechnogym` | Number | Warranty period in months |
| `warrantyPeriodEuroWellness` | Number | Euro Wellness warranty in months |
| `usageEndDate` | Date | Format: `YYYY-MM-DD` |

**Product Information:**

| Field | Type | Remark |
|-------|------|--------|
| `productName` | String | Product display name |
| `productCode` | String | Euro product code |
| `product2Id` | String | Salesforce Product2 ID |
| `articleNumber` | String | Article number |

**Salesforce Integration:**

| Field | Type | Remark |
|-------|------|--------|
| `salesOrder` | String | Sales order number |
| `recordTypeId` | String | Salesforce record type |
| `quantity` | Number | Quantity purchased |
| `project` | String | Salesforce project ID |
| `opportunity` | String | Salesforce opportunity ID |
| `opportunityProduct` | String | Salesforce opportunity product ID |
| `accountId` | String | Salesforce account ID |
| `contactId` | String | Salesforce contact ID |
| `parentId` | String | Parent asset ID |

**Delivery Order:**

| Field | Type | Remark |
|-------|------|--------|
| `doNumber` | String | Delivery order number |
| `doDate` | Date | Format: `YYYY-MM-DD` |
| `cnNumber` | String | Credit note number |

**Financial & Classification:**

| Field | Type | Remark |
|-------|------|--------|
| `price` | Number | Asset price |
| `category` | String | Asset category |
| `brand` | String | Brand name |
| `location` | String | Physical location |
| `tags` | String | Classification tags |
| `notes` | String | Additional notes |
| `description` | String | Asset description |

### Example Request

```json
{
  "asset_type_code": "ASSET",
  "name": "EXCITE LIVE CLIMB LIVE 700 METEOR BLACK",
  "external_id": "02iBW0000000f6QYAQA",
  "serial_number": "1234",
  "status": "Purchased",
  "purchase_date": "2023-08-06",
  "external_user_id": "001BW00000B3Ait",
  "upsert": false,
  "custom_fields": {
    "warrantyPeriodTechnogym": null,
    "warrantyPeriodEuroWellness": 24,
    "usageEndDate": null,
    "productName": "EXCITE LIVE CLIMB LIVE 700 METEOR BLACK",
    "productCode": "D-T01-CD03-DFEG3A10AN00EA2S",
    "product2Id": "01tBW0000001vMdYAI",
    "articleNumber": "D-T01-CD03-DFEG3A10AN00EA2S",
    "salesOrder": "233100523",
    "recordTypeId": "0126F000001WxVgQAK",
    "quantity": 1,
    "project": "a0iBW000000AOp3YAG",
    "opportunity": "006BW000006jxy9YAA",
    "opportunityProduct": "00kBW00000091ksYAA",
    "accountId": "001BW00000B3Ait",
    "contactId": null,
    "parentId": null,
    "doNumber": null,
    "doDate": null,
    "cnNumber": null,
    "price": 355300,
    "category": "Fitness Equipment",
    "brand": "Technogym",
    "location": "Warehouse A",
    "tags": null,
    "notes": null,
    "description": null
  }
}
```

### Example Response — 200 Success

```json
{
  "success": true,
  "data": {
    "asset_id": "7366abf1-59a3-4a57-b55e-8dc845213047",
    "external_id": "02iBW0000000f6QYAQA",
    "name": "EXCITE LIVE CLIMB LIVE 700 METEOR BLACK",
    "serial_number": "1234",
    "status": "Purchased",
    "purchase_date": "2023-08-06",
    "custom_fields": { "..." }
  },
  "meta": {
    "request_id": "req_abc123",
    "response_time_ms": 145
  }
}
```

### Example Response — 409 Asset Already Exists (when `upsert=false`)

```json
{
  "success": false,
  "error": "Asset already exists",
  "code": "ASSET_EXISTS",
  "details": "Asset with external_id '02iBW0000000f6QYAQA' already exists. Use upsert=true to update.",
  "request_id": "req_abc124"
}
```

### POSTMAN curl

```bash
curl --location 'https://open-api.rocket-loyalty.com/functions/v1/api-assets' \
--header 'Content-Type: application/json' \
--header 'x-api-key: YOUR_API_KEY_HERE' \
--data '{
  "asset_type_code": "ASSET",
  "name": "EXCITE LIVE CLIMB LIVE 700 METEOR BLACK",
  "external_id": "02iBW0000000f6QYAQA",
  "serial_number": "1234",
  "status": "Purchased",
  "purchase_date": "2023-08-06",
  "external_user_id": "001BW00000B3Ait",
  "custom_fields": {
    "warrantyPeriodEuroWellness": 24,
    "productName": "EXCITE LIVE CLIMB LIVE 700 METEOR BLACK",
    "productCode": "D-T01-CD03-DFEG3A10AN00EA2S",
    "salesOrder": "233100523",
    "price": 355300,
    "category": "Fitness Equipment",
    "brand": "Technogym",
    "location": "Warehouse A"
  }
}'
```

---

## 6. Update Existing Asset

Update existing asset information. All fields are **OPTIONAL**.

| Item | Value |
|------|-------|
| Method | `PATCH` |
| URI | `/api-assets/by-external-id/{external_id}` |
| Content-Type | `application/json` |

**Alternative URIs:**

- `/api-assets/by-serial-number/{serial_number}`
- `/api-assets/by-asset-code/{asset_code}`
- `/api-assets/{asset_id}` (UUID)

### Request Data Model

| Field | Type | Remark |
|-------|------|--------|
| `name` | String | Asset name |
| `status` | String | Asset status |
| `purchase_date` | Date | Format: `YYYY-MM-DD` |
| `install_date` | Date | Format: `YYYY-MM-DD` |
| `serial_number` | String | Equipment serial number |
| `custom_fields` | Object | Merges with existing custom fields (same 26 fields as create) |

> **Important:** Custom fields are **merged**, not replaced. To update specific fields, only include those fields in the `custom_fields` object.

### Example Request

```json
{
  "status": "Installed",
  "install_date": "2024-10-20",
  "custom_fields": {
    "location": "Gym Floor 3",
    "warrantyPeriodEuroWellness": 36,
    "price": 400000
  }
}
```

### Example Response — 200 Success

```json
{
  "success": true,
  "data": {
    "asset_id": "7366abf1-59a3-4a57-b55e-8dc845213047",
    "external_id": "02iBW0000000f6QYAQA",
    "name": "EXCITE LIVE CLIMB LIVE 700 METEOR BLACK",
    "serial_number": "1234",
    "status": "Installed",
    "purchase_date": "2023-08-06",
    "install_date": "2024-10-20",
    "custom_fields": {
      "warrantyPeriodEuroWellness": 36,
      "price": 400000,
      "location": "Gym Floor 3",
      "productCode": "D-T01-CD03-DFEG3A10AN00EA2S",
      "salesOrder": "233100523",
      "opportunity": "006BW000006jxy9YAA"
    },
    "updated_at": "2024-10-20T14:30:00.000Z"
  },
  "meta": {
    "request_id": "req_xyz789",
    "response_time_ms": 89
  }
}
```

### Example Response — 404 Asset Not Found

```json
{
  "success": false,
  "error": "Asset not found",
  "code": "ASSET_NOT_FOUND",
  "details": "No asset found with external_id '02iBW0000000f6QYAQA'",
  "request_id": "req_xyz790"
}
```

### POSTMAN curl

```bash
curl --location --request PATCH \
  'https://open-api.rocket-loyalty.com/functions/v1/api-assets/by-external-id/02iBW0000000f6QYAQA' \
--header 'Content-Type: application/json' \
--header 'x-api-key: YOUR_API_KEY_HERE' \
--data '{
  "status": "Installed",
  "install_date": "2024-10-20",
  "custom_fields": {
    "location": "Gym Floor 3",
    "warrantyPeriodEuroWellness": 36,
    "price": 400000
  }
}'
```

---

## 7. Create Maintenance Plan

Create new Maintenance Plans in the Rocket Loyalty system.

| Item | Value |
|------|-------|
| Method | `POST` |
| URI | `/api-assets` |
| Content-Type | `application/json` |

### Request Data Model

#### Core Fields

| Field | Required | Type | Remark |
|-------|----------|------|--------|
| `asset_type_code` | Mandatory | String | Must be `MAINTENANCE_PLAN` |
| `name` | Mandatory | String | Maintenance plan name |
| `external_id` | Optional | String | Salesforce Maintenance Plan ID (unique) |
| `status` | Optional | String | e.g. `Active`, `Expired` |
| `external_user_id` | Optional | String | Salesforce Account ID or contact reference |
| `covered_assets` | Optional | Array | Assets covered by this plan (see below) |
| `upsert` | Optional | Boolean | If `true`, updates existing; if `false`, errors if exists |
| `custom_fields` | Optional | Object | All maintenance plan fields (see below) |

#### `covered_assets` Array Structure

Each covered asset can be identified by **ONE** of:

| Field | Type | Remark |
|-------|------|--------|
| `asset_id` | UUID | Internal asset ID |
| `external_id` | String | Salesforce asset ID |
| `asset_code` | String | Internal asset code |
| `serial_number` | String | Equipment serial number |

```json
"covered_assets": [
  { "external_id": "02iBW0000000f6QYAQA" },
  { "serial_number": "SN12345" }
]
```

#### Custom Fields for MAINTENANCE_PLAN Type

**Plan Identification:**

| Field | Type | Remark |
|-------|------|--------|
| `maintenancePlanNumber` | String | Unique plan number (e.g. `MP-0411`) |
| `maintenancePlanType` | String | e.g. `Contract`, `Warranty` |
| `maintenancePlanStatus` | String | e.g. `Active`, `Expired` |
| `maintenancePlanTitle` | String | Plan title/headline |

**Work Type:**

| Field | Type | Remark |
|-------|------|--------|
| `workTypeName` | String | e.g. `Services Maintenance` |
| `workTypeId` | String | Salesforce work type ID |

**Work Order Configuration:**

| Field | Type | Remark |
|-------|------|--------|
| `workOrderGenerationStatus` | String | e.g. `NotStarted`, `InProgress` |
| `workOrderGenerationMethod` | String | e.g. `WorkOrderPerAsset` |

**Schedule & Timing:**

| Field | Type | Remark |
|-------|------|--------|
| `startDate` | Date | Format: `YYYY-MM-DD` |
| `endDate` | Date | Format: `YYYY-MM-DD` |
| `extendDate` | Date | Extension date if applicable |
| `frequency` | Number | Service frequency number |
| `frequencyType` | String | e.g. `Months`, `Days` |
| `generationTimeframe` | Number | Generation timeframe number |
| `generationTimeframeType` | String | e.g. `Months` |
| `nextSuggestedMaintenanceDate` | Date | Format: `YYYY-MM-DD` |

**Maintenance Window:**

| Field | Type | Remark |
|-------|------|--------|
| `maintenanceWindowStartDays` | Number | Window start in days |
| `maintenanceWindowEndDays` | Number | Window end in days |

**Salesforce Integration:**

| Field | Type | Remark |
|-------|------|--------|
| `serviceContractId` | String | Salesforce service contract ID |
| `salesOrder` | String | Sales order number |
| `recordTypeId` | String | Salesforce record type |
| `project` | String | Salesforce project ID |
| `opportunity` | String | Salesforce opportunity ID |
| `accountId` | String | Salesforce account ID |
| `contactId` | String | Salesforce contact ID |

**Plan Relationships & Configuration:**

| Field | Type | Remark |
|-------|------|--------|
| `parentMaintenancePlan` | String | Parent plan ID for hierarchy |
| `asset` | String | Direct asset reference |
| `serialNumber` | String | Serial number reference |
| `articleNumber` | String | Article number |
| `quantity` | Number | Quantity value |
| `mpRenewal` | Boolean | Renewal flag |
| `approvalStatus` | String | e.g. `NotRequired`, `Pending` |
| `allAssetInstalled` | Boolean | All assets installed flag |
| `activeExpire` | String | Active/Expire status |
| `description` | String | Plan description |

### Example Request

```json
{
  "asset_type_code": "MAINTENANCE_PLAN",
  "name": "6-Month Service Plan",
  "external_id": "1MPBW00000001Lt4AI",
  "status": "Active",
  "external_user_id": "001BW00000B3Ait",
  "upsert": false,
  "custom_fields": {
    "maintenancePlanNumber": "MP-0411",
    "maintenancePlanType": "Contract",
    "maintenancePlanStatus": "Active",
    "workTypeName": "Services Maintenance",
    "workTypeId": "08qBW0000000CFhYAM",
    "workOrderGenerationStatus": "NotStarted",
    "workOrderGenerationMethod": "WorkOrderPerAsset",
    "startDate": "2024-02-22",
    "endDate": "2026-02-22",
    "frequency": 6,
    "frequencyType": "Months",
    "generationTimeframe": 24,
    "generationTimeframeType": "Months",
    "nextSuggestedMaintenanceDate": "2024-08-22",
    "salesOrder": "233100555",
    "recordTypeId": "0126F000001WxIOQA0",
    "project": "a0iBW000000AeaTYAS",
    "opportunity": "006BW000007ZIKbYAO",
    "accountId": "001BW00000B3Ait",
    "quantity": 0,
    "mpRenewal": false,
    "approvalStatus": "NotRequired",
    "allAssetInstalled": false,
    "activeExpire": "Active"
  },
  "covered_assets": [
    { "external_id": "02iBW0000000f6QYAQA" }
  ]
}
```

### Example Response — 200 Success

```json
{
  "success": true,
  "data": {
    "asset_id": "d83789b7-5ec2-4135-8822-f30afb11997a",
    "external_id": "1MPBW00000001Lt4AI",
    "name": "6-Month Service Plan",
    "status": "Active",
    "asset_type": "MAINTENANCE_PLAN",
    "custom_fields": { "..." },
    "covered_assets": [
      {
        "asset_id": "7366abf1-59a3-4a57-b55e-8dc845213047",
        "external_id": "02iBW0000000f6QYAQA",
        "name": "EXCITE LIVE CLIMB LIVE 700 METEOR BLACK",
        "serial_number": "1234",
        "article_number": "D-T01-CD03-DFEG3A10AN00EA2S"
      }
    ],
    "created_at": "2024-11-06T13:54:00.000Z"
  },
  "meta": {
    "request_id": "req_maint001",
    "response_time_ms": 212
  }
}
```

### POSTMAN curl

```bash
curl --location 'https://open-api.rocket-loyalty.com/functions/v1/api-assets' \
--header 'Content-Type: application/json' \
--header 'x-api-key: YOUR_API_KEY_HERE' \
--data '{
  "asset_type_code": "MAINTENANCE_PLAN",
  "name": "6-Month Service Plan",
  "external_id": "1MPBW00000001Lt4AI",
  "status": "Active",
  "external_user_id": "001BW00000B3Ait",
  "custom_fields": { "..." },
  "covered_assets": [
    { "external_id": "02iBW0000000f6QYAQA" }
  ]
}'
```

---

## 8. Update Existing Maintenance Plan

Update existing Maintenance Plan details. All fields are **OPTIONAL**.

| Item | Value |
|------|-------|
| Method | `PATCH` |
| URI | `/api-assets/by-external-id/{external_id}` |
| Content-Type | `application/json` |

**Alternative URIs:**

- `/api-assets/by-asset-code/{asset_code}`
- `/api-assets/{asset_id}` (UUID)

### Request Data Model

| Field | Type | Remark |
|-------|------|--------|
| `name` | String | Maintenance plan name |
| `status` | String | Plan status |
| `custom_fields` | Object | Merges with existing — all 35 fields available (see Create API) |
| `covered_assets` | Array | **Replaces ALL** linked assets (not merged) |

> **Important Notes:**
> - Custom fields are **merged** (partial updates supported)
> - `covered_assets` array **replaces** the entire relationship (not merged)
> - To add assets, include both existing and new assets in the array

### Example Request

```json
{
  "status": "Active",
  "custom_fields": {
    "workTypeName": "Services Maintenance - Updated",
    "maintenancePlanStatus": "Active",
    "nextSuggestedMaintenanceDate": "2024-12-22",
    "frequency": 3,
    "frequencyType": "Months"
  },
  "covered_assets": [
    { "external_id": "02iBW0000000f6QYAQA" },
    { "serial_number": "SN67890" }
  ]
}
```

### Example Response — 200 Success

```json
{
  "success": true,
  "data": {
    "asset_id": "d83789b7-5ec2-4135-8822-f30afb11997a",
    "external_id": "1MPBW00000001Lt4AI",
    "name": "6-Month Service Plan",
    "status": "Active",
    "asset_type": "MAINTENANCE_PLAN",
    "custom_fields": {
      "maintenancePlanNumber": "MP-0411",
      "workTypeName": "Services Maintenance - Updated",
      "nextSuggestedMaintenanceDate": "2024-12-22",
      "frequency": 3,
      "frequencyType": "Months"
    },
    "covered_assets": [
      {
        "asset_id": "7366abf1-59a3-4a57-b55e-8dc845213047",
        "external_id": "02iBW0000000f6QYAQA",
        "name": "EXCITE LIVE CLIMB LIVE 700 METEOR BLACK",
        "serial_number": "1234"
      },
      {
        "asset_id": "8e6f3d06-c405-488f-961a-70bef350d5d5",
        "serial_number": "SN67890",
        "name": "BIKE PRO 500"
      }
    ],
    "updated_at": "2024-11-06T14:15:00.000Z"
  },
  "meta": {
    "request_id": "req_update001",
    "response_time_ms": 156
  }
}
```

### POSTMAN curl

```bash
curl --location --request PATCH \
  'https://open-api.rocket-loyalty.com/functions/v1/api-assets/by-external-id/1MPBW00000001Lt4AI' \
--header 'Content-Type: application/json' \
--header 'x-api-key: YOUR_API_KEY_HERE' \
--data '{
  "status": "Active",
  "custom_fields": {
    "workTypeName": "Services Maintenance - Updated",
    "frequency": 3,
    "frequencyType": "Months"
  },
  "covered_assets": [
    { "external_id": "02iBW0000000f6QYAQA" },
    { "serial_number": "SN67890" }
  ]
}'
```

---

## 9. Retrieve Asset / Maintenance Plan by ID

Retrieve existing asset or maintenance plan details.

| Item | Value |
|------|-------|
| Method | `GET` |

**URI Options:**

| URI | Lookup by |
|-----|-----------|
| `/api-assets/by-external-id/{external_id}` | Salesforce ID |
| `/api-assets/by-serial-number/{serial_number}` | Serial number |
| `/api-assets/by-asset-code/{asset_code}` | Internal code |
| `/api-assets/{asset_id}` | UUID |

### Example — Get Asset

```
GET https://open-api.rocket-loyalty.com/functions/v1/api-assets/by-external-id/02iBW0000000f6QYAQA
```

```json
{
  "success": true,
  "data": {
    "asset": {
      "asset_id": "7366abf1-59a3-4a57-b55e-8dc845213047",
      "external_id": "02iBW0000000f6QYAQA",
      "name": "EXCITE LIVE CLIMB LIVE 700 METEOR BLACK",
      "serial_number": "1234",
      "status": "Purchased",
      "purchase_date": "2023-08-06",
      "install_date": null,
      "asset_type": "ASSET",
      "user_id": null,
      "external_user_id": "001BW00000B3Ait",
      "custom_fields": { "..." },
      "covered_by_plans": []
    }
  },
  "meta": {
    "request_id": "req_get001",
    "response_time_ms": 78
  }
}
```

### Example — Get Maintenance Plan

```
GET https://open-api.rocket-loyalty.com/functions/v1/api-assets/by-external-id/1MPBW00000001Lt4AI
```

```json
{
  "success": true,
  "data": {
    "asset": {
      "asset_id": "d83789b7-5ec2-4135-8822-f30afb11997a",
      "external_id": "1MPBW00000001Lt4AI",
      "name": "6-Month Service Plan",
      "status": "Active",
      "asset_type": "MAINTENANCE_PLAN",
      "custom_fields": { "..." },
      "covered_assets": [
        {
          "asset_id": "7366abf1-59a3-4a57-b55e-8dc845213047",
          "external_id": "02iBW0000000f6QYAQA",
          "name": "EXCITE LIVE CLIMB LIVE 700 METEOR BLACK",
          "serial_number": "1234",
          "article_number": "D-T01-CD03-DFEG3A10AN00EA2S"
        }
      ]
    }
  },
  "meta": {
    "request_id": "req_get002",
    "response_time_ms": 95
  }
}
```

### POSTMAN curl

```bash
curl --location \
  'https://open-api.rocket-loyalty.com/functions/v1/api-assets/by-external-id/1MPBW00000001Lt4AI' \
--header 'x-api-key: YOUR_API_KEY_HERE'
```

---

## 10. Create Third Party Bill (Purchase Transaction)

Create new bills/purchase transactions in the Rocket Loyalty system.

> **Migration Note:** This replaces the old `/billing-gateway/euro/create-bill` endpoint.

| Item | Value |
|------|-------|
| Method | `POST` |
| URI | `/api-purchases` |
| Content-Type | `application/json` |

### Request Data Model

#### User Identification

| Field | Required | Type | Remark |
|-------|----------|------|--------|
| `external_user_id` | Mandatory* | String | Buyer phone number or Salesforce contact ID |
| `user_id` | Mandatory* | UUID | Internal user ID (*at least one required) |
| `seller_external_user_id` | Optional | String | Seller phone number or ID |
| `seller_user_id` | Optional | UUID | Internal seller ID |

#### Transaction Details

| Field | Required | Type | Remark |
|-------|----------|------|--------|
| `final_amount` | Mandatory | Number | Net amount customer pays |
| `total_amount` | Optional | Number | Defaults to `final_amount` |
| `discount_amount` | Optional | Number | Default: `0` |
| `tax_amount` | Optional | Number | Default: `0` |

#### Transaction Metadata

| Field | Required | Type | Remark |
|-------|----------|------|--------|
| `transaction_number` | Optional | String | Auto-generated if not provided |
| `transaction_date` | Optional | Timestamp | Default: `NOW()`, format: `YYYY-MM-DD` |
| `external_ref` | Optional | String | External order number (old: `external_order_no`) |
| `store_code` | Optional | String | Store identifier (old: `pos_store_code`) |
| `api_source` | Optional | String | Source system name (use `euro` for Euro Creations) |

#### Transaction Control

| Field | Required | Type | Remark |
|-------|----------|------|--------|
| `status` | Optional | String | Default: `completed`. Options: `pending`, `processing`, `completed`, `cancelled`, `refunded` |
| `payment_status` | Optional | String | Default: `pending` |
| `processing_method` | Optional | String | Default: `queue`. Options: `queue`, `direct`, `skip` |
| `earn_currency` | Optional | Boolean | Default: `true` (awards points automatically) |
| `notes` | Optional | String | Additional notes |

#### Line Items

| Field | Required | Type | Remark |
|-------|----------|------|--------|
| `items` | Optional | Array | Product line items (see below) |

#### `items` Array Structure

| Field | Required | Type | Remark |
|-------|----------|------|--------|
| `sku_code` | Mandatory | String | Product variant code (old: `variant_code`) |
| `quantity` | Mandatory | Number | Quantity purchased (old: `qty`) |
| `unit_price` | Mandatory | Number | Price per unit |
| `line_total` | Optional | Number | Auto-calculated if not provided (old: `net_sale_value`) |
| `discount_amount` | Optional | Number | Default: `0` |
| `tax_amount` | Optional | Number | Default: `0` |

> **Note:** The old system's `variant_name` is not required — the system resolves product name from `sku_code` lookup in product catalog.

### Example Request

```json
{
  "external_user_id": "+66863210111",
  "seller_external_user_id": "+66812345678",
  "store_code": "store_a1",
  "external_ref": "test_bill",
  "api_source": "euro",
  "transaction_date": "2024-08-02",
  "status": "completed",
  "payment_status": "paid",
  "final_amount": 3000,
  "total_amount": 3000,
  "discount_amount": 0,
  "tax_amount": 0,
  "processing_method": "queue",
  "earn_currency": true,
  "items": [
    {
      "sku_code": "12345",
      "quantity": 3,
      "unit_price": 1000,
      "line_total": 3000,
      "discount_amount": 0,
      "tax_amount": 0
    }
  ]
}
```

### Example Response — 200 Success

```json
{
  "success": true,
  "data": {
    "success": true,
    "transaction_id": "a1b2c3d4-5678-90ab-cdef-1234567890ab",
    "transaction_number": "TXN20241106000001",
    "user_id": "c573479a-fe36-48be-9f6f-a559fffe9016",
    "user_resolved": true,
    "seller_id": null,
    "store_id": null,
    "items_created": 1,
    "unknown_skus": ["12345"],
    "unknown_store": false
  },
  "meta": {
    "request_id": "req_purchase001",
    "response_time_ms": 234
  }
}
```

> **Note:** `unknown_skus` lists any SKU codes not found in the product catalog. The purchase is still created successfully. Currency will be awarded via the configured `processing_method` (default: `queue`, within 60 seconds).

### Example Response — 404 User Not Found

```json
{
  "success": false,
  "error": "User not found",
  "code": "USER_NOT_FOUND",
  "details": "No user found with external_user_id '+66863210111'. Please create user first via /api-users endpoint.",
  "request_id": "req_purchase002"
}
```

### POSTMAN curl

```bash
curl --location 'https://open-api.rocket-loyalty.com/functions/v1/api-purchases' \
--header 'Content-Type: application/json' \
--header 'x-api-key: YOUR_API_KEY_HERE' \
--data '{
  "external_user_id": "+66863210111",
  "seller_external_user_id": "+66812345678",
  "store_code": "store_a1",
  "external_ref": "test_bill",
  "api_source": "euro",
  "transaction_date": "2024-08-02",
  "status": "completed",
  "payment_status": "paid",
  "final_amount": 3000,
  "total_amount": 3000,
  "items": [
    {
      "sku_code": "12345",
      "quantity": 3,
      "unit_price": 1000,
      "line_total": 3000
    }
  ]
}'
```

---

## Error Codes

### Common Errors

| Code | Status | Description |
|------|--------|-------------|
| `MISSING_API_KEY` | 401 | `x-api-key` header not provided |
| `INVALID_API_KEY` | 401 | API key invalid or expired |
| `USER_NOT_FOUND` | 404 | User identifier not found |
| `ASSET_NOT_FOUND` | 404 | Asset identifier not found |
| `ASSET_EXISTS` | 409 | Asset already exists (`upsert=false`) |
| `USER_EXISTS` | 409 | User already exists (`upsert=false`) |
| `VALIDATION_FAILED` | 400 | Field validation failed |
| `TRANSACTION_LOCKED` | 400 | Cannot modify completed transaction |

### Error Response Format

```json
{
  "success": false,
  "error": "Error message",
  "code": "ERROR_CODE",
  "details": "Additional details",
  "request_id": "uuid"
}
```

---

## Field Mapping Reference

### Asset Fields (Old System → New)

| Old Field Name | New Location | New Field Name | Notes |
|----------------|-------------|----------------|-------|
| `id` | `external_id` | `external_id` | Salesforce Asset ID |
| `name` | `name` | `name` | Asset name |
| `serialNumber` | `serial_number` | `serial_number` | Equipment serial |
| `status` | `status` | `status` | Asset status |
| `purchaseDate` | `purchase_date` | `purchase_date` | Purchase date |
| `installDate` | `install_date` | `install_date` | Installation date |
| `warrantyPeriodTechnogym` | `custom_fields` | `warrantyPeriodTechnogym` | Direct mapping |
| `warrantyPeriodEuroWellness` | `custom_fields` | `warrantyPeriodEuroWellness` | Direct mapping |
| `usageEndDate` | `custom_fields` | `usageEndDate` | Direct mapping |
| `productName` | `custom_fields` | `productName` | Separated from name |
| `productCode` | `custom_fields` | `productCode` | Direct mapping |
| `product2Id` | `custom_fields` | `product2Id` | Direct mapping |
| `articleNumber` | `custom_fields` | `articleNumber` | Direct mapping |
| `salesOrder` | `custom_fields` | `salesOrder` | Direct mapping |
| `recordTypeId` | `custom_fields` | `recordTypeId` | Direct mapping |
| `quantity` | `custom_fields` | `quantity` | Direct mapping |
| `project` | `custom_fields` | `project` | Direct mapping |
| `opportunity` | `custom_fields` | `opportunity` | Direct mapping |
| `opportunityProduct` | `custom_fields` | `opportunityProduct` | Direct mapping |
| `accountId` | `custom_fields` | `accountId` | Direct mapping |
| `contactId` | `custom_fields` | `contactId` | Direct mapping |
| `parentId` | `custom_fields` | `parentId` | Direct mapping |
| `doNumber` | `custom_fields` | `doNumber` | Direct mapping |
| `doDate` | `custom_fields` | `doDate` | Direct mapping |
| `cnNumber` | `custom_fields` | `cnNumber` | Direct mapping |
| `price` | `custom_fields` | `price` | Direct mapping |
| `description` | `custom_fields` | `description` | Direct mapping |

### Maintenance Plan Fields (Old → New)

| Old Field Name | New Location | New Field Name | Notes |
|----------------|-------------|----------------|-------|
| `id` | `external_id` | `external_id` | Salesforce MP ID |
| `name` | `name` | `name` | Plan name |
| `status` | `status` | `status` | Plan status |
| `maintenancePlanNumber` | `custom_fields` | `maintenancePlanNumber` | Direct mapping |
| `maintenancePlanType` | `custom_fields` | `maintenancePlanType` | Direct mapping |
| `maintenancePlanStatus` | `custom_fields` | `maintenancePlanStatus` | Direct mapping |
| `maintenancePlanTitle` | `custom_fields` | `maintenancePlanTitle` | New field |
| `workTypeName` | `custom_fields` | `workTypeName` | Direct mapping |
| `workTypeId` | `custom_fields` | `workTypeId` | New field |
| `startDate` | `custom_fields` | `startDate` | Direct mapping |
| `endDate` | `custom_fields` | `endDate` | Direct mapping |
| `frequency` | `custom_fields` | `frequency` | Direct mapping |
| `frequencyType` | `custom_fields` | `frequencyType` | Direct mapping |
| `generationTimeframe` | `custom_fields` | `generationTimeframe` | Direct mapping |
| `generationTimeframeType` | `custom_fields` | `generationTimeframeType` | Direct mapping |
| `nextSuggestedMaintenanceDate` | `custom_fields` | `nextSuggestedMaintenanceDate` | Direct mapping |
| `mpRenewal` | `custom_fields` | `mpRenewal` | Direct mapping |
| `approvalStatus` | `custom_fields` | `approvalStatus` | Direct mapping |
| `allAssetInstalled` | `custom_fields` | `allAssetInstalled` | Direct mapping |
| `activeExpire` | `custom_fields` | `activeExpire` | Direct mapping |
| `maintenanceAssets` | `covered_assets` | `covered_assets` | Enhanced relationship structure |

### Bill Creation Fields (Old → New)

| Old Field Name | New Field Name | Location | Notes |
|----------------|---------------|----------|-------|
| `organization_id` | _(via API key)_ | Implicit | Merchant context from authentication |
| `third_party_name` | `api_source` | Body | Use `euro` for Euro Creations |
| `pos_store_code` | `store_code` | Body | Direct mapping |
| `external_order_no` | `external_ref` | Body | External order reference |
| `buyer_phone_number` | `external_user_id` | Body | Phone number or user reference |
| `seller_phone_number` | `seller_external_user_id` | Body | Seller phone or reference |
| `sale_date` | `transaction_date` | Body | Transaction date |
| `variant_code_list` | `items` | Body | Array of line items |
| `variant_code_list[].variant_code` | `items[].sku_code` | Body | Product SKU code |
| `variant_code_list[].variant_name` | _(auto-resolved)_ | — | Looked up from product catalog |
| `variant_code_list[].qty` | `items[].quantity` | Body | Quantity purchased |
| `variant_code_list[].net_sale_value` | `items[].line_total` | Body | Line total amount |

### User Fields Reference

| Field Name | Type | Default | Available Values | Notes |
|------------|------|---------|-----------------|-------|
| `user_stage` | String | `lead` | `lead`, `account`, `prospect`, `customer`, `churned` | Customer lifecycle stage |
| `brand_interest` | Array | `[]` | `luxury`, `sports`, `electronics`, `fashion`, `home` | Stored in form_submissions |

---

## Data Formats

### Success Response Format

All successful responses follow this structure:

```json
{
  "success": true,
  "data": { },
  "meta": {
    "request_id": "uuid",
    "response_time_ms": 250
  }
}
```

### Standard Headers

**Request Headers:**

- `x-api-key` — Your API key (required)
- `Content-Type: application/json` — for POST/PATCH

**Response Headers:**

- `X-Request-Id` — Unique request identifier for tracking
- `X-Response-Time` — Response time in milliseconds

### Data Type Conventions

| Type | Format |
|------|--------|
| Dates | `YYYY-MM-DD` (e.g. `2024-10-20`) |
| Timestamps | ISO 8601 with timezone |
| Numbers | Integers or decimals, JSON number type (no quotes) |
| Booleans | `true` or `false` (JSON boolean, not string) |
| Arrays | `["value1", "value2"]` — empty arrays `[]` allowed |
| UUIDs | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` (case insensitive) |
| Phone numbers | `+66XXXXXXXXX` (E.164). Both `0XX` and `+66` accepted on input. |
