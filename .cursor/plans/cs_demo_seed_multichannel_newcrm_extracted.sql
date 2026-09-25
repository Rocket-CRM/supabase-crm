-- CS demo seed: multichannel mock conversations for New CRM merchant
-- Merchant: 09b45463-3812-42fb-9c7f-9d43b6fd3eb9 (newcrm)

DO $$
DECLARE
  v_merchant        uuid := '09b45463-3812-42fb-9c7f-9d43b6fd3eb9';
  v_cred_line       uuid := '1fb215ac-7a1f-43d4-814d-1462551652eb';
  v_cred_shopee     uuid := '880bfbfa-4ccd-4a96-bfd5-a7c519014687';
  v_cred_lazada     uuid := 'af8fb1c5-3ea3-4fdc-a143-8acc6c9f1db7';
  v_cred_tiktok     uuid := 'ba29f380-c01f-4e40-ac27-0121bb7a2fc5';
  v_cred_facebook   uuid;
  v_cred_instagram  uuid;
  v_tier_gold       uuid := '144601ec-de04-47f8-89cc-29b8dd6109d5';
  v_tier_silver     uuid := '1d527b74-16f5-4f3e-a969-28edcd762c83';
  v_user_ploy       uuid;
  v_user_tick       uuid;
  v_contact_shopee  uuid;
  v_contact_lazada  uuid;
  v_contact_tiktok  uuid;
  v_contact_fb      uuid;
  v_contact_ig      uuid;
  v_contact_line    uuid;
  v_conv_shopee     uuid;
  v_conv_lazada     uuid;
  v_conv_tiktok     uuid;
  v_conv_fb         uuid;
  v_conv_ig         uuid;
  v_conv_line       uuid;
BEGIN
  -- Phase 0: placeholder credentials for FB / IG (demo display only)
  INSERT INTO merchant_credentials (merchant_id, service_name, credential_name, credentials, is_active, scope)
  VALUES (v_merchant, 'facebook', 'Rocket Beauty FB Page (Demo)', '{}'::jsonb, true, ARRAY['cs']::text[])
  RETURNING id INTO v_cred_facebook;

  INSERT INTO merchant_credentials (merchant_id, service_name, credential_name, credentials, is_active, scope)
  VALUES (v_merchant, 'instagram', 'Rocket Beauty IG (Demo)', '{}'::jsonb, true, ARRAY['cs']::text[])
  RETURNING id INTO v_cred_instagram;

  -- Phase 0b: fresh loyalty users on New CRM only
  INSERT INTO user_accounts (
    merchant_id, fullname, firstname, lastname, email, tel,
    tier_id, user_type, user_stage, is_signup_form_complete,
    acquisition_source, skip_cdc
  ) VALUES (
    v_merchant, 'Ploy Kannika', 'Ploy', 'Kannika', 'ploy.k@gmail.com', '+66894412201',
    v_tier_silver, 'buyer', 'customer', true,
    'cs_demo_seed_2026', true
  ) RETURNING id INTO v_user_ploy;

  UPDATE user_accounts
  SET member_code = fn_derive_member_code(v_user_ploy, v_merchant)
  WHERE id = v_user_ploy;

  INSERT INTO user_wallet (id, user_id, merchant_id, points_balance, ticket_balance)
  VALUES (v_user_ploy, v_user_ploy, v_merchant, 450, 0);

  INSERT INTO user_accounts (
    merchant_id, fullname, firstname, lastname, tel, line_id,
    tier_id, user_type, user_stage, is_signup_form_complete,
    acquisition_source, skip_cdc
  ) VALUES (
    v_merchant, 'Tick Srisuk', 'Tick', 'Srisuk', '+66819984420', 'line_demo_tick_01',
    v_tier_gold, 'buyer', 'customer', true,
    'cs_demo_seed_2026', true
  ) RETURNING id INTO v_user_tick;

  UPDATE user_accounts
  SET member_code = fn_derive_member_code(v_user_tick, v_merchant)
  WHERE id = v_user_tick;

  INSERT INTO user_wallet (id, user_id, merchant_id, points_balance, ticket_balance)
  VALUES (v_user_tick, v_user_tick, v_merchant, 1200, 0);

  -- Phase 1: contacts
  INSERT INTO cs_contacts (merchant_id, display_name, phone, email, language, tags, crm_user_id, custom_fields, first_contact_at, last_contact_at)
  VALUES (v_merchant, 'แป้ง.พี่แป้ง', '081-234-5598', NULL, 'th', ARRAY['demo-seed-2026','marketplace']::text[], NULL, '{"demo_seed": true}'::jsonb, '2026-06-11 09:12:00+00', '2026-06-11 14:05:00+00')
  RETURNING id INTO v_contact_shopee;

  INSERT INTO cs_contacts (merchant_id, display_name, phone, email, language, tags, crm_user_id, custom_fields, first_contact_at, last_contact_at)
  VALUES (v_merchant, 'Ploy_K', '089-441-2201', 'ploy.k@gmail.com', 'en', ARRAY['demo-seed-2026','refund']::text[], v_user_ploy, '{"demo_seed": true}'::jsonb, '2026-06-11 07:30:00+00', '2026-06-11 10:18:00+00')
  RETURNING id INTO v_contact_lazada;

  INSERT INTO cs_contacts (merchant_id, display_name, language, tags, custom_fields, first_contact_at, last_contact_at)
  VALUES (v_merchant, 'mimi_skincare', 'th', ARRAY['demo-seed-2026','pre-sale']::text[], '{"demo_seed": true}'::jsonb, '2026-06-10 11:00:00+00', '2026-06-10 15:42:00+00')
  RETURNING id INTO v_contact_tiktok;

  INSERT INTO cs_contacts (merchant_id, display_name, phone, language, tags, custom_fields, first_contact_at, last_contact_at)
  VALUES (v_merchant, 'สุดา วงศ์ดี', '062-889-3341', 'th', ARRAY['demo-seed-2026','promo']::text[], '{"demo_seed": true, "city": "Chiang Mai"}'::jsonb, '2026-06-09 08:15:00+00', '2026-06-09 09:40:00+00')
  RETURNING id INTO v_contact_fb;

  INSERT INTO cs_contacts (merchant_id, display_name, email, language, tags, custom_fields, first_contact_at, last_contact_at)
  VALUES (v_merchant, 'junjira.beauty', 'junjira.b@gmail.com', 'th', ARRAY['demo-seed-2026','allergy']::text[], '{"demo_seed": true}'::jsonb, '2026-06-10 18:20:00+00', '2026-06-10 19:05:00+00')
  RETURNING id INTO v_contact_ig;

  INSERT INTO cs_contacts (merchant_id, display_name, phone, language, tags, crm_user_id, custom_fields, first_contact_at, last_contact_at)
  VALUES (v_merchant, 'คุณติ๊ก', '081-998-4420', 'th', ARRAY['demo-seed-2026','loyalty']::text[], v_user_tick, '{"demo_seed": true}'::jsonb, '2026-06-11 11:45:00+00', '2026-06-11 12:22:00+00')
  RETURNING id INTO v_contact_line;

  -- Platform identities
  INSERT INTO cs_platform_identities (merchant_id, contact_id, platform_type, platform_user_id, platform_display_name, linked_at) VALUES
    (v_merchant, v_contact_shopee, 'shopee', 'shopee_buyer_88421', 'แป้ง.พี่แป้ง', '2026-06-11 09:12:00+00'),
    (v_merchant, v_contact_lazada, 'lazada', 'lazada_ploy_k_09', 'Ploy_K', '2026-06-11 07:30:00+00'),
    (v_merchant, v_contact_tiktok, 'tiktok', 'tiktok_mimi_772', 'mimi_skincare', '2026-06-10 11:00:00+00'),
    (v_merchant, v_contact_fb, 'facebook', 'fb_psuda_1188', 'สุดา วงศ์ดี', '2026-06-09 08:15:00+00'),
    (v_merchant, v_contact_ig, 'instagram', 'ig_junjira_552', 'junjira.beauty', '2026-06-10 18:20:00+00'),
    (v_merchant, v_contact_line, 'line', 'line_demo_tick_01', 'คุณติ๊ก', '2026-06-11 11:45:00+00');

  -- Phase 2: conversations
  INSERT INTO cs_conversations (merchant_id, credential_id, contact_id, modality, status, priority, intent, tags, platform_conversation_id, last_message_at, created_at)
  VALUES (v_merchant, v_cred_shopee, v_contact_shopee, 'chat', 'open', 'normal', NULL, ARRAY['demo-seed-2026']::text[], 'demo_shopee_88421', '2026-06-11 14:05:00+00', '2026-06-11 09:12:00+00')
  RETURNING id INTO v_conv_shopee;

  INSERT INTO cs_conversations (merchant_id, credential_id, contact_id, modality, status, priority, intent, tags, platform_conversation_id, last_message_at, created_at)
  VALUES (v_merchant, v_cred_lazada, v_contact_lazada, 'chat', 'open', 'high', 'refund', ARRAY['demo-seed-2026','refund']::text[], 'demo_lazada_302918447', '2026-06-11 10:18:00+00', '2026-06-11 07:30:00+00')
  RETURNING id INTO v_conv_lazada;

  INSERT INTO cs_conversations (merchant_id, credential_id, contact_id, modality, status, priority, tags, platform_conversation_id, last_message_at, created_at)
  VALUES (v_merchant, v_cred_tiktok, v_contact_tiktok, 'chat', 'open', 'normal', ARRAY['demo-seed-2026']::text[], 'demo_tiktok_mimi_772', '2026-06-10 15:42:00+00', '2026-06-10 11:00:00+00')
  RETURNING id INTO v_conv_tiktok;

  INSERT INTO cs_conversations (merchant_id, credential_id, contact_id, modality, status, priority, tags, platform_conversation_id, last_message_at, resolved_at, created_at)
  VALUES (v_merchant, v_cred_facebook, v_contact_fb, 'chat', 'resolved', 'normal', ARRAY['demo-seed-2026']::text[], 'demo_fb_psuda_1188', '2026-06-09 09:40:00+00', '2026-06-09 09:38:00+00', '2026-06-09 08:15:00+00')
  RETURNING id INTO v_conv_fb;

  INSERT INTO cs_conversations (merchant_id, credential_id, contact_id, modality, status, priority, tags, platform_conversation_id, last_message_at, created_at)
  VALUES (v_merchant, v_cred_instagram, v_contact_ig, 'chat', 'open', 'normal', ARRAY['demo-seed-2026']::text[], 'demo_ig_junjira_552', '2026-06-10 19:05:00+00', '2026-06-10 18:20:00+00')
  RETURNING id INTO v_conv_ig;

  INSERT INTO cs_conversations (merchant_id, credential_id, contact_id, modality, status, priority, tags, platform_conversation_id, last_message_at, created_at)
  VALUES (v_merchant, v_cred_line, v_contact_line, 'chat', 'open', 'normal', ARRAY['demo-seed-2026']::text[], 'demo_line_tick_01', '2026-06-11 12:22:00+00', '2026-06-11 11:45:00+00')
  RETURNING id INTO v_conv_line;

  -- Phase 3: messages (direct insert — agent rows skip outbound delivery trigger)

  -- Shopee
  INSERT INTO cs_messages (conversation_id, sender_type, content, message_type, created_at) VALUES
    (v_conv_shopee, 'contact', 'สั่งกันแดดมา ทำไมได้สีขาวขุ่นอ่ะ สั่งโทนใสนะ ออเดอร์ 24061288421', 'text', '2026-06-11 09:12:00+00'),
    (v_conv_shopee, 'ai', 'ขอโทษด้วยค่ะคุณแป้ง 🙏 เช็คออเดอร์ 24061288421 แล้ว สั่ง Shield Daily SPF50+ โทน Clear ถูกต้องค่ะ รบกวนส่งรูปหลอดที่ได้มาให้ดูหน่อยได้ไหมคะ', 'text', '2026-06-11 09:13:20+00'),
    (v_conv_shopee, 'contact', 'เดี๋ยวนะ ถ่ายให้', 'text', '2026-06-11 13:58:00+00'),
    (v_conv_shopee, 'contact', 'ได้อันนี้มา มันขาวมากเลย ทาแล้วหน้าเทา', 'text', '2026-06-11 14:02:00+00'),
    (v_conv_shopee, 'agent', 'คุณแป้งค่ะ ดูจากที่คุยแล้วน่าจะเป็นโทน Natural ที่คลังส่งผิดมาค่ะ ขอที่อยู่จัดส่งใหม่ เดี๋ยวส่ง Clear ให้ฟรี ไม่ต้องส่งคืน', 'text', '2026-06-11 14:05:00+00');

  -- Lazada
  INSERT INTO cs_messages (conversation_id, sender_type, content, message_type, created_at) VALUES
    (v_conv_lazada, 'contact', 'Hi order 302918447 arrived today but the Glow Serum box is wet inside?? bottle cap loose 😭', 'text', '2026-06-11 07:30:00+00'),
    (v_conv_lazada, 'ai', 'So sorry about that, Ploy. That''s definitely not the experience we want. Can you send 2 photos — the outer box and the bottle? I''ll flag this for a replacement or refund right away.', 'text', '2026-06-11 07:31:10+00'),
    (v_conv_lazada, 'contact', 'ok sec', 'text', '2026-06-11 09:55:00+00'),
    (v_conv_lazada, 'contact', 'sent already in chat', 'text', '2026-06-11 10:10:00+00'),
    (v_conv_lazada, 'agent', 'Got your photos. Approved full refund ฿890 back to Lazada wallet within 3–5 days. No need to return the damaged unit. I''ve added a note on your account.', 'text', '2026-06-11 10:18:00+00');

  -- TikTok
  INSERT INTO cs_messages (conversation_id, sender_type, content, message_type, created_at) VALUES
    (v_conv_tiktok, 'contact', 'สวัสดีค่า ผิวมันสิวเยอะ ควรเอา glow serum หรือ clear line ดี', 'text', '2026-06-10 11:00:00+00'),
    (v_conv_tiktok, 'ai', 'สวัสดีค่ะมีมี่ ✨ ถ้าสิวอักเสบเยอะ แนะนำ Clear line ก่อนค่ะ พอสิวลดแล้วค่อยเพิ่ม Glow Vitamin C ตอนเช้า ทาคู่กันได้ถ้าผิวไม่แสบ', 'text', '2026-06-10 11:01:30+00'),
    (v_conv_tiktok, 'contact', 'glow กับ clear ใช้พร้อมกันได้เลยหรอ', 'text', '2026-06-10 14:20:00+00'),
    (v_conv_tiktok, 'contact', 'กลัวแสบ ใช้ retinol อยู่', 'text', '2026-06-10 15:30:00+00'),
    (v_conv_tiktok, 'agent', 'ถ้าใช้ retinol อยู่ แนะนำ Clear ตอนเย็น / Glow ตอนเช้า ห่าง retinol อย่างน้อย 30 นาทีนะคะ ถ้าแสบให้หยุด', 'text', '2026-06-10 15:42:00+00');

  -- Facebook
  INSERT INTO cs_messages (conversation_id, sender_type, content, message_type, created_at) VALUES
    (v_conv_fb, 'contact', 'คูปอง GLOW15 ใส่แล้วขึ้นว่าใช้ไม่ได้ค่ะ ซื้อในเว็บ', 'text', '2026-06-09 08:15:00+00'),
    (v_conv_fb, 'ai', 'ขอโทษด้วยค่ะคุณสุดา รบกวนบอกยอดสั่งซื้อและสินค้าในตะกร้าหน่อยได้ไหมคะ จะเช็คเงื่อนไขคูปองให้', 'text', '2026-06-09 08:16:00+00'),
    (v_conv_fb, 'contact', 'ซื้อแค่ครีม 690 บาท', 'text', '2026-06-09 08:45:00+00'),
    (v_conv_fb, 'agent', 'GLOW15 ใช้ได้ขั้นต่ำ ฿800 ค่ะ ถ้าเพิ่ม cleanser ขวดเล็ก ฿190 จะครบ', 'text', '2026-06-09 09:10:00+00'),
    (v_conv_fb, 'contact', 'โอเค เดี๋ยวเพิ่ม', 'text', '2026-06-09 09:25:00+00'),
    (v_conv_fb, 'ai', 'ได้เลยค่ะ มีอะไรแจ้งได้เลยนะคะ 😊', 'text', '2026-06-09 09:40:00+00');

  -- Instagram
  INSERT INTO cs_messages (conversation_id, sender_type, content, message_type, created_at) VALUES
    (v_conv_ig, 'contact', 'hydra centella มีน้ำหอมไหม แพ้น้ำหอม', 'text', '2026-06-10 18:20:00+00'),
    (v_conv_ig, 'ai', 'Hydra Centella Cream ปราศจาก synthetic fragrance ค่ะ มีแค่กลิ่นอ่อนจากสารธรรมชาติ ถ้าแพ้รุนแรงแนะนำ patch test ที่แขนก่อน', 'text', '2026-06-10 18:21:00+00'),
    (v_conv_ig, 'contact', 'ok สั่งทางไหนดี', 'text', '2026-06-10 18:50:00+00'),
    (v_conv_ig, 'contact', 'มีลิงก์ไหม', 'text', '2026-06-10 18:55:00+00'),
    (v_conv_ig, 'agent', 'สั่งผ่าน rocketbeauty.co.th หรือ TikTok Shop ก็ได้ค่ะ ลิงก์ส่งในไบโอ', 'text', '2026-06-10 19:05:00+00');

  -- LINE
  INSERT INTO cs_messages (conversation_id, sender_type, content, message_type, created_at) VALUES
    (v_conv_line, 'contact', 'ติ๊กครับ แต้ม 1,200 แลกกันแดดได้ไหม', 'text', '2026-06-11 11:45:00+00'),
    (v_conv_line, 'ai', 'ได้ค่ะคุณติ๊ก Shield SPF50+ 1,200 แต้ม รับที่บ้านหรือรับที่เคาน์เตอร์', 'text', '2026-06-11 11:46:10+00'),
    (v_conv_line, 'contact', 'ส่งบ้าน เดิมเลย', 'text', '2026-06-11 12:10:00+00'),
    (v_conv_line, 'agent', 'จัดให้แล้วค่ะ ใช้ที่อยู่เดิม กทม. จัดส่งภายใน 2 วันทำการ', 'text', '2026-06-11 12:22:00+00');

  -- Phase 4: customer memory
  INSERT INTO cs_customer_memory (merchant_id, contact_id, category, key, value, confidence, source_conversation_id) VALUES
    (v_merchant, v_contact_shopee, 'preference', 'skin_type', 'oily', 0.9, v_conv_shopee),
    (v_merchant, v_contact_shopee, 'order', 'last_order', 'Shield SPF50 Clear ฿590 — order 24061288421', 1.0, v_conv_shopee),
    (v_merchant, v_contact_lazada, 'preference', 'preferred_channel', 'lazada', 1.0, v_conv_lazada),
    (v_merchant, v_contact_lazada, 'concern', 'skin_sensitivity', 'sensitive skin — patch test recommended', 0.85, v_conv_lazada),
    (v_merchant, v_contact_tiktok, 'preference', 'skin_concern', 'acne + dark spots', 0.9, v_conv_tiktok),
    (v_merchant, v_contact_tiktok, 'preference', 'budget', 'under ฿1,000', 0.8, v_conv_tiktok),
    (v_merchant, v_contact_fb, 'preference', 'city', 'Chiang Mai', 1.0, v_conv_fb),
    (v_merchant, v_contact_fb, 'preference', 'heard_from', 'Facebook ad', 0.9, v_conv_fb),
    (v_merchant, v_contact_ig, 'concern', 'allergy', 'fragrance — avoid synthetic perfume', 1.0, v_conv_ig),
    (v_merchant, v_contact_ig, 'preference', 'product_interest', 'Hydra Centella Cream', 0.95, v_conv_ig),
    (v_merchant, v_contact_line, 'preference', 'skin_type', 'combination', 0.85, v_conv_line),
    (v_merchant, v_contact_line, 'loyalty', 'points_balance_note', '1,200 points — redeeming sunscreen', 1.0, v_conv_line);

END $$;