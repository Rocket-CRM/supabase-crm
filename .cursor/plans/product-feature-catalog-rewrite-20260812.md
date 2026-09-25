# Product Feature Catalog — Copy rewrite + commercial nature (2026-08-12)

**Status:** Applied to live Supabase `wkevmsedchftztoolkmi` on 2026-08-12.  
**Workflow updated:** `workflows/product-feature-catalog/REFERENCE.md` §6.0 + §8.1.  
**Note:** §6.0 principle is *easy to digest, still complete* — never omit real modes/dimensions. Expiry row corrected accordingly.  
**Verified:** 89/89 `commercial_nature` set (39 core / 36 advanced / 7 addon / 7 consumption); signup form moved to `platform.signup`; view `v_internal_product_feature_catalog` exposes TH + commercial columns.

## Schema to add (needs approval)

```sql
ALTER TABLE internal_product_feature
  ADD COLUMN IF NOT EXISTS commercial_nature text,
  ADD COLUMN IF NOT EXISTS consumption_unit text;

ALTER TABLE internal_product_feature
  DROP CONSTRAINT IF EXISTS internal_product_feature_commercial_nature_check;

ALTER TABLE internal_product_feature
  ADD CONSTRAINT internal_product_feature_commercial_nature_check
  CHECK (commercial_nature IS NULL OR commercial_nature IN ('core','advanced','addon','consumption'));

ALTER TABLE internal_product_feature
  DROP CONSTRAINT IF EXISTS internal_product_feature_consumption_unit_check;

ALTER TABLE internal_product_feature
  ADD CONSTRAINT internal_product_feature_consumption_unit_check
  CHECK (
    (commercial_nature = 'consumption' AND consumption_unit IS NOT NULL)
    OR (COALESCE(commercial_nature, '') <> 'consumption' AND consumption_unit IS NULL)
  );

COMMENT ON COLUMN internal_product_feature.commercial_nature IS
  'How sold/charged: core | advanced | addon | consumption. Orthogonal to package membership.';
COMMENT ON COLUMN internal_product_feature.consumption_unit IS
  'Meter unit when commercial_nature=consumption (e.g. campaign_month, receipt).';
```

**Yes — encode unit type as its own column** (`consumption_unit`). Nature alone cannot price campaigns vs OCR receipts.

## Placement change

| feature_key | From | To |
|---|---|---|
| `loyalty.forms.signup_form` | Customer profile and forms | Signup & login (`platform.signup`) |

Keep `loyalty.forms.profile_fields`, `custom_fields`, `surveys` in forms group.

## Commercial nature proposal (all active features)

Legend: C=core, A=advanced, D=addon, M=consumption.

### Loyalty

| feature_key | Nature | Unit | Notes |
|---|---|---|---|
| platform.signup.login_methods | C | | |
| platform.signup.complete_profile | C | | |
| platform.signup.on_your_website | C | | |
| loyalty.forms.signup_form | C | | move group |
| platform.experience.display_settings | C | | |
| platform.governance.pdpa_consent | C | | |
| platform.governance.admin_shell | C | | |
| platform.governance.translation | C | | |
| loyalty.currency.points | C | | |
| loyalty.currency.tickets | A | | fungible vs non-fungible contrast |
| loyalty.currency.expiry | C | | TTL + fiscal modes + min validity |
| loyalty.currency.earn_rate_basic | C | | |
| loyalty.currency.earn_rate_advanced | A | | name dimensions |
| loyalty.currency.multipliers | A | | |
| loyalty.earn.channel_page | C | | concrete earn-card examples |
| loyalty.earn.purchase_sync | C | | |
| loyalty.earn.marketplace | C | | |
| loyalty.earn.qr_or_code | C | | |
| loyalty.earn.receipt_upload | A | | manual/admin review path |
| loyalty.earn.receipt_advanced | M | receipt | AI/OCR auto-approve |
| loyalty.earn.activity_proof | A | | |
| loyalty.earn.manual_adjust | C | | |
| loyalty.earn.openapi | D | | pairs with Open API addon |
| loyalty.reward.catalog | C | | |
| loyalty.reward.dynamic_pricing | A | | |
| loyalty.reward.eligibility | A | | |
| loyalty.reward.groups_limits | A | | |
| loyalty.reward.promo_codes | A | | |
| loyalty.reward.admin_push_claim | A | | |
| loyalty.burn.rate_default | C | | |
| loyalty.burn.rate_per_tier | A | | |
| loyalty.tier.ladder | C | | |
| loyalty.tier.upgrade_conditions | C | | |
| loyalty.tier.maintain_mode | C | | |
| loyalty.tier.evaluation_windows | A | | |
| loyalty.tier.per_tier_earn_rate | A | | |
| loyalty.tier.persona_scope | A | | |
| loyalty.campaign.mission_standard | M | campaign_month | all campaigns metered |
| loyalty.campaign.mission_milestone | M | campaign_month | |
| loyalty.campaign.referral | M | campaign_month | |
| loyalty.campaign.checkin | M | campaign_month | |
| loyalty.campaign.spin_wheel | M | campaign_month | |
| loyalty.campaign.lucky_draw | M | campaign_month | |
| loyalty.forms.profile_fields | C | | |
| loyalty.forms.custom_fields | C | | |
| loyalty.forms.surveys | A | | |
| loyalty.lifecycle.signup_outcomes | C | | |
| loyalty.lifecycle.birthday | C | | |
| loyalty.lifecycle.anniversary | A | | |
| loyalty.lifecycle.tier_change | A | | |
| loyalty.persona.tags_personas | C | | |
| loyalty.persona.user_types | A | | |
| loyalty.persona.entitlements | A | | |
| loyalty.store.master | C | | |
| loyalty.store.attributes | A | | |
| loyalty.frontline.customer_360 | C | | |
| loyalty.frontline.assisted_actions | A | | |
| loyalty.analytics.reports | C | | |
| loyalty.analytics.rfm | A | | |
| loyalty.analytics.funnel | A | | |
| loyalty.ops.customer_import_export | A | | |
| loyalty.ops.bulk_currency_import | A | | |
| loyalty.storefront.shopify_widget | D | | à la carte storefront |
| loyalty.storefront.shopify_burn | D | | |
| loyalty.stored_value.cards | D | | |
| loyalty.stored_value.store_credit | D | | |
| loyalty.event_promo.engine | A | | confirm vs addon |
| loyalty.integrations.open_api | D | | |

### Marketing Automation

| feature_key | Nature | Unit | Notes |
|---|---|---|---|
| marketing_automation.workflows.multi_step | C | | confirm if MA has separate advanced SKU |
| marketing_automation.workflows.audiences | C | | |
| marketing_automation.ai_decisioning.agent | A | | **flag:** may become consumption later |
| marketing_automation.ai_analysis.recommendations | A | | **flag:** may become consumption later |

### Customer Service

| feature_key | Nature | Unit | Notes |
|---|---|---|---|
| customer_service.connectivity.omnichannel_inbox | C | | |
| customer_service.connectivity.channel_connectors | C | | |
| customer_service.connectivity.phone_numbers | D | | numbers often metered elsewhere — confirm |
| customer_service.chat_voice.chat | C | | |
| customer_service.chat_voice.voice | A | | |
| customer_service.agent_productivity.quick_replies | C | | |
| customer_service.agent_productivity.knowledge_search | C | | |
| customer_service.agent_productivity.live_assist | A | | **flag:** AI assist may be consumption |
| customer_service.routing_workflows.routing | C | | |
| customer_service.routing_workflows.chatbot_flows | A | | |
| customer_service.analytics.service_analytics | C | | |
| customer_service.ai_agent.brand_ai | A | | **flag:** likely consumption later |
| customer_service.aop_actions.aops | A | | |
| customer_service.aop_actions.knowledge_base | C | | |
| customer_service.aop_actions.customer_actions | A | | |
| customer_service.supervisor_ai.quality_scoring | A | | **flag:** may be consumption |
| customer_service.supervisor_ai.watchtower | A | | **flag:** may be consumption |

## English + Thai rewrite draft

### Placement / critical fixes

| feature_key | name | name_th | summary | summary_th | includes |
|---|---|---|---|---|---|
| loyalty.forms.signup_form | Custom signup / profile completion form | ฟอร์มสมัคร / กรอกโปรไฟล์แบบกำหนดเอง | Choose which fields members answer when they sign up or finish their profile after login. | เลือกว่าสมาชิกต้องกรอกฟิลด์ใดตอนสมัครหรือตอนกรอกโปรไฟล์หลังล็อกอิน | ["Lives under Signup & login","Surveys stay under forms"] |
| loyalty.currency.points | Points balance | ยอดคะแนน (Points) | Members hold one fungible points balance — every point is interchangeable and can be spent on rewards or discounts. | สมาชิกมียอดคะแนนแบบ fungible — คะแนนทุกหน่วยใช้แทนกันได้ และนำไปแลกของรางวัลหรือส่วนลดได้ | [] |
| loyalty.currency.tickets | Tickets (non-fungible tokens) | Tickets (โทเคนแบบไม่แทนกันได้) | Tickets are non-fungible token balances: each ticket type is separate and cannot be mixed with another type or with points. | Tickets เป็นยอดโทเคนแบบ non-fungible — แต่ละประเภทแยกกัน และใช้ปนกับประเภทอื่นหรือกับคะแนนไม่ได้ | ["Raffle tickets","Parking passes","VIP access passes","Birthday vouchers"] |
| loyalty.currency.expiry | Points expiry | วันหมดอายุของคะแนน | Choose how points expire: rolling TTL after each earn (e.g. 12 months), or on fiscal periods (monthly to annual) with a minimum validity so points earned near period-end are not wiped immediately. | เลือกว่าคะแนนหมดอายุแบบใด: นับอายุจากวันที่ได้รับแบบ TTL (เช่น 12 เดือน) หรือตัดตามรอบบัญชี (รายเดือนถึงรายปี) พร้อมอายุขั้นต่ำ เพื่อไม่ให้คะแนนที่ได้ปลายรอบหมดทันที | ["TTL: expire 12 months after earning","Quarterly expiry + 3-month minimum","Fiscal year-end month configurable"] |
| loyalty.currency.earn_rate_advanced | Earn rate — advanced | อัตราการได้คะแนน — ขั้นสูง | Set different earn rates by channel, store, product (SKU/brand/category), tier, or persona — not one flat rate. | ตั้งอัตราได้คะแนนต่างกันตามช่องทาง ร้าน สินค้า (SKU/แบรนด์/หมวด) Tier หรือ persona — ไม่ใช่เรทเดียว | ["2× on Shopee","Higher rate at flagship stores","Gold tier 1.5×","Double on skincare"] |
| loyalty.earn.channel_page | Earn page setup | ตั้งค่าหน้า Earn | Choose which earn cards appear on the member Earn page — for example upload a receipt, claim a marketplace order, or scan a QR. | เลือกว่าการ์ดใดจะโชว์บนหน้า Earn ของสมาชิก เช่น อัปโหลดใบเสร็จ เคลมออเดอร์ marketplace หรือสแกน QR | ["Cards can also deep-link to missions or referral when those programs are on"] |

### Full rewrite table (remaining rows — EN/TH)

| feature_key | name | name_th | summary | summary_th | includes |
|---|---|---|---|---|---|
| platform.signup.login_methods | Login with LINE or phone OTP | เข้าสู่ระบบด้วย LINE หรือ OTP ทางโทรศัพท์ | Members sign in with LINE, a phone OTP, or both — you choose which methods your brand allows. | สมาชิกเข้าสู่ระบบด้วย LINE, OTP ทางโทรศัพท์ หรือทั้งสองแบบ — คุณเลือกว่าแบรนด์เปิดวิธีใด | [] |
| platform.signup.complete_profile | Signup profile completion | กรอกโปรไฟล์หลังสมัคร | After login, members complete the profile fields you require before they enter the app. | หลังล็อกอิน สมาชิกกรอกฟิลด์โปรไฟล์ที่คุณกำหนดก่อนเข้าแอป | [] |
| platform.signup.on_your_website | Signup on your own website | สมัครสมาชิกบนเว็บไซต์ของคุณ | Run Rocket signup/login on your own website or online store so members join without leaving your site. | ฝัง flow สมัคร/ล็อกอินของ Rocket บนเว็บหรือร้านออนไลน์ของคุณได้ โดยสมาชิกไม่ต้องออกจากเว็บคุณ | [] |
| platform.experience.display_settings | Homepage & screen layout | จัดหน้าแรกและเลย์เอาต์หน้าจอ | Arrange homepage blocks members see — banners, points, tier progress, featured rewards, menus — without engineering work. | จัดบล็อกบนหน้าแรกที่สมาชิกเห็น — แบนเนอร์ คะแนน ความคืบหน้า Tier ของรางวัลเด่น เมนู — โดยไม่ต้องพึ่งงาน engineer | [] |
| platform.governance.pdpa_consent | Privacy consent (PDPA) | ความยินยอมความเป็นส่วนตัว (PDPA) | Members accept your privacy terms at signup, and you keep a record of that consent. | สมาชิกยอมรับเงื่อนไขความเป็นส่วนตัวตอนสมัคร และคุณเก็บหลักฐานความยินยอมไว้ | [] |
| platform.governance.admin_shell | Admin users & permissions | ผู้ใช้แอดมินและสิทธิ์การใช้งาน | Invite your team to admin and control what each role can see or change. | เชิญทีมเข้าแอดมิน และกำหนดว่าแต่ละ role ดูหรือแก้ได้อะไร | [] |
| platform.governance.translation | Multiple languages | หลายภาษา | Show rewards, forms, tiers, and app text in the member’s language (for example Thai and English). | แสดงของรางวัล ฟอร์ม Tier และข้อความในแอปตามภาษาของสมาชิก (เช่น ไทยและอังกฤษ) | [] |
| loyalty.currency.earn_rate_basic | Earn rate — basic | อัตราการได้คะแนน — พื้นฐาน | Set a single flat earn rate for how spending turns into points (for example 100 THB = 1 point). | ตั้งอัตราได้คะแนนแบบเรทเดียวทั้งโปรแกรม เช่น ใช้จ่าย 100 บาท ได้ 1 คะแนน | ["Contrast: advanced rates vary by channel/store/product/tier/persona"] |
| loyalty.currency.multipliers | Bonus point multipliers | ตัวคูณคะแนนโบนัส | Multiply points for selected products or categories — for example double points on skincare. | คูณคะแนนสำหรับสินค้าหรือหมวดที่เลือก เช่น double points สินค้าสกินแคร์ | [] |
| loyalty.earn.purchase_sync | Earn from purchase sync | ได้คะแนนจากการซิงค์การซื้อ | Points are added automatically when a purchase arrives from your POS or online store. | ระบบเติมคะแนนอัตโนมัติเมื่อมีการซื้อจาก POS หรือร้านออนไลน์ของคุณ | [] |
| loyalty.earn.marketplace | Earn from marketplace orders | ได้คะแนนจากออเดอร์ marketplace | Members claim or match a Shopee, Lazada, or TikTok Shop order to earn points. | สมาชิกเคลมหรือจับคู่ออเดอร์ Shopee, Lazada หรือ TikTok Shop เพื่อรับคะแนน | [] |
| loyalty.earn.qr_or_code | Earn from QR / code scan | ได้คะแนนจากสแกน QR / รหัส | Members scan a QR or enter a code on a product, receipt, or poster to collect points. | สมาชิกสแกน QR หรือกรอกรหัสบนสินค้า ใบเสร็จ หรือโปสเตอร์เพื่อรับคะแนน | [] |
| loyalty.earn.receipt_upload | Earn from receipt upload | ได้คะแนนจากการอัปโหลดใบเสร็จ | Members photograph a paper receipt; points are awarded after staff review and approval. | สมาชิกถ่ายใบเสร็จกระดาษ แล้วได้คะแนนหลังพนักงานตรวจและอนุมัติ | [] |
| loyalty.earn.receipt_advanced | Receipt AI / OCR auto-approve | ตรวจใบเสร็จด้วย AI / OCR อัตโนมัติ | Auto-approve receipt uploads with AI/OCR, and optionally award points from receipt line items. | อนุมัติใบเสร็จอัตโนมัติด้วย AI/OCR และให้คะแนนจากรายการสินค้าในใบเสร็จได้ | ["Metered per receipt"] |
| loyalty.earn.activity_proof | Earn from activity proof upload | ได้คะแนนจากหลักฐานกิจกรรม | Members upload a photo as proof of a non-purchase activity, then earn after review. | สมาชิกอัปโหลดรูปเป็นหลักฐานกิจกรรมที่ไม่ใช่การซื้อ แล้วได้คะแนนหลังผ่านการตรวจ | [] |
| loyalty.earn.manual_adjust | Manual points adjust (Front Line) | ปรับคะแนนด้วยมือ (Front Line) | Staff add or correct a member’s points in Front Line for service recovery, mistakes, or migrations. | พนักงานเติมหรือแก้คะแนนใน Front Line ได้ สำหรับชดเชยบริการ ความผิดพลาด หรือการย้ายข้อมูล | [] |
| loyalty.earn.openapi | Earn via Open API | ให้คะแนนผ่าน Open API | Your systems grant points by calling Rocket’s API (partners or custom apps). | ระบบของคุณเรียก API ของ Rocket เพื่อให้คะแนนได้เอง (พาร์ทเนอร์หรือแอปคัสตอม) | [] |
| loyalty.reward.catalog | Reward catalog & redeem | แคตตาล็อกของรางวัลและการแลก | Members browse rewards and redeem them for points. | สมาชิกเลือกดูและแลกของรางวัลด้วยคะแนน | [] |
| loyalty.reward.dynamic_pricing | Dynamic reward points pricing | ราคาคะแนนของรางวัลแบบไดนามิก | The same reward can cost different points for different members. | ของรางวัลชิ้นเดียวกันอาจใช้คะแนนต่างกันตามสมาชิก | [] |
| loyalty.reward.eligibility | Reward eligibility filters | ตัวกรองสิทธิ์แลกของรางวัล | Control who can see or redeem a reward by tier, persona, time window, and similar rules. | ควบคุมว่าใครเห็นหรือแลกของรางวัลได้ ตาม Tier, persona, ช่วงเวลา และกฎใกล้เคียง | [] |
| loyalty.reward.groups_limits | Reward groups & shared limits | กลุ่มของรางวัลและโควต้าร่วม | Limit how members choose across a set of related rewards that share a quota. | จำกัดการเลือกระหว่างชุดของรางวัลที่ใช้โควต้าร่วมกัน | [] |
| loyalty.reward.promo_codes | Promo code fulfillment | ส่งมอบด้วยโปรโมโค้ด | Issue a unique promo or coupon code when a member redeems. | ออกโปรโมหรือคูปองโค้ดแบบไม่ซ้ำเมื่อสมาชิกแลก | [] |
| loyalty.reward.admin_push_claim | Admin push & claim links/QR | แอดมินส่งของรางวัลและลิงก์/QR เคลม | Push a reward to one member, or distribute via a claim link or QR. | ส่งของรางวัลให้สมาชิกแบบ 1:1 หรือแจกผ่านลิงก์เคลม/QR | [] |
| loyalty.burn.rate_default | Burn rate — merchant default | อัตรา burn — ค่าเริ่มต้นร้านค้า | Convert points into a money discount at checkout using your default burn rate. | แปลงคะแนนเป็นส่วนลดเงินตอนชำระเงินตามอัตรา burn เริ่มต้นของร้าน | [] |
| loyalty.burn.rate_per_tier | Burn rate — per-tier override | อัตรา burn — ปรับตาม Tier | Override the burn-to-discount rate by tier, or turn burn off for some tiers. | ปรับอัตราแลกคะแนนเป็นส่วนลดตาม Tier หรือปิด burn ในบาง Tier | [] |
| loyalty.tier.ladder | Tier ladder & benefits | บันได Tier และสิทธิประโยชน์ | Define member tiers with display benefits and the order members progress through. | กำหนดระดับสมาชิก พร้อมสิทธิที่แสดงผลและลำดับการเลื่อนขั้น | [] |
| loyalty.tier.upgrade_conditions | Tier upgrade conditions | เงื่อนไขเลื่อน Tier | Set how much earning (points or spend) is required to move up a tier. | ตั้งว่าต้องสะสมเท่าไร (คะแนนหรือยอดใช้จ่าย) จึงเลื่อน Tier ได้ | [] |
| loyalty.tier.maintain_mode | Tier maintain / re-qualify mode | โหมดรักษา / ยืนยันสิทธิ์ Tier | Choose whether a tier stays once earned, or members must re-qualify each period. | เลือกว่า Tier คงถาวรเมื่อได้แล้ว หรือต้องยืนยันสิทธิ์ใหม่ทุกช่วงเวลา | [] |
| loyalty.tier.evaluation_windows | Tier evaluation windows & timing | ช่วงเวลาประเมิน Tier | Choose the window used to measure tier progress (calendar year or rolling months) and when upgrades apply. | เลือกหน้าต่างเวลาที่ใช้วัดความคืบหน้า Tier (ปีปฏิทินหรือ rolling months) และจังหวะที่อัปเกรดมีผล | [] |
| loyalty.tier.per_tier_earn_rate | Per-tier earn rate benefits | อัตราได้คะแนนตาม Tier | Give different earn rates by the member’s current tier. | ให้อัตราได้คะแนนต่างกันตาม Tier ปัจจุบันของสมาชิก | [] |
| loyalty.tier.persona_scope | Persona-scoped tier ladders | บันได Tier ตาม persona | Run different tier ladders for different personas or user types. | ใช้บันได Tier คนละชุดตาม persona หรือประเภทผู้ใช้ | [] |
| loyalty.campaign.mission_standard | Missions — standard | Mission — แบบมาตรฐาน | Members complete several goals in any order to unlock a mission reward. | สมาชิกทำหลายเป้าหมายลำดับใดก็ได้ เพื่อปลดล็อกของรางวัลจาก Mission | [] |
| loyalty.campaign.mission_milestone | Missions — milestone / progressive | Mission — แบบ milestone / ทีละขั้น | Members finish ordered mission steps — step 1 before step 2 unlocks. | สมาชิกทำ Mission ทีละขั้นตามลำดับ — ขั้น 1 เสร็จก่อนขั้น 2 จึงปลดล็อก | [] |
| loyalty.campaign.referral | Referral | Referral (แนะนำเพื่อน) | Members invite friends with a code; both sides can earn when the rules are met. | สมาชิกเชิญเพื่อนด้วยรหัส เมื่อครบเงื่อนไขทั้งสองฝ่ายรับรางวัลได้ | [] |
| loyalty.campaign.checkin | Check-in | Check-in | Members check in on a daily or weekly rhythm to build streaks and earn rewards. | สมาชิกเช็คอินรายวันหรือรายสัปดาห์เพื่อสะสม streak และรับของรางวัล | [] |
| loyalty.campaign.spin_wheel | Spin wheel | วงล้อสุ่ม (Spin wheel) | Members spend points or tickets to spin for a random prize. | สมาชิกใช้คะแนนหรือ tickets หมุนวงล้อลุ้นรางวัลแบบสุ่ม | [] |
| loyalty.campaign.lucky_draw | Mass lucky draw | จับฉลากจำนวนมาก (Lucky draw) | Run currency-entry lucky draws and select winners offline. | จัดจับฉลากที่เข้าด้วยสกุลเงิน แล้วคัดผู้ชนะแบบออฟไลน์ | [] |
| loyalty.forms.profile_fields | Profile field configuration | ตั้งค่าฟิลด์โปรไฟล์ | Configure the default profile fields you collect (email, phone, name, address, and similar). | กำหนดฟิลด์โปรไฟล์มาตรฐานที่เก็บ (อีเมล โทรศัพท์ ชื่อ ที่อยู่ และฟิลด์ใกล้เคียง) | [] |
| loyalty.forms.custom_fields | Custom fields | ฟิลด์กำหนดเอง | Add merchant-defined fields beyond the default profile set. | เพิ่มฟิลด์ที่ร้านค้าสร้างเอง นอกเหนือชุดโปรไฟล์มาตรฐาน | [] |
| loyalty.forms.surveys | Survey forms | ฟอร์มแบบสำรวจ | Run survey-style forms for feedback and member data enrichment. | ใช้ฟอร์มแบบ survey เพื่อเก็บฟีดแบ็กและเสริมข้อมูลสมาชิก | [] |
| loyalty.lifecycle.signup_outcomes | Signup lifecycle automation | Automation เมื่อสมัครสมาชิก | Automatically award points, rewards, or tags when members finish signup. | ให้คะแนน ของรางวัล หรือแท็กอัตโนมัติเมื่อสมาชิกสมัครครบ | [] |
| loyalty.lifecycle.birthday | Birthday lifecycle automation | Automation วันเกิด | Automatically trigger loyalty outcomes around a member’s birthday. | ทริกเกอร์ผลลัพธ์ loyalty อัตโนมัติช่วงวันเกิดสมาชิก | [] |
| loyalty.lifecycle.anniversary | Anniversary lifecycle automation | Automation วันครบรอบสมาชิก | Automatically trigger loyalty outcomes on membership anniversary. | ทริกเกอร์ผลลัพธ์ loyalty อัตโนมัติในวันครบรอบการเป็นสมาชิก | [] |
| loyalty.lifecycle.tier_change | Tier-change lifecycle automation | Automation เมื่อเปลี่ยน Tier | Automatically trigger outcomes when a member upgrades or downgrades tier. | ทริกเกอร์ผลลัพธ์อัตโนมัติเมื่อสมาชิกเลื่อนหรือลด Tier | [] |
| loyalty.persona.tags_personas | Tags & personas | แท็กและ persona | Classify members with tags and personas for eligibility, automation, and reporting. | จัดกลุ่มสมาชิกด้วยแท็กและ persona เพื่อใช้กับสิทธิ์ automation และการรายงาน | [] |
| loyalty.persona.user_types | User types | ประเภทผู้ใช้ (User types) | Use structural user types (for example buyer vs seller) in rules and tier ladders. | ใช้ประเภทผู้ใช้เชิงโครงสร้าง (เช่น ผู้ซื้อ/ผู้ขาย) ในกฎและบันได Tier | [] |
| loyalty.persona.entitlements | Persona entitlements | สิทธิพิเศษตาม persona | Grant a persona extra access or benefits beyond normal tags. | ให้ persona ได้สิทธิหรือการเข้าถึงเพิ่ม นอกเหนือแท็กทั่วไป | [] |
| loyalty.store.master | Store master | ข้อมูลร้าน (Store master) | Maintain outlets used for earning, redemption, and reporting. | ดูแลสาขาที่ใช้กับการได้คะแนน การแลก และการรายงาน | [] |
| loyalty.store.attributes | Store attribute classification | จัดหมวดแอตทริบิวต์ร้าน | Classify stores by channel, region, or business attributes for rules. | จัดประเภทร้านตามช่องทาง ภูมิภาค หรือคุณลักษณะธุรกิจเพื่อใช้กับกฎ | [] |
| loyalty.frontline.customer_360 | Customer 360 / Front Line | Customer 360 / Front Line | Give staff a Customer 360 view: status, tier progress, history, and member context. | ให้พนักงานเห็นมุมมอง Customer 360: สถานะ ความคืบหน้า Tier ประวัติ และบริบทสมาชิก | [] |
| loyalty.frontline.assisted_actions | Front Line assisted actions | การช่วยเหลือใน Front Line | Staff help a member from Front Line: adjust points, push a reward, or mark a reward used. | พนักงานช่วยสมาชิกจาก Front Line ได้: ปรับคะแนน ส่งของรางวัล หรือทำเครื่องหมายใช้แล้ว | [] |
| loyalty.analytics.reports | Loyalty analytics reports | รายงาน analytics ของ loyalty | Use 30+ reports across purchases, points, redemptions, campaigns, and members. | ใช้รายงานกว่า 30 ฉบับครอบคลุมการซื้อ คะแนน การแลก Campaign และสมาชิก | [] |
| loyalty.analytics.rfm | RFM scoring | คะแนน RFM | Score members by how recently, how often, and how much they buy — for targeting. | ให้คะแนนสมาชิกจากความใกล้ ความถี่ และมูลค่าการซื้อ เพื่อใช้กำหนดเป้า | [] |
| loyalty.analytics.funnel | Funnel stages | ขั้น Funnel | Define journey stages and report conversion between them. | กำหนดขั้นใน journey และรายงาน conversion ระหว่างขั้น | [] |
| loyalty.ops.customer_import_export | Customer import / export | นำเข้า / ส่งออกสมาชิก | Bulk import or export member profiles for migrations and operations. | นำเข้าหรือส่งออกโปรไฟล์สมาชิกเป็นชุด สำหรับย้ายระบบและการดำเนินงาน | [] |
| loyalty.ops.bulk_currency_import | Bulk currency import | นำเข้าคะแนน/ตั๋วเป็นชุด | Bulk load points or tickets for migrations or campaigns. | โหลดคะแนนหรือ tickets จำนวนมากสำหรับย้ายระบบหรือแคมเปญ | [] |
| loyalty.storefront.shopify_widget | Shopify loyalty widget | Widget loyalty บน Shopify | Show member loyalty status on the Shopify storefront. | แสดงสถานะ loyalty ของสมาชิกบนหน้าร้าน Shopify | [] |
| loyalty.storefront.shopify_burn | Shopify points-to-discount | ใช้คะแนนเป็นส่วนลดบน Shopify | Let members burn points to a discount in Shopify checkout journeys. | ให้สมาชิกใช้คะแนนเป็นส่วนลดใน journey checkout ของ Shopify | [] |
| loyalty.stored_value.cards | Stored value cards | บัตรมูลค่าเก็บเงิน (Stored value) | Issue prepaid cash-equivalent cards with a monetary balance. | ออกบัตรเติมเงินที่มียอดเทียบเท่าเงินสด | [] |
| loyalty.stored_value.store_credit | Store credit | Store credit | Issue promo or store-credit balances that stay separate from points. | ออกยอดเครดิตโปรโมหรือร้าน ที่แยกจากคะแนน | [] |
| loyalty.event_promo.engine | Event promotion engine | เอนจินโปรโมชันอีเวนต์ | Run event-specific freebies or discounts with claim mappings. | จัดของแถมหรือส่วนลดเฉพาะอีเวนต์ พร้อมการจับคู่สิทธิ์เคลม | [] |
| loyalty.integrations.open_api | Loyalty Open API | Loyalty Open API | Partners call APIs for users, wallet, purchases, redemptions, and assets. | พาร์ทเนอร์เรียก API สำหรับผู้ใช้ wallet การซื้อ การแลก และ assets | [] |
| marketing_automation.workflows.multi_step | Multi-step workflow automation | Workflow อัตโนมัติหลายขั้น | Marketers build fixed journeys that react to events, wait, branch, send messages, and run loyalty actions. | นักการตลาดสร้าง journey แบบกำหนดไว้ ที่ตอบอีเวนต์ รอ แยกทาง ส่งข้อความ และทำ action ฝั่ง loyalty | [] |
| marketing_automation.workflows.audiences | Audience membership automation | Automation สมาชิกใน Audience | Maintain dynamic or static audiences and use join/leave as workflow triggers and targeting. | ดูแล audience แบบ dynamic หรือ static แล้วใช้การเข้า/ออกเป็นทริกเกอร์และเป้าของ Workflow | [] |
| marketing_automation.ai_decisioning.agent | AI decisioning agent | AI decisioning agent | Set goals, allowed actions, outcomes, and constraints; the agent chooses ACT, WAIT, or SKIP per member. | ตั้งเป้า action ที่อนุญาต ผลลัพธ์ และข้อจำกัด แล้ว agent เลือกระหว่าง ACT, WAIT หรือ SKIP รายสมาชิก | [] |
| marketing_automation.ai_analysis.recommendations | AI analysis and recommendations | AI วิเคราะห์และแนะนำ | Analyze workflow and agent results, then recommend what marketers should change next. | วิเคราะห์ผล Workflow และ agent แล้วแนะนำว่านักการตลาดควรปรับอะไรต่อ | [] |
| customer_service.connectivity.omnichannel_inbox | Omnichannel unified inbox | Inbox รวม Omnichannel | Agents work one inbox across connected channels with one customer record. | เอเจนต์ทำงานใน inbox เดียวข้ามช่องทางที่เชื่อม พร้อมบันทึกลูกค้าเดียวกัน | [] |
| customer_service.connectivity.channel_connectors | Channel connectors | ตัวเชื่อมช่องทาง | Connect marketplaces, messaging apps, email, web, SMS, and related surfaces into CS. | เชื่อม marketplace แอปแชท อีเมล เว็บ SMS และช่องทางเกี่ยวข้องเข้าสู่ CS | [] |
| customer_service.connectivity.phone_numbers | Phone number management | จัดการหมายเลขโทรศัพท์ | Provision and manage phone numbers used for voice and SMS service. | จัดเตรียมและดูแลเบอร์ที่ใช้กับ voice และ SMS ในบริการลูกค้า | [] |
| customer_service.chat_voice.chat | Chat conversations | บทสนทนา Chat | Handle async chat with full history and agent tools. | รับเรื่องแชทแบบ asynchronous พร้อมประวัติเต็มและเครื่องมือของเอเจนต์ | [] |
| customer_service.chat_voice.voice | Voice console | คอนโซล Voice | Handle voice contacts with the same customer context used for chat. | รับสายด้วยบริบทลูกค้าชุดเดียวกับที่ใช้กับแชท | [] |
| customer_service.agent_productivity.quick_replies | Quick replies | Quick replies | Agents insert approved reply snippets for faster, consistent answers. | เอเจนต์แทรกข้อความตอบที่อนุมัติแล้ว เพื่อตอบเร็วและโทนสม่ำเสมอ | [] |
| customer_service.agent_productivity.knowledge_search | Knowledge search for agents | ค้นหา Knowledge สำหรับเอเจนต์ | Agents search the knowledge base while handling a live conversation. | เอเจนต์ค้นหา knowledge base ระหว่างคุยกับลูกค้าสด ๆ | [] |
| customer_service.agent_productivity.live_assist | Live assist | Live assist | Suggest replies and context to agents mid-conversation. | ช่วยเอเจนต์ระหว่างสนทนาด้วยข้อความแนะนำและบริบท | [] |
| customer_service.routing_workflows.routing | Routing and assignment | Routing และการมอบหมาย | Route conversations to queues, skills, or agents based on rules. | ส่งต่อบทสนทนาไปคิว ทักษะ หรือเอเจนต์ตามกฎ | [] |
| customer_service.routing_workflows.chatbot_flows | Chatbot flows | Chatbot flows | Run visual chatbot workflows before or beside human agents. | รัน chatbot workflow แบบมองเห็นขั้นตอน ก่อนหรือควบคู่เอเจนต์คน | [] |
| customer_service.analytics.service_analytics | Service analytics | Service analytics | Report volume, response times, CSAT, containment, and agent productivity. | รายงานปริมาณบทสนทนา เวลาตอบ CSAT containment และผลิตภาพเอเจนต์ | [] |
| customer_service.ai_agent.brand_ai | AI service agent | AI service agent | Brand-configured AI handles or assists conversations under tone, language, and escalation rules. | AI ที่ตั้งค่าตามแบรนด์ รับหรือช่วยคุยภายใต้กฎโทน ภาษา และการส่งต่อคน | [] |
| customer_service.aop_actions.aops | Agent operating procedures (AOPs) | Agent operating procedures (AOPs) | Define per-intent procedures the AI follows when resolving issues. | กำหนดขั้นตอนตาม intent ที่ AI ต้องทำตามเมื่อแก้ปัญหาลูกค้า | [] |
| customer_service.aop_actions.knowledge_base | Knowledge base | Knowledge base | Store and retrieve service knowledge with citations for agents and AI. | เก็บและดึงความรู้บริการ พร้อม citation สำหรับเอเจนต์และ AI | [] |
| customer_service.aop_actions.customer_actions | Customer actions | Customer actions | Run permitted lookups, loyalty actions, or integrations from service flows. | สั่ง lookup, action ฝั่ง loyalty หรืออินทิเกรชันที่อนุญาตจาก flow บริการ | [] |
| customer_service.supervisor_ai.quality_scoring | Quality scoring | คะแนนคุณภาพ (Quality scoring) | Score human and AI conversations for quality, policy adherence, and coaching signals. | ให้คะแนนบทสนทนาของคนและ AI ด้านคุณภาพ การทำตามนโยบาย และสัญญาณสำหรับโค้ช | [] |
| customer_service.supervisor_ai.watchtower | Supervisor AI / Watchtower | Supervisor AI / Watchtower | Supervisor review of AI and human cases that feeds prompt/AOP improvement. | รีวิวโดย supervisor ที่ตรวจเคส AI และคน แล้วป้อนกลับเพื่อปรับ prompt/AOP | [] |

## Apply order (after approval)

1. `apply_migration` for commercial columns + checks.
2. One transaction: move `loyalty.forms.signup_form` → `platform.signup`; UPDATE all name/summary/name_th/summary_th/includes/commercial_nature/consumption_unit; append change-log rows.
3. Reconcile package membership later if consumption campaigns should leave `loyalty_core` (separate pricing decision).

## Open questions for you

1. Confirm commercial tags marked **flag** (AI agents, live assist, phone numbers, event promo, Shopify, stored value).
2. Confirm campaigns currently in `loyalty_core` stay package-listed but meter as `consumption` (recommended), or should leave core package.
3. Approve schema + apply rewrite to live catalog?
