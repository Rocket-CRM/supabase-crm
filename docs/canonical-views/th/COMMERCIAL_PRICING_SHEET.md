# Commercial Pricing Sheet

มุมมอง billable unit ของ Rocket CRM เขียนจาก Product Feature Catalog — ไม่ใช่รายการฟีเจอร์ครบทุกตัว

**Contract:** `workflows/canonical-views/REFERENCE.md`  
**Voice:** `Writing Principles/CANONICAL_VIEW_COPY_PRINCIPLES.md`  
**Language:** TH  
**Prices:** ว่าง (`—`) จนกว่า sales run จะใส่ราคาจาก `list-prices.json` ตาม scale สมาชิก  
**Table grammar:** Feature · Unit · Price (Merz / Rocket Deck)  
**Sections** = modules. **Rows** = การจัดกลุ่มแผน (Core / Advanced) และ/หรือโมเดลคิดเงิน

ใช้คู่กับ [Features Summary](./FEATURES_SUMMARY.md) เมื่อผู้ซื้อต้องการรายละเอียด coverage

---

## Loyalty

### Loyalty Core (`loyalty_core`)

| Feature | Unit | Price |
| --- | --- | --- |
| Loyalty Core | ต่อเดือน | — |

- **สมัครสมาชิก** ผ่าน LINE หรือ OTP เบอร์มือถือ พร้อมออกแบบฟอร์มสมัครเองได้
- **คะแนน** ยอดคงเหลือ วันหมดอายุ อัตราสะสมพื้นฐาน และปรับอัตราแยกตาม Tier ได้
- **ช่องทางสะสมคะแนน** ซิงค์ยอดซื้อ marketplace สแกน QR/โค้ด อัปโหลดใบเสร็จ และปรับคะแนนด้วยมือ
- **ของรางวัล** แคตตาล็อกและการแลก กำหนดสิทธิ์ว่าใครแลกได้ และแจกโค้ดโปรโมชันตอนแลก
- **Burn** ใช้คะแนนแทนส่วนลดตอนชำระเงิน กำหนดเองได้ว่ากี่คะแนนเท่ากับส่วนลดเท่าไร
- **Member tiers** ตั้งเงื่อนไขการเลื่อนขั้นและการรักษาระดับได้เอง
- **Persona และแท็ก** ใช้จัดกลุ่มเป้าหมายและกำหนดสิทธิ์
- **Lifecycle automations** ให้รางวัลอัตโนมัติตามวงจรสมาชิก — วันเกิด วันสมัคร วันครบรอบ และตอนเปลี่ยน Tier
- **Member app UI CMS** แก้หน้าจอที่สมาชิกเห็นได้เอง (หน้าแรก แบนเนอร์ คะแนน เมนู ของรางวัลแนะนำ)
- **Admin portal** ตั้งค่า loyalty จากแอดมิน — รหัสของรางวัล อัตราได้คะแนนตาม Tier การตั้งค่า Space ความยินยอม PDPA ภาษา และนำเข้าข้อมูลลูกค้า
- **Front Line** พนักงานหน้าร้านค้นสมาชิกแล้วช่วยได้ — ปรับคะแนน ส่งของรางวัล หรือกดใช้สิทธิ์แทนลูกค้า
- **รายงาน** กว่า 30 ฉบับในแอดมินมาตรฐาน ครอบคลุม Members, Member 360, การแลกของรางวัล, ธุรกรรม, Campaign และอื่น ๆ

### Loyalty Advanced (เพิ่มจาก Core) (`loyalty_advanced`)

| Feature | Unit | Price |
| --- | --- | --- |
| Loyalty Advanced (เพิ่มจาก Core) | ต่อเดือน | — |

- **อัตราสะสมคะแนนขั้นสูง** ตั้งเรทแยกตามช่องทาง กลุ่มร้าน หรือหมวดสินค้า และใส่ตัวคูณได้ เช่น คะแนน 2 เท่าในหมวดสกินแคร์ หรือเฉพาะสมาชิกบางประเภท
- **ของรางวัลขั้นสูง** Flash rewards เปิดให้แลกเฉพาะช่วงสั้น ๆ และตั้งโควตาร่วมกันหลายรางวัลได้ละเอียด
- **Tier ขั้นสูง** กำหนดรอบประเมิน Tier และตั้งชุด Tier แยกตาม persona
- **Surveys** เก็บฟีดแบ็กและข้อมูลสมาชิกเพิ่มด้วยฟอร์มแบบสำรวจ
- **ประเภทสมาชิก** เช่น นักเรียน/นักศึกษา หรือลูกค้าองค์กร ใช้กำหนดกฎและอัตราสะสมคะแนน
- **Segment** แบ่งกลุ่มสมาชิกด้วยเงื่อนไขที่ตั้งเองหรือ RFM แล้วส่ง LINE หรือ SMS ถึงกลุ่มนั้นได้เลย

### Campaigns (`loyalty_campaigns`)

| Feature | Unit | Price |
| --- | --- | --- |
| Campaigns | ต่อหน่วยแคมเปญ / เดือน | — |

- **Missions** ให้สมาชิกเก็บภารกิจ จะทำข้อไหนก่อนก็ได้ หรือไล่ทีละขั้นแบบ milestone
- **Referral** ให้สมาชิกชวนเพื่อนด้วยโค้ด แล้วได้รางวัลทั้งสองฝ่าย
- **Check-in** เช็คอินรายวันหรือรายสัปดาห์ สะสมวันต่อเนื่องเพื่อรับรางวัล
- **Spin wheel** ใช้คะแนนหมุนวงล้อลุ้นรางวัล
- **Lucky draw** ใช้คะแนนแลกสิทธิ์ลุ้นรางวัล แล้วจับผู้ชนะ

*หนึ่งหน่วยแคมเปญ = แคมเปญหนึ่งประเภทที่เปิดใช้งานในเดือนนั้น — Mission, Referral, Check-in, Spin wheel หรือ Lucky draw*

### Receipt AI / OCR auto-approve (`loyalty_receipt_auto_approve`)

| Feature | Unit | Price |
| --- | --- | --- |
| Receipt AI / OCR auto-approve | ต่อใบเสร็จ | — |

- **Receipt AI** อ่านใบเสร็จด้วย OCR แล้วอนุมัติคะแนนให้อัตโนมัติ

### Open API (`loyalty_open_api`)

| Feature | Unit | Price |
| --- | --- | --- |
| Open API | ต่อเดือน | — |

- **Open API** เชื่อม POS แอป หรือเว็บไซต์ของคุณเข้ากับ Rocket — ทั้งข้อมูลสมาชิก ยอดซื้อ คะแนน การแลก และ assets ระบบของคุณยังเป็นต้นทางข้อมูลเหมือนเดิม ส่วน Rocket ดูแลการเก็บและคิดคะแนนให้

### SMS (`loyalty_sms`)

| Feature | Unit | Price |
| --- | --- | --- |
| SMS | ต่อเดือน | — |

- **SMS** ส่วนที่เกินโควตา คิดข้อความละ 0.25 บาท

*ที่จำนวนสมาชิกระดับนี้ รวมข้อความฟรี {{sms_included}} ข้อความต่อเดือน*

---

## Shopify

### Shopify loyalty plugin (`loyalty_shopify`)

| Feature | Unit | Price |
| --- | --- | --- |
| Shopify loyalty plugin | ต่อเดือน | — |

*Loyalty widget บนร้าน Shopify ที่เชื่อมกับช่องทางอื่นนอก Shopify ได้ด้วย พร้อมเชื่อมกับ Shopify โดยตรง*

- **ออเดอร์ Shopify** สมาชิกได้รับคะแนนอัตโนมัติเมื่อออเดอร์ Shopify ชำระเงินแล้ว
- **Shopify widget** แสดงสถานะสมาชิกและคะแนนบนหน้าร้าน
- **Shopify burn** ใช้คะแนนเป็นส่วนลดในหน้า checkout ของ Shopify
- **จับคู่สมาชิก** จับคู่ลูกค้า Shopify กับสมาชิก Rocket ให้อัตโนมัติ ด้วยอีเมล เบอร์โทร หรือ Shopify id

---

## Marketing Automation

### Workflows (`marketing_automation_core`)

| Feature | Unit | Price |
| --- | --- | --- |
| Workflows | ต่อเดือน | — |

- **Workflows** เส้นทางอัตโนมัติหลายขั้น ส่งข้อความถึงสมาชิกและสั่งงานฝั่ง loyalty ได้ในชุดเดียว
- **LINE Flex** ออกแบบการ์ด LINE Flex แล้วเรียกใช้ในขั้นตอนส่งข้อความของ Workflow
- **Audiences** กลุ่มสมาชิกที่ใช้เป็นทริกเกอร์ให้ Workflow เริ่มทำงาน

*ราคานี้ครอบคลุม Workflow ที่เปิดใช้งานพร้อมกัน 10 ชุด*

### AI (`marketing_automation_advanced`)

| Feature | Unit | Price |
| --- | --- | --- |
| AI | ต่อเดือน | — |

- **AI decisioning** ตัดสินใจรายคนว่าจะ ACT, WAIT หรือ SKIP ตามเป้าหมายและข้อจำกัดที่คุณตั้งไว้
- **AI analysis** วิเคราะห์ผลที่ออกมา แล้วแนะนำว่าควรปรับอะไรใน Workflow และ agent

---

## Customer Service

### Customer Service Software (`customer_service_core`)

| Feature | Unit | Price |
| --- | --- | --- |
| Customer Service Software | ต่อผู้ใช้งาน / เดือน | — |

- **Omnichannel inbox** รวมทุกช่องทางที่เชื่อมไว้มาอยู่ในกล่องเดียว
- **แชทและสายโทร** ทำงานบนข้อมูลลูกค้าชุดเดียวกัน
- **Quick replies** ข้อความสำเร็จรูปและการค้นคลังความรู้ระหว่างคุยกับลูกค้า
- **Routing** จ่ายงานเข้าคิว ทีม หรือเจ้าหน้าที่ตามกฎที่ตั้งไว้
- **Knowledge base** คลังความรู้กลางสำหรับเจ้าหน้าที่และ AI
- **Service analytics** ปริมาณงาน เวลาตอบ และ CSAT

### AI Customer Service Agent (`customer_service_ai`)

| Feature | Unit | Price |
| --- | --- | --- |
| AI Customer Service Agent | ต่อเคสที่ปิดสำเร็จ | — |

- **AI service agent** ตอบลูกค้าแทนได้ ภายใต้โทนการสื่อสารและกฎการส่งต่อที่คุณกำหนด
- **AOPs** ขั้นตอนการทำงานที่ AI ต้องทำตาม รวมถึงการดำเนินการให้ลูกค้าได้จากในบทสนทนา
- **Live assist** แนะนำข้อความให้เจ้าหน้าที่ระหว่างคุยกับลูกค้า
- **Chatbot flows** ออกแบบบทสนทนาอัตโนมัติไว้คุยก่อนหรือคุยควบคู่กับคน
- **Quality scoring** ให้คะแนนคุณภาพบทสนทนา พร้อม Supervisor AI คอยตรวจงานทั้งของคนและ AI
