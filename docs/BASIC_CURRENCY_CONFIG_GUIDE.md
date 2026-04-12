# Basic Currency Config — คู่มือการใช้งาน GET / UPSERT

## ภาพรวม

หน้า Basic Currency Config ใช้สำหรับตั้งค่าอัตราการได้รับ currency (Points / Store Credit / Ticket) แบบง่าย โดยมี 2 ส่วนหลัก:

1. **Earn Rate** — อัตราการแลก (เช่น จ่าย 35 บาท = 1 point)
2. **Points Multiplier** — ตัวคูณโบนัส (เช่น 3X ในช่วง weekend)

FE ใช้ **1 local variable** เก็บข้อมูลทั้งหน้า → แก้ไขตาม input ของ user → ส่งกลับไป save ทั้งก้อน

---

## API Endpoints

| Action | RPC Function | Method |
|---|---|---|
| ดึงข้อมูล | `bff_get_basic_currency_config` | POST `/rest/v1/rpc/bff_get_basic_currency_config` |
| บันทึก | `bff_upsert_basic_currency_config` | POST `/rest/v1/rpc/bff_upsert_basic_currency_config` |

---

## 1. GET — ดึงข้อมูล Config

### Request

```json
{
  "p_target_currency": "points",
  "p_target_entity_id": null
}
```

| Parameter | ค่าที่ใช้ | คำอธิบาย |
|---|---|---|
| `p_target_currency` | `"points"` | สำหรับหน้า Points config |
| `p_target_currency` | `"ticket"` | สำหรับหน้า Store Credit หรือ Ticket อื่น |
| `p_target_entity_id` | `null` | ใช้กับ Points (ไม่ต้องระบุ) |
| `p_target_entity_id` | `"<ticket_type_id>"` | ใช้กับ Ticket/Store Credit (ระบุ ticket type) |

### Response — กรณียังไม่เคยตั้งค่า (New)

```json
{
  "target_currency": "points",
  "target_entity_id": null,
  "earn_factor_group_id": null,
  "earn_rate": {
    "different_rate_per_tier": false,
    "single_rate": null,
    "single_rate_factor_id": null,
    "rates": [],
    "excluded_products": []
  },
  "multipliers": {
    "stackable": true,
    "items": []
  }
}
```

### Response — กรณีมี Config อยู่แล้ว (Edit)

```json
{
  "target_currency": "points",
  "target_entity_id": null,
  "earn_factor_group_id": "b5f94549-ea70-4c49-8ca2-105dfdddf92a",
  "earn_rate": {
    "different_rate_per_tier": true,
    "single_rate": null,
    "single_rate_factor_id": null,
    "rates": [
      {
        "factor_id": "70b9f6f2-...",
        "tier_id": "cf997e9e-...",
        "tier_name": "Platinum",
        "earn_factor_amount": 25,
        "earn_conditions_group_id": "c6fbd9a2-..."
      },
      {
        "factor_id": "0e6caf6d-...",
        "tier_id": "fe645996-...",
        "tier_name": "Gold",
        "earn_factor_amount": 35,
        "earn_conditions_group_id": "16b67990-..."
      },
      {
        "factor_id": "a480115d-...",
        "tier_id": "d608f490-...",
        "tier_name": "Silver",
        "earn_factor_amount": 30,
        "earn_conditions_group_id": "15390d4c-..."
      }
    ],
    "excluded_products": [
      {
        "condition_id": "abc123-...",
        "entity": "product_sku",
        "entity_ids": ["sku-uuid-1", "sku-uuid-2", "sku-uuid-3"]
      }
    ]
  },
  "multipliers": {
    "stackable": false,
    "items": [
      {
        "factor_id": "5f6f6c44-...",
        "active_status": true,
        "earn_factor_amount": 3,
        "window_start": "2022-07-20T00:00:00+00:00",
        "window_end": "2022-07-20T23:59:59+00:00",
        "earn_conditions_group_id": "ba57c950-...",
        "timing": {
          "day_of_week": [0, 6],
          "hour_start": 0,
          "hour_end": 23
        },
        "tiers": [
          { "tier_id": "fe645996-...", "tier_name": "Gold" },
          { "tier_id": "cf997e9e-...", "tier_name": "Platinum" },
          { "tier_id": "ddd11111-...", "tier_name": "Diamond" }
        ],
        "include_products": [
          {
            "condition_id": "prod-cond-1",
            "entity": "product_product",
            "entity_ids": ["prod-uuid-1", "prod-uuid-2", "prod-uuid-3"]
          }
        ]
      }
    ]
  }
}
```

### Response — กรณี Config ซับซ้อนเกินไป (ต้องใช้ Advanced)

```json
{
  "mode": "not_basic",
  "reason": "Multiple earn factor groups found for this currency type"
}
```

เมื่อได้ `mode: "not_basic"` ให้ redirect user ไปหน้า Advanced editor

---

## 2. UPSERT — บันทึก Config

### Request

ส่ง **ทั้งก้อน** ของ local variable ที่ได้จาก GET กลับมา (หลัง user แก้ไขแล้ว)

```json
{
  "p_config": { ... ทั้ง object ... }
}
```

### Response — สำเร็จ

```json
{
  "success": true,
  "code": "CREATED",
  "title": "Basic Currency Config Created",
  "description": "Basic points config saved",
  "earn_factor_group_id": "b5f94549-...",
  "factors_created": 4,
  "factors_updated": 0,
  "factors_deleted": 0,
  "conditions_groups_created": 4,
  "conditions_groups_deleted": 0
}
```

---

## วิธีใช้งาน — Mapping จาก UI ไปยัง JSON

### ส่วนที่ 1: Earn Rate (อัตราการได้รับ)

![Basic Points Config UI](assets/image-cc843566-3f2e-4790-b1b1-ff9ae23383bf.png)

#### Toggle "Different rate per tier"

| สถานะ Toggle | JSON Field | คำอธิบาย |
|---|---|---|
| **ปิด** (อัตราเดียว) | `earn_rate.different_rate_per_tier = false` | ใส่ค่าใน `earn_rate.single_rate` |
| **เปิด** (แต่ละ Tier) | `earn_rate.different_rate_per_tier = true` | ใส่ค่าใน `earn_rate.rates[]` |

#### กรณีอัตราเดียว (Toggle ปิด)

User กรอกแค่ 1 ช่อง เช่น "ใช้จ่าย 30 บาท ได้ 1 point" → FE set:

```json
"earn_rate": {
  "different_rate_per_tier": false,
  "single_rate": 30,
  "rates": []
}
```

#### กรณีอัตราตาม Tier (Toggle เปิด) — ตรงกับรูป

ตาราง Tier ในรูป: Gold=35, Silver=30, Platinum=25

FE ต้องรู้ `tier_id` ของแต่ละ Tier (ดึงจาก `tier_master` หรือ `get_all_entity_options`)

```json
"earn_rate": {
  "different_rate_per_tier": true,
  "single_rate": null,
  "rates": [
    { "factor_id": null, "tier_id": "<gold_uuid>", "earn_factor_amount": 35, "earn_conditions_group_id": null },
    { "factor_id": null, "tier_id": "<silver_uuid>", "earn_factor_amount": 30, "earn_conditions_group_id": null },
    { "factor_id": null, "tier_id": "<platinum_uuid>", "earn_factor_amount": 25, "earn_conditions_group_id": null }
  ]
}
```

> **หมายเหตุ**: `earn_factor_amount` = จำนวนเงินที่ต้องจ่ายเพื่อได้ 1 หน่วย currency  
> Gold=35 หมายถึง จ่าย 35 บาท ได้ 1 point (อัตราแย่กว่า Platinum=25)

#### Excluded Products — สินค้าที่ไม่ร่วมรายการ

ปุ่ม pills ในรูป: Zeroed, Wunderlust, ABC Classic

```json
"excluded_products": [
  {
    "condition_id": null,
    "entity": "product_sku",
    "entity_ids": ["<zeroed_sku_uuid>", "<wunderlust_sku_uuid>", "<abc_classic_sku_uuid>"]
  }
]
```

> `entity` เป็นได้หลายแบบ: `product_sku`, `product_product`, `product_brand`, `product_category`  
> FE เลือก entity type ตามที่ user เลือก, `entity_ids` คือ UUID ของ item ที่เลือก

---

### ส่วนที่ 2: Points Multiplier (ตัวคูณ)

#### Allow Stacking Toggle

```json
"multipliers": {
  "stackable": true   // เปิด = true, ปิด = false
}
```

**stackable = true**: ตัวคูณหลายตัวรวมกันได้ (เช่น 2X + 1.5X = 3.5X)  
**stackable = false**: ใช้แค่ตัวที่ดีที่สุด

#### แต่ละ Multiplier Card (Condition 1, Condition 2, ...)

Multiplier Card ตัวที่ 1 ในรูป:

| UI Element | JSON Field | ค่าตัวอย่าง |
|---|---|---|
| Active toggle | `items[0].active_status` | `true` / `false` |
| Multiplier rate (3 X) | `items[0].earn_factor_amount` | `3` |
| Window start date | `items[0].window_start` | `"2022-07-20T00:00:00Z"` |
| Window end date | `items[0].window_end` | `"2022-07-20T23:59:59Z"` |
| Timing dropdown (Weekend) | `items[0].timing.day_of_week` | `[0, 6]` (อาทิตย์=0, เสาร์=6) |
| Tier pills (Gold, Platinum, Diamond) | `items[0].tiers[]` | array ของ `{ tier_id, tier_name }` |
| Include products pills | `items[0].include_products[]` | array ของ `{ entity, entity_ids }` |

#### Timing Mapping

| Dropdown Value | `day_of_week` | `hour_start` | `hour_end` |
|---|---|---|---|
| Weekend | `[0, 6]` | `0` | `23` |
| Weekday | `[1, 2, 3, 4, 5]` | `0` | `23` |
| Everyday (ทุกวัน) | `[0, 1, 2, 3, 4, 5, 6]` | `0` | `23` |
| ไม่กำหนด | `timing: null` | — | — |
| Custom (ระบุเอง) | `[วันที่เลือก]` | `ชั่วโมงเริ่ม` | `ชั่วโมงจบ` |

> `day_of_week`: 0=อาทิตย์, 1=จันทร์, 2=อังคาร, 3=พุธ, 4=พฤหัส, 5=ศุกร์, 6=เสาร์  
> `hour_start` / `hour_end`: 0-23 (ช่วง 24 ชม.)

#### ตัวอย่าง Multiplier Card เต็ม (จากรูป Condition 1)

```json
{
  "factor_id": null,
  "active_status": false,
  "earn_factor_amount": 3,
  "window_start": "2022-07-20T00:00:00Z",
  "window_end": "2022-07-20T23:59:59Z",
  "earn_conditions_group_id": null,
  "timing": {
    "day_of_week": [0, 6],
    "hour_start": 0,
    "hour_end": 23
  },
  "tiers": [
    { "tier_id": "<gold_uuid>", "tier_name": "Gold" },
    { "tier_id": "<platinum_uuid>", "tier_name": "Platinum" },
    { "tier_id": "<diamond_uuid>", "tier_name": "Diamond" }
  ],
  "include_products": [
    {
      "condition_id": null,
      "entity": "product_product",
      "entity_ids": ["<powerflex_uuid>", "<movepro_uuid>", "<urbanease_uuid>", "<runflex_uuid>"]
    }
  ]
}
```

#### "+ Add Multiplier" ปุ่ม

เมื่อ user กดเพิ่ม → FE push object ใหม่เข้า `multipliers.items[]` โดย field ทุกตัวเป็น null/default

#### ลบ Multiplier (ปุ่มถังขยะ)

เมื่อ user กดลบ → FE ลบ object ออกจาก `multipliers.items[]` → ตอน save ระบบจะลบ factor ที่หายไปอัตโนมัติ

---

## Flow การทำงานของ FE (สรุป)

```
1. Page Load
   │
   ├─ เรียก bff_get_basic_currency_config('points')
   │
   ├─ ถ้าได้ { mode: "not_basic" }
   │     └─ Redirect ไปหน้า Advanced Editor
   │
   └─ ถ้าได้ JSON ปกติ
         └─ เก็บใน local variable (เช่น config = response)
              │
              ├─ Bind UI elements กับ config fields
              │     ├─ Toggle "Different rate per tier" ← config.earn_rate.different_rate_per_tier
              │     ├─ Rate inputs ← config.earn_rate.rates[] หรือ config.earn_rate.single_rate
              │     ├─ Excluded products pills ← config.earn_rate.excluded_products[]
              │     ├─ Stackable toggle ← config.multipliers.stackable
              │     └─ Multiplier cards ← config.multipliers.items[]
              │
              ├─ User แก้ไข → update config variable
              │
              └─ กด Save
                    │
                    ├─ เรียก bff_upsert_basic_currency_config(config)
                    │
                    ├─ ถ้า success = true
                    │     └─ แสดง toast "บันทึกสำเร็จ"
                    │     └─ (optional) เรียก GET อีกครั้งเพื่อ refresh IDs
                    │
                    └─ ถ้า success = false
                          └─ แสดง error message
```

---

## การใช้กับ Store Credit / Ticket อื่น

หน้าเดียวกัน แค่เปลี่ยน parameter:

| หน้า | `p_target_currency` | `p_target_entity_id` |
|---|---|---|
| Points Config | `"points"` | `null` |
| Store Credit Config | `"ticket"` | `"<credit_ticket_type_id>"` |
| Raffle Ticket Config | `"ticket"` | `"<raffle_ticket_type_id>"` |

FE หา `credit_ticket_type_id` จาก `ticket_type` table ที่ `is_credit = true` ของ merchant นั้น

---

## สิ่งที่ Backend ทำให้อัตโนมัติ (FE ไม่ต้อง Handle)

| สิ่งที่เกิดขึ้น | Backend จัดการเอง |
|---|---|
| สร้าง earn_factor_group ตัวแรก | สร้างอัตโนมัติเมื่อ `earn_factor_group_id = null` |
| สร้าง earn_conditions_group per factor | สร้างอัตโนมัติเมื่อ `earn_conditions_group_id = null` |
| ลบ factor ที่หายไป | ลบอัตโนมัติ — factor ที่ไม่อยู่ใน request จะถูกลบ |
| ลบ conditions group ที่ไม่มีใครใช้ | ลบอัตโนมัติหลัง factor ถูกลบ |
| ลบ group เปล่า | ลบอัตโนมัติถ้าไม่มี factor เหลือ |
| สร้าง excluded product conditions ซ้ำทุก tier | ทำอัตโนมัติ — FE ส่ง excluded_products ครั้งเดียว, backend replicate ให้ทุก tier |
| จัดการ earn_factor_time_conditions | สร้าง/ลบตาม timing field ที่ส่งมา |

---

## Fields ที่ FE ไม่ต้องแก้ (Read-Only)

Fields เหล่านี้ GET คืนมาเพื่อแสดงผล แต่ UPSERT จะ ignore:

- `tier_name` — ชื่อ tier (ใช้แสดงใน UI)
- `entity_names` — ชื่อ product (ถ้ามี)

FE ส่งกลับมาได้ ไม่มีผลอะไร ระบบจะไม่สนใจ

---

## Fields ที่ FE ต้องเก็บไว้ (สำคัญสำหรับ Round-Trip)

Fields เหล่านี้ **ต้อง** ส่งกลับมาตอน save เพื่อให้ระบบ update แทนที่จะสร้างใหม่:

- `earn_factor_group_id`
- `factor_id` (ในแต่ละ rate และ multiplier)
- `earn_conditions_group_id` (ในแต่ละ rate และ multiplier)
- `condition_id` (ใน excluded_products และ include_products)
- `single_rate_factor_id`

> ถ้า field เหล่านี้เป็น `null` → ระบบจะสร้าง object ใหม่  
> ถ้ามีค่า → ระบบจะ update object เดิม
