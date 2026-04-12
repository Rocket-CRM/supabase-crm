# คู่มือทดสอบ OCR — FuturePark Receipt Evaluation

## ภาพรวม

ระบบนี้ใช้วัด **ความแม่นยำของ OCR pipeline** (Roboflow + Claude) โดยเทียบผลที่ได้กับ **Ground Truth** (ค่าที่ถูกต้องที่ตรวจสอบแล้ว)

ทุกครั้งที่แก้ prompt หรือเปลี่ยน config → **รัน eval ก่อน deploy** เพื่อดูว่า accuracy ดีขึ้นหรือแย่ลง

### Base URL

```
https://crm-batch-upload.onrender.com
```

### ⚠️ สิ่งสำคัญ: Ground Truth ต้องถูกต้อง

ค่า `correct_result` ใน `custom_futurepark_receipt_groundtruth` ถูก seed มาจาก `ocr_suggestions` ตอนที่ receipt ถูก approve — **ค่าเหล่านี้อาจไม่ถูกต้อง** เพราะ admin approve โดยไม่ได้ตรวจทุก field

**ก่อนใช้ eval อย่างจริงจัง ต้อง:**
1. เปิดรูปใบเสร็จจริง
2. ตรวจสอบค่าใน `correct_result` ว่าตรงกับใบเสร็จจริง
3. แก้ค่าที่ผิดใน table `custom_futurepark_receipt_groundtruth`

ถ้า ground truth ผิด → ผล eval จะไม่มีความหมาย

---

## ค่าใช้จ่ายโดยประมาณ

### ต่อ 100 ใบเสร็จ

| Service | รายละเอียด | ค่าใช้จ่าย |
|---|---|---|
| **Claude Haiku 4.5** | 200 calls (2 ต่อใบ) × ~2,100 input tokens + ~250 output tokens | **~$0.35** (~12 บาท) |
| **Roboflow** | 100 calls (workflow classify + OCR) | **~$0.50–5.00** (~17–170 บาท)* |
| **รวม** | | **~$1–5 ต่อ 100 ใบ** (~35–180 บาท) |

\* ค่า Roboflow ขึ้นกับ plan (v1 = ถูก, v2 = คิดตามเวลา execution)

### ต่อ 1 รอบ eval ทั้งหมด (392 ใบ)

| | ต่ำสุด | สูงสุด |
|---|---|---|
| Claude | ~$1.40 (48 บาท) | ~$1.40 (48 บาท) |
| Roboflow | ~$2 (68 บาท) | ~$20 (680 บาท) |
| **รวม** | **~$3.40 (116 บาท)** | **~$21 (728 บาท)** |

---

## Endpoints ทั้งหมด

| Method | Endpoint | ใช้ทำอะไร |
|---|---|---|
| POST | `/api/ocr-eval/stores` | ดูรายการร้านค้าที่มีใน ground truth |
| POST | `/api/ocr-eval/single` | ทดสอบ OCR กับรูปใบเสร็จ 1 ใบ |
| POST | `/api/ocr-eval/start` | เริ่ม eval run (ทำงาน background, ไม่มี timeout) |
| GET | `/api/ocr-eval/progress/:run_id` | เช็คความคืบหน้า + accuracy ระหว่างทำ |
| POST | `/api/ocr-eval/cancel/:run_id` | ยกเลิก eval ที่กำลังรันอยู่ |

---

## 1. ดูร้านค้าที่มีใน Ground Truth

ดูว่ามีร้านไหนบ้าง มีกี่ใบเสร็จ

```bash
curl -X POST https://crm-batch-upload.onrender.com/api/ocr-eval/stores \
  -H "Content-Type: application/json" \
  -d '{}'
```

**ตัวอย่างผลลัพธ์:**

```json
{
  "success": true,
  "stores": [
    { "store_code": "110399", "store_name": "STARBUCKS COFFEE", "test_cases": 137 },
    { "store_code": "110906", "store_name": "EVE and BOY", "test_cases": 45 },
    { "store_code": "160014", "store_name": "Dr.PONG", "test_cases": 37 },
    { "store_code": "108853", "store_name": "H&M", "test_cases": 29 }
  ],
  "total_cases": 392
}
```

---

## 2. ทดสอบ OCR รูปเดียว

ส่งรูปใบเสร็จ 1 ใบ → ได้ผลลัพธ์ OCR กลับมาทันที (ไม่เทียบ ground truth)

```bash
curl -X POST https://crm-batch-upload.onrender.com/api/ocr-eval/single \
  -H "Content-Type: application/json" \
  -d '{
    "image_url": "https://wkevmsedchftztoolkmi.supabase.co/storage/v1/object/public/images/receipts/10de947e-ff05-4e2b-88ff-c853e5a69cb3/d127ae1c-eb0d-4266-85a4-b8ce80b8fffa/0.jpg"
  }'
```

**ตัวอย่างผลลัพธ์:**

```json
{
  "success": true,
  "result": {
    "store_name": "Sushiro",
    "belongs_to_futurepark": "yes",
    "receipt_number": "T48-9874013",
    "receipt_datetime": "2026-03-20T19:08:00",
    "net_amount_after_discount": 352,
    "payment_method": "QR"
  },
  "duration_ms": 6200
}
```

---

## 3. เริ่ม Eval Run

### Parameters

| Parameter | Type | Required | คำอธิบาย |
|---|---|---|---|
| `store_code` | string[] | ไม่ | กรองเฉพาะร้านที่ต้องการ ส่งเป็น array เช่น `["110399", "110906"]` |
| `limit` | number | ไม่ | จำนวนใบเสร็จสูงสุดที่จะทดสอบ ไม่ระบุ = ใช้ทั้งหมด |
| `random` | boolean | ไม่ | `true` = สุ่มเลือก, `false` (default) = เรียงตาม created_at |
| `tags_filter` | string[] | ไม่ | กรองตาม tags เช่น `["futurepark_yes"]` |
| `merchant_code` | string | ไม่ | default = `"futurepark"` |

### ตัวอย่าง: สุ่ม 10 ใบจาก Starbucks

```bash
curl -X POST https://crm-batch-upload.onrender.com/api/ocr-eval/start \
  -H "Content-Type: application/json" \
  -d '{
    "store_code": ["110399"],
    "limit": 10,
    "random": true
  }'
```

### ตัวอย่าง: สุ่ม 50 ใบจากทุกร้าน

```bash
curl -X POST https://crm-batch-upload.onrender.com/api/ocr-eval/start \
  -H "Content-Type: application/json" \
  -d '{
    "limit": 50,
    "random": true
  }'
```

### ตัวอย่าง: ทุกใบของ H&M + EVE and BOY

```bash
curl -X POST https://crm-batch-upload.onrender.com/api/ocr-eval/start \
  -H "Content-Type: application/json" \
  -d '{
    "store_code": ["108853", "110906"]
  }'
```

### ตัวอย่าง: ทุกใบทุกร้าน (392 ใบ, ใช้เวลา ~30-60 นาที)

```bash
curl -X POST https://crm-batch-upload.onrender.com/api/ocr-eval/start \
  -H "Content-Type: application/json" \
  -d '{}'
```

**ผลลัพธ์ (ได้กลับมาทันที ไม่ต้องรอ):**

```json
{
  "success": true,
  "run_id": "a1b2c3d4-e5f6-...",
  "total_receipts": 10,
  "selection": "store_code=[110399], random, 10/392 available",
  "message": "Eval started. Use GET /progress/:run_id to check status."
}
```

---

## 4. เช็คความคืบหน้า

ใช้ `run_id` จากขั้นตอนก่อนหน้า เรียกได้เรื่อยๆ ระหว่างที่ระบบยังทำงานอยู่

```bash
curl https://crm-batch-upload.onrender.com/api/ocr-eval/progress/RUN_ID
```

**ผลลัพธ์ระหว่างรัน:**

```json
{
  "success": true,
  "status": "running",
  "processed": 6,
  "total": 10,
  "remaining": 4,
  "passed": 4,
  "failed": 2,
  "overall_accuracy": 0.6667,
  "by_field": {
    "prediction_class":          { "pass": 6, "fail": 0, "accuracy": 1.0 },
    "belongs_to_futurepark":     { "pass": 6, "fail": 0, "accuracy": 1.0 },
    "receipt_number":            { "pass": 5, "fail": 1, "accuracy": 0.8333 },
    "receipt_datetime":          { "pass": 4, "fail": 2, "accuracy": 0.6667 },
    "net_amount_after_discount": { "pass": 5, "fail": 1, "accuracy": 0.8333 }
  },
  "recent_failures": [
    {
      "image_url": "https://...",
      "store_name": "Starbucks Coffee",
      "field": "receipt_datetime",
      "expected": "2024-11-17T18:20:00",
      "actual": "2025-11-17T18:20:00"
    }
  ]
}
```

**ผลลัพธ์เมื่อเสร็จ:**

```json
{
  "success": true,
  "status": "completed",
  "processed": 10,
  "total": 10,
  "passed": 7,
  "failed": 3,
  "overall_accuracy": 0.7,
  "by_field": { ... },
  "failures": [ ... ]
}
```

---

## 5. ยกเลิก Eval

ถ้าต้องการหยุด eval ที่กำลังรัน

```bash
curl -X POST https://crm-batch-upload.onrender.com/api/ocr-eval/cancel/RUN_ID
```

---

## วิธีอ่านผลลัพธ์

### `overall_accuracy`

สัดส่วนใบเสร็จที่ **ทุก field ถูกหมด** เช่น 0.7 = 70% ของใบเสร็จผ่านทุก field

### `by_field`

ความแม่นยำแยกตาม field:

| Field | ดูอะไร | วิธีเปรียบเทียบ |
|---|---|---|
| `prediction_class` | รหัสร้านค้า 6 หลักจาก Roboflow classifier | exact string match |
| `belongs_to_futurepark` | ใช่ร้านใน FuturePark ไหม | exact: yes/no/uncertain |
| `receipt_number` | เลขที่ใบเสร็จ | exact string match |
| `receipt_datetime` | วันที่ใบเสร็จ | เทียบแค่วันที่ (ไม่สนเวลา) |
| `net_amount_after_discount` | ยอดเงิน | ตัวเลข ±1 (ปัดเศษ) |

### `recent_failures`

รายการ field ที่ผิด พร้อม expected vs actual — ใช้ดูว่า prompt ต้องแก้ตรงไหน

---

## Workflow แนะนำ

```
1. แก้ prompt ใน custom_futureparkocrprompts
         ↓
2. รัน eval: POST /api/ocr-eval/start
         ↓
3. เช็คผล: GET /api/ocr-eval/progress/:run_id
         ↓
4. ถ้า accuracy ≥ ครั้งก่อน → deploy prompt ใหม่
   ถ้า accuracy ตก → ดู failures แก้ prompt ใหม่ → กลับข้อ 2
```

---

## เวลาโดยประมาณ

| จำนวนใบเสร็จ | เวลาโดยประมาณ |
|---|---|
| 10 ใบ | ~1-2 นาที |
| 50 ใบ | ~5-8 นาที |
| 100 ใบ | ~10-15 นาที |
| 392 ใบ (ทั้งหมด) | ~30-60 นาที |

---

## ตาราง DB ที่เกี่ยวข้อง

| Table | ใช้ทำอะไร |
|---|---|
| `custom_futurepark_receipt_groundtruth` | เก็บใบเสร็จ + ค่าที่ถูกต้อง (ต้องตรวจสอบด้วยมือ) |
| `custom_futurepark_ocr_eval_runs` | ประวัติการรัน eval — accuracy, prompt snapshot |
| `custom_futurepark_ocr_eval_results` | ผลลัพธ์รายใบเสร็จของแต่ละ run |
| `custom_futureparkocrprompts` | Claude prompts ที่ OCR ใช้ (`is_futurepark`, `net_amount_extraction`) |
