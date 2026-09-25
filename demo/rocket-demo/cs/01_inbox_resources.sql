-- Rocket Demo CS inbox Content Panel seed
-- Merchant: rocket-demo / fae172a5-de90-440e-a766-db6a5982cc9b
-- Idempotent on resource_code / category_name for this merchant.

DO $$
DECLARE
  v_mid uuid := 'fae172a5-de90-440e-a766-db6a5982cc9b';
  v_cat_greet uuid;
  v_cat_orders uuid;
  v_cat_clinic uuid;
  v_cat_product uuid;
BEGIN
  -- Categories (no unique constraint — select-then-insert)
  SELECT id INTO v_cat_greet FROM resource_content_category
  WHERE merchant_id = v_mid AND category_name = 'Greeting & Closing' LIMIT 1;
  IF v_cat_greet IS NULL THEN
    INSERT INTO resource_content_category (merchant_id, category_name, sort_order, is_active)
    VALUES (v_mid, 'Greeting & Closing', 10, true) RETURNING id INTO v_cat_greet;
  END IF;

  SELECT id INTO v_cat_orders FROM resource_content_category
  WHERE merchant_id = v_mid AND category_name = 'Orders & Shipping' LIMIT 1;
  IF v_cat_orders IS NULL THEN
    INSERT INTO resource_content_category (merchant_id, category_name, sort_order, is_active)
    VALUES (v_mid, 'Orders & Shipping', 20, true) RETURNING id INTO v_cat_orders;
  END IF;

  SELECT id INTO v_cat_clinic FROM resource_content_category
  WHERE merchant_id = v_mid AND category_name = 'Clinic Booking' LIMIT 1;
  IF v_cat_clinic IS NULL THEN
    INSERT INTO resource_content_category (merchant_id, category_name, sort_order, is_active)
    VALUES (v_mid, 'Clinic Booking', 30, true) RETURNING id INTO v_cat_clinic;
  END IF;

  SELECT id INTO v_cat_product FROM resource_content_category
  WHERE merchant_id = v_mid AND category_name = 'Product & Promo' LIMIT 1;
  IF v_cat_product IS NULL THEN
    INSERT INTO resource_content_category (merchant_id, category_name, sort_order, is_active)
    VALUES (v_mid, 'Product & Promo', 40, true) RETURNING id INTO v_cat_product;
  END IF;

  -- Helper: delete prior seed by code then insert
  DELETE FROM resource_content
  WHERE merchant_id = v_mid
    AND resource_code LIKE 'RKT-%';

  -- Quick replies
  INSERT INTO resource_content (
    merchant_id, resource_type, resource_code, name, content,
    category_id, language, search_tags, is_active, sort_order, trigger_patterns, metadata
  ) VALUES
  (v_mid, 'quick_reply', 'RKT-QR-WELCOME', 'Welcome Greeting',
   E'สวัสดีค่ะ ยินดีต้อนรับสู่ Rocket Clinic & Rocket Club ค่ะ\nดิฉันยินดีช่วยเรื่องแพ็กเกจคลินิก สินค้าสกินแคร์ ออเดอร์ และการนัดหมาย\nรบกวนแจ้งชื่อและสิ่งที่ต้องการให้ช่วยได้เลยค่ะ',
   v_cat_greet, 'th', ARRAY['greeting','welcome'], true, 10,
   ARRAY['สวัสดี','hello','hi','ยินดีต้อนรับ'], '{"seed":"SEED-RKT-CS"}'::jsonb),

  (v_mid, 'quick_reply', 'RKT-QR-ASK-ORDER', 'Ask for Order Number',
   E'เพื่อตรวจสอบสถานะให้ถูกต้อง รบกวนส่งเลขที่คำสั่งซื้อค่ะ\n(เช่น RKT-ORD-123456 หรือเลขจาก Shopee/Lazada/TikTok)\nและแจ้งช่องทางที่สั่งซื้อด้วยนะคะ',
   v_cat_orders, 'th', ARRAY['order','tracking'], true, 20,
   ARRAY['order number','เลขออเดอร์','tracking'], '{"seed":"SEED-RKT-CS"}'::jsonb),

  (v_mid, 'quick_reply', 'RKT-QR-TRACKING', 'Tracking Status Template',
   E'ตรวจพบออเดอร์ของคุณแล้วค่ะ\n• สถานะ: {{status}}\n• ผู้ขนส่ง: {{carrier}}\n• Tracking: {{tracking_number}}\n• ประมาณการจัดส่ง: {{eta}}\nติดตามพัสดุได้ที่ {{tracking_url}} ค่ะ',
   v_cat_orders, 'th', ARRAY['shipping','tracking'], true, 30,
   ARRAY['track','สถานะพัสดุ','tracking'], '{"seed":"SEED-RKT-CS"}'::jsonb),

  (v_mid, 'quick_reply', 'RKT-QR-PKG-INTRO', 'Clinic Package Options Intro',
   E'Rocket Clinic มีแพ็กเกจยอดนิยมดังนี้ค่ะ\n1) Skin Analysis — วิเคราะห์ผิว 45 นาที\n2) Glow Laser Basic — เลเซอร์ผิวกระจ่างใส\n3) Wellness Skin Checkup — ตรวจสุขภาพผิวเชิงลึก\nบอกอาการหรือเป้าหมายผิวได้เลย จะช่วยแนะนำแพ็กเกจที่เหมาะค่ะ',
   v_cat_clinic, 'th', ARRAY['clinic','package','booking'], true, 40,
   ARRAY['แพ็กเกจ','จองคิว','นัดแพทย์','laser','clinic'], '{"seed":"SEED-RKT-CS"}'::jsonb),

  (v_mid, 'quick_reply', 'RKT-QR-ASK-TIME', 'Ask Preferred Appointment Time',
   E'แพ็กเกจที่แนะนำคือ {{package_name}} ค่ะ\nรบกวนแจ้งวันและช่วงเวลาที่สะดวก (เช่น พุธหน้า ช่วงบ่าย)\nคลินิกเปิด จ–อา 10:00–20:00 ที่สาขา Siam Paragon และ EmQuartier ค่ะ',
   v_cat_clinic, 'th', ARRAY['clinic','schedule'], true, 50,
   ARRAY['เวลานัด','วันไหนว่าง','appointment time'], '{"seed":"SEED-RKT-CS"}'::jsonb),

  (v_mid, 'quick_reply', 'RKT-QR-BOOK-OK', 'Booking Confirmed',
   E'ยืนยันการนัดหมายเรียบร้อยค่ะ\n• แพ็กเกจ: {{package_name}}\n• วันเวลา: {{slot}}\n• สาขา: {{branch}}\n• รหัสจอง: {{booking_ref}}\nกรุณามาก่อนเวลานัด 15 นาที และงดสครับแรง 24 ชม.ก่อนทำหัตถการค่ะ',
   v_cat_clinic, 'th', ARRAY['clinic','booking','confirm'], true, 60,
   ARRAY['จองสำเร็จ','booking confirmed','รหัสจอง'], '{"seed":"SEED-RKT-CS"}'::jsonb),

  (v_mid, 'quick_reply', 'RKT-QR-MEDICAL', 'Medical Boundary Handoff',
   E'ขออภัยค่ะ ดิฉันไม่สามารถให้คำวินิจฉัย แนะนำยา หรือแปลผลแล็บได้\nหากต้องการคำปรึกษาจากแพทย์/ผู้เชี่ยวชาญ ดิฉันช่วยจองคิวที่ Rocket Clinic หรือโอนเรื่องให้ทีมผู้เชี่ยวชาญดูแลต่อได้เลยค่ะ\nต้องการให้จองนัด หรือโอนต่อคะ?',
   v_cat_clinic, 'th', ARRAY['medical','escalate','safety'], true, 70,
   ARRAY['เป็นอะไร','กินยาอะไร','วินิจฉัย','diagnosis','prescribe'], '{"seed":"SEED-RKT-CS"}'::jsonb),

  (v_mid, 'quick_reply', 'RKT-QR-PROMO', 'Current Promo Blurb',
   E'โปรโมชัน Rocket Club ช่วงนี้ค่ะ\n• ซื้อสกินแคร์ครบ ฿1,500 รับส่วนลด 10%\n• สมาชิก Gold ขึ้นไป แลกแต้มคูณ 1.5x ที่คลินิก\n• แพ็กเกจ Skin Analysis จองออนไลน์ลด ฿200\nสนใจโปรไหนเป็นพิเศษไหมคะ?',
   v_cat_product, 'th', ARRAY['promo','points'], true, 80,
   ARRAY['โปร','ส่วนลด','promo','campaign'], '{"seed":"SEED-RKT-CS"}'::jsonb),

  (v_mid, 'quick_reply', 'RKT-QR-CLOSE-OK', 'Closing - Issue Resolved',
   E'ยินดีที่ช่วยได้ค่ะ หากมีคำถามเพิ่มเติมเกี่ยวกับสินค้า คลินิก หรือออเดอร์ ทักมาได้ตลอดนะคะ\nขอบคุณที่เป็นลูกค้า Rocket Club ค่ะ ✨',
   v_cat_greet, 'th', ARRAY['closing'], true, 90,
   ARRAY['ขอบคุณ','resolved','ปิดเคส'], '{"seed":"SEED-RKT-CS"}'::jsonb),

  (v_mid, 'quick_reply', 'RKT-QR-CLOSE-PEND', 'Closing - Pending Follow-up',
   E'ได้รับเรื่องไว้แล้วค่ะ ทีมจะอัปเดตให้ภายใน 1 วันทำการ\nหากมีเอกสาร/รูปเพิ่มเติม ส่งมาในแชทนี้ได้เลยค่ะ',
   v_cat_greet, 'th', ARRAY['closing','pending'], true, 100,
   ARRAY['รออัปเดต','follow up','pending'], '{"seed":"SEED-RKT-CS"}'::jsonb),

  (v_mid, 'quick_reply', 'RKT-QR-RETURN', 'Return Policy One-liner',
   E'สินค้าที่ยังไม่เปิดซีล คืน/เปลี่ยนได้ภายใน 7 วันหลังได้รับของ (ช่องทางออนไลน์) หรือ 14 วันหากซื้อหน้าร้าน\nสินค้าเปิดใช้แล้วรับคืนเฉพาะกรณีชำรุดจากผู้ผลิตค่ะ\nส่งเลขออเดอร์มาได้เลย จะช่วยตรวจสิทธิ์ให้ค่ะ',
   v_cat_orders, 'th', ARRAY['return','policy'], true, 110,
   ARRAY['คืนสินค้า','เปลี่ยนสินค้า','return'], '{"seed":"SEED-RKT-CS"}'::jsonb),

  (v_mid, 'quick_reply', 'RKT-QR-VERIFY', 'Verify Customer Identity',
   E'เพื่อความปลอดภัยของข้อมูล รบกวนยืนยันตัวตนด้วยค่ะ\n• ชื่อ-นามสกุลที่ใช้สมัครสมาชิก\n• เบอร์โทรศัพท์ที่ผูกกับบัญชี\nหรือเลขสมาชิก Rocket Club (ถ้ามี) ค่ะ',
   v_cat_greet, 'th', ARRAY['identity','verify'], true, 15,
   ARRAY['ยืนยันตัวตน','verify','เบอร์โทร'], '{"seed":"SEED-RKT-CS"}'::jsonb),

  (v_mid, 'quick_reply', 'RKT-QR-LAYER', 'Skincare Layering Tip',
   E'ลำดับเลเยอร์สกินแคร์แนะนำค่ะ\n1) Cleanser 2) Toner 3) Serum (บางก่อนหนา) 4) Moisturizer 5) SPF (กลางวัน)\nหลีกเลี่ยง Vitamin C คู่ Retinol ในเวลาเดียวกัน — ใช้ C เช้า / Retinol ค่ำ\nสนใจตัวไหนเป็นพิเศษ เช่น GlowLab Niacinamide หรือ AgeSoft Retinol ไหมคะ?',
   v_cat_product, 'th', ARRAY['skincare','howto'], true, 120,
   ARRAY['layering','ลำดับใช้','ใช้ยังไง'], '{"seed":"SEED-RKT-CS"}'::jsonb);

  -- Rich content cards
  INSERT INTO resource_content (
    merchant_id, resource_type, resource_code, name, content,
    rich_content, category_id, language, search_tags, is_active, sort_order, metadata
  ) VALUES
  (v_mid, 'rich_content', 'RKT-RC-CLINIC-MENU', 'Clinic Package Menu',
   'Rocket Clinic package menu cards',
   jsonb_build_object('blocks', jsonb_build_array(jsonb_build_object(
     'type', 'carousel',
     'items', jsonb_build_array(
       jsonb_build_object('type','card','title','Skin Analysis','subtitle','วิเคราะห์ผิว 45 นาที','badge','Popular',
         'fields', jsonb_build_array(
           jsonb_build_object('label','Price','value','฿1,490'),
           jsonb_build_object('label','Duration','value','45 min')
         )),
       jsonb_build_object('type','card','title','Glow Laser Basic','subtitle','เลเซอร์ผิวกระจ่างใส','badge','Clinic Pick',
         'fields', jsonb_build_array(
           jsonb_build_object('label','Price','value','฿3,900'),
           jsonb_build_object('label','Duration','value','60 min')
         )),
       jsonb_build_object('type','card','title','Wellness Skin Checkup','subtitle','ตรวจสุขภาพผิวเชิงลึก','badge','New',
         'fields', jsonb_build_array(
           jsonb_build_object('label','Price','value','฿2,490'),
           jsonb_build_object('label','Duration','value','75 min')
         ))
     )
   ))),
   v_cat_clinic, 'th', ARRAY['clinic','packages'], true, 10, '{"seed":"SEED-RKT-CS"}'::jsonb),

  (v_mid, 'rich_content', 'RKT-RC-BOOK-CONFIRM', 'Booking Confirmation Card',
   'Appointment confirmation card template',
   jsonb_build_object('blocks', jsonb_build_array(jsonb_build_object(
     'type', 'card',
     'title', 'นัดหมายยืนยันแล้ว',
     'subtitle', 'Rocket Clinic',
     'fields', jsonb_build_array(
       jsonb_build_object('label','Package','value','{{package_name}}'),
       jsonb_build_object('label','When','value','{{slot}}'),
       jsonb_build_object('label','Branch','value','{{branch}}'),
       jsonb_build_object('label','Ref','value','{{booking_ref}}')
     )
   ))),
   v_cat_clinic, 'th', ARRAY['clinic','booking'], true, 20, '{"seed":"SEED-RKT-CS"}'::jsonb),

  (v_mid, 'rich_content', 'RKT-RC-BESTSELLERS', 'Bestseller Product Cards',
   'Top Rocket Club skincare bestsellers',
   jsonb_build_object('blocks', jsonb_build_array(jsonb_build_object(
     'type', 'carousel',
     'items', jsonb_build_array(
       jsonb_build_object('type','card','title','GlowLab Niacinamide Bright Serum 30ml','subtitle','Brightening','badge','#1',
         'fields', jsonb_build_array(jsonb_build_object('label','Price','value','฿890'))),
       jsonb_build_object('type','card','title','AgeSoft Retinol Night Repair 30ml','subtitle','Night repair','badge','Hero',
         'fields', jsonb_build_array(jsonb_build_object('label','Price','value','฿1,190'))),
       jsonb_build_object('type','card','title','RiceGlow Gentle Rice Cleansing Foam 150ml','subtitle','Daily cleanse','badge','Starter',
         'fields', jsonb_build_array(jsonb_build_object('label','Price','value','฿390')))
     )
   ))),
   v_cat_product, 'th', ARRAY['product','bestsellers'], true, 30, '{"seed":"SEED-RKT-CS"}'::jsonb),

  (v_mid, 'rich_content', 'RKT-RC-ROUTINE', 'Morning Skincare Routine',
   'Suggested AM routine for Rocket Club',
   jsonb_build_object('blocks', jsonb_build_array(jsonb_build_object(
     'type', 'card',
     'title', 'Morning Routine',
     'subtitle', 'Cleanse → Treat → Protect',
     'fields', jsonb_build_array(
       jsonb_build_object('label','1','value','RiceGlow Gentle Rice Cleansing Foam'),
       jsonb_build_object('label','2','value','GlowLab Niacinamide Bright Serum'),
       jsonb_build_object('label','3','value','AquaLayer Hyaluronic Moisture Ampoule'),
       jsonb_build_object('label','4','value','SPF (Protect) — every morning')
     )
   ))),
   v_cat_product, 'en', ARRAY['routine','howto'], true, 40, '{"seed":"SEED-RKT-CS"}'::jsonb),

  (v_mid, 'rich_content', 'RKT-RC-PROMO', 'Active Promo Card',
   'Current Rocket Club promotions',
   jsonb_build_object('blocks', jsonb_build_array(jsonb_build_object(
     'type', 'card',
     'title', 'Rocket Club July Offers',
     'subtitle', 'Retail + Clinic',
     'badge', 'Limited',
     'fields', jsonb_build_array(
       jsonb_build_object('label','Retail','value','Spend ฿1,500 get 10% off'),
       jsonb_build_object('label','Clinic','value','Skin Analysis -฿200 online'),
       jsonb_build_object('label','Gold+','value','1.5x points at clinic')
     )
   ))),
   v_cat_product, 'en', ARRAY['promo'], true, 50, '{"seed":"SEED-RKT-CS"}'::jsonb),

  (v_mid, 'rich_content', 'RKT-RC-HOURS', 'Clinic Hours & Branches',
   'Rocket Clinic hours and locations',
   jsonb_build_object('blocks', jsonb_build_array(jsonb_build_object(
     'type', 'card',
     'title', 'Rocket Clinic Hours',
     'subtitle', 'Tue–Sun 10:00–20:00 (Closed Mon)',
     'fields', jsonb_build_array(
       jsonb_build_object('label','Siam Paragon','value','B1 Beauty Zone'),
       jsonb_build_object('label','EmQuartier','value','G Floor'),
       jsonb_build_object('label','Booking','value','LINE / phone / agent assist')
     )
   ))),
   v_cat_clinic, 'en', ARRAY['hours','location'], true, 60, '{"seed":"SEED-RKT-CS"}'::jsonb),

  (v_mid, 'rich_content', 'RKT-RC-RETURNS', 'Return & Exchange Guide',
   'Retail return guide card',
   jsonb_build_object('blocks', jsonb_build_array(jsonb_build_object(
     'type', 'card',
     'title', 'Returns & Exchanges',
     'fields', jsonb_build_array(
       jsonb_build_object('label','Online','value','7 days unopened'),
       jsonb_build_object('label','In-store','value','14 days unopened'),
       jsonb_build_object('label','Opened','value','Defects only')
     )
   ))),
   v_cat_orders, 'en', ARRAY['return'], true, 70, '{"seed":"SEED-RKT-CS"}'::jsonb);

  -- Links
  INSERT INTO resource_content (
    merchant_id, resource_type, resource_code, name, content, link_url,
    category_id, language, search_tags, is_active, sort_order, metadata
  ) VALUES
  (v_mid, 'link', 'RKT-LK-LOCATOR', 'Store & Clinic Locator',
   'Find Rocket Club stores and Rocket Clinic branches',
   'https://demo.rocket-club.example/locator',
   v_cat_clinic, 'en', ARRAY['location','store'], true, 10, '{"seed":"SEED-RKT-CS"}'::jsonb),
  (v_mid, 'link', 'RKT-LK-BOOK', 'Self-serve Booking (Demo)',
   'Demo booking page for clinic packages',
   'https://demo.rocket-club.example/clinic/book',
   v_cat_clinic, 'en', ARRAY['booking'], true, 20, '{"seed":"SEED-RKT-CS"}'::jsonb),
  (v_mid, 'link', 'RKT-LK-INGREDIENTS', 'Ingredient FAQ',
   'Product formula and ingredient explainers',
   'https://demo.rocket-club.example/ingredients',
   v_cat_product, 'en', ARRAY['ingredients','formula'], true, 30, '{"seed":"SEED-RKT-CS"}'::jsonb);

END $$;
