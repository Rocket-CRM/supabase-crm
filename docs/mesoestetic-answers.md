# mesoestetic — ตอบคำถาม Technical

**จัดทำโดย:** Rocket CRM Team
**วันที่:** 1 เมษายน 2026

> หมายเหตุ: เดิมเราเสนอ BigCommerce เป็น commerce platform แต่ปัจจุบัน Rocket CRM รองรับ Shopify แล้ว และแนะนำ Shopify มากกว่าเนื่องจาก advanced features ที่ครบกว่า และ plugin ecosystem ที่ใหญ่กว่ามาก (10,000+ apps vs ~1,000 apps บน BigCommerce) คำตอบด้านล่างจึงอิงกับ Shopify เป็นหลัก

---

## 1. Chatbot - LINE CRM (Webhook URL)

**คำถาม:** ตอนนี้ทางบริษัท ซื้อตัว Chatbot อยู่ ผมเห็นว่า Webhook URL มันมีอยู่อันเดียว/1 account มันต้องเลือกหรือครับหรือว่ามีทางแก้ไหม หรือว่ามี Solution ไหม เช่น API

**ได้ครับ มีทางแก้** — ใช้ Webhook Proxy Router รับ webhook จาก LINE แล้ว fan-out ไปทั้ง Chatbot และ Rocket CRM พร้อมกัน

จริงที่ LINE Official Account จำกัด Webhook URL ได้แค่ 1 อัน นี่เป็นข้อจำกัดของ LINE Platform เอง ไม่เกี่ยวกับ commerce platform

วิธีที่แนะนำคือใช้ **Hookdeck Webhook Proxy** — ตั้ง Hookdeck เป็น Webhook URL ของ LINE OA แล้ว Hookdeck จะ route events ไปทั้ง Chatbot endpoint และ Rocket CRM endpoint พร้อมกัน

**ไม่มีค่าใช้จ่ายเพิ่มเติม** — Rocket CRM ใช้ Hookdeck เป็น infrastructure อยู่แล้วสำหรับ marketplace webhook routing ไม่ต้องจ่ายเพิ่มหรือตั้งระบบใหม่

| วิธี | ค่าใช้จ่ายเพิ่ม | ความซับซ้อน | แนะนำ |
|------|----------------|------------|-------|
| **Hookdeck Webhook Proxy** | ไม่มี — ใช้ infrastructure เดิม | ต่ำ | แนะนำ |
| Chatbot vendor forward events ออก | ขึ้นกับ vendor | ปานกลาง | ถ้า vendor รองรับ |
| LINE API Polling | อาจมี | สูง, ไม่ real-time | ไม่แนะนำ |

---

## 2. Owner ของ Commerce Platform

**คำถาม:** อันนี้คือระบบของ Big Commerce ที่เชื่อมโยงกับตัว Rocket ใช่ไหมครับ เราสามารถที่จะปรับแต่งหรือเป็น Owner Account ได้ขนาดไหนครับ เช่น ถ้าเกิดว่าเราต้องการที่จะลง Plugin เพิ่มสามารถที่จะทำได้ไหม

**ได้ครับ เป็น Owner เต็ม 100% ลง Plugin เพิ่มได้ไม่จำกัด**

mesoestetic จะเป็นเจ้าของ Shopify account เต็มที่ ควบคุมทุกอย่างเอง — themes, apps, payment, domain, staff accounts

| ด้าน | Shopify (แนะนำ) | BigCommerce (เดิม) |
|------|---------|-------------------|
| Account ownership | เป็นเจ้าของ 100%, เชิญ staff ได้หลาย role | เป็นเจ้าของได้เหมือนกัน แต่ ecosystem เล็กกว่า |
| Plugin/App install | 10,000+ apps ติดตั้งเองได้ทันที | ~1,000 apps ตัวเลือกน้อยกว่า |
| Theme customization | Drag & drop editor + Liquid template ถ้าต้องการ custom | Stencil theme — ยากกว่า, community เล็กกว่า |
| Payment gateways (TH) | Shopify Payments + 2C2P, Omise, SCB ผ่าน app | ต้อง custom integration มากกว่า |
| Rocket CRM integration | รองรับเต็ม — Shopify webhooks, embed loyalty component ใน theme | รองรับเช่นกัน แต่ Shopify ecosystem แข็งแรงกว่า |

---

## 3. Tracking Parameter Pass-Through

### 3.1 URL Parameter (UTM / Click ID)

**คำถาม:** เมื่อ User คลิก Ad แล้ว Redirect ผ่าน LINE Permission Page ก่อนมาถึง Landing Page — ระบบของคุณรองรับการ pass-through parameter ต่อไปนี้ได้ไหมครับ: UTM parameters (utm_source, utm_medium, utm_campaign, utm_content, utm_term), Facebook Click ID (fbclid), TikTok Click ID (ttclid), LINE Click ID (ถ้ามี)

**ได้ทุกตัว** — แยกเป็น 2 ส่วน:

- **Shopify (Landing Page):** รับ UTM, fbclid, ttclid จาก URL ได้อัตโนมัติ ไม่ต้องตั้งค่าอะไร
- **LINE Permission Page → Shopify:** LINE Login redirect จะ forward query parameters ต่อไปถ้าตั้ง redirect URI ถูกต้อง ระบบ auth ของ Rocket CRM เก็บ original query params ใน OAuth state parameter แล้ว append กลับหลัง redirect

| Parameter | Shopify รับอัตโนมัติ | LINE Redirect Pass-Through |
|-----------|---------------------|---------------------------|
| `utm_source`, `utm_medium`, `utm_campaign`, `utm_content`, `utm_term` | ใช่ | ใช่ — config ใน redirect flow |
| `fbclid` | ใช่ | ใช่ |
| `ttclid` | ใช่ | ใช่ |
| LINE Click ID | N/A — LINE Ads ไม่มี click ID แบบ fbclid, ใช้ UTM tracking แทน | N/A |

**คำถาม:** ถ้ารองรับ ทำงานอัตโนมัติ หรือต้องตั้งค่าเพิ่มเติม?

- **ฝั่ง Shopify:** อัตโนมัติเต็ม ไม่ต้องตั้งค่า
- **ฝั่ง LINE redirect:** ต้อง config OAuth state parameter carry-forward ในระบบ auth ของ Rocket CRM (dev effort ต่ำ, เป็น standard pattern)

---

### 3.2 Cookie / Session

**คำถาม:** หลังจาก Redirect ข้าม Domain (จาก LINE มายัง Landing Page) Cookie ที่เกี่ยวกับ Tracking ยังคงอยู่ไหม?

**ไม่** — redirect จาก LINE domain (access.line.me) มา Shopify domain เป็น cross-domain, first-party cookies จาก ad platform จะไม่ติดมา เป็นข้อจำกัดของ browser (ITP/ETP) ไม่เกี่ยวกับ platform ใด

**คำถาม:** ระบบสร้าง _fbc (Facebook) หรือ _ttp (TikTok) Cookie ใหม่จาก Click ID ที่ติดมาใน URL ได้ไหม?

**ได้ อัตโนมัติ** — Meta Pixel และ TikTok Pixel บน Shopify สร้าง `_fbc` จาก `fbclid` และ `_ttp` จาก `ttclid` ที่ติดมาใน URL ให้เอง ตราบใดที่ click ID ติดมาถึง URL เป็น standard pixel behavior ไม่ต้อง dev อะไรเพิ่ม

---

### 3.3 Server-Side / CAPI Integration

**คำถาม:** Platform ของคุณรองรับการส่ง Event ผ่าน Conversions API (Meta CAPI) และ TikTok Events API ไหม?

**ได้ทั้งคู่ Built-in บน Shopify** ไม่ต้อง dev:

- **Meta CAPI:** Facebook & Instagram app ของ Shopify ส่ง server-side events (Purchase, AddToCart, ViewContent) ผ่าน CAPI อัตโนมัติ ตั้งค่าผ่าน Shopify admin กด connect
- **TikTok Events API:** TikTok app for Shopify ส่ง server-side events อัตโนมัติ ตั้งค่าผ่าน Shopify admin เหมือนกัน

**คำถาม:** ถ้า fbclid หรือ ttclid หายระหว่าง Redirect — มี Fallback mechanism อะไรที่ใช้แทนได้บ้าง (เช่น external_id, phone, email hashing)?

**มีหลายชั้น** — Shopify CAPI ส่ง fallback data อัตโนมัติ:

| Fallback | วิธีทำงาน | ต้อง dev ไหม |
|----------|----------|-------------|
| `external_id` (hashed customer ID) | Shopify ส่งอัตโนมัติเมื่อ customer logged in | ไม่ |
| `em` (hashed email) | Shopify hash + ส่งอัตโนมัติ | ไม่ |
| `ph` (hashed phone) | Shopify hash + ส่งอัตโนมัติ | ไม่ |
| Advanced Matching | Meta/TikTok ใช้ data เหล่านี้จับคู่ user กลับแม้ click ID หาย | ไม่ |

---

### 3.4 LINE-Specific

**คำถาม:** เมื่อ User ผ่าน LINE Permission Page แล้ว — ระบบเก็บ LINE UID ไว้ไหม?

**ใช่ เก็บ** — Rocket CRM เก็บ LINE UID เป็น core identity field ระบบ auth-line edge function แลก LINE auth code เป็น line_user_id แล้วบันทึกใน user profile อัตโนมัติ

**คำถาม:** LINE UID สามารถ map กับ Tracking Event ที่ส่งไปยัง Ad Platform ได้ไหม?

**ได้บางส่วน** — Rocket CRM push `line_uid` ลง DataLayer ได้ เพื่อให้ GTM ส่งต่อไป ad platform เป็น `external_id` สำหรับ matching แต่ Meta/TikTok ไม่รู้จัก LINE UID โดยตรง ใช้ได้แค่เป็น external_id ช่วย cross-device matching email + phone hashed ยังเป็น primary matching key ที่ effective กว่า

---

## 4. Requirements Document — GTM & DataLayer

### 4.1 GTM Container

**รายการ:** ติดตั้ง GTM Container บน Rocket CRM ทุกหน้า — เราจะให้ GTM Container ID

**ได้** — Shopify รองรับ GTM container ผ่าน theme settings หรือ Google & YouTube channel app ได้ทันที สำหรับ loyalty pages ที่ embed อยู่ใน Shopify theme ผ่าน Rocket CRM component GTM ของ Shopify ครอบอยู่แล้ว

---

### 4.2 E-Commerce DataLayer Events

**รายการ:** Push DataLayer Event ทุก Event ตาม Spec (view_item, add_to_cart, view_cart, begin_checkout, add_payment_info, purchase, refund, search)

**ได้ทุก event อัตโนมัติบน Shopify** — Shopify ใช้ Customer Events (Web Pixels) push GA4 ecommerce events ทั้งหมดโดยไม่ต้อง custom DataLayer push

| Event | Shopify Built-in | Dev Effort |
|-------|-----------------|------------|
| `view_item` | ใช่ | ไม่มี |
| `add_to_cart` | ใช่ | ไม่มี |
| `view_cart` | ใช่ | ไม่มี |
| `begin_checkout` | ใช่ | ไม่มี |
| `add_payment_info` | ใช่ | ไม่มี |
| `purchase` | ใช่ (thank you page) | ไม่มี |
| `refund` | ใช่ | ไม่มี |
| `search` | ใช่ | ไม่มี |

---

### 4.3 Loyalty & Engagement DataLayer Events

**รายการ:** points_earned, points_redeemed, view_promotion, sign_up, login

**ได้บางส่วน** — loyalty events ต้อง implement เพิ่มในฝั่ง Rocket CRM:

| Event | ใครทำ | สถานะ |
|-------|-------|-------|
| `sign_up` | Rocket CRM | ต้อง develop — เพิ่ม DataLayer push ใน loyalty signup component |
| `login` | Rocket CRM | ต้อง develop — เพิ่ม DataLayer push ใน login flow |
| `points_earned` | Rocket CRM | ต้อง develop — push event เมื่อ currency award สำเร็จ |
| `points_redeemed` | Rocket CRM | ต้อง develop — push event เมื่อ redemption สำเร็จ |
| `view_promotion` | Shopify (store banners) + Rocket CRM (loyalty promotions) | Shopify built-in สำหรับ store promos / CRM promos ต้อง develop |

---

### 4.4 URL Parameter Pass-Through ผ่าน LINE Permission Page

**รายการ:** fbclid, ttclid, UTM ต้องติดมาถึง Rocket Page — Pass-Through URL Parameter ผ่าน LINE Permission Page

**ได้** — ตอบไว้ใน Section 3.1 แล้ว ต้อง config OAuth state parameter carry-forward (dev effort ต่ำ)

---

### 4.5 LINE UID หลัง Permission Page

**รายการ:** เก็บ LINE UID หลัง Permission Page และส่งใน DataLayer — ใช้สำหรับ CRM Mapping ฝั่งเรา

**ได้** — Rocket CRM เก็บ LINE UID อัตโนมัติอยู่แล้ว ส่วน DataLayer push ต้อง develop เพิ่มเล็กน้อย (dev effort ต่ำ)

---

### 4.6 User Data Hashed ใน DataLayer

**รายการ:** Push User Data (email, phone) แบบ Hashed ใน DataLayer ตอน Register/Login — Hash ด้วย SHA-256 ก่อน Push

**ได้** — ข้อมูลทั้งหมดมีอยู่ในระบบ Rocket CRM แล้ว ต้อง develop แค่ส่วน hashing + DataLayer push:

| Field | มีข้อมูลใน CRM แล้ว | ต้อง develop |
|-------|---------------------|-------------|
| `user_id` | ใช่ | Push ลง DataLayer ตอน login |
| `line_uid` | ใช่ | Push ลง DataLayer หลัง LINE permission |
| `phone_sha256` | ใช่ (normalize +66 format อยู่แล้ว) | Hash SHA-256 server-side แล้ว push |
| `email_sha256` | ใช่ | Hash SHA-256 lowercase แล้ว push |
| `fn_sha256`, `ln_sha256` | ใช่ | Hash SHA-256 lowercase แล้ว push |

---

## สรุป

| หมวด | ทำได้ไหม | Shopify Built-in | Rocket CRM Dev | ค่าใช้จ่ายเพิ่ม |
|------|---------|-----------------|----------------|----------------|
| LINE Webhook Proxy (Chatbot + CRM) | ได้ | — | Config Hookdeck routing | ไม่มี — ใช้ infra เดิม |
| Account Ownership + Plugins | ได้ 100% | Full control, 10,000+ apps | — | ไม่มี |
| E-Commerce Events (GA4 DataLayer) | ได้ทั้งหมด | Built-in ทุก event | ไม่ต้องทำ | ไม่มี |
| Meta CAPI | ได้ | Built-in | ไม่ต้องทำ | ไม่มี |
| TikTok Events API | ได้ | Built-in | ไม่ต้องทำ | ไม่มี |
| GTM Installation | ได้ | Theme settings | ไม่ต้องทำ | ไม่มี |
| UTM/Click ID on Shopify pages | ได้ อัตโนมัติ | Built-in | ไม่ต้องทำ | ไม่มี |
| UTM/Click ID Pass-Through (LINE → Shopify) | ได้ | — | Dev effort ต่ำ | ไม่มี |
| Cookie Recreation (_fbc, _ttp) | ได้ อัตโนมัติ | Pixel behavior | ไม่ต้องทำ | ไม่มี |
| CAPI Fallback (hashed email/phone) | ได้ อัตโนมัติ | Built-in | ไม่ต้องทำ | ไม่มี |
| LINE UID Capture | ได้ | — | มีอยู่แล้ว | ไม่มี |
| LINE UID → Ad Platform Mapping | ได้บางส่วน | — | Push DataLayer (dev ต่ำ) | ไม่มี |
| Loyalty DataLayer Events | ได้ | — | ต้อง develop (ปานกลาง) | ไม่มี |
| Hashed User Data Push | ได้ | — | ต้อง develop (ปานกลาง) | ไม่มี |

ส่วนใหญ่ของ requirement ที่ mesoestetic ถามมาเป็นงาน commerce tracking ซึ่ง Shopify จัดการได้หมดแบบไม่ต้อง dev (GA4, CAPI, GTM, pixel cookies, fallback matching) ส่วนที่ต้อง develop เพิ่มมีแค่ loyalty-specific events กับ LINE parameter forwarding ไม่มีค่าใช้จ่ายเพิ่มเติมทั้งหมดเพราะใช้ infrastructure เดิมของ Rocket CRM
