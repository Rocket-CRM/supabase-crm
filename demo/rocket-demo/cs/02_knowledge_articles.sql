-- Rocket Demo CS knowledge base seed
-- Merchant: fae172a5-de90-440e-a766-db6a5982cc9b

DO $$
DECLARE
  v_mid uuid := 'fae172a5-de90-440e-a766-db6a5982cc9b';
BEGIN
  DELETE FROM cs_knowledge_articles
  WHERE merchant_id = v_mid
    AND source_type = 'demo_seed'
    AND source_url = 'seed://rocket-demo/cs';

  INSERT INTO cs_knowledge_articles (
    merchant_id, title, content, category, language,
    source_type, source_url, status, is_custom_answer, question_patterns, priority
  ) VALUES
  -- Clinic packages
  (v_mid, 'Rocket Clinic Package: Skin Analysis',
   E'## Skin Analysis\nPrice: ฿1,490 | Duration: 45 minutes | Branches: Siam Paragon, EmQuartier\n\nIncludes digital skin scan, barrier assessment, and a personalized home-care recommendation.\nNot a medical diagnosis. Suitable for first-time clinic visitors.\nPrep: arrive with clean face, no makeup preferred.\nCancellation: free up to 24 hours before appointment.',
   'clinic_packages', 'en', 'demo_seed', 'seed://rocket-demo/cs', 'active', false, '{}', 0),

  (v_mid, 'Rocket Clinic Package: Glow Laser Basic',
   E'## Glow Laser Basic\nPrice: ฿3,900 | Duration: 60 minutes\n\nAesthetic brightening laser session for uneven tone concerns. Performed by licensed clinic staff after consultation.\nContraindications (book consult first): pregnancy, active infection, recent strong peels.\nAftercare: SPF daily, avoid sauna 48h. AI agents must not claim medical outcomes.',
   'clinic_packages', 'en', 'demo_seed', 'seed://rocket-demo/cs', 'active', false, '{}', 0),

  (v_mid, 'Rocket Clinic Package: Wellness Skin Checkup',
   E'## Wellness Skin Checkup\nPrice: ฿2,490 | Duration: 75 minutes\n\nDeeper skin wellness review combining analysis + lifestyle questionnaire + product plan.\nGood for customers with chronic dryness or sensitivity questions who need a specialist—not OTC advice only.',
   'clinic_packages', 'en', 'demo_seed', 'seed://rocket-demo/cs', 'active', false, '{}', 0),

  (v_mid, 'แพ็กเกจคลินิก Rocket Clinic (สรุป)',
   E'แพ็กเกจยอดนิยม:\n1) Skin Analysis ฿1,490 (45 นาที)\n2) Glow Laser Basic ฿3,900 (60 นาที)\n3) Wellness Skin Checkup ฿2,490 (75 นาที)\nเปิด จ–อา 10:00–20:00 สาขา Siam Paragon และ EmQuartier\nจองผ่านแชทได้ โดยยืนยันแพ็กเกจ + วันเวลา ก่อนออกใบจอง',
   'clinic_packages', 'th', 'demo_seed', 'seed://rocket-demo/cs', 'active', true,
   ARRAY['แพ็กเกจคลินิก','มีแพ็กเกจอะไร','clinic package','จองเลเซอร์','skin analysis'], 90),

  (v_mid, 'Rocket Clinic Booking & Cancellation Policy',
   E'## Booking rules\n- Confirm package + date/time + branch before issuing booking ref (format BK-RKT-####).\n- Deposit: none for Skin Analysis; Glow Laser may require ฿500 hold (demo).\n- Cancel/reschedule free ≥24h before; late cancel may forfeit hold.\n- Arrive 15 minutes early. Bring member ID if Rocket Club member.',
   'clinic_policy', 'en', 'demo_seed', 'seed://rocket-demo/cs', 'active', false, '{}', 0),

  (v_mid, 'Clinic Hours and Locations',
   E'Rocket Clinic operates inside Rocket Club stores:\n- Siam Paragon B1 Beauty Zone\n- EmQuartier G Floor\nHours: Tue–Sun 10:00–20:00, closed Monday.\nRetail stores also include CentralWorld, Maya Chiang Mai, and Rocket Club Online.',
   'clinic_policy', 'en', 'demo_seed', 'seed://rocket-demo/cs', 'active', true,
   ARRAY['clinic hours','เปิดกี่โมง','สาขาคลินิก','clinic location'], 80),

  (v_mid, 'Generic Prep & Aftercare (Non-prescriptive)',
   E'General guidance only — not personalized medical advice:\nBefore visit: cleanse gently, avoid strong actives night before if staff advises.\nAfter aesthetic sessions: moisturize, use SPF, avoid picking skin.\nAny pain, swelling, or unexpected reaction → contact clinic / escalate to specialist; do not self-medicate from chat.',
   'clinic_policy', 'en', 'demo_seed', 'seed://rocket-demo/cs', 'active', false, '{}', 0),

  -- Product / formula
  (v_mid, 'GlowLab Niacinamide Bright Serum — Formula Notes',
   E'Product: GlowLab Niacinamide Bright Serum 30ml\nKey idea: niacinamide supports brighter-looking tone and oil balance for many skin types.\nHow to use: after toner, pea-sized amount AM/PM; follow with moisturizer; SPF in AM.\nNot a drug. Not for diagnosing melasma or acne. If irritation persists, stop and book Skin Analysis.',
   'product_formula', 'en', 'demo_seed', 'seed://rocket-demo/cs', 'active', false, '{}', 0),

  (v_mid, 'AgeSoft Retinol Night Repair — Formula Notes',
   E'Product: AgeSoft Retinol Night Repair 30ml\nEvening-only cosmetic retinol serum. Start 2x/week, build tolerance.\nAlways use SPF next morning. Do not combine same night with strong acids or Vitamin C.\nPregnancy/breastfeeding: do not recommend — route to pharmacist/clinic consult.\nSevere burning/rash → stop and escalate.',
   'product_formula', 'en', 'demo_seed', 'seed://rocket-demo/cs', 'active', true,
   ARRAY['retinol','age soft','how to use retinol','เรตินอล'], 85),

  (v_mid, 'RiceGlow Gentle Rice Cleansing Foam — Overview',
   E'Mild daily cleanser with rice extract positioning for gentle cleanse. Suitable starter SKU.\nUse AM/PM, massage 20–30s, rinse. Follow with toner/serum.\nNot a treatment for eczema or infection.',
   'product_formula', 'en', 'demo_seed', 'seed://rocket-demo/cs', 'active', false, '{}', 0),

  (v_mid, 'SPF & Protect Category Guidance',
   E'Protect step is last in AM routines. Reapply when outdoors as directed on pack.\nAgents may explain “why SPF matters for cosmetic routines” but must not give medical UV treatment advice.',
   'product_formula', 'en', 'demo_seed', 'seed://rocket-demo/cs', 'active', false, '{}', 0),

  (v_mid, 'Can I Mix Serums Together?',
   E'Safe pairs (cosmetic guidance): Niacinamide + HA moisturizer; Vitamin C AM + Retinol PM.\nAvoid same-time: Vitamin C + Retinol; AHA/BHA + Retinol.\nLayer: cleanser → toner → serum thin-to-thick → moisturizer → SPF (AM).\nIf customer asks about treating a disease, use medical boundary script.',
   'product_howto', 'en', 'demo_seed', 'seed://rocket-demo/cs', 'active', true,
   ARRAY['mix serums','layering','ใช้เซรั่มคู่กัน','combine vitamin c retinol'], 88),

  (v_mid, 'Morning Skincare Routine (Rocket Club)',
   E'Recommended demo routine:\n1) RiceGlow Gentle Rice Cleansing Foam\n2) GlowLab Niacinamide Bright Serum\n3) AquaLayer Hyaluronic Moisture Ampoule\n4) SPF Protect\nCustomize via Skin Analysis if unsure.',
   'product_howto', 'en', 'demo_seed', 'seed://rocket-demo/cs', 'active', false, '{}', 0),

  (v_mid, 'When Product Advice Should Become a Clinic Visit',
   E'Book clinic / specialist when: persistent irritation, suspected allergy, pregnancy product questions beyond label, pigmentation diagnosis requests, or customer asks what disease they have.\nRetail chat can suggest SKUs and routines; clinic handles assessment.',
   'product_howto', 'en', 'demo_seed', 'seed://rocket-demo/cs', 'active', false, '{}', 0),

  -- Promotions
  (v_mid, 'Current Rocket Club Promotions',
   E'Active demo promos:\n- Retail: spend ฿1,500 get 10% off skincare\n- Clinic: Skin Analysis online booking -฿200\n- Gold+ members: 1.5x points on clinic packages\n- Free standard shipping over ฿999 (online retail)\nPromos are demo copy for CS — confirm at checkout.',
   'promotions', 'en', 'demo_seed', 'seed://rocket-demo/cs', 'active', true,
   ARRAY['current promo','โปรโมชัน','ส่วนลด','free shipping','มีโปรอะไร'], 95),

  (v_mid, 'Rocket Club Points on Clinic vs Retail',
   E'Retail purchases earn points per merchant earn rules (demo: ~0.1 pt/THB).\nClinic packages can earn bonus for Gold+ (1.5x demo).\nRedemptions use Rocket Club rewards catalog. Agents should not invent point balances — look up profile tools when available.',
   'promotions', 'en', 'demo_seed', 'seed://rocket-demo/cs', 'active', false, '{}', 0),

  (v_mid, 'Shipping Information',
   E'Standard shipping 1–3 business days in Bangkok, 2–5 elsewhere (demo).\nTracking appears after handoff to carrier. Provide order number + platform (Shopee/Lazada/TikTok/Rocket Online).\nLINE chat channel is not the same as marketplace platform.',
   'promotions', 'en', 'demo_seed', 'seed://rocket-demo/cs', 'active', true,
   ARRAY['shipping','จัดส่งกี่วัน','delivery time'], 70),

  -- Medical boundaries
  (v_mid, 'What AI and Agents Must Not Answer (Medical)',
   E'Hard boundaries:\n- No diagnosis, no prescribing, no lab interpretation, no dosing.\n- No claims that a cosmetic product “treats” disease.\n- For medical questions: refuse → offer clinic booking or specialist ticket.\nAllowed: package info, store hours, product usage as on label, promo facts.',
   'medical_boundary', 'en', 'demo_seed', 'seed://rocket-demo/cs', 'active', true,
   ARRAY['diagnosis','prescribe','lab result','เป็นโรคอะไร','กินยาตัวไหน','doctor advice'], 100),

  (v_mid, 'Doctor vs OTC Skincare — Routing Guide',
   E'OTC / chat OK: routine building, ingredient education, stock, orders, promos.\nClinic booking: laser interest, stubborn concerns, pregnancy product caution, irritation not improving.\nSpecialist ticket: explicit medical advice requests, emergencies (advise ER if urgent — do not triage online).',
   'medical_boundary', 'en', 'demo_seed', 'seed://rocket-demo/cs', 'active', false, '{}', 0),

  (v_mid, 'Pregnancy-Safe Product Questions',
   E'Do not assert any active (especially retinol/acids) is pregnancy-safe.\nScript: We cannot advise for pregnancy — please ask your physician or book Rocket Clinic consult. Offer to pause retinol recommendations and suggest gentle cleanser + moisturizer only as general retail options pending doctor advice.',
   'medical_boundary', 'en', 'demo_seed', 'seed://rocket-demo/cs', 'active', true,
   ARRAY['pregnancy','pregnant','ตั้งครรภ์','breastfeeding','ให้นม'], 98),

  -- Extra retail FAQs
  (v_mid, 'What is Rocket Club / Rocket Clinic?',
   E'Rocket Club is the loyalty + retail skincare brand (RiceGlow, GlowLab, AgeSoft, etc.).\nRocket Clinic is the in-store aesthetic/wellness clinic arm for packages and specialist consults.\nOne membership; chat can help with both retail and clinic intents.',
   'clinic_policy', 'en', 'demo_seed', 'seed://rocket-demo/cs', 'active', true,
   ARRAY['what is rocket','rocket club','rocket clinic','โรเก็ตคือ'], 75),

  (v_mid, 'How Do I Track My Order?',
   E'Share your order number and purchase platform. Agent/AI will look up order and shipping.\nYou will receive carrier name, tracking number, status, and ETA when available.\nIf not found after verification, escalate to human support.',
   'promotions', 'en', 'demo_seed', 'seed://rocket-demo/cs', 'active', true,
   ARRAY['track my order','tracking number','เช็คพัสดุ','ติดตามพัสดุ'], 92),

  (v_mid, 'Return and Exchange Policy',
   E'Unopened: 7 days online / 14 days in-store.\nOpened: manufacturer defect only.\nClinic packages: service bookings follow cancellation policy, not retail returns.\nProvide order number to check eligibility.',
   'clinic_policy', 'en', 'demo_seed', 'seed://rocket-demo/cs', 'active', true,
   ARRAY['return policy','exchange','คืนสินค้า','เปลี่ยนสินค้า'], 86);

END $$;
