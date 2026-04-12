# Data Migration: MongoDB → Supabase

> เอกสารนี้อธิบาย **วัตถุประสงค์ของแต่ละตาราง** และ **วิธีการย้ายข้อมูล** เท่านั้น
> รายละเอียด field mapping ทั้งหมดอยู่ใน `DATA_MIGRATION_FIELD_MAPPING.csv`

---

## สรุปภาพรวม

ย้ายข้อมูลจาก MongoDB (13 databases, document-oriented) ไปยัง Supabase/PostgreSQL (relational, normalized)

**ข้อแตกต่างหลัก:**

| เรื่อง | MongoDB (เก่า) | Supabase (ใหม่) |
|---|---|---|
| ID | ObjectId (24 hex) | UUID |
| โครงสร้าง | Nested documents & arrays | Normalized tables + JSONB |
| Naming | ผสม camelCase / snake_case | snake_case เท่านั้น |
| Multi-tenancy | merchantId (ObjectId/String) | merchant_id (UUID FK → merchant_master) |

---

## วัตถุประสงค์ของแต่ละตาราง Supabase

### Entity Tables (ข้อมูลหลัก)

| ตาราง | หน้าที่ | มี mongo_id | Migration |
|---|---|---|---|
| `merchant_master` | ข้อมูลร้านค้า/แบรนด์ หนึ่งแถวต่อหนึ่ง merchant | ✅ | **ไม่ migrate** — มีอยู่แล้ว 22 rows ใน Supabase ต้อง backfill mongo_id ให้ match กับ MongoDB ObjectId |
| `tier_master` | นิยาม tier (ระดับสมาชิก) ของแต่ละ merchant | ✅ | **ตรวจสอบ** — ถ้ามีอยู่แล้วก็ backfill mongo_id เหมือน merchant_master |
| `store_master` | ข้อมูลสาขา/ร้านค้า | ✅ | **ตรวจสอบ** — เช่นเดียวกัน |
| `consent_versions` | เวอร์ชันของ PDPA form ที่ลูกค้ายินยอม | ✅ | Migrate จาก loyaltydb.pdpas |
| `user_accounts` | **ข้อมูลสมาชิก (end-user)** หนึ่งแถวต่อคนต่อ merchant มี profile, tier FK, persona FK, notification toggles **ไม่รวม admin** — admin จะเชิญใหม่ผ่าน admin_users | ✅ |
| `reward_master` | คำจำกัดความรางวัล/คูปอง/สิทธิพิเศษ ทั้ง rewards และ QR coupons จาก MongoDB รวมอยู่ที่นี่ | ✅ |
| `reward_category` | หมวดหมู่รางวัล เช่น "อาหารและเครื่องดื่ม", "สินค้า" | ✅ |

### Balance & Wallet

| ตาราง | หน้าที่ | มี mongo_id |
|---|---|---|
| `user_wallet` | ยอดเงินคงเหลือปัจจุบัน (points + tickets) หนึ่งแถวต่อ user ต่อ merchant อัปเดตอัตโนมัติเมื่อ wallet_ledger มีรายการใหม่ | ✅ |

### Ledger Tables (ประวัติธุรกรรม — immutable)

| ตาราง | หน้าที่ | มี mongo_id |
|---|---|---|
| `wallet_ledger` | **บันทึกธุรกรรมแต้มทุกรายการ** — earn, burn ทุกรายการคือหนึ่งแถว เป็น source of truth สำหรับการคำนวณแต้มทั้งหมด | ✅ |
| `currency_transactions_schedule` | ธุรกรรมแต้มที่รอดำเนินการ (delayed earn) จะทำงานเมื่อถึง execution_datetime | ✅ |
| `tier_change_ledger` | ประวัติการเปลี่ยน tier — initial, upgrade, downgrade ทุกครั้งจะบันทึก from/to tier | ✅ |
| `reward_redemptions_ledger` | ประวัติการแลกรางวัล — ตั้งแต่แลก → ใช้ → ยกเลิก พร้อมแต้มที่หัก, promo code, สถานะ fulfillment | ✅ |
| `order_ledger_mkp` | คำสั่งซื้อ marketplace (Lazada/Shopee/TikTok) รวมเป็นตารางเดียว แยกด้วย platform | ✅ |
| `user_consent_ledger` | PDPA consent audit trail — ทุกครั้งที่ลูกค้ายอมรับ/ปฏิเสธ consent form | ✅ |

### Child / Normalized Tables (ไม่มี mongo_id)

ตารางเหล่านี้เกิดจากการ normalize embedded documents/arrays ไม่มี `_id` เป็นของตัวเอง:

| ตาราง | หน้าที่ | มาจาก |
|---|---|---|
| `user_address` | ที่อยู่ไทย (จังหวัด/อำเภอ/ตำบล) | contacts.address embedded doc |
| `tier_progress` | สถานะ tier ปัจจุบัน — progress %, deadline | users.memberTier + contacts tier fields |
| `user_communication_preferences` | ตั้งค่าการแจ้งเตือนรายหัวข้อ | users.notifSetting.events[] |
| `form_submissions` + `form_responses` | ข้อมูล custom fields ในระบบ form (event-sourcing) | contacts.customFields[] |
| `survey_answers` | คำตอบแบบสำรวจ | contacts.surveyQuestions[] |
| `reward_points_conditions` | ราคาแต้มตาม tier | rewards.tierPointList[] |
| `reward_promo_code` | pool ของ promo code | rewards.alienCodePartnerList[] |
| `order_items_ledger_mkp` | รายการสินค้าใน order | *_order_transactions.items[] |

---

## หลักการจัดการ ID

### mongo_id — หัวใจของการย้ายข้อมูล

ทุกตารางที่รับข้อมูลจาก MongoDB document ที่มี `_id` เป็นของตัวเอง จะมีคอลัมน์ `mongo_id text`:

- **`id`** → UUID ใหม่ (gen_random_uuid) — ใช้ในระบบ Supabase ต่อไป
- **`mongo_id`** → ObjectId ดั้งเดิมจาก MongoDB — สำหรับ traceability และ FK resolution

**ไม่ใช่** การแปลง ObjectId เป็น UUID โดยตรง แต่สร้าง UUID ใหม่และเก็บ ObjectId เดิมไว้แยก

### ทำไมต้องทำแบบนี้

1. UUID ใหม่ไม่มีร่องรอยของ ObjectId — สะอาดสำหรับระบบใหม่
2. mongo_id ทำให้สามารถ trace กลับไป MongoDB ได้ — สำคัญสำหรับ debugging และ support
3. FK resolution ทำได้ง่ายด้วย batch JOIN — ไม่ต้องแปลง ObjectId เป็น UUID แบบ deterministic

---

## วิธีการ Resolve FK (Foreign Key)

### ปัญหา

ใน MongoDB record เช่น wallet_ledger อ้างอิง `userId: "507f1f77..."` แต่ใน Supabase user คนนั้นจะมี `id: 'e7f8a9b0-...'` (UUID ใหม่) ต้องแปลงอ้างอิงทั้งหมดให้ตรง

### วิธีแก้: Two-Pass Import + Batch FK Resolution

**Pass 1 — Import โดยเก็บ mongo reference ไว้ชั่วคราว:**

แต่ละตารางจะมีคอลัมน์ชั่วคราว `_mongo_*` (เช่น `_mongo_user_id`, `_mongo_merchant_id`) เก็บค่า ObjectId/String ดั้งเดิม ส่วนคอลัมน์ FK จริง (`user_id`, `merchant_id`) ยังเป็น NULL

**Pass 2 — Batch UPDATE เพื่อ resolve UUID:**

```sql
UPDATE wallet_ledger wl
SET user_id = ua.id
FROM user_accounts ua
WHERE wl._mongo_user_id = ua.mongo_id
  AND wl.user_id IS NULL;
```

หลักการคือ JOIN ระหว่าง `_mongo_*` ชั่วคราว กับ `mongo_id` ของตารางเป้าหมาย

**Pass 3 — ลบคอลัมน์ชั่วคราว:**

หลังตรวจสอบแล้วว่าทุก FK resolve ครบ ก็ลบ `_mongo_*` columns ออกได้ ส่วน `mongo_id` เก็บไว้ 3-6 เดือนสำหรับ support

---

## สิ่งที่ไม่ย้าย

### Admin Users

ระบบเก่ามี flag `isLoyaltyAdmin`, `isPosAdmin` บน loyaltydb.users — ระบบใหม่ admin อยู่ใน `admin_users` table แยกต่างหาก **ไม่ migrate admin** จะเชิญใหม่ทั้งหมด user_accounts.role จะเป็น `'user'` ทั้งหมด

### Aggregate Fields

contacts มีฟิลด์สถิติ ~25 ตัว เช่น `totalSaleAmount`, `pointBalance`, `totalRewardUsed` — เหล่านี้เป็น denormalized cache ในระบบใหม่จะ derive จาก ledger tables แทน

### Denormalized Names

ชื่อที่ซ้ำจาก master data เช่น `tierName`, `storeName`, `adminName` — ใน Supabase ดึงจาก JOIN

---

## Transform Codes (ใช้ใน CSV)

| Code | ความหมาย |
|---|---|
| `direct` | คัดลอกตรงๆ (type ตรงกัน) |
| `cast::type` | แปลง type เช่น Decimal128 → numeric |
| `gen_random_uuid()` | สร้าง UUID ใหม่สำหรับ primary key |
| `resolve_fk` | FK ต้อง resolve หลัง import ผ่าน mongo_id ของตารางเป้าหมาย |
| `resolve_lookup` | Lookup ค่าจาก reference table เช่น รหัสจังหวัด → ชื่อจังหวัด |
| `derive` | คำนวณจากข้อมูลอื่น ไม่ใช่คัดลอกตรง |
| `epoch→timestamptz` | แปลง epoch milliseconds เป็น timestamp |
| `jsonb` | เก็บใน JSONB column |
| `normalize` | embedded array/doc แตกออกเป็นแถวในตารางลูก |
| `default` | ใช้ค่า default ที่ระบุ |
| `generate` | สร้างค่าใหม่ เช่น slug, sequential code |
| `match` | ใช้สำหรับ UPDATE — จับคู่กับ row ที่มีอยู่แล้ว |
| `skip` | ไม่ migrate ฟิลด์นี้ |

---

## Enum Values ที่ถูกต้อง (ตรวจจาก Supabase schema จริง)

| Enum Name | ค่าที่ใช้ได้ | ใช้ใน |
|---|---|---|
| `user_type` | buyer, seller | user_accounts.user_type |
| `role` | user, admin | user_accounts.role |
| `reward_visibility` | user, admin, campaign | reward_master.visibility |
| `reward_fulfillment_method` | shipping, pickup, digital, printed | reward_master.fulfillment_method |
| `reward_expire_mode` | relative_days, relative_mins, absolute_date | reward_master.use_expire_mode |
| `currency_transaction_type` | burn, earn | wallet_ledger.transaction_type |
| `wallet_transaction_source_type` | purchase, campaign, manual, reward_redemption, referral, redemption_cancellation, mission, code, activity, amp | wallet_ledger.source_type + redemptions.source_type |
| `currency` | points, ticket | wallet_ledger.currency |
| `currency_component` | base, bonus, adjustment, reversal | wallet_ledger.component |
| `tier_change_type` | initial, upgrade, downgrade, manual, scheduled | tier_change_ledger.change_type |
| `rewards_redemption_fulfillment_status` | pending, shipped, delivered, completed, cancelled, reject | reward_redemptions_ledger.fulfillment_status |
| `metric` | points, ticket, sales, orders | tier_progress.upgrade_metric_needed + maintain_metric_needed |

---

## Mapping จาก MongoDB ค่าเดิม → Enum ใหม่

### user_type
- `CUSTOMER` → `buyer`
- `MERCHANT` → `seller`

### wallet_ledger.transaction_type
- `GIVEN` / `EARNED` → `earn`
- `DEDUCT` / `DEDUCTED` → `burn`
- `EXPIRED` → `burn` (เก็บ `{"original_type": "expired"}` ใน metadata)
- `VOIDED` → `burn` (เก็บ `{"original_type": "voided"}` ใน metadata)

### wallet_ledger.source_type
- `SALE` → `purchase`
- `ADMIN` / `CRM_USER` / `SYSTEM` → `manual`
- อื่นๆ ดูจาก context: receipt upload → `activity`, mission → `mission`

### tier_change_ledger.change_type
- `ASSIGN` → `initial`
- `UPGRADE` → `upgrade`
- `DOWNGRADE` → `downgrade`

### reward_master.visibility
- `REWARD` → `user`
- `BENEFIT` → `admin`

### reward_master.fulfillment_method
- `TAKEAWAY` → `pickup`
- `DELIVERY` → `shipping`

### reward_master.use_expire_mode
- `DAY` → `relative_days`
- `MINUTE` → `relative_mins`
- `HOUR` → `relative_mins` (ต้องแปลง use_expire_ttl: ชั่วโมง × 60 = นาที)

### reward_redemptions_ledger.fulfillment_status (derive จาก status ไม่ใช่ exchangedType)
- `REDEEMED` → `pending`
- `USED` → `completed`
- `CANCELLED` → `cancelled`

### reward_redemptions_ledger.source_type
- `REWARD` / `BENEFIT` → `reward_redemption`
- `COUPON` → `code`
- ถ้า `isMission=true` → `mission`

---

## ลำดับการ Migrate (ตาม FK dependency)

| Step | Action | ตาราง |
|---|---|---|
| 0 | Prerequisites (ต้องมีก่อน) | `merchant_master`, `tier_master`, `store_master` |
| 1 | Consent form definitions | `consent_versions` (จาก loyaltydb.pdpas) |
| 2 | **Area 1:** Accounts | `user_accounts`, `user_address`, `tier_progress`, `form_submissions`, `form_responses`, `survey_answers` |
| 3 | **Area 2:** Points Balance | `user_wallet` |
| 4 | **Area 5:** Reward Master | `reward_master`, `reward_category`, `reward_points_conditions`, `reward_promo_code` |
| 5 | **Area 3:** Points History | `wallet_ledger`, `currency_transactions_schedule` |
| 6 | **Area 4:** Tier Movement | `tier_change_ledger` |
| 7 | **Area 6:** Redemptions | `reward_redemptions_ledger` |
| 8 | **Area 7:** Marketplace Orders | `order_ledger_mkp`, `order_items_ledger_mkp` |
| 9 | **Area 8:** Marketplace Claims | `order_ledger_mkp` (UPDATE เท่านั้น) |
| 10 | **Area 9:** PDPA Consent | `user_consent_ledger` |

---

## แหล่งข้อมูลหลายแหล่งที่ต้องระวัง

### user_accounts — 3 แหล่ง merge
1. `loyaltydb.contacts` — **หลัก** สำหรับ profile (ชื่อ, อีเมล, โทร, tier, ที่อยู่)
2. `loyaltydb.users` — **หลัก** สำหรับ identity (LINE ID, notification, user_type)
3. `crm_user_db.users` — **fallback** เฉพาะฟิลด์ที่ขาดจาก 2 แหล่งข้างบน

**ลำดับความสำคัญ:** contacts > users > crm_user_db

### wallet_ledger — 2 ยุค
1. `loyaltydb.points` — ยุคเก่า (camelCase, ObjectId, epoch expiry)
2. `crm_point_db.point_transactions` — ยุคใหม่ (snake_case, String, Date expiry)

**ใช้ dedup_key ป้องกันซ้ำ:** `'legacy:{mongo_id}'` vs `'crm_point:{mongo_id}'`

### reward_master — 2 ประเภทรวม
1. `loyaltydb.rewards` — รางวัลแลกแต้ม
2. `loyaltydb.qrtables` — คูปอง QR/URL

ทั้งสองรวมอยู่ใน `reward_master` — แยกด้วย `visibility` และ `fulfillment_method`

---

## การตรวจสอบหลัง Migrate

### 1. Orphan Check (FK ที่ไม่ resolve)
```sql
SELECT count(*) FROM wallet_ledger WHERE user_id IS NULL;
SELECT count(*) FROM reward_redemptions_ledger WHERE reward_id IS NULL;
SELECT count(*) FROM tier_change_ledger WHERE to_tier_id IS NULL;
```
**คาดหวัง:** ศูนย์สำหรับ mandatory FK (nullable FK เช่น from_tier_id ที่เป็น initial assign อาจเป็น NULL ได้)

### 2. Balance Reconciliation
```sql
SELECT uw.user_id, uw.points_balance, COALESCE(SUM(wl.signed_amount), 0) AS calc
FROM user_wallet uw
LEFT JOIN wallet_ledger wl ON wl.user_id = uw.user_id
GROUP BY uw.user_id, uw.points_balance
HAVING uw.points_balance != COALESCE(SUM(wl.signed_amount), 0);
```

### 3. Row Count Comparison
เทียบจำนวนแถวจาก MongoDB กับ Supabase ทุกตาราง

### 4. Duplicate Check
```sql
SELECT mongo_id, count(*) FROM user_accounts
WHERE mongo_id IS NOT NULL GROUP BY mongo_id HAVING count(*) > 1;
```

---

## Cleanup หลังตรวจสอบเสร็จ

1. **ลบคอลัมน์ชั่วคราว** (`_mongo_*`) ที่ใช้สำหรับ FK resolution
2. **เก็บ mongo_id** ไว้ 3-6 เดือนสำหรับ support/debugging
3. **เปิด triggers และ FK constraints** ที่ปิดไว้ตอน import
4. หลัง 3-6 เดือน สามารถลบ mongo_id ได้ถ้าไม่ต้องการแล้ว
