# Samitivej Loyalty App — Mockup Design Brief

**Purpose:** Brief for graphic designer to create UI mockups for the Samitivej CRM Loyalty App (Well by Samitivej webview / LINE LIFF / Website).

**Platform:** Mobile-first (webview inside Well app & LINE). Design at 375×812 (iPhone viewport). All screens must also work as responsive web.

**Branding:** Use Samitivej brand colors and style. Reference: samitivejhospitals.com. Clean, medical-professional feel — not playful, not generic fintech.

**Language:** Thai primary. Show English toggle where relevant.

**Bottom Navigation (persistent on all pages):**
`Home` | `Wallet` | `My QR` | `Buy` | `Profile`

---

## 1. HOME

### 1A. General Home (Default — no persona override)

**Top Section — Member Card**
- Greeting: "สวัสดีค่ะ คุณสมศรี"
- Tier badge: **Gold** (with visual icon/color)
- Coin balance: **4,280 Coins**
- Member type label: "Engagement Member"
- Tier progress bar: Gold → Platinum (68% — "อีก 1,720 coins ภายใน 31 ธ.ค. 69")
- Tap card → goes to Tier Progress page

**Personalized Package Offer (1 card)**
- "แนะนำสำหรับคุณ" — e.g. "ตรวจสุขภาพสตรี อายุน้อยกว่า 40 ปี" ~~23,500~~ **14,500 ฿**
- Tap → Buy Package Detail

**Highlight Menu (icon row, 2 items prominent)**
- Wallet (coin icon + balance "4,280")
- Redeem Rewards (gift icon)

**Functional Menu (icon grid, 4 items)**
- Earn Coins (star icon)
- My Entitlements (clipboard icon)
- Buy Membership (crown icon — "Divine Elite")
- Articles (book icon)

**Package Carousel — "แพ็กเกจสุขภาพ"**
Horizontal scroll cards. Each card shows: image, package name, price (strikethrough + promo price), "ซื้อเลย" CTA.

Example cards (use real data):
1. "Basic Check-up ชาย/หญิง" — ~~7,500~~ **4,500 ฿**
2. "ตรวจสุขภาพ สตรี < 40 ปี" — ~~23,500~~ **14,500 ฿**
3. "ตรวจสุขภาพ บุรุษ < 50 ปี" — ~~39,000~~ **25,900 ฿**
4. "Comprehensive Longevity & Alzheimer" — ~~73,800~~ **48,500 ฿**

"ดูทั้งหมด →" link at end.

**Reward Carousel — "แลก Coins เป็นสิทธิ์"**
Horizontal scroll cards. Each card: image, reward name, coin cost, "แลกเลย" CTA.

Example cards:
1. "คูปองร้านอาหาร 100 ฿" — 200 Coins
2. "ส่วนลด Spa 20%" — 500 Coins
3. "Starbucks Gift Card 200 ฿" — 400 Coins
4. "ที่จอดรถฟรี 1 ครั้ง" — 100 Coins

"ดูทั้งหมด →" link at end.

---

### 1B. Home — Persona Variant (Corporate Partner e.g. CRC)

Same layout as General Home but with persona-specific overrides:

**Top Section — Member Card changes:**
- Type label: "Corporate Member — CRC Group"
- Sub-label: "Executive Level"
- Additional badge/ribbon: CRC logo or "Corporate" tag
- Tier badge still shows (can hold both: Gold tier + CRC Executive)

**Personalized Package Offer:**
- "สิทธิ์พิเศษ CRC Executive" — e.g. "Executive Health Checkup" at corporate-discounted price

**Additional Section — "สิทธิ์องค์กรของคุณ"**
- Standing benefit cards: "ส่วนลด OPD 25%", "Executive Lounge Access", "ส่วนลด Pharmacy 15%"
- These are NOT consumable — they're always-on benefits shown as info cards

**Rest of page:** Same carousels (packages, rewards) but may show Corporate-exclusive items marked with a "Corporate" badge.

---

## 2. BUY PACKAGE

### 2A. Package List Page

**Top:** Search bar + filter chips
- Category filter pills: `ทั้งหมด` | `ตรวจสุขภาพ` | `ทันตกรรม` | `กายภาพบำบัด` | `ผิวหนัง` | `ตา`
- Additional filters (sheet/modal): Gender (ชาย/หญิง), Age range, Price range, Branch (สุขุมวิท / ศรีนครินทร์)
- Sort: แนะนำ / ราคาต่ำ-สูง / ราคาสูง-ต่ำ / ใหม่ล่าสุด

**Package Cards (vertical list)**
Each card: thumbnail image, package name, price (strikethrough + promo), branch tag, "ซื้อเลย" button.

Use real packages:
1. "Basic Check-up ชาย/หญิง" — ~~7,500~~ **4,500 ฿** — สุขุมวิท
2. "ตรวจสุขภาพ สตรี อายุน้อยกว่า 30 ปี" — ~~12,000~~ **7,000 ฿** — สุขุมวิท
3. "ตรวจสุขภาพ สตรี < 40 ปี" — ~~23,500~~ **14,500 ฿** — สุขุมวิท
4. "ตรวจสุขภาพ บุรุษ < 50 ปี + คัดกรองมะเร็งปอด" — ~~48,000~~ **33,500 ฿** — สุขุมวิท
5. "Comprehensive Longevity & Alzheimer (สตรี > 60 ปี)" — ~~111,000~~ **70,000 ฿** — สุขุมวิท
6. "ตรวจสุขภาพก่อนมีบุตร สตรี" — ~~18,000~~ **14,000 ฿** — สุขุมวิท

**Design ref:** Look at samitivejhospitals.com/th/package and Shopee/Lazada health package listing pages for layout reference.

### 2B. Package Detail Page

**Hero:** Package image (medical/wellness photo)

**Title + Price:**
- "ตรวจสุขภาพสตรี อายุน้อยกว่า 40 ปี"
- ~~23,500 ฿~~ **14,500 ฿** (promo badge: "ประหยัด 38%")
- Branch: "สมิติเวช สุขุมวิท"
- Valid until: "31 ธ.ค. 2569"

**Included Services (expandable list):**
- ✓ ตรวจร่างกายทั่วไปโดยแพทย์
- ✓ ตรวจความสมบูรณ์ของเม็ดเลือด (CBC)
- ✓ ตรวจระดับน้ำตาล (FBS)
- ✓ ตรวจการทำงานของไต (BUN, Creatinine)
- ✓ ตรวจการทำงานของตับ (SGOT, SGPT)
- ✓ ตรวจไขมันในเลือด (Cholesterol, Triglyceride, HDL, LDL)
- ✓ X-Ray ปอด
- ✓ ตรวจปัสสาวะ
- ✓ ตรวจคัดกรองมะเร็งปากมดลูก (Pap Smear)
- ✓ อัลตราซาวด์ช่องท้อง

**Conditions/Notes:**
- สำหรับสตรีอายุ 30-39 ปี
- ใช้ได้ที่: สมิติเวช สุขุมวิท
- มีผลภายใน 365 วันหลังซื้อ

**Coin Discount Section:**
- "ใช้ Coins แทนส่วนลด" toggle
- "คุณมี 4,280 Coins (= 4,280 ฿ ส่วนลด)" — slider to choose amount
- Net price updates live: "ราคาสุทธิ: **10,220 ฿**"

**CTA:** "ซื้อแพ็กเกจ — 14,500 ฿" (or net price if coins applied)

### 2C. Checkout / Payment Page

- Order summary: Package name, qty 1, price
- Coin discount applied (if any): "-4,280 Coins (4,280 ฿)"
- Total to pay: **10,220 ฿**
- Payment method: Credit/Debit Card (Rocket gateway)
- Card input fields (standard)
- "ยืนยันการชำระเงิน" CTA

### 2D. Purchase Success

- Checkmark animation
- "ซื้อสำเร็จ!"
- "ตรวจสุขภาพสตรี อายุน้อยกว่า 40 ปี ถูกเพิ่มใน Wallet ของคุณแล้ว"
- **Primary CTA:** "ดูใน Wallet →" (goes to Wallet > Coupons & Entitlements)
- **Secondary:** "กลับหน้าหลัก"
- Show: +145 Coins earned from this purchase (earn rate feedback)

---

## 3. BUY MEMBERSHIP

### 3A. Membership Type List

**Page title:** "สมัครสมาชิก Premium"

Membership cards (vertical, full-width):

1. **Divine Elite 1 ปี** — 50,000 ฿/ปี
   - "ส่วนลด OPD สูงสุด 15% • คูปองร้านอาหาร 12 ใบ • Exclusive Lounge"
   - "ดูรายละเอียด →"

2. **Divine Elite 3 ปี** — 120,000 ฿ (ประหยัด 30,000 ฿)
   - "ส่วนลด OPD สูงสุด 20% • คูปองร้านอาหาร 36 ใบ • Parking ฟรี"
   - "ดูรายละเอียด →"

3. **Wellness Plus** — 25,000 ฿/ปี
   - "ส่วนลด Spa 30% • คูปองตรวจสุขภาพ 2 ครั้ง • Pharmacy 10%"
   - "ดูรายละเอียด →"

### 3B. Membership Landing Page (e.g. Divine Elite 1 Year)

**Hero banner:** Premium lifestyle image + "Divine Elite" branding

**Benefits breakdown — 3 sections:**

**คูปองบังคับ (Mandatory — you get these automatically):**
- 12× คูปองร้านอาหาร 100 ฿ (1 ต่อเดือน)
- 2× คูปองที่จอดรถฟรี
- 1× ตรวจสุขภาพประจำปี

**คูปองเลือก (Elective — pick 3 from these 8):**
- Spa Treatment 60 min
- ทำฟัน Scaling & Polishing
- ตรวจตาประจำปี
- นวดแผนไทย 90 min
- คูปองร้านอาหาร 500 ฿
- ตรวจผิวหนัง
- Physiotherapy 1 session
- Vitamin IV Drip 1 session

**ส่วนลดตลอดอายุสมาชิก (Standing Benefits — unlimited use):**
- ส่วนลด OPD 15% (ทุกครั้งที่มาใช้บริการ)
- ส่วนลด Pharmacy 10%
- ส่วนลด Dental 10%

**Price + CTA:**
- "50,000 ฿/ปี" — "สมัครเลย"
- Same checkout flow as Buy Package (2C → 2D)

---

## 4. WALLET

### 4A. Wallet Main Page

**Top Section:**
- Coin balance (large): **4,280 Coins**
- "= 4,280 ฿ ส่วนลด" (burn rate context)
- Quick actions: "เติม Coins" | "ประวัติ Coins"

**2 Main Tabs:**

#### Tab 1: "คูปอง & สิทธิ์" (Coupons & Entitlements)

Sub-tabs for category:
`ทั้งหมด` | `โรงพยาบาล` | `ร้านอาหาร` | `Wellness & Spa` | `พันธมิตร`

Filter chips: `ใช้ครั้งเดียว` | `หลายครั้ง` | `ยังไม่ใช้` | `ใช้แล้ว` | `หมดอายุ`

**Card list — example items:**

1. **ตรวจสุขภาพสตรี < 40 ปี** — hospital icon
   - Status: "พร้อมใช้"
   - Expiry: "หมดอายุ 31 ธ.ค. 2570"
   - Type badge: `ใช้ครั้งเดียว`

2. **กายภาพบำบัด 5 ครั้ง** — clipboard icon
   - **"เหลือ 3/5 ครั้ง"** (prominent, colored — this is critical to show on list)
   - Expiry: "หมดอายุ 15 มี.ค. 2570"
   - Type badge: `หลายครั้ง`
   - Progress bar: 2/5 used

3. **คูปองร้านอาหาร 100 ฿** — food icon
   - Status: "พร้อมใช้"
   - From: "Divine Elite — เดือน มี.ค."
   - Type badge: `ใช้ครั้งเดียว`

4. **Starbucks 200 ฿** — partner icon
   - Status: "พร้อมใช้"
   - Redeemed via: "แลกด้วย 400 Coins"
   - Type badge: `ใช้ครั้งเดียว`

5. **ที่จอดรถฟรี** — car icon
   - **"เหลือ 4/5 ครั้ง"**
   - Type badge: `หลายครั้ง`

#### Tab 2: "สิทธิ์ถาวร" (Standing Benefits)

Info-style cards (no "use" action — these are always-on):

1. **ส่วนลด OPD 15%** — "ใช้ได้ไม่จำกัด • ถึง 31 ธ.ค. 2570"
   - Source: "Divine Elite"
2. **ส่วนลด Pharmacy 10%** — "ใช้ได้ไม่จำกัด • ถึง 31 ธ.ค. 2570"
   - Source: "Divine Elite"
3. **ส่วนลด OPD 25%** — "ใช้ได้ไม่จำกัด • ถึง 30 มิ.ย. 2570"
   - Source: "Corporate — CRC Executive"
   - Note: Standing benefits auto-resolve precedence. If both 15% and 25% apply, the system shows 25% to hospital billing. But in Wallet we show ALL benefits the user holds, with a note: "ระบบเลือกส่วนลดสูงสุดอัตโนมัติ"

### 4B. Coupon / Entitlement Detail Page

**Design as a "slip" / voucher visual with QR code.**

**Example: กายภาพบำบัด 5 ครั้ง**

- Slip header: Samitivej logo + package name
- **Big QR Code** (center) — scannable by hospital staff
- Below QR: Coupon code "SVJ-PHYS-2026-A1B2C3"
- **Usage counter (prominent): "เหลือ 3/5 ครั้ง"**
- Progress dots: ●●○○○ (2 used, 3 remaining)
- Usage history:
  - ครั้งที่ 1: 15 ม.ค. 2570 — สุขุมวิท, แผนกกายภาพ
  - ครั้งที่ 2: 12 ก.พ. 2570 — สุขุมวิท, แผนกกายภาพ
- Expiry: "หมดอายุ 15 มี.ค. 2570"
- Conditions: "ใช้ได้ที่สมิติเวช สุขุมวิท และ ศรีนครินทร์ • นัดหมายล่วงหน้า 24 ชม."

**Example: Single-use coupon (ร้านอาหาร 100 ฿)**

- Slip header: Samitivej logo + restaurant icon
- **Big QR Code**
- Code: "SVJ-FOOD-MAR26-X9Y8Z7"
- Status: "พร้อมใช้"
- Value: "ส่วนลด 100 ฿"
- From: "Divine Elite — คูปองเดือน มี.ค."
- Valid at: "ร้านอาหารในโรงพยาบาลสมิติเวชทุกสาขา"
- Expiry: "31 มี.ค. 2570"
- **"ใช้คูปอง"** button (staff taps to mark used)

---

## 5. REDEEM REWARDS

### 5A. Reward Catalog

**Top:** "แลกสิทธิ์ด้วย Coins" — Balance shown: "4,280 Coins"

Category tabs: `ทั้งหมด` | `ร้านอาหาร` | `Lifestyle` | `สุขภาพ` | `พันธมิตร`

**Reward cards (grid 2-col):**
1. "คูปองร้านอาหาร 100 ฿" — **200 Coins** — 48 remaining
2. "Starbucks 200 ฿" — **400 Coins** — 120 remaining
3. "ส่วนลด Spa 20%" — **500 Coins** — 30 remaining
4. "ที่จอดรถฟรี 1 ครั้ง" — **100 Coins** — unlimited
5. "Amazon Gift Card 500 ฿" — **1,000 Coins** — 15 remaining
6. "ตรวจฟันฟรี 1 ครั้ง" — **800 Coins** — 25 remaining

Show dynamic pricing hint: If user is Platinum, show "Platinum Price: 350 Coins" vs regular "500 Coins" with strikethrough.

### 5B. Reward Detail + Confirm

- Reward image
- Name, description, conditions
- Points cost: **400 Coins** (show tier-specific price if applicable)
- Stock: "เหลือ 120 สิทธิ์"
- Expiry after redemption: "ใช้ภายใน 30 วัน"
- **"แลกเลย — 400 Coins"** CTA
- Confirmation modal: "ยืนยันแลก Starbucks 200 ฿ ด้วย 400 Coins?" → Confirm / Cancel
- Success: "แลกสำเร็จ! ดูใน Wallet →"

---

## 6. TIER

### 6A. Tier Benefit Comparison

**Page title:** "ระดับสมาชิก"

**Comparison table (horizontal scroll):**

| | Silver | Gold | Platinum |
|---|---|---|---|
| **Earn Rate** | 1 Coin/100฿ | 1.5 Coins/100฿ | 2 Coins/100฿ |
| **Burn Rate** | 1 Coin = 0.25฿ | 1 Coin = 0.50฿ | 1 Coin = 1.00฿ |
| **OPD ส่วนลด** | — | 5% | 10% |
| **Redeem Price** | ราคาปกติ | ลด 10% | ลด 25% |
| **ที่จอดรถฟรี** | — | 2 ครั้ง/เดือน | ไม่จำกัด |
| **Priority Booking** | — | — | ✓ |
| **Birthday Bonus** | 100 Coins | 300 Coins | 1,000 Coins |

Highlight user's current tier column (e.g. Gold highlighted).

### 6B. Tier Progress Page (click from Home card)

**Current tier card:** "Gold Member" with badge
**Progress to next tier:** 
- Visual progress bar: Gold ████████░░ Platinum
- "4,280 / 6,000 Coins ภายใน 31 ธ.ค. 2569"
- "อีก 1,720 Coins เพื่อเลื่อนเป็น Platinum"

**How to earn more (actionable tips):**
- "🏥 ใช้บริการตรวจสุขภาพ — ได้ 1.5 Coins ต่อ 100 ฿"
- "📖 อ่านบทความ — ได้ 5 Coins ต่อบทความ"
- "👥 ชวนเพื่อน — ได้ 200 Coins ต่อคน"
- "🎯 ทำ Mission — ได้สูงสุด 500 Coins"

**Maintenance requirement:**
- "รักษาระดับ Gold: สะสม 3,000 Coins ภายใน ม.ค. - ธ.ค. 2570"
- Progress: "ปัจจุบัน: 4,280 / 3,000 ✓ ผ่านเกณฑ์แล้ว"

**"เปรียบเทียบสิทธิ์ทุกระดับ →"** link to 6A

---

## 7. MISSIONS

### 7A. Mission List Page

**Page title:** "ภารกิจ" — "ทำภารกิจ สะสม Coins และของรางวัล"

**Filter tabs:** `ทั้งหมด` | `กำลังทำ` | `สำเร็จแล้ว`

**Mission cards (each shows: icon, name, reward, progress, type badge):**

---

**STANDARD MISSIONS (one-time goal):**

1. **🏥 เช็คอัพครั้งแรก**
   - "ตรวจสุขภาพประจำปี 1 ครั้ง"
   - Reward: **+200 Coins**
   - Progress: 0/1
   - Badge: `ครั้งเดียว`

2. **📋 ทำแบบสำรวจ**
   - "ตอบแบบสำรวจความพึงพอใจ"
   - Reward: **+50 Coins**
   - Progress: 0/1
   - Badge: `ครั้งเดียว`

3. **👥 ชวนเพื่อน 1 คน**
   - "เชิญเพื่อนสมัครสมาชิกสำเร็จ"
   - Reward: **+200 Coins**
   - Progress: 0/1
   - Badge: `ครั้งเดียว`

---

**CROSS-DEPARTMENT MISSIONS:**

4. **🏥 สำรวจ 3 แผนก**
   - "ใช้บริการ 3 แผนกที่แตกต่างกัน"
   - Example sub-conditions: ☐ ตรวจสุขภาพ ☐ ทันตกรรม ☐ ผิวหนัง ☐ ตา ☐ กายภาพบำบัด (any 3)
   - Reward: **+500 Coins + คูปองร้านอาหาร 200 ฿**
   - Progress: 1/3 (✓ ตรวจสุขภาพ)
   - Badge: `ข้ามแผนก`

---

**ACTIVITY-BASED MISSIONS:**

5. **📖 นักอ่านสุขภาพ**
   - "อ่านบทความสุขภาพ 5 บทความ"
   - Reward: **+100 Coins**
   - Progress: 2/5
   - Badge: `กิจกรรม`

6. **❤️ แชร์ความรู้**
   - "แชร์บทความบน Facebook หรือ LINE 3 ครั้ง"
   - Reward: **+150 Coins**
   - Progress: 1/3
   - Badge: `กิจกรรม`

7. **👥 ชวนเพื่อน 5 คน**
   - "เชิญเพื่อนสมัครสมาชิกสำเร็จ 5 คน"
   - Reward: **+1,000 Coins + Starbucks 500 ฿**
   - Progress: 2/5
   - Badge: `กิจกรรม`

---

**MILESTONE MISSIONS (multi-level — show all levels, current level highlighted):**

8. **🏥 แชมป์ตรวจสุขภาพ** `Milestone`
   - Level 1: ตรวจสุขภาพ 1 ครั้ง → **+200 Coins** ✓ สำเร็จ
   - Level 2: ตรวจสุขภาพ 3 ครั้ง → **+500 Coins** ◻ 1/3 (current)
   - Level 3: ตรวจสุขภาพ 5 ครั้ง → **+1,000 Coins + คูปอง Spa** ◻ 1/5
   - Level 4: ตรวจสุขภาพ 10 ครั้ง → **+3,000 Coins + ตรวจฟรี 1 ครั้ง** ◻ 1/10
   - Visual: Vertical stepper with checkmarks and progress

9. **💰 นักช้อปสุขภาพ** `Milestone`
   - Level 1: ซื้อแพ็กเกจ 1 ครั้ง → **+100 Coins** ✓ สำเร็จ
   - Level 2: ซื้อแพ็กเกจ 3 ครั้ง → **+300 Coins** ◻ 1/3 (current)
   - Level 3: ซื้อแพ็กเกจรวม 50,000 ฿ → **+1,000 Coins + Upgrade Tier** ◻ 15,000/50,000
   - Visual: Vertical stepper

### 7B. Mission Detail Page

**Example: "สำรวจ 3 แผนก"**

- Hero icon / illustration
- Title: "สำรวจ 3 แผนก"
- Description: "ใช้บริการที่แผนกต่างๆ ของสมิติเวช 3 แผนก เพื่อรับ Coins และคูปองพิเศษ"
- Reward: "+500 Coins + คูปองร้านอาหาร 200 ฿"
- Expiry: "ภายใน 31 ธ.ค. 2569"

**Progress checklist:**
- ✓ ตรวจสุขภาพ (15 ม.ค. 2569)
- ☐ ทันตกรรม
- ☐ ผิวหนัง / ตา / กายภาพ / อื่นๆ (any 2 more)

Progress bar: 1/3

**CTA:** None (progress is automatic from hospital visits). Show note: "ระบบจะอัปเดตอัตโนมัติเมื่อคุณใช้บริการ"

---

## 8. PARTNER LANDING PAGE

### Example: Marriott Bonvoy × Samitivej

**Full-page layout, banner-driven:**

**Hero Banner:** Marriott × Samitivej co-branded image
- "Marriott Bonvoy Exclusive Health Privileges"
- Sub: "สิทธิ์พิเศษสำหรับสมาชิก Marriott Bonvoy"

**User's Partner Status:**
- "คุณสมศรี — Marriott Bonvoy Gold"
- Badge/ribbon showing partner level

**Exclusive Packages (banner cards):**
1. Banner: "Executive Health Checkup" — ส่วนลด 20% สำหรับ Bonvoy Gold — **~~25,900~~ 20,720 ฿**
2. Banner: "Wellness Retreat Package" — Bonvoy Gold exclusive — **18,500 ฿**
3. Banner: "Dental Premium" — ส่วนลด 15% — **~~8,500~~ 7,225 ฿**

**Standing Benefits (always-on for this partner level):**
- ส่วนลด OPD 10% (Bonvoy Gold)
- Priority Appointment Booking
- Complimentary Parking 2 ครั้ง/เดือน

**Note at bottom:** "สิทธิ์กำหนดโดยสมิติเวช อาจเปลี่ยนแปลงโดยไม่ต้องแจ้งล่วงหน้า"

**Design note:** This page should feel like a branded microsite — distinct from the main app pages. Each partner gets different banner imagery and color accent. Content is set by Samitivej marketing, not the partner.

---

## 9. ARTICLES

### 9A. Article Card (on Home)

- Thumbnail image + title: "10 สัญญาณเตือน ที่ควรตรวจหัวใจ"
- "อ่านแล้วได้ 5 Coins"
- Tap → Article page

### 9B. Article Read Page

**Use real example: "10 สัญญาณเตือน ที่ควรตรวจหัวใจ"**

- Hero image: Heart health illustration
- Title, author (Dr. Somchai, Cardiologist), date
- Article body text (use placeholder but realistic Thai medical content, ~3 paragraphs)
- Reading progress bar at top

**Coin earned toast:** After scrolling past 75%: "🎉 +5 Coins สำหรับการอ่านบทความ!"

**Engagement actions (below article):**
- ❤️ Like (tap → "+2 Coins")
- 📤 Share:
  - "แชร์บน Facebook → +10 Coins"
  - "แชร์บน LINE → +10 Coins"
- Show total earned this article: "+17 Coins"

**Related articles carousel at bottom**

---

## 10. SURVEY

**Page title:** "แบบสำรวจ"

- Survey card: "แบบสำรวจความพึงพอใจหลังตรวจสุขภาพ"
- Reward: "+50 Coins"
- Est. time: "2 นาที"
- Tap → Survey form

**Survey form (simple example, 3 questions):**
1. "คุณพึงพอใจกับบริการตรวจสุขภาพครั้งล่าสุดมากน้อยแค่ไหน?" — 5 star rating
2. "คุณจะแนะนำสมิติเวชให้เพื่อนหรือครอบครัวหรือไม่?" — NPS 0-10 scale
3. "มีข้อเสนอแนะเพิ่มเติมไหม?" — Open text

**Submit → "+50 Coins ได้รับแล้ว!" toast**

---

## 11. HISTORY

**Page title:** "ประวัติ"

**Tabs:** `ทั้งหมด` | `Coins` | `คูปอง` | `แพ็กเกจ`

**Unified timeline (most recent first):**

- **16 มี.ค. 69** — ได้รับ +145 Coins (ซื้อแพ็กเกจตรวจสุขภาพ 14,500 ฿)
- **16 มี.ค. 69** — ซื้อแพ็กเกจ "ตรวจสุขภาพสตรี < 40 ปี" — 14,500 ฿
- **15 มี.ค. 69** — ใช้คูปองร้านอาหาร 100 ฿ — สมิติเวช สุขุมวิท
- **12 มี.ค. 69** — แลก Starbucks 200 ฿ — ใช้ 400 Coins
- **10 มี.ค. 69** — ได้รับ +5 Coins (อ่านบทความ "10 สัญญาณเตือนหัวใจ")
- **10 มี.ค. 69** — ได้รับ +10 Coins (แชร์บทความบน LINE)
- **1 มี.ค. 69** — ได้รับ คูปองร้านอาหาร 100 ฿ (Divine Elite — เดือน มี.ค.)
- **28 ก.พ. 69** — กายภาพบำบัด ครั้งที่ 2/5 — สุขุมวิท

Each entry: icon (coin/coupon/package), description, amount/value, date

---

## 12. INVITE FRIENDS

**Page title:** "ชวนเพื่อน"

**Your referral code (prominent):**
- Code: **SOMSRI2026** (large, copyable)
- "แชร์โค้ดนี้ให้เพื่อน เมื่อเพื่อนสมัครสำเร็จ คุณได้รับ 200 Coins!"

**Share buttons:**
- แชร์ทาง LINE
- แชร์ทาง Facebook
- คัดลอกลิงก์

**Referral stats:**
- "ชวนสำเร็จ: 2 คน"
- "Coins ที่ได้รับ: 400 Coins"

**Referral history:**
- คุณมานี — สมัครเมื่อ 1 ก.พ. 69 — +200 Coins ✓
- คุณสมชาย — สมัครเมื่อ 15 ม.ค. 69 — +200 Coins ✓

**Mission tie-in:**
- "🎯 ชวนเพื่อนอีก 3 คน เพื่อรับ 1,000 Coins + Starbucks 500 ฿" (links to Mission #7)

---

## 13. MY QR (Bottom Nav)

**Quick-access QR screen** — opens directly from bottom nav.

- Large QR code (user's member QR)
- Member name: "คุณสมศรี"
- Member ID: "SVJ-2026-001234"
- Tier badge: Gold
- Brightness auto-max on this screen (note for dev)
- Purpose: Staff scans at reception for identification / benefit lookup

---

## Screen Count Summary

| # | Screen | Priority |
|---|--------|----------|
| 1 | Home — General | P1 |
| 2 | Home — Corporate Persona | P1 |
| 3 | Buy Package — List | P1 |
| 4 | Buy Package — Detail | P1 |
| 5 | Buy Package — Checkout | P1 |
| 6 | Buy Package — Success | P1 |
| 7 | Buy Membership — Type List | P1 |
| 8 | Buy Membership — Landing | P1 |
| 9 | Wallet — Coupons & Entitlements | P1 |
| 10 | Wallet — Standing Benefits | P1 |
| 11 | Wallet — Coupon Detail (slip + QR) | P1 |
| 12 | Wallet — Multi-use Detail (3/5 remaining) | P1 |
| 13 | Redeem Rewards — Catalog | P1 |
| 14 | Redeem Rewards — Detail + Confirm | P1 |
| 15 | Tier — Benefit Comparison | P1 |
| 16 | Tier — Progress Page | P1 |
| 17 | Missions — List | P1 |
| 18 | Missions — Detail (cross-dept example) | P1 |
| 19 | Partner Landing — Marriott | P2 |
| 20 | Article — Read + Share | P1 |
| 21 | Survey | P2 |
| 22 | History | P1 |
| 23 | Invite Friends | P1 |
| 24 | My QR | P1 |

**Total: 24 screens** (20 P1 + 4 P2)
