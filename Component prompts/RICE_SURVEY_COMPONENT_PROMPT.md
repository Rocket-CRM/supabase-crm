# Prompt: Build Rice Farmer Survey Component for WeWeb

## Overview

Build a **single custom coded WeWeb component** (Vue 3 composition API) for conducting rice farmer field interviews. Use the **Polaris Vue** npm package and follow the **Polaris component structure guidelines** from the official GitHub repo (https://github.com/nicepkg/polaris-vue). Adhere to Polaris spacing, typography tokens, form patterns, and layout primitives throughout.

The component handles **user lookup by phone, optional signup for new users, and the full survey** — all in one flow.

All labels are in Thai. The component is for field interviewers using tablets/phones.

---

## Component Flow (3 phases)

```
Phase 1: USER IDENTIFICATION
┌──────────────────────────┐
│  Tel Input               │
│  Enter farmer's phone    │
│  [ค้นหา] button          │
└────────────┬─────────────┘
             │
     ┌───────┴───────┐
     │  Lookup user  │ ← query user_accounts by tel + merchant_id
     └───────┬───────┘
             │
      ┌──────┴──────┐
      ▼              ▼
   FOUND         NOT FOUND
      │              │
      │              ▼
      │    Phase 2: SIGNUP
      │    ┌────────────────────────┐
      │    │  Show signup form      │
      │    │  • firstname, lastname │
      │    │  • จังหวัด/อำเภอ/ตำบล   │
      │    │  • พืชที่ปลูก, พื้นที่    │
      │    │  [ลงทะเบียนและเริ่มสำรวจ]│
      │    └────────────┬───────────┘
      │                 │
      ▼                 ▼
Phase 3: SURVEY (sections A → E → Review → Submit)
┌──────────────────────────────────────┐
│  Step 1: A) ข้อมูลทั่วไป (A1-A9)      │
│  Step 2: B) วัชพืช                    │
│  Step 3: C) แมลง/หนอน                 │
│  Step 4: D) โรค                       │
│  Step 5: E) สารอารักขาพืช              │
│  Step 6: ตรวจสอบและส่ง                 │
└──────────────────────────────────────┘
             │
             ▼
    On Submit:
    • If new user → create user_accounts + user_address + USER_PROFILE responses
    • Then → create RICE_BIGGROWER_2026 form_submission + form_responses
    • Show success notification
```

---

## Component Props (only these are dynamic)

```typescript
interface RiceSurveyProps {
  userId: string;          // UUID of the interviewer (logged-in staff conducting the interview)
  accessToken: string;     // Supabase JWT of the interviewer
  source?: string;         // defaults to "field_interview"
  onComplete?: (result: { submissionId: string; farmerId: string; isNewUser: boolean }) => void;
  onClose?: () => void;
}
```

Everything else is hardcoded.

---

## Hardcoded Constants

```typescript
const SUPABASE_URL = 'https://wkevmsedchftztoolkmi.supabase.co';
const SUPABASE_ANON_KEY = ''; // Fill with actual anon key

// Survey form
const FORM_ID = '622bed39-c4df-4d5d-9c4b-2ac4873104fa';
const FORM_CODE = 'RICE_BIGGROWER_2026';
const MERCHANT_ID = '8f67aa08-dfce-454d-bfb1-effc4ee45f1f';

// Syngenta USER_PROFILE form (for new user signup custom fields)
const USER_PROFILE_FORM_ID = 'a0000000-0000-0000-0000-000000000001';
```

---

## Phase 1: User Identification (Tel Lookup)

### UI

A single Polaris `<Card>` with:
- Title: "แบบสอบถามเกษตรกร — ข้าว"
- Subtitle: "กรุณากรอกหมายเลขโทรศัพท์ของเกษตรกร"
- `<TextField>` — label="หมายเลขโทรศัพท์", type="tel", placeholder="08X-XXX-XXXX"
- `<Button primary>` — "ค้นหา"
- Show `<Spinner>` while searching

### Lookup Logic

```typescript
async function lookupFarmer(tel: string) {
  const normalizedTel = normalizeTel(tel); // 0812345678 → +66812345678

  const { data, error } = await supabase
    .from('user_accounts')
    .select('id, firstname, lastname, tel, merchant_id')
    .eq('merchant_id', MERCHANT_ID)
    .eq('tel', normalizedTel)
    .maybeSingle();

  return data; // null if not found, user object if found
}

function normalizeTel(tel: string): string {
  let cleaned = tel.replace(/[\s\-]/g, '');
  if (cleaned.startsWith('0')) cleaned = '+66' + cleaned.substring(1);
  else if (cleaned.startsWith('66') && !cleaned.startsWith('+66')) cleaned = '+' + cleaned;
  else if (!cleaned.startsWith('+')) cleaned = '+66' + cleaned;
  return cleaned;
}
```

### After Lookup

- **User FOUND:** Show a Polaris `<Banner status="success">` with "พบข้อมูล: {firstname} {lastname}" and a "เริ่มสำรวจ" (Start Survey) button. Store `farmerUserId`. Skip to Phase 3.
- **User NOT FOUND:** Show `<Banner status="info">` with "ไม่พบข้อมูลในระบบ กรุณากรอกข้อมูลลงทะเบียน". Show Phase 2 (Signup).

---

## Phase 2: Signup (new users only)

This section collects the **standard Syngenta signup fields** — same data the normal signup flow collects, but done inline by the interviewer.

### Syngenta Default Fields (from user_field_config)

| field_key | Label | Input Type | Required | Storage |
|-----------|-------|-----------|----------|---------|
| `firstname` | ชื่อ | `<TextField>` | Yes | `user_accounts.firstname` |
| `lastname` | นามสกุล | `<TextField>` | Yes | `user_accounts.lastname` |
| `city` | จังหวัด | `<Select>` (cascading) | Yes | `user_address.city` |
| `district` | อำเภอ | `<Select>` (cascading) | Yes | `user_address.district` |
| `subdistrict` | ตำบล | `<Select>` (cascading) | Yes | `user_address.subdistrict` |

**Note on cascading selects:** province → district → subdistrict is a standard Thai address pattern. You can either:
- Use simple `<TextField>` inputs (simpler, acceptable for field interviews), OR
- Fetch address data from a Thai address API/static JSON for cascading dropdowns (better UX but more work)

For MVP, use `<TextField>` for all three. Mark them as free text.

### Syngenta USER_PROFILE Custom Fields (from form_fields)

| field_key | Label | Input Type | Required |
|-----------|-------|-----------|----------|
| `crop` | พืชที่ปลูก | `<Select>` multi-select | Yes |
| `area` | พื้นที่เพาะปลูก (ไร่) | `<TextField type="number">` | Yes |

**Crop options:** Fetch from `form_field_options` where `field_id` matches the crop field in USER_PROFILE form. OR hardcode if you already know them. Query to get them:

```typescript
const { data: cropOptions } = await supabase
  .from('form_field_options')
  .select('option_value, option_label, order_index')
  .eq('field_id', CROP_FIELD_ID)
  .order('order_index');
```

### Signup State

```typescript
const signupData = reactive({
  firstname: '',
  lastname: '',
  city: '',
  district: '',
  subdistrict: '',
  crop: [],        // array of selected crop values
  area: null,      // number
});
```

### Signup Validation

All fields required. Show Polaris `<InlineError>` under each empty required field when user tries to proceed.

### After Signup Section

User clicks "ลงทะเบียนและเริ่มสำรวจ" button → data is stored in state (NOT saved to DB yet — saved on final survey submit). Proceed to Phase 3.

---

## Phase 3: Survey (sections A through E)

### NO DEMOGRAPHICS STEP — removed

The survey demographics (name, gender, address, phone) are all handled by Phase 1 (tel lookup) and Phase 2 (signup). The survey starts directly with Section A.

### Wizard Steps

| Step | Title | Content |
|------|-------|---------|
| 1 | A) ข้อมูลทั่วไปเกี่ยวกับการปลูกข้าว | A1-A9: age, area, months, years, seasons, varieties, yield, prices |
| 2 | B) คำถามเกี่ยวกับการจัดการวัชพืช | Weed matrix: B1 checkboxes → B2 damage + B3 control ratings |
| 3 | C) คำถามเกี่ยวกับแมลง/หนอน | Insect matrix: C1 checkboxes → C2 stages + C3 damage + C4 control |
| 4 | D) คำถามเกี่ยวกับโรค | Disease matrix: D1 checkboxes → D2 stages + D3 damage + D4 control |
| 5 | E) คำถามเกี่ยวกับการใช้สารอารักขาพืช | Spray table + E6 cost breakdown + E7 investment plan |
| 6 | ตรวจสอบและส่ง | Review summary → submit button |

---

## Field Registry (hardcode all IDs — survey fields only)

```typescript
const FIELDS = {
  // Section A
  a1_age:              { id: '83b257a7-5398-4ab0-af0a-5ff729d8eaaa', type: 'number', required: true, min: 15, max: 99 },
  a2_rice_area_rai:    { id: '30999277-192e-41d8-8ab9-a9f0a6863f05', type: 'number', required: true, min: 1 },
  a3_harvest_month:    { id: '7255950e-19d0-41fb-b009-09e842ccd3ae', type: 'single_select', required: true },
  a4_farming_years:    { id: 'e6feaad3-5e94-4c90-833d-12896f7a4c9f', type: 'number', required: true, min: 1 },
  a5_seasons_per_year: { id: '34311768-e671-4236-8b5d-8647ed50b36f', type: 'number', required: true, min: 1, max: 4 },
  a6_rice_varieties:   { id: '428b2d8c-8041-4251-ada5-f68ff1597d55', type: 'object', required: true },
  a7_yield_per_rai:    { id: '1e963188-8f41-45c7-a355-5ab8be9e1c08', type: 'number', required: true, min: 0 },
  a8_selling_price:    { id: '1830157d-786c-45fe-a3a4-e7521ae1d1db', type: 'number', required: true, min: 0 },
  a9_breakeven_price:  { id: 'dde52e35-8406-4a39-acc3-c40cbbb0f6c5', type: 'number', required: true, min: 0 },

  // Section B (single composite field)
  b_weed_assessment:   { id: '1e0aedb8-074d-4fe8-8dd5-bd4edc4c8a4d', type: 'object', required: false },

  // Section C (single composite field)
  c_insect_assessment: { id: '29c2c930-fe42-423d-9789-ded2574b7605', type: 'object', required: false },

  // Section D (single composite field)
  d_disease_assessment:{ id: '2b6f0034-13c5-4ea9-933c-eae20f7018f2', type: 'object', required: false },

  // Section E
  e1_e5_spray_applications: { id: 'c679d268-48f7-441b-a295-b3fb15baf642', type: 'object', required: false },
  e6_total_cost:       { id: 'a4eaca64-d961-4835-91ac-27ba68c50f97', type: 'number', required: false, min: 0 },
  e6_1_herbicide_pct:  { id: 'ceaef267-3ea7-4084-bdc2-55907d7ab626', type: 'number', required: false, min: 0, max: 100 },
  e6_2_insecticide_pct:{ id: 'e0c1e3d6-74ab-43fa-b629-4d55a5f0c362', type: 'number', required: false, min: 0, max: 100 },
  e6_3_fungicide_pct:  { id: '9d13b1de-3c8e-4668-a031-5e0251d1a9fe', type: 'number', required: false, min: 0, max: 100 },
  e6_4_hormone_pct:    { id: '1c735204-25c1-477a-afa9-31b21fe1fcfb', type: 'number', required: false, min: 0, max: 100 },
  e7_investment_plan:  { id: 'a86fc9ec-0d11-4281-b58b-980da42488d7', type: 'single_select', required: true },
} as const;
```

Demographics field IDs still exist in the DB but are **not used by this component**. The component only submits survey responses for the fields above.

---

## Hardcoded Option Lists

### Harvest Month Options (A3)
```typescript
const MONTH_OPTIONS = [
  { value: '1', label: 'มกราคม' },   { value: '2', label: 'กุมภาพันธ์' },
  { value: '3', label: 'มีนาคม' },   { value: '4', label: 'เมษายน' },
  { value: '5', label: 'พฤษภาคม' },  { value: '6', label: 'มิถุนายน' },
  { value: '7', label: 'กรกฎาคม' },  { value: '8', label: 'สิงหาคม' },
  { value: '9', label: 'กันยายน' },  { value: '10', label: 'ตุลาคม' },
  { value: '11', label: 'พฤศจิกายน' }, { value: '12', label: 'ธันวาคม' },
];
```

### Weed List (B1) — 39 individual items (ungrouped for granular analysis)
```typescript
const WEED_OPTIONS = [
  { code: 'weed_01', label: 'หญ้าข้าวนก' },
  { code: 'weed_02', label: 'หญ้าพุ่มพวง' },
  { code: 'weed_03', label: 'หญ้าคอมมิวนิสต์' },
  { code: 'weed_04', label: 'หญ้าข้าวนกสีชมพ' },
  { code: 'weed_05', label: 'หญ้าข้าวปล้อง' },
  { code: 'weed_06', label: 'หญ้านก' },
  { code: 'weed_07', label: 'หญ้าแดง' },
  { code: 'weed_08', label: 'หญ้ากระดูกไก่' },
  { code: 'weed_09', label: 'หญ้าก้านธูป' },
  { code: 'weed_10', label: 'หญ้าสล้าง' },
  { code: 'weed_11', label: 'หญ้าดอกขาว' },
  { code: 'weed_12', label: 'หญ้าลิเก' },
  { code: 'weed_13', label: 'หญ้าไม้กวาด' },
  { code: 'weed_14', label: 'ผักปอดนา' },
  { code: 'weed_15', label: 'หญ้าจำปา' },
  { code: 'weed_16', label: 'ผักพริก' },
  { code: 'weed_17', label: 'ผักปุ่มปลา' },
  { code: 'weed_18', label: 'หนวดปลาดุก' },
  { code: 'weed_19', label: 'หญ้าหนวดแมว' },
  { code: 'weed_20', label: 'หญ้าไข่กบ' },
  { code: 'weed_21', label: 'หญ้าไข่เขียด' },
  { code: 'weed_22', label: 'กกขนาก' },
  { code: 'weed_23', label: 'หญ้าดอกต่อ' },
  { code: 'weed_24', label: 'ผือน้อย' },
  { code: 'weed_25', label: 'กกทราย' },
  { code: 'weed_26', label: 'กกแดง' },
  { code: 'weed_27', label: 'หญ้ารังกา' },
  { code: 'weed_28', label: 'เซ่งใบมน' },
  { code: 'weed_29', label: 'เทียนนา' },
  { code: 'weed_30', label: 'โสนคางคก' },
  { code: 'weed_31', label: 'หญ้าชะกาดน้ำเค็ม' },
  { code: 'weed_32', label: 'หญ้าชันกาศ' },
  { code: 'weed_33', label: 'หญ้ากุศลา' },
  { code: 'weed_34', label: 'ปอวัชพืช' },
  { code: 'weed_35', label: 'สะอึก' },
  { code: 'weed_36', label: 'โสนหางไก่' },
  { code: 'weed_37', label: 'ข้าวดีด' },
  { code: 'weed_other_1', label: 'อื่นๆ (ระบุ) 1', hasCustomInput: true },
  { code: 'weed_other_2', label: 'อื่นๆ (ระบุ) 2', hasCustomInput: true },
];
```

### Insect List (C1) — 9 items
```typescript
const INSECT_OPTIONS = [
  { code: 'pest_01', label: 'บั่ว' },
  { code: 'pest_02', label: 'เพลี้ยกระโดดสีน้ำตาล' },
  { code: 'pest_03', label: 'เพลี้ยไฟ' },
  { code: 'pest_04', label: 'แมลงสิง' },
  { code: 'pest_05', label: 'หนอนกอข้าว' },
  { code: 'pest_06', label: 'หนอนห่อใบข้าว' },
  { code: 'pest_07', label: 'แมลงดำหนาม' },
  { code: 'pest_other_1', label: 'อื่นๆ (ระบุ) 1', hasCustomInput: true },
  { code: 'pest_other_2', label: 'อื่นๆ (ระบุ) 2', hasCustomInput: true },
];
```

### Disease List (D1) — 11 items
```typescript
const DISEASE_OPTIONS = [
  { code: 'disease_01', label: 'โรคกาบใบเน่า' },
  { code: 'disease_02', label: 'โรคกาบใบแห้ง' },
  { code: 'disease_03', label: 'โรคขอบใบแห้ง' },
  { code: 'disease_04', label: 'โรคดอกกระถิน' },
  { code: 'disease_05', label: 'โรคใบขีดสีน้ำตาล' },
  { code: 'disease_06', label: 'โรคใบจุดสีน้ำตาล' },
  { code: 'disease_07', label: 'โรคเมล็ดด่าง' },
  { code: 'disease_08', label: 'โรคไหม้' },
  { code: 'disease_09', label: 'โรคใบขีดโน้มตาล' },
  { code: 'disease_other_1', label: 'อื่นๆ (ระบุ) 1', hasCustomInput: true },
  { code: 'disease_other_2', label: 'อื่นๆ (ระบุ) 2', hasCustomInput: true },
];
```

### Growth Stages (used in C2, D2, E1-E5)
```typescript
const GROWTH_STAGES = [
  { value: 1, label: 'ระยะข้าวเล็ก', key: 'small_stage' },
  { value: 2, label: 'ระยะแตกกอ', key: 'tillering_stage' },
  { value: 3, label: 'ระยะข้าวท้อง', key: 'booting_stage' },
  { value: 4, label: 'ระยะสุกแก่/เก็บเกี่ยว', key: 'maturity_stage' },
];
```

### Investment Plan Options (E7) — 8 items
```typescript
const INVESTMENT_OPTIONS = [
  { value: '1', label: 'ลงทุนเพิ่มขึ้น' },
  { value: '2', label: 'ลงทุนเท่าเดิม' },
  { value: '3', label: 'ลงทุนลดลงไม่เกิน 10%' },
  { value: '4', label: 'ลงทุนลดลง 11% - 20%' },
  { value: '5', label: 'ลงทุนลดลง 21% - 30%' },
  { value: '6', label: 'ลงทุนลดลง 31% - 40%' },
  { value: '7', label: 'ลงทุนลดลง 41% - 50%' },
  { value: '8', label: 'ลงทุนลดลงมากกว่า 50%' },
];
```

---

## Step-by-Step UI Specification (Survey Steps)

### Step 1: Section A — General Farm Info

| Field | Component | Notes |
|-------|-----------|-------|
| a1_age | `<TextField type="number">` | label="A1. ปัจจุบันนี้คุณอายุเท่าไร (ปี)", min=15, max=99, suffix="ปี" |
| a2_rice_area_rai | `<TextField type="number">` | label="A2. ...ปลูกข้าวรวมทั้งสิ้นกี่ไร่", min=1, suffix="ไร่" |
| a3_harvest_month | `<Select>` | label="A3. ...เก็บเกี่ยวเสร็จสิ้นในเดือนไหน", options=MONTH_OPTIONS |
| a4_farming_years | `<TextField type="number">` | label="A4. ...ปลูกข้าวมากี่ปี", min=1, suffix="ปี" |
| a5_seasons_per_year | `<TextField type="number">` | label="A5. ...ปลูกข้าวทั้งหมดกี่ฤดู", min=1, max=4, suffix="ฤดู" |
| **a6_rice_varieties** | **`<VarietyRepeater>`** | See below |
| a7_yield_per_rai | `<TextField type="number">` | label="A7. ผลผลิตต่อไร่...", min=0, suffix="กก./ไร่" |
| a8_selling_price | `<TextField type="number">` | label="A8. ราคาขายข้าว...", min=0, suffix="บาท/ตัน" |
| a9_breakeven_price | `<TextField type="number">` | label="A9. ราคาข้าวขั้นต่ำที่จะไม่ขาดทุน", min=0, suffix="บาท/ตัน" |

#### A6 Repeater Sub-Component

Small table with "เพิ่มพันธุ์" (Add variety) button. Each row:
- **A6.1** พันธุ์ข้าว — `<TextField>` (e.g. "กข61")
- **A6.2** อายุเก็บเกี่ยว — `<TextField type="number">` suffix="วัน"
- Delete row button (icon only)

Start with 1 empty row. Max 5 rows. Stored as `object_value`:
```json
[{ "variety": "กข61", "harvest_days": 120 }]
```

### Steps 2-4: Assessment Matrices (B, C, D)

**IMPORTANT — "Store All Items" behavior:** The component must initialize the matrix with ALL items from the options list, each set to `found: false`. When the interviewer checks an item, it flips to `found: true` and the rating inputs appear. On save, **all rows are included** (both found and not found). This ensures explicit "not found" data vs ambiguous missing data — critical for downstream analysis.

#### Step 2: Section B — Weed Assessment Matrix

1. Header: "B1. คุณพบเจอวัชพืชอะไรบ้างในนาข้าวในฤดูกาลล่าสุด"
2. Scrollable list of 39 individual weed items (from WEED_OPTIONS), each as a `<Checkbox>`.
3. When checked (`found: true`), a rating row expands:
   - **B2** "ระดับความเสียหาย" — radio 1-5 (1=แทบไม่เสียหาย, 5=เสียหายมาก)
   - **B3** "ความยากง่ายในการควบคุม" — radio 1-5 (1=ง่ายมาก, 5=ยากมาก)
4. Items with `hasCustomInput: true`: additional `<TextField>` for custom name when checked.

**Stored as object_value (ALL items, found + not found):**
```json
{
  "items": [
    { "code": "weed_01", "found": true, "damage": 4, "control_difficulty": 3 },
    { "code": "weed_02", "found": false, "damage": null, "control_difficulty": null },
    { "code": "weed_03", "found": false, "damage": null, "control_difficulty": null },
    { "code": "weed_other_1", "found": true, "custom_name": "ชื่อวัชพืช", "damage": 3, "control_difficulty": 4 }
  ]
}
```

#### Step 3: Section C — Insect Assessment Matrix

Same pattern as B but with growth stage column.
1. Checkbox list of 9 insect items (INSECT_OPTIONS)
2. When checked, expand:
   - **C2** "ระยะที่เจอ" — 4 checkboxes (multi-select from GROWTH_STAGES)
   - **C3** "ระดับความเสียหาย" — radio 1-5
   - **C4** "ความยากง่ายในการควบคุม" — radio 1-5

**Stored as object_value (ALL items):**
```json
{
  "items": [
    { "code": "pest_01", "found": true, "stages": [1, 2], "damage": 5, "control_difficulty": 4 },
    { "code": "pest_02", "found": false, "stages": [], "damage": null, "control_difficulty": null },
    { "code": "pest_05", "found": true, "stages": [2, 3], "damage": 3, "control_difficulty": 3 }
  ]
}
```

#### Step 4: Section D — Disease Assessment Matrix

Identical structure to C. ALL 11 disease items stored (found + not found).

### Step 5: Section E — Pesticide Usage

Same specs as before — spray table + E6 cost breakdown + E7 select.

### Step 6: Review & Submit

Read-only summary with edit links per section. For new users, also show the signup data (name, address, crops) in the review under a "ข้อมูลผู้สัมภาษณ์" header.

---

## Data Submission — Supabase Calls

### Supabase Client Init

```typescript
import { createClient } from '@supabase/supabase-js';

const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  global: { headers: { Authorization: `Bearer ${props.accessToken}` } }
});
```

### Submit Flow (called on final submit button)

```typescript
async function handleSubmit() {
  isSubmitting.value = true;
  submitError.value = null;
  debugLog('Starting submission...');

  try {
    let farmerId = farmerUser.value?.id;
    let isNewUser = false;

    // ─── STEP 1: Create user if new ───
    if (!farmerId) {
      isNewUser = true;
      debugLog('Creating new user account...');

      // 1a. Insert user_accounts
      const { data: newUser, error: userErr } = await supabase
        .from('user_accounts')
        .insert({
          merchant_id: MERCHANT_ID,
          tel: normalizedTel.value,
          firstname: signupData.firstname,
          lastname: signupData.lastname,
          is_signup_form_complete: true,
        })
        .select('id')
        .single();

      if (userErr) throw new Error(`User creation failed: ${userErr.message}`);
      farmerId = newUser.id;
      debugLog(`User created: ${farmerId}`);

      // 1b. Insert user_address
      const { error: addrErr } = await supabase
        .from('user_address')
        .insert({
          user_id: farmerId,
          city: signupData.city,
          district: signupData.district,
          subdistrict: signupData.subdistrict,
        });

      if (addrErr) debugLog(`Address insert warning: ${addrErr.message}`);

      // 1c. Save USER_PROFILE custom fields (crop, area)
      const { data: profileSub, error: profSubErr } = await supabase
        .from('form_submissions')
        .insert({
          form_id: USER_PROFILE_FORM_ID,
          merchant_id: MERCHANT_ID,
          user_id: farmerId,
          status: 'completed',
          source: 'field_interview',
          submitted_at: new Date().toISOString(),
        })
        .select('id')
        .single();

      if (!profSubErr && profileSub) {
        // Insert crop and area responses
        // NOTE: You need the field IDs for crop and area from the USER_PROFILE form.
        // Query them once on component mount or hardcode if known.
        await supabase.from('form_responses').insert([
          { submission_id: profileSub.id, field_id: CROP_FIELD_ID, array_value: signupData.crop },
          { submission_id: profileSub.id, field_id: AREA_FIELD_ID, text_value: String(signupData.area) },
        ]);
      }
      debugLog('Signup data saved');
    }

    // ─── STEP 2: Create survey submission ───
    debugLog('Creating survey submission...');
    const { data: submission, error: subErr } = await supabase
      .from('form_submissions')
      .insert({
        form_id: FORM_ID,
        merchant_id: MERCHANT_ID,
        user_id: farmerId,
        status: 'completed',
        source: props.source || 'field_interview',
        submitted_at: new Date().toISOString(),
      })
      .select('id')
      .single();

    if (subErr) throw new Error(`Submission creation failed: ${subErr.message}`);
    debugLog(`Submission created: ${submission.id}`);

    // ─── STEP 3: Insert survey responses ───
    const responses = buildResponses(submission.id);
    debugLog(`Inserting ${responses.length} responses...`);

    const { error: respErr } = await supabase
      .from('form_responses')
      .insert(responses);

    if (respErr) throw new Error(`Response insert failed: ${respErr.message}`);

    // ─── SUCCESS ───
    debugLog('Submission complete!');
    showNotification('success', 'บันทึกแบบสอบถามเรียบร้อยแล้ว');
    props.onComplete?.({ submissionId: submission.id, farmerId, isNewUser });

  } catch (err) {
    const msg = err instanceof Error ? err.message : 'Unknown error';
    submitError.value = msg;
    debugLog(`ERROR: ${msg}`);
    showNotification('error', `เกิดข้อผิดพลาด: ${msg}`);
  } finally {
    isSubmitting.value = false;
  }
}
```

### Build Responses Helper

```typescript
function buildResponses(submissionId: string) {
  const responses = [];

  // Simple number/text fields → text_value
  const simpleMap = {
    a1_age: surveyData.a1_age,
    a2_rice_area_rai: surveyData.a2_rice_area_rai,
    a3_harvest_month: surveyData.a3_harvest_month,
    a4_farming_years: surveyData.a4_farming_years,
    a5_seasons_per_year: surveyData.a5_seasons_per_year,
    a7_yield_per_rai: surveyData.a7_yield_per_rai,
    a8_selling_price: surveyData.a8_selling_price,
    a9_breakeven_price: surveyData.a9_breakeven_price,
    e6_total_cost: surveyData.e6_total_cost,
    e6_1_herbicide_pct: surveyData.e6_1_herbicide_pct,
    e6_2_insecticide_pct: surveyData.e6_2_insecticide_pct,
    e6_3_fungicide_pct: surveyData.e6_3_fungicide_pct,
    e6_4_hormone_pct: surveyData.e6_4_hormone_pct,
    e7_investment_plan: surveyData.e7_investment_plan,
  };

  for (const [key, value] of Object.entries(simpleMap)) {
    if (value !== null && value !== undefined && value !== '') {
      responses.push({
        submission_id: submissionId,
        field_id: FIELDS[key].id,
        text_value: String(value),
      });
    }
  }

  // Complex fields → object_value
  const complexMap = {
    a6_rice_varieties: surveyData.a6_rice_varieties,
    b_weed_assessment: surveyData.b_weed_assessment,
    c_insect_assessment: surveyData.c_insect_assessment,
    d_disease_assessment: surveyData.d_disease_assessment,
    e1_e5_spray_applications: surveyData.e1_e5_spray_applications,
  };

  for (const [key, value] of Object.entries(complexMap)) {
    if (value !== null) {
      responses.push({
        submission_id: submissionId,
        field_id: FIELDS[key].id,
        object_value: value,
      });
    }
  }

  return responses;
}
```

---

## Notification System

### UI Component: `<NotificationBar>`

A fixed-position bar at the top of the component (inside the Polaris `<Frame>` if available, otherwise absolute positioned). Uses Polaris `<Banner>` inside a toast-like container.

```typescript
const notifications = ref<Array<{
  id: string;
  type: 'success' | 'error' | 'info' | 'warning';
  message: string;
  timestamp: number;
}>>([]);

function showNotification(type: 'success' | 'error' | 'info' | 'warning', message: string) {
  const id = Date.now().toString();
  notifications.value.push({ id, type, message, timestamp: Date.now() });
  // Auto-dismiss success/info after 5 seconds
  if (type === 'success' || type === 'info') {
    setTimeout(() => dismissNotification(id), 5000);
  }
  // Error/warning stay until dismissed manually
}

function dismissNotification(id: string) {
  notifications.value = notifications.value.filter(n => n.id !== id);
}
```

### Render

```html
<div class="notification-stack">
  <PolarissBanner
    v-for="n in notifications"
    :key="n.id"
    :status="n.type === 'error' ? 'critical' : n.type"
    @dismiss="dismissNotification(n.id)"
  >
    {{ n.message }}
  </PolarissBanner>
</div>
```

### When to Show Notifications

| Event | Type | Message |
|-------|------|---------|
| User found by tel | `success` | `พบข้อมูล: ${firstname} ${lastname}` |
| User not found | `info` | `ไม่พบข้อมูลในระบบ กรุณากรอกข้อมูลลงทะเบียน` |
| Validation error on Next | `warning` | `กรุณากรอกข้อมูลที่จำเป็นให้ครบ` |
| Submission success | `success` | `บันทึกแบบสอบถามเรียบร้อยแล้ว` |
| Submission error | `error` | `เกิดข้อผิดพลาด: ${error.message}` |
| Network error | `error` | `ไม่สามารถเชื่อมต่อเซิร์ฟเวอร์ได้ กรุณาลองใหม่` |
| New user created | `success` | `สร้างบัญชีเกษตรกรเรียบร้อย` |

---

## Debug Panel

### UI

A collapsible panel at the bottom of the component. Hidden by default, toggled by a small "🔧 Debug" button in the footer.

When expanded, shows a scrollable log of all actions with timestamps:

```typescript
const debugMessages = ref<Array<{ time: string; message: string }>>([]);
const showDebug = ref(false);

function debugLog(message: string) {
  const time = new Date().toLocaleTimeString('th-TH');
  debugMessages.value.push({ time, message });
  console.log(`[RiceSurvey] ${time}: ${message}`);
}
```

### What to Log

```
[14:32:01] Component mounted, interviewer: abc-123
[14:32:15] Tel lookup: +66812345678
[14:32:16] User found: def-456 (สมชาย ดีมาก)
[14:35:42] Starting submission...
[14:35:43] Creating survey submission...
[14:35:43] Submission created: ghi-789
[14:35:44] Inserting 14 responses...
[14:35:44] Submission complete!
```

OR for new user:

```
[14:32:01] Component mounted, interviewer: abc-123
[14:32:15] Tel lookup: +66899876543
[14:32:16] User not found, showing signup form
[14:40:22] Starting submission...
[14:40:22] Creating new user account...
[14:40:23] User created: xyz-111
[14:40:23] Address saved
[14:40:24] Signup data saved
[14:40:24] Creating survey submission...
[14:40:25] Submission created: sub-222
[14:40:25] Inserting 14 responses...
[14:40:26] Submission complete!
```

---

## Complete State Shape

```typescript
// ─── Component phase ───
const phase = ref<'tel_lookup' | 'signup' | 'survey'>('tel_lookup');
const currentSurveyStep = ref(1); // 1-6 within survey

// ─── Tel lookup ───
const telInput = ref('');
const normalizedTel = ref('');
const isLookingUp = ref(false);
const farmerUser = ref<{ id: string; firstname: string; lastname: string } | null>(null);
const isNewUser = ref(false);

// ─── Signup data (new users only) ───
const signupData = reactive({
  firstname: '',
  lastname: '',
  city: '',
  district: '',
  subdistrict: '',
  crop: [],
  area: null as number | null,
});

// ─── Survey data ───
const surveyData = reactive({
  a1_age: null as number | null,
  a2_rice_area_rai: null as number | null,
  a3_harvest_month: null as string | null,
  a4_farming_years: null as number | null,
  a5_seasons_per_year: null as number | null,
  a6_rice_varieties: [{ variety: '', harvest_days: null as number | null }],
  a7_yield_per_rai: null as number | null,
  a8_selling_price: null as number | null,
  a9_breakeven_price: null as number | null,

  // Initialize with ALL items from option lists, each found: false
  // On mount: WEED_OPTIONS.map(w => ({ code: w.code, found: false, damage: null, control_difficulty: null }))
  b_weed_assessment: { items: [] as AssessmentItem[] },
  // On mount: INSECT_OPTIONS.map(i => ({ code: i.code, found: false, stages: [], damage: null, control_difficulty: null }))
  c_insect_assessment: { items: [] as AssessmentItem[] },
  // On mount: DISEASE_OPTIONS.map(d => ({ code: d.code, found: false, stages: [], damage: null, control_difficulty: null }))
  d_disease_assessment: { items: [] as AssessmentItem[] },

  e1_e5_spray_applications: {
    stages: {
      small_stage:    { total_sprays: 0, applications: [] as SprayApp[] },
      tillering_stage:{ total_sprays: 0, applications: [] as SprayApp[] },
      booting_stage:  { total_sprays: 0, applications: [] as SprayApp[] },
      maturity_stage: { total_sprays: 0, applications: [] as SprayApp[] },
    }
  },
  e6_total_cost: null as number | null,
  e6_1_herbicide_pct: null as number | null,
  e6_2_insecticide_pct: null as number | null,
  e6_3_fungicide_pct: null as number | null,
  e6_4_hormone_pct: null as number | null,
  e7_investment_plan: null as string | null,
});

// ─── UI state ───
const isSubmitting = ref(false);
const submitError = ref<string | null>(null);
const notifications = ref<Notification[]>([]);
const debugMessages = ref<DebugMsg[]>([]);
const showDebug = ref(false);
```

---

## Reusable Sub-Components

### 1. `<AssessmentMatrix>`
Props: `title`, `items` (options list), `showStages` (bool), `modelValue` (v-model), `damageLabel`, `controlLabel`
Used in Steps 2, 3, 4. Only `showStages` and options list differ.

### 2. `<RatingScale>`
Props: `modelValue`, `min=1`, `max=5`, `lowLabel`, `highLabel`
Renders 5 radio buttons in a row.

### 3. `<SprayStagePanel>`
Props: `stage` (GrowthStage), `modelValue` (v-model for spray data)
Renders E1 counter + dynamic E2-E5 rows.

### 4. `<VarietyRepeater>`
Props: `modelValue` (array of {variety, harvest_days})
Add/remove rows, max 5.

### 5. `<NotificationBar>`
Renders stacked Polaris Banners for notifications.

### 6. `<DebugPanel>`
Collapsible log viewer at bottom.

---

## Validation Rules

**Phase 1 (Tel):** Phone must be 9-10 digits (after stripping formatting).

**Phase 2 (Signup):** firstname, lastname, city, district, subdistrict, crop (≥1 selected), area (>0) — all required.

**Step 1 (A):** A1 (15-99), A2 (≥1), A3 (selected), A4 (≥1), A5 (1-4), A6 (≥1 row with both filled), A7 (≥0), A8 (≥0), A9 (≥0).

**Steps 2-4:** Not required. But if an item is checked, its ratings become required. If showStages, at least one stage must be selected for checked items.

**Step 5:** If total_sprays > 0, product (E2) is required per spray row. E6 percentages: warn if not summing to 100. E7 is required.

**Step 6:** Review only. Submit triggers the full flow.

---

## Polaris Usage Notes

- Use `<Page>` as outer wrapper with step title
- Use `<Card>` for each logical section
- Use `<FormLayout>` and `<FormLayout.Group>` for field arrangement
- Use `<ProgressBar>` or custom step indicator for survey progress
- Use `<Banner>` for notifications and inline validation
- Use `<Button primary>` for Next/Submit, `<Button plain>` for Back
- Use `<Spinner>` during API calls
- Use `<InlineStack>` and `<BlockStack>` for layout
- Mobile-first: tablet portrait (768px) is the primary target

---

## Reference Documents

- **Forms.md** (provided separately): describes form_templates, form_fields, form_submissions, form_responses schema, and the WeWeb form handler patterns
- **Signup_Login.md** (provided separately): describes bff-auth-complete, bff_save_user_profile, user_accounts schema, user_field_config, and the full auth flow

The form template `RICE_BIGGROWER_2026` and the `USER_PROFILE` form already exist in the Syngenta merchant's database. The component does NOT need to fetch template structure — everything is hardcoded above.
