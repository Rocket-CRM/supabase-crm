-- Expand Rocket Demo CS inbox: multi-channel, Thai multi-step AI agentic + manual agent replies
-- Merchant: fae172a5-de90-440e-a766-db6a5982cc9b (rocket-demo)

DO $$
DECLARE
  v_merchant uuid := 'fae172a5-de90-440e-a766-db6a5982cc9b';
  v_cred_line uuid := 'f7561578-0b04-4f00-ab8a-53667a9cd7bd';
  v_cred_shopee uuid := 'eb9f11c6-4185-4c66-856f-d0dc9ae6a3be';
  v_cred_lazada uuid := 'b322a9aa-dedb-4e32-b80b-1dda1c60b9a4';
  v_cred_tiktok uuid := '0f55dc4c-ed76-41b1-9676-3fd28cda2b59';
  v_cred_fb uuid := 'ec01eddd-2585-4c8b-96e5-9b49fbe72a07';
  v_cred_ig uuid := '34c0c660-6c90-41cb-9061-d687a8971790';
  v_cred_wa uuid;
  v_cred_email uuid;
  v_cred_web uuid;

  v_proc_track uuid := '4dd6ee92-8554-4581-acb7-5cae97083053';
  v_proc_clinic uuid := '5151b4de-2c9a-4b8e-887a-6285cc925f2f';
  v_proc_ecom uuid := '4f80826e-aa0f-4c6b-b2b7-1e9ef57eb65a';
  v_proc_return uuid;
  v_proc_skin uuid;

  v_c uuid;
  v_cv uuid;
  v_existing int;
BEGIN
  SELECT count(*) INTO v_existing
  FROM cs_conversations
  WHERE merchant_id = v_merchant AND 'demo-seed-v2' = ANY(tags);
  IF v_existing > 0 THEN
    RAISE NOTICE 'demo-seed-v2 already present (%); skipping', v_existing;
    RETURN;
  END IF;

  INSERT INTO cs_procedures (
    merchant_id, name, description, trigger_intent, flexibility,
    raw_content, compiled_steps, config, guardrails, is_active, version
  )
  SELECT v_merchant, p.name, p.description, p.trigger_intent, p.flexibility,
         p.raw_content, p.compiled_steps, p.config, p.guardrails, true, 1
  FROM cs_procedures p
  WHERE p.merchant_id = '09b45463-3812-42fb-9c7f-9d43b6fd3eb9'
    AND p.name IN ('Return and Exchange Handler', 'Skin Reaction / Allergy Complaint Handler')
    AND NOT EXISTS (
      SELECT 1 FROM cs_procedures x
      WHERE x.merchant_id = v_merchant AND x.name = p.name
    );

  SELECT id INTO v_proc_return FROM cs_procedures
  WHERE merchant_id = v_merchant AND name = 'Return and Exchange Handler' LIMIT 1;
  SELECT id INTO v_proc_skin FROM cs_procedures
  WHERE merchant_id = v_merchant AND name = 'Skin Reaction / Allergy Complaint Handler' LIMIT 1;

  INSERT INTO merchant_credentials (merchant_id, service_name, credential_name, credentials, is_active, scope, merchant_code)
  VALUES (v_merchant, 'whatsapp', 'Rocket Demo WhatsApp (Demo)', '{}'::jsonb, true, ARRAY['cs']::text[], 'rocket-demo')
  RETURNING id INTO v_cred_wa;

  INSERT INTO merchant_credentials (merchant_id, service_name, credential_name, credentials, is_active, scope, merchant_code)
  VALUES (v_merchant, 'email', 'Rocket Demo Email (Demo)', '{}'::jsonb, true, ARRAY['cs']::text[], 'rocket-demo')
  RETURNING id INTO v_cred_email;

  INSERT INTO merchant_credentials (merchant_id, service_name, credential_name, credentials, is_active, scope, merchant_code)
  VALUES (v_merchant, 'web_chat', 'Rocket Demo Web Chat (Demo)', '{}'::jsonb, true, ARRAY['cs']::text[], 'rocket-demo')
  RETURNING id INTO v_cred_web;

  ALTER TABLE cs_messages DISABLE TRIGGER trg_cs_messages_deliver_outbound;

  -- 1) LINE — AI multi-step order tracking (Thai)
  INSERT INTO cs_contacts (merchant_id, display_name, phone, language, tags, custom_fields, first_contact_at, last_contact_at)
  VALUES (v_merchant, 'น้องฟ้า', '086-112-3344', 'th', ARRAY['demo-seed-2026','demo-seed-v2','tracking']::text[], '{"demo_seed":true}'::jsonb, now()-interval '90 minutes', now()-interval '12 minutes')
  RETURNING id INTO v_c;

  INSERT INTO cs_platform_identities (merchant_id, contact_id, platform_type, platform_user_id, platform_display_name, linked_at)
  VALUES (v_merchant, v_c, 'line', 'line_demo_fah_01', 'น้องฟ้า', now()-interval '90 minutes');

  INSERT INTO cs_conversations (
    merchant_id, credential_id, contact_id, modality, status, priority, intent, tags,
    platform_conversation_id, last_message_at, created_at,
    active_procedure_id, procedure_state
  ) VALUES (
    v_merchant, v_cred_line, v_c, 'chat', 'open', 'normal', 'order_tracking',
    ARRAY['demo-seed-2026','demo-seed-v2','ai-agentic']::text[],
    'demo_rd_v2_line_track_fah', now()-interval '12 minutes', now()-interval '90 minutes',
    v_proc_track,
    jsonb_build_object(
      'intent','order_tracking',
      'procedure_id', v_proc_track,
      'procedure_name','Order Tracking Handler',
      'current_step', 3,
      'started_at', (now()-interval '90 minutes'),
      'data_collected', jsonb_build_object(
        'order_number','RB-260722-8841',
        'platform','line_shop',
        'carrier','Kerry',
        'tracking_no','KY123998812TH',
        'status','out_for_delivery'
      ),
      'actions_taken', jsonb_build_array('Lookup Order','Get Tracking')
    )
  ) RETURNING id INTO v_cv;

  INSERT INTO cs_messages (conversation_id, sender_type, content, message_type, created_at) VALUES
    (v_cv, 'contact', 'สวัสดีค่ะ อยากเช็คสถานะออเดอร์หน่อย', 'text', now()-interval '90 minutes'),
    (v_cv, 'ai', 'สวัสดีค่ะคุณฟ้า 😊 แอดมิน AI ช่วยเช็คให้ได้เลยค่ะ รบกวนเลขออเดอร์หน่อยนะคะ (ขึ้นต้นด้วย RB- ได้เลย)', 'text', now()-interval '89 minutes'),
    (v_cv, 'contact', 'RB-260722-8841 ค่ะ', 'text', now()-interval '85 minutes'),
    (v_cv, 'ai', 'ได้รับเลข RB-260722-8841 แล้วค่ะ กำลังค้นหาในระบบ… พบออเดอร์ Shield SPF50+ Clear 1 ชิ้น สั่งผ่าน LINE SHOP เมื่อวานนี้ สถานะตอนนี้คือ “กำลังจัดส่ง” ค่ะ สั่งจากช่องทางไหนเพิ่มเติมไหมคะ หรือใช้เลขนี้พอ?', 'text', now()-interval '84 minutes'),
    (v_cv, 'contact', 'LINE SHOP ค่ะ มีเลขพัสดุไหม', 'text', now()-interval '70 minutes'),
    (v_cv, 'ai', 'มีค่ะ พัสดุเคอรี่ เลข KY123998812TH สถานะล่าสุด: คนขับกำลังนำจ่ายในพื้นที่ กทม. คาดถึงวันนี้ 16:00–20:00 น. ค่ะ ต้องการให้ส่งลิงก์ติดตามเพิ่มไหมคะ?', 'text', now()-interval '69 minutes'),
    (v_cv, 'contact', 'ส่งลิงก์ให้หน่อยค่ะ แล้วถ้าไม่ถึงวันนี้ทำไง', 'text', now()-interval '25 minutes'),
    (v_cv, 'ai', E'ลิงก์ติดตาม: https://th.kerryexpress.com/track?no=KY123998812TH\n\nถ้าไม่ถึงภายในวันนี้ ระบบจะอัปเดตเป็น “ล่าช้า” อัตโนมัติ และแอดมิน AI จะเปิดเคสชดเชยคูปอง ฿50 ให้โดยไม่ต้องแจ้งใหม่ค่ะ มีอย่างอื่นให้ช่วยต่อไหมคะ?', 'text', now()-interval '12 minutes');

  INSERT INTO cs_customer_memory (merchant_id, contact_id, category, key, value, confidence, source_conversation_id) VALUES
    (v_merchant, v_c, 'order', 'active_order', 'RB-260722-8841 Kerry KY123998812TH', 1.0, v_cv),
    (v_merchant, v_c, 'preference', 'channel', 'line', 0.9, v_cv);

  -- 2) LINE — Manual agent takeover
  INSERT INTO cs_contacts (merchant_id, display_name, phone, language, tags, custom_fields, first_contact_at, last_contact_at)
  VALUES (v_merchant, 'คุณแพท', '081-555-7788', 'th', ARRAY['demo-seed-2026','demo-seed-v2','vip','agent-manual']::text[], '{"demo_seed":true,"vip":true}'::jsonb, now()-interval '3 hours', now()-interval '20 minutes')
  RETURNING id INTO v_c;

  INSERT INTO cs_platform_identities (merchant_id, contact_id, platform_type, platform_user_id, platform_display_name, linked_at)
  VALUES (v_merchant, v_c, 'line', 'line_demo_pat_vip', 'คุณแพท', now()-interval '3 hours');

  INSERT INTO cs_conversations (
    merchant_id, credential_id, contact_id, modality, status, priority, intent, tags,
    platform_conversation_id, last_message_at, created_at
  ) VALUES (
    v_merchant, v_cred_line, v_c, 'chat', 'open', 'urgent', 'complaint',
    ARRAY['demo-seed-2026','demo-seed-v2','agent-manual']::text[],
    'demo_rd_v2_line_agent_pat', now()-interval '20 minutes', now()-interval '3 hours'
  ) RETURNING id INTO v_cv;

  INSERT INTO cs_messages (conversation_id, sender_type, content, message_type, created_at) VALUES
    (v_cv, 'contact', 'ผิดหวังมาก สั่ง Age Rewind ไป 2 ขวด ได้ของหมดอายุมา', 'text', now()-interval '3 hours'),
    (v_cv, 'ai', 'ขอโทษอย่างสูงค่ะคุณแพท เรื่องนี้สำคัญมาก ขอเลขออเดอร์และรูปวันหมดอายุบนหลอดหน่อยนะคะ จะเร่งตรวจสอบให้', 'text', now()-interval '2 hours 58 minutes'),
    (v_cv, 'contact', 'RB-260720-1102 รูปส่งแล้ว หมดอายุเดือนที่แล้ว!', 'text', now()-interval '2 hours 40 minutes'),
    (v_cv, 'ai', 'ยืนยันวันหมดอายุจากรูปแล้วค่ะ เคสนี้เกินอำนาจ AI กำลังโอนให้เจ้าหน้าที่ดูแลต่อทันที', 'text', now()-interval '2 hours 38 minutes'),
    (v_cv, 'system', 'Conversation assigned to Agent Nicha', 'system', now()-interval '2 hours 37 minutes'),
    (v_cv, 'agent', E'คุณแพทคะ แอดมินนิชาดูแลต่อแล้วนะคะ ตรวจคลังพบล็อตผิดพลาดจริง ขออนุญาตดำเนินการดังนี้:\n1) รับคืนของเดิมโดยร้านออกไปรับฟรี\n2) ส่ง Age Rewind ล็อตใหม่ 2 ขวด ภายในพรุ่งนี้\n3) แถม Shield Travel Size + คืนแต้ม 500\nรบกวนยืนยันที่อยู่จัดส่งเดิมได้ไหมคะ', 'text', now()-interval '2 hours 30 minutes'),
    (v_cv, 'contact', 'ที่อยู่เดิมได้เลย ขอบคุณที่รับผิดชอบ', 'text', now()-interval '40 minutes'),
    (v_cv, 'agent', 'ยืนยันคิวรับของพรุ่งนี้ 10:00–12:00 น. แล้วค่ะ ส่งของใหม่พร้อมกัน Ticket #CS-85721 เปิดไว้ให้ติดตามได้ในแอป ถ้าต้องการใบกำกับภาษีบอกเพิ่มได้นะคะ', 'text', now()-interval '20 minutes');

  -- 3) Shopee — AI multi-step return (Thai)
  INSERT INTO cs_contacts (merchant_id, display_name, phone, language, tags, custom_fields, first_contact_at, last_contact_at)
  VALUES (v_merchant, 'เบลล์ช้อป', '089-221-0099', 'th', ARRAY['demo-seed-2026','demo-seed-v2','return']::text[], '{"demo_seed":true}'::jsonb, now()-interval '5 hours', now()-interval '45 minutes')
  RETURNING id INTO v_c;

  INSERT INTO cs_platform_identities (merchant_id, contact_id, platform_type, platform_user_id, platform_display_name, linked_at)
  VALUES (v_merchant, v_c, 'shopee', 'shopee_belle_992', 'เบลล์ช้อป', now()-interval '5 hours');

  INSERT INTO cs_conversations (
    merchant_id, credential_id, contact_id, modality, status, priority, intent, tags,
    platform_conversation_id, last_message_at, created_at,
    active_procedure_id, procedure_state
  ) VALUES (
    v_merchant, v_cred_shopee, v_c, 'chat', 'open', 'high', 'return_request',
    ARRAY['demo-seed-2026','demo-seed-v2','ai-agentic']::text[],
    'demo_rd_v2_shopee_return_belle', now()-interval '45 minutes', now()-interval '5 hours',
    v_proc_return,
    jsonb_build_object(
      'intent','return_request',
      'procedure_id', v_proc_return,
      'procedure_name','Return and Exchange Handler',
      'current_step', 4,
      'started_at', (now()-interval '5 hours'),
      'data_collected', jsonb_build_object(
        'order_number','24072399102',
        'reason','wrong_shade',
        'request_type','exchange',
        'product','Shield SPF50 Natural',
        'wanted_product','Shield SPF50 Clear',
        'photos_received', true,
        'eligible', true
      ),
      'actions_taken', jsonb_build_array('Lookup Order','Check Return Policy','Create Exchange Draft')
    )
  ) RETURNING id INTO v_cv;

  INSERT INTO cs_messages (conversation_id, sender_type, content, message_type, created_at) VALUES
    (v_cv, 'contact', 'ได้กันแดดโทน Natural มา แต่สั่ง Clear ค่ะ ขอเปลี่ยนได้ไหม', 'text', now()-interval '5 hours'),
    (v_cv, 'ai', 'ได้ค่ะคุณเบลล์ ช่วยยืนยันก่อนนะคะว่าต้องการ “เปลี่ยนสินค้า” หรือ “คืนเงิน” ดีคะ?', 'text', now()-interval '4 hours 58 minutes'),
    (v_cv, 'contact', 'ขอเปลี่ยนเป็น Clear ค่ะ', 'text', now()-interval '4 hours 50 minutes'),
    (v_cv, 'ai', 'รับทราบค่ะ เปลี่ยนเป็น Shield SPF50+ Clear รบกวนเลขออเดอร์ Shopee และส่งรูปสินค้า+ใบเสร็จในแชทหน่อยนะคะ', 'text', now()-interval '4 hours 49 minutes'),
    (v_cv, 'contact', 'ออเดอร์ 24072399102 ส่งรูปแล้ว', 'text', now()-interval '4 hours 20 minutes'),
    (v_cv, 'ai', E'ตรวจออเดอร์ 24072399102 แล้วค่ะ สั่ง Clear จริง แต่คลังส่ง Natural ผิด อยู่ในเงื่อนไขเปลี่ยนฟรีภายใน 14 วัน\nขั้นตอนถัดไป:\n1) ร้านออกเลขคืนพัสดุให้\n2) ส่ง Clear ไปก่อน ไม่ต้องรอของคืนถึง\nยืนยันที่อยู่เดิมบน Shopee ได้ไหมคะ?', 'text', now()-interval '4 hours 18 minutes'),
    (v_cv, 'contact', 'ที่อยู่เดิมได้เลยค่ะ', 'text', now()-interval '50 minutes'),
    (v_cv, 'ai', 'สร้างใบแลกเปลี่ยน EX-77201 แล้วค่ะ ส่ง Clear วันนี้ คาดถึง พรุ่งนี้–มะรืนนี้ และส่งเลขคืนพัสดุในแชทนี้ภายใน 1 ชม. ค่ะ มีอย่างอื่นให้ช่วยไหมคะ?', 'text', now()-interval '45 minutes');

  -- 4) Shopee — Manual agent
  INSERT INTO cs_contacts (merchant_id, display_name, language, tags, custom_fields, first_contact_at, last_contact_at)
  VALUES (v_merchant, 'ช้อปเปอร์มีน', 'th', ARRAY['demo-seed-2026','demo-seed-v2','agent-manual']::text[], '{"demo_seed":true}'::jsonb, now()-interval '6 hours', now()-interval '35 minutes')
  RETURNING id INTO v_c;

  INSERT INTO cs_platform_identities (merchant_id, contact_id, platform_type, platform_user_id, platform_display_name, linked_at)
  VALUES (v_merchant, v_c, 'shopee', 'shopee_meen_441', 'ช้อปเปอร์มีน', now()-interval '6 hours');

  INSERT INTO cs_conversations (
    merchant_id, credential_id, contact_id, modality, status, priority, tags,
    platform_conversation_id, last_message_at, created_at
  ) VALUES (
    v_merchant, v_cred_shopee, v_c, 'chat', 'open', 'high',
    ARRAY['demo-seed-2026','demo-seed-v2','agent-manual']::text[],
    'demo_rd_v2_shopee_agent_meen', now()-interval '35 minutes', now()-interval '6 hours'
  ) RETURNING id INTO v_cv;

  INSERT INTO cs_messages (conversation_id, sender_type, content, message_type, created_at) VALUES
    (v_cv, 'contact', 'เปิดกล่องมาได้แค่เซรั่ม ไม่มีกันแดดที่แถมในไลฟ์', 'text', now()-interval '6 hours'),
    (v_cv, 'contact', 'ออเดอร์ 24072355001 ค่ะ', 'text', now()-interval '5 hours 55 minutes'),
    (v_cv, 'ai', 'ขอโทษค่ะ กำลังเช็คโปรไลฟ์ให้ เคสแถมหายจะโอนเจ้าหน้าที่ยืนยันสต็อกให้ค่ะ', 'text', now()-interval '5 hours 54 minutes'),
    (v_cv, 'system', 'Handed off to Agent Beam', 'system', now()-interval '5 hours 50 minutes'),
    (v_cv, 'agent', 'คุณมีนค่ะ แอดมินบีมเช็คคำสั่งซื้อไลฟ์ 23 ก.ค. แล้ว ของแถม Shield mini ควรอยู่ในกล่องจริง ขออนุญาตส่งของแถมให้ใหม่ฟรี พร้อมโค้ด SHOPEE50 ใช้ครั้งถัดไป ยืนยันชื่อผู้รับกับเบอร์โทรใน Shopee ได้ไหมคะ?', 'text', now()-interval '5 hours 40 minutes'),
    (v_cv, 'contact', 'ชื่อมีน เบอร์ในแอปถูกแล้วค่ะ', 'text', now()-interval '1 hour'),
    (v_cv, 'agent', 'จัดส่งของแถมแล้วค่ะ เลขพัสดุ SPX2407239981 จะอัปเดตในแชทเมื่อเข้าระบบ คูปอง SHOPEE50 ใส่ในส่วนลดร้านได้ถึงสิ้นเดือน ขอบคุณที่รอและขออภัยอีกครั้งนะคะ', 'text', now()-interval '35 minutes');

  -- 5) Lazada — AI multi-step skin reaction (Thai)
  INSERT INTO cs_contacts (merchant_id, display_name, phone, email, language, tags, custom_fields, first_contact_at, last_contact_at)
  VALUES (v_merchant, 'มายด์.สกิน', '092-448-2211', 'mind.skin@example.com', 'th', ARRAY['demo-seed-2026','demo-seed-v2','allergy']::text[], '{"demo_seed":true}'::jsonb, now()-interval '4 hours', now()-interval '18 minutes')
  RETURNING id INTO v_c;

  INSERT INTO cs_platform_identities (merchant_id, contact_id, platform_type, platform_user_id, platform_display_name, linked_at)
  VALUES (v_merchant, v_c, 'lazada', 'lazada_mind_220', 'มายด์.สกิน', now()-interval '4 hours');

  INSERT INTO cs_conversations (
    merchant_id, credential_id, contact_id, modality, status, priority, intent, tags,
    platform_conversation_id, last_message_at, created_at,
    active_procedure_id, procedure_state
  ) VALUES (
    v_merchant, v_cred_lazada, v_c, 'chat', 'open', 'urgent', 'skin_reaction_complaint',
    ARRAY['demo-seed-2026','demo-seed-v2','ai-agentic']::text[],
    'demo_rd_v2_lazada_skin_mind', now()-interval '18 minutes', now()-interval '4 hours',
    v_proc_skin,
    jsonb_build_object(
      'intent','skin_reaction_complaint',
      'procedure_id', v_proc_skin,
      'procedure_name','Skin Reaction / Allergy Complaint Handler',
      'current_step', 5,
      'started_at', (now()-interval '4 hours'),
      'data_collected', jsonb_build_object(
        'product','Glow Serum 15%',
        'symptoms', jsonb_build_array('redness','itching'),
        'onset_hours', 6,
        'usage_stopped', true,
        'allergy_history', false,
        'order_number','LZ-88912044',
        'resolution_offered','refund_and_soothing_kit'
      ),
      'actions_taken', jsonb_build_array('Safety Triage','Lookup Order','Draft Refund')
    )
  ) RETURNING id INTO v_cv;

  INSERT INTO cs_messages (conversation_id, sender_type, content, message_type, created_at) VALUES
    (v_cv, 'contact', 'ใช้ Glow Serum แล้วหน้าแดงคันมาก กลัวแพ้', 'text', now()-interval '4 hours'),
    (v_cv, 'ai', 'ขอโทษที่ทำให้กังวลนะคะคุณมายด์ ปลอดภัยมาก่อนเสมอ — ตอนนี้หยุดใช้แล้วหรือยังคะ? และอาการแดงคันเริ่มเมื่อไหร่หลังทา?', 'text', now()-interval '3 hours 58 minutes'),
    (v_cv, 'contact', 'หยุดแล้ว แดงหลังทาประมาณ 6 ชม. ค่ะ', 'text', now()-interval '3 hours 50 minutes'),
    (v_cv, 'ai', E'ขอบคุณที่หยุดใช้ทันทีค่ะ ไม่แนะนำวินิจฉัยเองนะคะ ถ้าบวม หายใจลำบาก หรือผื่นลามเร็ว ให้พบแพทย์ฉุกเฉิน\n\nตอนนี้รบกวนบอกเพิ่ม:\n1) เคยแพ้วิตามินซี/fragrance ไหม\n2) เลขออเดอร์ Lazada\n3) มีรูปผื่นส่งได้ไหมคะ', 'text', now()-interval '3 hours 48 minutes'),
    (v_cv, 'contact', 'ไม่เคยแพ้ ค่ะ ออเดอร์ LZ-88912044 ส่งรูปแล้ว', 'text', now()-interval '3 hours 20 minutes'),
    (v_cv, 'ai', E'รับรูปและออเดอร์ LZ-88912044 แล้วค่ะ สินค้า Glow Serum 15% ซื้อเมื่อ 3 วันที่แล้ว ยังอยู่ในเงื่อนไขคืนเงินจากอาการแพ้\nขั้นตอนที่ AI ทำแล้ว:\n✓ ประเมินความเร่งด่วน (ไม่ฉุกเฉิน แต่ต้องดูแล)\n✓ ตรวจออเดอร์\n✓ ร่างคำขอคืนเงินเต็มจำนวน ฿890\n\nต้องการให้ดำเนินการคืนเงินเลย หรืออยากได้ชุดปลอบผิว Hydra mini แทนคะ?', 'text', now()-interval '3 hours 18 minutes'),
    (v_cv, 'contact', 'ขอคืนเงิน และอยากได้ชุดปลอบผิวด้วยได้ไหม', 'text', now()-interval '30 minutes'),
    (v_cv, 'ai', E'ได้ค่ะ อนุมัติคืนเงิน ฿890 เข้ากระเป๋า Lazada ใน 3–5 วัน และส่ง Hydra Soothing Kit ฟรี ไม่ต้องส่งคืนเซรั่ม\nคำแนะนำเบื้องต้น: ล้างน้ำเปล่า หลีกเลี่ยงแอคทีฟ 2–3 วัน หากอาการไม่ดีขึ้นใน 48 ชม. ควรพบแพทย์ผิวหนังนะคะ\nต้องการให้สรุปเป็นข้อความส่งแพทย์ไหมคะ?', 'text', now()-interval '18 minutes');

  -- 6) Lazada — Manual agent refund chase
  INSERT INTO cs_contacts (merchant_id, display_name, language, tags, custom_fields, first_contact_at, last_contact_at)
  VALUES (v_merchant, 'K.Ann Lazada', 'en', ARRAY['demo-seed-2026','demo-seed-v2','agent-manual']::text[], '{"demo_seed":true}'::jsonb, now()-interval '8 hours', now()-interval '55 minutes')
  RETURNING id INTO v_c;

  INSERT INTO cs_platform_identities (merchant_id, contact_id, platform_type, platform_user_id, platform_display_name, linked_at)
  VALUES (v_merchant, v_c, 'lazada', 'lazada_ann_88', 'K.Ann Lazada', now()-interval '8 hours');

  INSERT INTO cs_conversations (
    merchant_id, credential_id, contact_id, modality, status, priority, intent, tags,
    platform_conversation_id, last_message_at, created_at
  ) VALUES (
    v_merchant, v_cred_lazada, v_c, 'chat', 'open', 'high', 'refund',
    ARRAY['demo-seed-2026','demo-seed-v2','agent-manual']::text[],
    'demo_rd_v2_lazada_agent_ann', now()-interval '55 minutes', now()-interval '8 hours'
  ) RETURNING id INTO v_cv;

  INSERT INTO cs_messages (conversation_id, sender_type, content, message_type, created_at) VALUES
    (v_cv, 'contact', 'Refund for LZ-770012 still not in wallet after 6 days', 'text', now()-interval '8 hours'),
    (v_cv, 'ai', 'Sorry about the wait — I can see refund RF-44021 was approved. Connecting you to a specialist to chase Lazada wallet posting.', 'text', now()-interval '7 hours 58 minutes'),
    (v_cv, 'system', 'Assigned to Agent May', 'system', now()-interval '7 hours 55 minutes'),
    (v_cv, 'agent', 'Hi Ann, May here. I escalated with Lazada Pay. Reference PAY-992811. They confirmed wallet credit will post within 24h. I also added a ฿100 shop voucher on your account as apology. I will reply here once the credit shows.', 'text', now()-interval '7 hours 40 minutes'),
    (v_cv, 'contact', 'ok please update me', 'text', now()-interval '2 hours'),
    (v_cv, 'agent', 'Update: Lazada Pay shows credit processing now (txn LZP-558201). Should appear before tonight. Voucher code ANN100 is active for 14 days. Ping me if it is still missing tomorrow morning.', 'text', now()-interval '55 minutes');

  -- 7) TikTok — AI multi-step ecommerce (Thai)
  INSERT INTO cs_contacts (merchant_id, display_name, language, tags, custom_fields, first_contact_at, last_contact_at)
  VALUES (v_merchant, 'พลอยติดตาม', 'th', ARRAY['demo-seed-2026','demo-seed-v2','presale']::text[], '{"demo_seed":true}'::jsonb, now()-interval '7 hours', now()-interval '25 minutes')
  RETURNING id INTO v_c;

  INSERT INTO cs_platform_identities (merchant_id, contact_id, platform_type, platform_user_id, platform_display_name, linked_at)
  VALUES (v_merchant, v_c, 'tiktok', 'tt_ployfollow_11', 'พลอยติดตาม', now()-interval '7 hours');

  INSERT INTO cs_conversations (
    merchant_id, credential_id, contact_id, modality, status, priority, intent, tags,
    platform_conversation_id, last_message_at, created_at,
    active_procedure_id, procedure_state
  ) VALUES (
    v_merchant, v_cred_tiktok, v_c, 'chat', 'open', 'normal', 'place_order',
    ARRAY['demo-seed-2026','demo-seed-v2','ai-agentic']::text[],
    'demo_rd_v2_tt_ecom_ploy', now()-interval '25 minutes', now()-interval '7 hours',
    v_proc_ecom,
    jsonb_build_object(
      'intent','place_order',
      'procedure_id', v_proc_ecom,
      'procedure_name','Ecommerce Order Assistant',
      'current_step', 4,
      'started_at', (now()-interval '7 hours'),
      'data_collected', jsonb_build_object(
        'skin_type','oily_acne',
        'budget',1000,
        'goals', jsonb_build_array('acne','brightening'),
        'recommended', jsonb_build_array('Clear Cleanser','Glow Serum travel'),
        'cart_total', 890,
        'promo_code','TTGLOW10'
      ),
      'actions_taken', jsonb_build_array('Search Products','Apply Promo','Build Cart Link')
    )
  ) RETURNING id INTO v_cv;

  INSERT INTO cs_messages (conversation_id, sender_type, content, message_type, created_at) VALUES
    (v_cv, 'contact', 'ดูไลฟ์เมื่อกี้ อยากเริ่มดูแลสิว+ผิวหมอง งบไม่เกินพัน', 'text', now()-interval '7 hours'),
    (v_cv, 'ai', E'ได้เลยค่ะคุณพลอย 😊 ขอถามสั้นๆ เพื่อจัดเซ็ตให้ถูก\n1) ผิวประเภทไหน (มัน/แห้ง/ผสม/แพ้ง่าย)\n2) มีสิวอักเสบอยู่ตอนนี้ไหม\n3) งบประมาณประมาณเท่าไหร่คะ', 'text', now()-interval '6 hours 58 minutes'),
    (v_cv, 'contact', 'ผิวมัน สิวอักเสบ มีงบ 1000', 'text', now()-interval '6 hours 40 minutes'),
    (v_cv, 'ai', E'โอเคค่ะ จากเงื่อนไขผิวมัน+สิวอักเสบ+งบ ≤฿1,000 แนะนำชุดเริ่มต้น:\n• Clear Foam Cleanser ฿390\n• Glow Serum Travel 15ml ฿500\nรวม ฿890 (ยังไม่เกินงบ)\n\nช่วงสิวอักเสบ: ใช้ Clear เย็น / Glow เช้า ห่างกัน และหลีกเลี่ยง retinol คู่กันก่อนนะคะ ต้องการให้ส่งลิงก์ตะกร้านี้ไหมคะ?', 'text', now()-interval '6 hours 38 minutes'),
    (v_cv, 'contact', 'เอาเลย มีโค้ดไลฟ์ไหม', 'text', now()-interval '3 hours'),
    (v_cv, 'ai', E'มีค่ะ ใส่โค้ด TTGLOW10 ลดเพิ่ม 10% เหลือประมาณ ฿801\nลิงก์ตะกร้า: https://tiktok.com/@rocketbeauty/cart/demo801\n\nขั้นตอนที่ AI ทำครบแล้ว:\n✓ เก็บข้อมูลผิว/งบ\n✓ ค้นหาสินค้าที่เข้าเงื่อนไข\n✓ ใส่โปรไลฟ์\n✓ สร้างลิงก์ตะกร้า\nหลังชำระแล้วทักเลขออเดอร์มา เดี๋ยวช่วยยืนยันของแถมไลฟ์ให้ค่ะ', 'text', now()-interval '25 minutes');

  -- 8) TikTok — Manual agent
  INSERT INTO cs_contacts (merchant_id, display_name, language, tags, custom_fields, first_contact_at, last_contact_at)
  VALUES (v_merchant, 'tiktok.nana', 'th', ARRAY['demo-seed-2026','demo-seed-v2','agent-manual']::text[], '{"demo_seed":true}'::jsonb, now()-interval '9 hours', now()-interval '40 minutes')
  RETURNING id INTO v_c;

  INSERT INTO cs_platform_identities (merchant_id, contact_id, platform_type, platform_user_id, platform_display_name, linked_at)
  VALUES (v_merchant, v_c, 'tiktok', 'tt_nana_77', 'tiktok.nana', now()-interval '9 hours');

  INSERT INTO cs_conversations (
    merchant_id, credential_id, contact_id, modality, status, priority, tags,
    platform_conversation_id, last_message_at, created_at
  ) VALUES (
    v_merchant, v_cred_tiktok, v_c, 'chat', 'open', 'normal',
    ARRAY['demo-seed-2026','demo-seed-v2','agent-manual']::text[],
    'demo_rd_v2_tt_agent_nana', now()-interval '40 minutes', now()-interval '9 hours'
  ) RETURNING id INTO v_cv;

  INSERT INTO cs_messages (conversation_id, sender_type, content, message_type, created_at) VALUES
    (v_cv, 'contact', 'สั่งในไลฟ์ได้กระเป๋าผ้า แต่ในคลิปบอกแถมพัด', 'text', now()-interval '9 hours'),
    (v_cv, 'ai', 'ขออภัยค่ะ กำลังเช็คของแถมไลฟ์รอบนั้นให้ จะส่งต่อเจ้าหน้าที่ยืนยันคลิปโปรโมชันนะคะ', 'text', now()-interval '8 hours 58 minutes'),
    (v_cv, 'agent', 'คุณนานะคะ แอดมินกอล์ฟดูคลิปไลฟ์ย้อนหลังแล้ว ช่วงนาทีที่ 42 พิธีกรพูด “แถมพัด” จริง แต่ระบบดึงสต็อกกระเป๋าผ้าผิด ขอส่งพัดให้เพิ่มฟรี และกระเป๋าผ้ารับเป็นของสมนาคุณได้เลย ไม่ต้องส่งคืนค่ะ', 'text', now()-interval '8 hours 30 minutes'),
    (v_cv, 'contact', 'โอเค ส่งพัดมาได้เลย', 'text', now()-interval '1 hour'),
    (v_cv, 'agent', 'สร้างออเดอร์ของแถม TT-GIFT-3301 แล้วค่ะ จัดส่งพร้อมแทร็กใน 24 ชม. ขอบคุณที่แจ้งและขออภัยในความสับสนนะคะ', 'text', now()-interval '40 minutes');

  -- 9) Facebook — AI multi-step clinic booking (Thai)
  INSERT INTO cs_contacts (merchant_id, display_name, phone, language, tags, custom_fields, first_contact_at, last_contact_at)
  VALUES (v_merchant, 'คุณออย', '061-889-1200', 'th', ARRAY['demo-seed-2026','demo-seed-v2','booking']::text[], '{"demo_seed":true,"city":"Bangkok"}'::jsonb, now()-interval '11 hours', now()-interval '70 minutes')
  RETURNING id INTO v_c;

  INSERT INTO cs_platform_identities (merchant_id, contact_id, platform_type, platform_user_id, platform_display_name, linked_at)
  VALUES (v_merchant, v_c, 'facebook', 'fb_oi_5501', 'คุณออย', now()-interval '11 hours');

  INSERT INTO cs_conversations (
    merchant_id, credential_id, contact_id, modality, status, priority, intent, tags,
    platform_conversation_id, last_message_at, created_at,
    active_procedure_id, procedure_state
  ) VALUES (
    v_merchant, v_cred_fb, v_c, 'chat', 'open', 'normal', 'appointment_booking',
    ARRAY['demo-seed-2026','demo-seed-v2','ai-agentic']::text[],
    'demo_rd_v2_fb_clinic_oi', now()-interval '70 minutes', now()-interval '11 hours',
    v_proc_clinic,
    jsonb_build_object(
      'intent','appointment_booking',
      'procedure_id', v_proc_clinic,
      'procedure_name','Clinic Package Booking',
      'current_step', 4,
      'started_at', (now()-interval '11 hours'),
      'data_collected', jsonb_build_object(
        'customer_name','ออย',
        'phone','061-889-1200',
        'concern','dull_skin',
        'package','Glow Facial 60min',
        'branch','Siam',
        'slot','2026-07-25T14:00:00+07'
      ),
      'actions_taken', jsonb_build_array('Propose Packages','Check Availability','Hold Slot')
    )
  ) RETURNING id INTO v_cv;

  INSERT INTO cs_messages (conversation_id, sender_type, content, message_type, created_at) VALUES
    (v_cv, 'contact', 'อยากจองทรีตเมนต์หน้าใส สาขาสยาม', 'text', now()-interval '11 hours'),
    (v_cv, 'ai', 'ได้ค่ะคุณออย 😊 ขอชื่อที่ใช้จอง เบอร์โทร และปัญหาผิวหลักสั้นๆ (เช่น หมองคล้ำ สิว ริ้วรอย) เพื่อแนะนำแพ็กเกจให้ตรงนะคะ', 'text', now()-interval '10 hours 58 minutes'),
    (v_cv, 'contact', 'ออย 061-889-1200 ผิวหมองคล้ำค่ะ', 'text', now()-interval '10 hours 40 minutes'),
    (v_cv, 'ai', E'แนะนำ Glow Facial 60 นาที ที่สาขาสยาม เหมาะกับผิวหมอง ค่าบริการ ฿1,890 (สมาชิกลดเหลือ ฿1,590)\nมีค้าว่าง:\n• พรุ่งนี้ 14:00\n• มะรืนนี้ 11:00 / 16:30\nเลือกช่วงไหนดีคะ?', 'text', now()-interval '10 hours 38 minutes'),
    (v_cv, 'contact', 'พรุ่งนี้ 14:00 ได้ไหม', 'text', now()-interval '2 hours'),
    (v_cv, 'ai', E'จองชั่วคราวให้แล้วค่ะ\n✓ ชื่อ: ออย\n✓ เบอร์: 061-889-1200\n✓ แพ็กเกจ: Glow Facial 60 นาที\n✓ สาขา: สยาม\n✓ วันเวลา: 25 ก.ค. 2026 เวลา 14:00 น.\n\nขั้นตอนที่เหลือ: ชำระมัดจำ ฿300 เพื่อล็อกคิว หรือให้เจ้าหน้าที่โทรยืนยันก็ได้ค่ะ เลือกแบบไหนดีคะ?', 'text', now()-interval '70 minutes');

  -- 10) Facebook — Manual agent resolved
  INSERT INTO cs_contacts (merchant_id, display_name, phone, language, tags, custom_fields, first_contact_at, last_contact_at)
  VALUES (v_merchant, 'สมชาย FB', '083-770-1122', 'th', ARRAY['demo-seed-2026','demo-seed-v2','agent-manual','promo']::text[], '{"demo_seed":true}'::jsonb, now()-interval '2 days', now()-interval '2 hours')
  RETURNING id INTO v_c;

  INSERT INTO cs_platform_identities (merchant_id, contact_id, platform_type, platform_user_id, platform_display_name, linked_at)
  VALUES (v_merchant, v_c, 'facebook', 'fb_somchai_33', 'สมชาย FB', now()-interval '2 days');

  INSERT INTO cs_conversations (
    merchant_id, credential_id, contact_id, modality, status, priority, tags,
    platform_conversation_id, last_message_at, created_at, resolved_at
  ) VALUES (
    v_merchant, v_cred_fb, v_c, 'chat', 'resolved', 'normal',
    ARRAY['demo-seed-2026','demo-seed-v2','agent-manual']::text[],
    'demo_rd_v2_fb_agent_somchai', now()-interval '2 hours', now()-interval '2 days', now()-interval '2 hours'
  ) RETURNING id INTO v_cv;

  INSERT INTO cs_messages (conversation_id, sender_type, content, message_type, created_at) VALUES
    (v_cv, 'contact', 'โฆษณาบอกซื้อ 2 แถม 1 แต่คิดเงินครบ 3 ชิ้น', 'text', now()-interval '2 days'),
    (v_cv, 'ai', 'ขอเลขออเดอร์และลิงก์โฆษณาหน่อยนะคะ จะตรวจเงื่อนไขโปรให้', 'text', now()-interval '2 days' + interval '2 minutes'),
    (v_cv, 'contact', 'เว็บออเดอร์ WEB-55210 ค่ะ', 'text', now()-interval '2 days' + interval '20 minutes'),
    (v_cv, 'agent', 'คุณสมชายคะ แอดมินพิมพ์ตรวจแล้ว โปร 2แถม1 ใช้ได้เฉพาะชุด Glow+Hydra ไม่รวม Age Rewind ที่อยู่ในออเดอร์ อย่างไรก็ตาม เพื่อประสบการณ์ที่ดี แอดมินปรับส่วนลดให้เท่ากับของแถม 1 ชิ้น (คืน ฿690 เข้าบัตรใน 5 วันทำการ) และส่งโค้ด FBBUY2 สำหรับครั้งหน้าค่ะ', 'text', now()-interval '1 day'),
    (v_cv, 'contact', 'โอเค ขอบคุณมาก', 'text', now()-interval '3 hours'),
    (v_cv, 'agent', 'ดำเนินการคืนเงิน REF-FB-55210 แล้วค่ะ ปิดเคสเรียบร้อย หากยอดไม่เข้าภายใน 5 วัน ทักกลับได้เลยนะคะ', 'text', now()-interval '2 hours');

  -- 11) Instagram — AI multi-step tracking (Thai)
  INSERT INTO cs_contacts (merchant_id, display_name, email, language, tags, custom_fields, first_contact_at, last_contact_at)
  VALUES (v_merchant, 'mint.glow', 'mint.glow@example.com', 'th', ARRAY['demo-seed-2026','demo-seed-v2','tracking']::text[], '{"demo_seed":true}'::jsonb, now()-interval '100 minutes', now()-interval '8 minutes')
  RETURNING id INTO v_c;

  INSERT INTO cs_platform_identities (merchant_id, contact_id, platform_type, platform_user_id, platform_display_name, linked_at)
  VALUES (v_merchant, v_c, 'instagram', 'ig_mint_glow', 'mint.glow', now()-interval '100 minutes');

  INSERT INTO cs_conversations (
    merchant_id, credential_id, contact_id, modality, status, priority, intent, tags,
    platform_conversation_id, last_message_at, created_at,
    active_procedure_id, procedure_state
  ) VALUES (
    v_merchant, v_cred_ig, v_c, 'chat', 'open', 'normal', 'order_tracking',
    ARRAY['demo-seed-2026','demo-seed-v2','ai-agentic']::text[],
    'demo_rd_v2_ig_track_mint', now()-interval '8 minutes', now()-interval '100 minutes',
    v_proc_track,
    jsonb_build_object(
      'intent','order_tracking',
      'procedure_id', v_proc_track,
      'procedure_name','Order Tracking Handler',
      'current_step', 3,
      'started_at', (now()-interval '100 minutes'),
      'data_collected', jsonb_build_object(
        'order_number','IG-260723-441',
        'platform','instagram_shop',
        'status','packed',
        'eta','2026-07-24'
      ),
      'actions_taken', jsonb_build_array('Lookup Order')
    )
  ) RETURNING id INTO v_cv;

  INSERT INTO cs_messages (conversation_id, sender_type, content, message_type, created_at) VALUES
    (v_cv, 'contact', 'สั่ง Hydra จาก IG shop ยังไม่ได้รับเลขพัสดุ', 'text', now()-interval '100 minutes'),
    (v_cv, 'ai', 'ได้ค่ะ รบกวนชื่อในออเดอร์หรือเลข IG-… หน่อยนะคะ จะเช็คสถานะแพ็กของให้', 'text', now()-interval '98 minutes'),
    (v_cv, 'contact', 'IG-260723-441 ชื่อมิ้นท์ ค่ะ', 'text', now()-interval '80 minutes'),
    (v_cv, 'ai', E'พบออเดอร์ IG-260723-441 แล้วค่ะ สินค้า Hydra Centella แพ็กเรียบร้อย รอคิวเข้าระบบขนส่ง คาดมีเลขพัสดุภายในวันนี้ 18:00 น.\nต้องการให้แจ้งเลขอัตโนมัติในแชทนี้เมื่อเข้าระบบไหมคะ?', 'text', now()-interval '78 minutes'),
    (v_cv, 'contact', 'เอาเลย แล้วจะถึงเมื่อไหร่', 'text', now()-interval '20 minutes'),
    (v_cv, 'ai', E'เปิดการแจ้งเตือนเลขพัสดุให้แล้วค่ะ\nสรุปที่ AI ทำ:\n✓ เก็บเลขออเดอร์+ชื่อ\n✓ ตรวจสถานะคลัง (packed)\n✓ ประมาณการถึง 24 ก.ค.\n✓ ตั้งแจ้งเตือนเลขพัสดุอัตโนมัติ\nถ้าเกิน 18:00 ยังไม่มีเลข ระบบจะเอสเคเลตให้เจ้าหน้าที่เองค่ะ', 'text', now()-interval '8 minutes');

  -- 12) Instagram — Manual agent authenticity
  INSERT INTO cs_contacts (merchant_id, display_name, language, tags, custom_fields, first_contact_at, last_contact_at)
  VALUES (v_merchant, 'beautybyjane', 'th', ARRAY['demo-seed-2026','demo-seed-v2','agent-manual']::text[], '{"demo_seed":true}'::jsonb, now()-interval '14 hours', now()-interval '50 minutes')
  RETURNING id INTO v_c;

  INSERT INTO cs_platform_identities (merchant_id, contact_id, platform_type, platform_user_id, platform_display_name, linked_at)
  VALUES (v_merchant, v_c, 'instagram', 'ig_jane_99', 'beautybyjane', now()-interval '14 hours');

  INSERT INTO cs_conversations (
    merchant_id, credential_id, contact_id, modality, status, priority, tags,
    platform_conversation_id, last_message_at, created_at
  ) VALUES (
    v_merchant, v_cred_ig, v_c, 'chat', 'open', 'normal',
    ARRAY['demo-seed-2026','demo-seed-v2','agent-manual']::text[],
    'demo_rd_v2_ig_agent_jane', now()-interval '50 minutes', now()-interval '14 hours'
  ) RETURNING id INTO v_cv;

  INSERT INTO cs_messages (conversation_id, sender_type, content, message_type, created_at) VALUES
    (v_cv, 'contact', 'ซื้อ Glow จากร้านอื่นใน IG กลัวของปลอม ช่วยเช็คแบทช์โค้ดให้ได้ไหม', 'text', now()-interval '14 hours'),
    (v_cv, 'ai', 'ขอบคุณที่ระวังของแท้ค่ะ รบกวนส่งรูปแบทช์ใต้หลอดและชื่อร้านที่ซื้อมา เจ้าหน้าที่จะยืนยันให้', 'text', now()-interval '13 hours 58 minutes'),
    (v_cv, 'contact', 'ร้าน @skindeal.th แบทช์ GLO2409X', 'text', now()-interval '13 hours 30 minutes'),
    (v_cv, 'agent', E'คุณเจนคะ แอดมินเฟิร์นตรวจรหัส GLO2409X แล้ว ไม่พบในระบบผลิตของเรา และ @skindeal.th ไม่ใช่ตัวแทนอย่างเป็นทางการ แนะนำหยุดใช้ทันที\nทางแบรนด์ช่วยได้ดังนี้:\n1) ส่งของแท้ Glow ราคาพิเศษครีเอเตอร์ -30%\n2) แจ้งเตือนเพจเกี่ยวกับร้านดังกล่าว\nต้องการลิงก์ของแท้จาก IG Shop ทางการไหมคะ?', 'text', now()-interval '13 hours'),
    (v_cv, 'contact', 'เอาลิงก์ของแท้เลยค่ะ', 'text', now()-interval '1 hour'),
    (v_cv, 'agent', E'ลิงก์ทางการ: https://www.instagram.com/rocketbeauty/shop\nโค้ดครีเอเตอร์ JANE30 ใช้ได้ 7 วัน จำกัด 1 สิทธิ์ หากต้องการใบรับรองของแท้หลังสั่ง แจ้งเลขออเดอร์มาได้เลยค่ะ', 'text', now()-interval '50 minutes');

  -- 13) WhatsApp — AI then agent
  INSERT INTO cs_contacts (merchant_id, display_name, phone, language, tags, custom_fields, first_contact_at, last_contact_at)
  VALUES (v_merchant, 'คุณบอส WA', '066-123-4599', 'th', ARRAY['demo-seed-2026','demo-seed-v2','whatsapp']::text[], '{"demo_seed":true}'::jsonb, now()-interval '160 minutes', now()-interval '15 minutes')
  RETURNING id INTO v_c;

  INSERT INTO cs_platform_identities (merchant_id, contact_id, platform_type, platform_user_id, platform_display_name, linked_at)
  VALUES (v_merchant, v_c, 'whatsapp', 'wa_boss_4599', 'คุณบอส WA', now()-interval '160 minutes');

  INSERT INTO cs_conversations (
    merchant_id, credential_id, contact_id, modality, status, priority, intent, tags,
    platform_conversation_id, last_message_at, created_at,
    active_procedure_id, procedure_state
  ) VALUES (
    v_merchant, v_cred_wa, v_c, 'chat', 'open', 'normal', 'order_tracking',
    ARRAY['demo-seed-2026','demo-seed-v2','ai-agentic','agent-manual']::text[],
    'demo_rd_v2_wa_boss', now()-interval '15 minutes', now()-interval '160 minutes',
    v_proc_track,
    jsonb_build_object(
      'intent','order_tracking',
      'procedure_id', v_proc_track,
      'procedure_name','Order Tracking Handler',
      'current_step', 2,
      'data_collected', jsonb_build_object('order_number','WA-7781','status','delayed'),
      'actions_taken', jsonb_build_array('Lookup Order')
    )
  ) RETURNING id INTO v_cv;

  INSERT INTO cs_messages (conversation_id, sender_type, content, message_type, created_at) VALUES
    (v_cv, 'contact', 'พัสดุ WA-7781 เลยกำหนดแล้ว 2 วัน', 'text', now()-interval '160 minutes'),
    (v_cv, 'ai', 'ขอโทษสำหรับความล่าช้านะคะ กำลังเช็ค WA-7781 ให้… พบว่าขนส่งอัปเดตติดปัญหาพื้นที่น้ำท่วม ต้องการให้เปลี่ยนเป็นส่งใหม่จากคลังสำรอง หรือรอเส้นทางเดิมคะ?', 'text', now()-interval '158 minutes'),
    (v_cv, 'contact', 'ขอส่งใหม่จากคลังสำรอง และอยากคุยคนจริง', 'text', now()-interval '140 minutes'),
    (v_cv, 'ai', 'รับเรื่องเปลี่ยนเส้นทางแล้วค่ะ กำลังเชื่อมต่อเจ้าหน้าที่เพื่อยืนยันสล็อตส่งใหม่ให้', 'text', now()-interval '138 minutes'),
    (v_cv, 'agent', 'คุณบอสคะ นิชาเองค่ะ เปิดออเดอร์ทดแทน WA-7781-R แล้ว ส่ง Kerry วันนี้ คาดถึงพรุ่งนี้ พร้อมโค้ดชดเชย DELAY100 ใช้ได้ทันที', 'text', now()-interval '15 minutes');

  -- 14) Email — Manual agent B2B
  INSERT INTO cs_contacts (merchant_id, display_name, email, language, tags, custom_fields, first_contact_at, last_contact_at)
  VALUES (v_merchant, 'Procurement@RetailCo', 'procurement@retailco.example', 'en', ARRAY['demo-seed-2026','demo-seed-v2','agent-manual','email']::text[], '{"demo_seed":true}'::jsonb, now()-interval '1 day 3 hours', now()-interval '3 hours')
  RETURNING id INTO v_c;

  INSERT INTO cs_platform_identities (merchant_id, contact_id, platform_type, platform_user_id, platform_display_name, linked_at)
  VALUES (v_merchant, v_c, 'email', 'procurement@retailco.example', 'Procurement@RetailCo', now()-interval '1 day 3 hours');

  INSERT INTO cs_conversations (
    merchant_id, credential_id, contact_id, modality, status, priority, tags,
    platform_conversation_id, last_message_at, created_at
  ) VALUES (
    v_merchant, v_cred_email, v_c, 'chat', 'open', 'high',
    ARRAY['demo-seed-2026','demo-seed-v2','agent-manual']::text[],
    'demo_rd_v2_email_procurement', now()-interval '3 hours', now()-interval '1 day 3 hours'
  ) RETURNING id INTO v_cv;

  INSERT INTO cs_messages (conversation_id, sender_type, content, message_type, created_at) VALUES
    (v_cv, 'contact', 'Hi, we need a tax invoice for PO-8891 (120 units Glow Serum). Please advise.', 'text', now()-interval '1 day 3 hours'),
    (v_cv, 'ai', 'Thanks — I can prepare the invoice request. Sharing with our billing specialist for company details verification.', 'text', now()-interval '1 day 2 hours 58 minutes'),
    (v_cv, 'agent', E'Hello — May from Rocket Beauty billing. Please reply with:\n1) Legal company name\n2) Tax ID\n3) Billing address\n4) Preferred e-invoice email\nI will issue within 1 business day after details are complete.', 'text', now()-interval '1 day 2 hours'),
    (v_cv, 'contact', 'RetailCo Co., Ltd / 0105567890123 / 88 Sukhumvit / ap@retailco.example', 'text', now()-interval '5 hours'),
    (v_cv, 'agent', 'Received. Draft e-invoice INV-2026-4412 generated for PO-8891. PDF sent to ap@retailco.example. Reply here if any field needs correction before we finalize.', 'text', now()-interval '3 hours');

  -- 15) Web chat — AI multi-step gift order (Thai)
  INSERT INTO cs_contacts (merchant_id, display_name, language, tags, custom_fields, first_contact_at, last_contact_at)
  VALUES (v_merchant, 'ผู้เยี่ยมชมเว็บ', 'th', ARRAY['demo-seed-2026','demo-seed-v2','web']::text[], '{"demo_seed":true}'::jsonb, now()-interval '50 minutes', now()-interval '6 minutes')
  RETURNING id INTO v_c;

  INSERT INTO cs_conversations (
    merchant_id, credential_id, contact_id, modality, status, priority, intent, tags,
    platform_conversation_id, last_message_at, created_at,
    active_procedure_id, procedure_state
  ) VALUES (
    v_merchant, v_cred_web, v_c, 'chat', 'open', 'normal', 'place_order',
    ARRAY['demo-seed-2026','demo-seed-v2','ai-agentic']::text[],
    'demo_rd_v2_web_guest_01', now()-interval '6 minutes', now()-interval '50 minutes',
    v_proc_ecom,
    jsonb_build_object(
      'intent','place_order',
      'procedure_id', v_proc_ecom,
      'procedure_name','Ecommerce Order Assistant',
      'current_step', 3,
      'data_collected', jsonb_build_object(
        'order_goal','gift_set',
        'recipient','แม่',
        'budget',2000,
        'recommended','Hydra + Shield gift set'
      ),
      'actions_taken', jsonb_build_array('Clarify Need','Search Products')
    )
  ) RETURNING id INTO v_cv;

  INSERT INTO cs_messages (conversation_id, sender_type, content, message_type, created_at) VALUES
    (v_cv, 'contact', 'หาของขวัญให้แม่ งบสองพัน', 'text', now()-interval '50 minutes'),
    (v_cv, 'ai', 'ได้ค่ะ 😊 ของขวัญให้คุณแม่ งบ ~฿2,000 — ผิวแม่มีปัญหาหลักอะไรคะ (แห้ง/หมอง/กันแดด) หรือชอบชุดเซ็ตสำเร็จรูป?', 'text', now()-interval '48 minutes'),
    (v_cv, 'contact', 'ผิวแห้ง อยากได้ครีม+กันแดด', 'text', now()-interval '35 minutes'),
    (v_cv, 'ai', E'แนะนำชุดของขวัญ:\n• Hydra Centella Cream ฿890\n• Shield SPF50+ Clear ฿590\n• กล่องของขวัญ+โบว์ ฿120\nรวม ฿1,600 (เหลือช่องใส่การ์ดข้อความ)\n\nต้องการให้ใส่ข้อความบนการ์ดไหมคะ? และส่งด่วนใน กทม. วันนี้ได้ถึง 15:00 น. ค่ะ', 'text', now()-interval '33 minutes'),
    (v_cv, 'contact', 'ข้อความว่า “รักแม่ที่สุด” ส่งด่วนได้ไหม', 'text', now()-interval '15 minutes'),
    (v_cv, 'ai', E'จัดให้ค่ะ\n✓ เลือกชุด Hydra+Shield+กล่อง\n✓ ใส่ข้อความการ์ด: “รักแม่ที่สุด”\n✓ โหมดส่งด่วน กทม.\nลิงก์ชำระ: https://rocketbeauty.co.th/cart/gift-1600-express\nหลังชำระเสร็จ ทักเลขออเดอร์มา เดี๋ยวยืนยันคิวด่วนให้ค่ะ', 'text', now()-interval '6 minutes');

  ALTER TABLE cs_messages ENABLE TRIGGER trg_cs_messages_deliver_outbound;

EXCEPTION WHEN OTHERS THEN
  ALTER TABLE cs_messages ENABLE TRIGGER trg_cs_messages_deliver_outbound;
  RAISE;
END $$;
