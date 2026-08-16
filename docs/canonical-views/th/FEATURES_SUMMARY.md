# Features Summary

สรุปฟีเจอร์ตามกลุ่มของ Rocket CRM เขียนจาก Product Feature Catalog — **ครบทุกฟีเจอร์ที่ใช้งานอยู่** สำหรับ RFP / เทียบคู่แข่ง เป็นประโยคขายสั้น (ไม่ใช่การถ่ายเอกสารจาก catalog)

**Contract:** `workflows/canonical-views/REFERENCE.md`  
**Voice:** `Writing Principles/CANONICAL_VIEW_COPY_PRINCIPLES.md`  
**Language:** TH  
**Companion:** [Commercial Pricing Sheet](./COMMERCIAL_PRICING_SHEET.md) (billable units; clustered highlights)  
**Sections** = modules (H2). **Rows** = feature groups (H3). HTML export: one ModuleBlock ต่อโมดูล

แต่ละ bullet คือหนึ่งฟีเจอร์จาก catalog: ชื่อที่ขายได้ + ประโยคสรุปสั้นหนึ่งประโยค

**ไม่ใส่ในมุมมองนี้** (catalog ยังอยู่): Tickets, Event promotions. ข้อมูลคุณสมบัติของร้านอธิบายรวมในอัตราสะสมคะแนน ไม่แยกบรรทัด. PDPA, ภาษา และ Customer 360 รวมใน **Admin portal and reports** (รายการตั้งค่า + Member 360 เป็นพื้นที่หลัก)

---

## Loyalty (ระบบสมาชิกและสะสมคะแนน)

### Signup & login (สมัครและเข้าสู่ระบบ) (`platform.signup`)

| Feature group | Capabilities |
| --- | --- |
| Signup & login (สมัครและเข้าสู่ระบบ) | (see bullets) |

- **เข้าสู่ระบบด้วย LINE หรือ OTP เบอร์มือถือ**
  สมาชิกเข้าสู่ระบบด้วย LINE, OTP เบอร์มือถือ หรือเปิดทั้งสองแบบ — คุณเลือกเองว่าจะให้ใช้วิธีไหน
- **กรอกโปรไฟล์ให้ครบหลังสมัคร**
  กำหนดให้สมาชิกกรอกข้อมูลที่คุณต้องการหลังเข้าสู่ระบบ ก่อนเริ่มใช้งานแอป
- **สมัครสมาชิกบนเว็บไซต์ของคุณเอง**
  วางหน้าสมัครของ Rocket ไว้บนเว็บไซต์คุณ สมาชิกสมัครได้โดยไม่ต้องออกจากแบรนด์
- **ฟอร์มสมัครแบบกำหนดเอง**
  เลือกเองว่าจะให้สมาชิกกรอกข้อมูลอะไรบ้าง ตอนสมัครหรือตอนเก็บโปรไฟล์เพิ่ม

### Points (คะแนน) (`loyalty.currency`)

| Feature group | Capabilities |
| --- | --- |
| Points (คะแนน) | (see bullets) |

- **ยอดคะแนน**
  คะแนนชุดเดียวใช้ได้ทุกอย่าง ทั้งแลกของรางวัลและใช้เป็นส่วนลด
- **วันหมดอายุของคะแนน**
  ตั้งให้หมดอายุแบบนับจากวันที่ได้รับ (เช่น 12 เดือน) หรือตัดตามรอบบัญชี พร้อมกำหนดอายุขั้นต่ำ เพื่อไม่ให้คะแนนที่เพิ่งได้ปลายรอบหมดทันที
- **อัตราสะสมคะแนนพื้นฐาน**
  ใช้เรทเดียวทั้งโปรแกรมว่ายอดใช้จ่ายแปลงเป็นคะแนนเท่าไร (เช่น 100 บาท = 1 คะแนน)
- **อัตราสะสมคะแนนขั้นสูง**
  ตั้งเรทแยกตามช่องทางขาย ร้านหรือกลุ่มร้าน หรือหมวดสินค้า และใส่ตัวคูณได้ เช่น คะแนน 2 เท่าในหมวดสกินแคร์ หรือเฉพาะสมาชิกนักเรียน
- **ตัวคูณคะแนนโบนัส**
  คูณคะแนนให้เฉพาะสินค้า หมวด หรือประเภทสมาชิกที่เลือกไว้ — เช่น คะแนน 2 เท่าในหมวดสกินแคร์

### Earn channels (ช่องทางสะสมคะแนน) (`loyalty.earn`)

| Feature group | Capabilities |
| --- | --- |
| Earn channels (ช่องทางสะสมคะแนน) | (see bullets) |

- **หน้า Earn ของสมาชิก**
  เลือกได้ว่าจะให้วิธีสะสมคะแนนแบบไหนขึ้นบนหน้า Earn — เช่น อัปโหลดใบเสร็จ เคลมออเดอร์ marketplace หรือสแกน QR
- **สะสมคะแนนจากการซิงค์ยอดซื้อ**
  ระบบเติมคะแนนให้อัตโนมัติเมื่อมียอดซื้อเข้ามาจาก POS หรือร้านออนไลน์
- **สะสมคะแนนจากออเดอร์ marketplace**
  สมาชิกเคลมหรือจับคู่ออเดอร์ Shopee, Lazada หรือ TikTok Shop เพื่อรับคะแนน ส่วนออเดอร์ Shopify รับคะแนนผ่าน Shopify plugin
- **สะสมคะแนนจากการสแกน QR / กรอกโค้ด**
  สมาชิกสแกน QR หรือกรอกโค้ดที่อยู่บนสินค้า ใบเสร็จ หรือโปสเตอร์
- **สะสมคะแนนจากการอัปโหลดใบเสร็จ**
  สมาชิกถ่ายรูปใบเสร็จกระดาษส่งเข้ามา แล้วได้คะแนนหลังพนักงานตรวจ
- **Receipt AI / OCR auto-approve**
  ให้ AI/OCR อ่านใบเสร็จแล้วอนุมัติอัตโนมัติ อ่านลึกถึงรายการสินค้าได้ (คิดเงินต่อใบเสร็จ)
- **สะสมคะแนนจากหลักฐานการทำกิจกรรม**
  สมาชิกอัปโหลดรูปเป็นหลักฐานกิจกรรมที่ไม่ใช่การซื้อ แล้วได้คะแนนหลังตรวจ
- **ปรับคะแนนด้วยมือ**
  พนักงานเติมหรือแก้คะแนนใน Front Line ได้ ทั้งกรณีชดเชยลูกค้า แก้ความผิดพลาด หรือย้ายข้อมูลเข้าระบบ
- **ให้คะแนนผ่าน Open API**
  ระบบของคุณเรียก API ของ Rocket เพื่อสั่งให้คะแนนได้เอง

### Rewards (ของรางวัล) (`loyalty.reward`)

| Feature group | Capabilities |
| --- | --- |
| Rewards (ของรางวัล) | (see bullets) |

- **แคตตาล็อกของรางวัลและการแลก**
  สมาชิกเลือกดูของรางวัลในแอปแล้วแลกด้วยคะแนนได้เลย
- **คะแนนแลกแบบยืดหยุ่น**
  ของรางวัลชิ้นเดียวกันตั้งให้ใช้คะแนนไม่เท่ากันในแต่ละกลุ่มสมาชิกได้
- **สิทธิ์การแลกของรางวัล**
  กำหนดว่าใครเห็นหรือแลกได้บ้าง ตาม Tier, persona, ช่วงเวลา และเงื่อนไขอื่น
- **กลุ่มของรางวัลและโควตาร่วม**
  จำกัดจำนวนที่สมาชิกแลกได้ในชุดของรางวัลที่ใช้โควตาร่วมกัน
- **Flash rewards**
  เปิดให้แลกเฉพาะช่วงสั้น ๆ ระดับนาทีหรือเป็นรอบดรอป ให้สมาชิกรีบแลกก่อนปิด
- **โค้ดโปรโมชันตอนแลก**
  ออกโค้ดส่วนลดหรือคูปองแบบไม่ซ้ำให้ทันทีที่สมาชิกแลก
- **แอดมินส่งของรางวัลและลิงก์เคลม**
  ส่งของรางวัลตรงถึงสมาชิกรายคน หรือแจกเป็นลิงก์เคลม / QR

### Points-to-discount (ใช้คะแนนเป็นส่วนลด) (`loyalty.burn`)

| Feature group | Capabilities |
| --- | --- |
| Points-to-discount (ใช้คะแนนเป็นส่วนลด) | (see bullets) |

- **ใช้คะแนนเป็นส่วนลดตอนชำระเงิน**
  กำหนดว่ากี่คะแนนเท่ากับส่วนลดกี่บาทตอนจ่ายเงิน — เป็นอัตราตั้งต้นของทั้งโปรแกรม
- **อัตราส่วนลดแยกตาม Tier**
  ให้แต่ละ Tier แลกคะแนนเป็นส่วนลดได้ในอัตราต่างกัน หรือปิดไม่ให้บาง Tier ใช้ก็ได้

### Tiers (ระดับสมาชิก) (`loyalty.tier`)

| Feature group | Capabilities |
| --- | --- |
| Tiers (ระดับสมาชิก) | (see bullets) |

- **Member tiers**
  ตั้งระดับสมาชิกพร้อมสิทธิประโยชน์ที่แสดงในแอป และลำดับการไต่ระดับ
- **เงื่อนไขการเลื่อน Tier**
  กำหนดว่าสมาชิกต้องทำถึงเท่าไรจึงเลื่อนขั้น — เช่น คะแนนที่สะสมได้หรือยอดใช้จ่าย
- **การรักษาระดับ Tier**
  เลือกได้ว่าจะให้คงระดับถาวรเมื่อได้แล้ว หรือต้องทำยอดใหม่ทุกรอบเพื่อรักษาระดับ
- **รอบประเมิน Tier**
  วัดความคืบหน้าเป็นปีปฏิทินหรือแบบย้อนหลังกี่เดือนก็ได้ และเลือกว่าการเลื่อนขั้นมีผลเมื่อไร
- **อัตราสะสมคะแนนตาม Tier**
  ให้เรทสะสมคะแนนต่างกันตามระดับปัจจุบันของสมาชิก
- **ชุด Tier แยกตาม persona**
  ใช้โปรแกรม Tier คนละชุดกับแต่ละ persona หรือประเภทสมาชิก — เช่น นักเรียนกับลูกค้าองค์กร

### Campaigns (แคมเปญ) (`loyalty.campaign`)

| Feature group | Capabilities |
| --- | --- |
| Campaigns (แคมเปญ) | (see bullets) |

- **Missions — แบบมาตรฐาน**
  สมาชิกเก็บภารกิจหลายข้อ จะทำข้อไหนก่อนก็ได้ ครบแล้วปลดล็อกของรางวัล
- **Missions — แบบ milestone**
  สมาชิกต้องไล่ทีละขั้นตามลำดับ — ทำขั้น 1 ให้เสร็จก่อน ขั้น 2 จึงเปิด
- **Referral**
  สมาชิกชวนเพื่อนด้วยโค้ดของตัวเอง เข้าเงื่อนไขแล้วได้รางวัลทั้งสองฝ่าย
- **Check-in**
  เช็คอินรายวันหรือรายสัปดาห์ สะสมวันต่อเนื่องเพื่อรับของรางวัล
- **Spin wheel**
  สมาชิกใช้คะแนนหรือ ticket หมุนวงล้อลุ้นรางวัล
- **Lucky draw**
  สมาชิกใช้คะแนนหรือ ticket แลกสิทธิ์ลุ้นรางวัล แล้วคุณจับผู้ชนะนอกระบบ

### Customer profile and forms (โปรไฟล์และฟอร์ม) (`loyalty.forms`)

| Feature group | Capabilities |
| --- | --- |
| Customer profile and forms (โปรไฟล์และฟอร์ม) | (see bullets) |

- **ข้อมูลโปรไฟล์**
  เลือกได้ว่าจะเก็บข้อมูลอะไรบ้าง (อีเมล เบอร์โทร ชื่อ ที่อยู่ และอื่น ๆ)
- **ข้อมูลโปรไฟล์ที่เพิ่มเอง**
  เพิ่มข้อมูลที่แบรนด์คุณต้องการ นอกเหนือจากชุดมาตรฐาน
- **Surveys**
  ใช้ฟอร์มแบบสำรวจเก็บฟีดแบ็กและข้อมูลสมาชิกเพิ่มเติม

### Lifecycle automations (ระบบอัตโนมัติตามวงจรสมาชิก) (`loyalty.lifecycle`)

| Feature group | Capabilities |
| --- | --- |
| Lifecycle automations (ระบบอัตโนมัติตามวงจรสมาชิก) | (see bullets) |

- **อัตโนมัติตอนสมัคร**
  ให้คะแนน ของรางวัล หรือติดแท็กให้อัตโนมัติเมื่อสมาชิกสมัครเสร็จ
- **อัตโนมัติวันเกิด**
  ส่งคะแนนหรือสิทธิพิเศษอื่นให้อัตโนมัติในช่วงวันเกิดของสมาชิก
- **อัตโนมัติวันครบรอบ**
  ส่งสิทธิพิเศษให้อัตโนมัติในวันครบรอบการเป็นสมาชิก
- **อัตโนมัติเมื่อเปลี่ยน Tier**
  ส่งสิทธิพิเศษให้อัตโนมัติเมื่อสมาชิกเลื่อนขั้นหรือหล่นระดับ

### Segmentation (การแบ่งกลุ่มสมาชิก) (`loyalty.persona`)

| Feature group | Capabilities |
| --- | --- |
| Segmentation (การแบ่งกลุ่มสมาชิก) | (see bullets) |

- **แท็กและ persona**
  จัดกลุ่มสมาชิกไว้ใช้กำหนดสิทธิ์ ตั้งระบบอัตโนมัติ และดูรายงาน
- **ประเภทสมาชิก**
  เช่น นักเรียน/นักศึกษา หรือลูกค้าองค์กร ใช้กำหนดกฎ อัตราสะสมคะแนน และชุด Tier
- **สิทธิ์พิเศษตาม persona**
  ให้บาง persona เข้าถึงหรือได้สิทธิ์เพิ่ม นอกเหนือจากแท็กทั่วไป
- **ส่ง LINE หรือ SMS ถึง Segment**
  ส่ง LINE หรือ SMS ถึงกลุ่มสมาชิกที่คัดด้วยเงื่อนไขที่ตั้งเองหรือ RFM — ใช้ระบบส่งข้อความชุดเดียวกับ Marketing Automation

### Store network (เครือข่ายสาขา) (`loyalty.store`)

| Feature group | Capabilities |
| --- | --- |
| Store network (เครือข่ายสาขา) | (see bullets) |

- **รายชื่อสาขา**
  ทะเบียนสาขาที่ใช้อ้างอิงทั้งการสะสมคะแนน การแลกของรางวัล และการออกรายงาน

### Member app UI CMS (CMS แอปสมาชิก) (`platform.experience`)

| Feature group | Capabilities |
| --- | --- |
| Member app UI CMS (CMS แอปสมาชิก) | (see bullets) |

- **Member app UI CMS**
  แก้หน้าจอแอปสมาชิกได้เองผ่าน CMS — แบนเนอร์ คะแนน ความคืบหน้า Tier ของรางวัลแนะนำ เมนู — โดยไม่ต้องรอทีมพัฒนา

### Admin portal and reports (แอดมินและรายงาน) (`platform.governance`)

| Feature group | Capabilities |
| --- | --- |
| Admin portal and reports (แอดมินและรายงาน) | (see bullets) |

- **Admin portal**
  ตั้งค่า loyalty จากแอดมิน: รหัสของรางวัล อัตราได้คะแนนตาม Tier การตั้งค่า Space ความยินยอม PDPA ภาษา และสิทธิ์ของทีม
- **รายงาน**
  รายงานกว่า 30 ฉบับในแอดมินมาตรฐาน พื้นที่หลัก: Members, Member 360, การแลกของรางวัล, ธุรกรรม, Campaign

### Front Line (`loyalty.frontline`)

| Feature group | Capabilities |
| --- | --- |
| Front Line | (see bullets) |

- **Front Line**
  พนักงานหน้าร้านค้นสมาชิกแล้วช่วยได้ทันที: ปรับคะแนน ส่งของรางวัล ทำเครื่องหมายว่าใช้แล้ว แก้โปรไฟล์ หรือเปลี่ยนเบอร์และ persona

### RFM and funnels (RFM และ Funnel) (`loyalty.analytics`)

| Feature group | Capabilities |
| --- | --- |
| RFM and funnels (RFM และ Funnel) | (see bullets) |

- **คะแนน RFM**
  จัดอันดับสมาชิกจากความสดของการซื้อ ความถี่ และมูลค่า — เอาไปใช้เลือกกลุ่มเป้าหมายต่อได้
- **ขั้นของ Funnel**
  กำหนดขั้นตอนใน journey แล้วดูรายงานอัตราการผ่านแต่ละขั้น

### Admin, data operations, and integrations (แอดมิน การจัดการข้อมูล และการเชื่อมต่อ) (`loyalty.ops`)

| Feature group | Capabilities |
| --- | --- |
| Admin, data operations, and integrations (แอดมิน การจัดการข้อมูล และการเชื่อมต่อ) | (see bullets) |

- **นำเข้า / ส่งออกข้อมูลสมาชิก**
  นำเข้าหรือส่งออกโปรไฟล์สมาชิกทีละมาก ๆ สำหรับย้ายระบบและงานประจำวัน
- **นำเข้าคะแนนทีละมาก ๆ**
  อัปโหลดคะแนนเป็นชุดใหญ่ ทั้งตอนย้ายระบบและตอนทำแคมเปญ

### Open API & integrations (Open API และการเชื่อมต่อ) (`loyalty.integrations`)

| Feature group | Capabilities |
| --- | --- |
| Open API & integrations (Open API และการเชื่อมต่อ) | (see bullets) |

- **Open API**
  เชื่อม POS แอป หรือเว็บไซต์ของคุณเข้ากับ Rocket — ทั้งข้อมูลสมาชิก ยอดซื้อ คะแนน การแลก และ assets ระบบของคุณยังเป็นต้นทางข้อมูลเหมือนเดิม ส่วน Rocket ดูแลการเก็บและคิดคะแนนให้

---

## Shopify

### Shopify loyalty plugin (ปลั๊กอิน loyalty สำหรับ Shopify) (`loyalty.storefront`)

| Feature group | Capabilities |
| --- | --- |
| Shopify loyalty plugin (ปลั๊กอิน loyalty สำหรับ Shopify) | (see bullets) |

Loyalty widget บนร้าน Shopify ที่เชื่อมกับช่องทางอื่นนอก Shopify ได้ด้วย พร้อมเชื่อมกับ Shopify โดยตรง

- **สะสมคะแนนจากออเดอร์ Shopify**
  สมาชิกได้รับคะแนนอัตโนมัติเมื่อออเดอร์ Shopify ชำระเงินแล้ว
- **Shopify loyalty widget**
  แสดงสถานะสมาชิกและคะแนนบนหน้าร้าน Shopify
- **ใช้คะแนนเป็นส่วนลดบน Shopify**
  ให้สมาชิกใช้คะแนนเป็นส่วนลดในหน้า checkout ของ Shopify
- **จับคู่สมาชิก Shopify**
  จับคู่ลูกค้า Shopify กับสมาชิก Rocket ให้อัตโนมัติ ด้วย Shopify id, อีเมล หรือเบอร์โทร

---

## Marketing Automation (การตลาดอัตโนมัติ)

### Multi-step workflows (Workflow หลายขั้น) (`marketing_automation.workflows`)

| Feature group | Capabilities |
| --- | --- |
| Multi-step workflows (Workflow หลายขั้น) | (see bullets) |

- **Workflow หลายขั้น**
  วางเส้นทางไว้ล่วงหน้า ให้ระบบรอจังหวะ แยกทางตามเงื่อนไข ส่งข้อความ และสั่งงานฝั่ง loyalty ได้เอง
- **ข้อความ LINE Flex**
  ออกแบบการ์ด LINE Flex แล้วเรียกใช้เป็นขั้นตอนส่งข้อความใน Workflow
- **Audience automation**
  กลุ่มสมาชิกแบบอัปเดตอัตโนมัติหรือแบบตายตัว ใช้การเข้า/ออกกลุ่มเป็นทริกเกอร์ให้ Workflow เริ่มทำงาน

### AI decisioning (`marketing_automation.ai_decisioning`)

| Feature group | Capabilities |
| --- | --- |
| AI decisioning | (see bullets) |

- **AI decisioning agent**
  คุณตั้งเป้าหมาย ระบุ action ที่ทำได้ และขีดจำกัดไว้ จากนั้น agent จะตัดสินใจรายคนว่าจะ ACT, WAIT หรือ SKIP

### AI analysis (AI ช่วยวิเคราะห์) (`marketing_automation.ai_analysis`)

| Feature group | Capabilities |
| --- | --- |
| AI analysis (AI ช่วยวิเคราะห์) | (see bullets) |

- **AI วิเคราะห์และแนะนำ**
  วิเคราะห์ผลของ Workflow และ agent แล้วแนะนำว่านักการตลาดควรปรับอะไรต่อ

---

## Customer Service (บริการลูกค้า)

### Omnichannel inbox and connectivity (Inbox รวมทุกช่องทาง) (`customer_service.connectivity`)

| Feature group | Capabilities |
| --- | --- |
| Omnichannel inbox and connectivity (Inbox รวมทุกช่องทาง) | (see bullets) |

- **Omnichannel inbox**
  รวมทุกช่องทางที่เชื่อมไว้มาอยู่ในกล่องเดียว บนข้อมูลลูกค้าชุดเดียวกัน
- **ตัวเชื่อมช่องทาง**
  เชื่อมแอปแชท อีเมล เว็บ SMS marketplace และช่องทางอื่นที่เกี่ยวข้อง
- **เบอร์โทรศัพท์**
  จัดหาและดูแลเบอร์ที่ใช้รับสายและส่ง SMS

### Chat and voice (แชทและสายโทร) (`customer_service.chat_voice`)

| Feature group | Capabilities |
| --- | --- |
| Chat and voice (แชทและสายโทร) | (see bullets) |

- **แชท**
  แชทที่ไม่ต้องออนไลน์พร้อมกัน เก็บประวัติครบและมีเครื่องมือให้เจ้าหน้าที่
- **สายโทร**
  รับสายลูกค้าโดยเห็นข้อมูลชุดเดียวกับที่ใช้ตอนแชท

### Agent productivity (เครื่องมือช่วยเจ้าหน้าที่) (`customer_service.agent_productivity`)

| Feature group | Capabilities |
| --- | --- |
| Agent productivity (เครื่องมือช่วยเจ้าหน้าที่) | (see bullets) |

- **Quick replies**
  ข้อความสำเร็จรูปที่อนุมัติไว้แล้ว ช่วยให้ตอบเร็วขึ้นและโทนตรงกันทั้งทีม
- **ค้นคลังความรู้**
  เจ้าหน้าที่ค้น knowledge base ได้ทันทีระหว่างคุยกับลูกค้า
- **Live assist**
  แนะนำข้อความและข้อมูลประกอบให้เจ้าหน้าที่ระหว่างสนทนา

### Routing and chatbot workflows (Routing และ chatbot) (`customer_service.routing_workflows`)

| Feature group | Capabilities |
| --- | --- |
| Routing and chatbot workflows (Routing และ chatbot) | (see bullets) |

- **Routing**
  จ่ายบทสนทนาเข้าคิว ทีมตามความชำนาญ หรือเจ้าหน้าที่รายคน ตามกฎที่ตั้งไว้
- **Chatbot flows**
  ออกแบบบทสนทนาอัตโนมัติแบบเห็นทุกขั้นตอน ใช้คุยก่อนหรือคุยควบคู่กับคน

### Service analytics (รายงานงานบริการ) (`customer_service.analytics`)

| Feature group | Capabilities |
| --- | --- |
| Service analytics (รายงานงานบริการ) | (see bullets) |

- **Service analytics**
  ปริมาณงาน เวลาตอบ CSAT สัดส่วนเคสที่ปิดได้โดยไม่ต้องส่งต่อคน และประสิทธิภาพเจ้าหน้าที่

### AI service agent (`customer_service.ai_agent`)

| Feature group | Capabilities |
| --- | --- |
| AI service agent | (see bullets) |

- **AI service agent**
  AI ที่ตั้งค่าตามแบรนด์คุณ รับคุยเองหรือช่วยเจ้าหน้าที่ ภายใต้โทนการสื่อสาร ภาษา และกฎการส่งต่อที่คุณกำหนด

### AOPs, knowledge, and customer actions (AOP คลังความรู้ และการดำเนินการให้ลูกค้า) (`customer_service.aop_actions`)

| Feature group | Capabilities |
| --- | --- |
| AOPs, knowledge, and customer actions (AOP คลังความรู้ และการดำเนินการให้ลูกค้า) | (see bullets) |

- **Agent operating procedures (AOPs)**
  ขั้นตอนการทำงานแยกตามเรื่องที่ลูกค้าติดต่อมา ให้ AI ทำตามเวลาแก้ปัญหา
- **Knowledge base**
  คลังความรู้งานบริการ อ้างอิงแหล่งที่มาได้ ใช้ได้ทั้งเจ้าหน้าที่และ AI
- **การดำเนินการให้ลูกค้า**
  กำหนดว่า AI ค้นข้อมูล สั่งงานฝั่ง loyalty หรือเรียกระบบที่เชื่อมไว้อะไรได้บ้างจากในบทสนทนา

### Supervisor AI and quality scoring (Supervisor AI และการให้คะแนนคุณภาพ) (`customer_service.supervisor_ai`)

| Feature group | Capabilities |
| --- | --- |
| Supervisor AI and quality scoring (Supervisor AI และการให้คะแนนคุณภาพ) | (see bullets) |

- **Quality scoring**
  ให้คะแนนบทสนทนาทั้งของคนและ AI ทั้งด้านคุณภาพ การทำตามนโยบาย และจุดที่ควรโค้ชเพิ่ม
- **Supervisor AI**
  ตรวจงานเคสของ AI และของคน แล้วส่งสิ่งที่พบกลับไปปรับ prompt และ AOP ให้ดีขึ้น
