-- Ausiris PDPA notice + membership consent (Thai canonical, English translations).
-- Idempotent. Does not touch rocket-demo or New CRM.

CREATE OR REPLACE FUNCTION public.custom_ausiris_demo_bootstrap_consent()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_mid uuid := custom_ausiris_demo_merchant_id();
  v_notice uuid;
  v_tos uuid;
  v_notice_title_th text := 'หนังสือแจ้งการคุ้มครองข้อมูลส่วนบุคคล';
  v_notice_title_en text := 'Privacy Notice';
  v_notice_preview_th text := 'ออสิริสเก็บ ใช้ และเปิดเผยข้อมูลสมาชิกเพื่อบริหารโปรแกรมสมาชิก ออมทอง และสิทธิประโยชน์';
  v_notice_preview_en text := 'Ausiris collects, uses, and discloses member data to run membership, gold savings, and benefits.';
  v_tos_title_th text := 'ข้อกำหนดและเงื่อนไขการใช้บริการสมาชิก';
  v_tos_title_en text := 'Membership Terms and Conditions';
  v_tos_preview_th text := 'การสมัครและใช้สิทธิสมาชิก ถือว่าท่านยอมรับข้อกำหนดของโปรแกรมสมาชิกออสิริส';
  v_tos_preview_en text := 'By joining and using member benefits, you accept the Ausiris membership terms.';
  v_notice_th text;
  v_notice_en text;
  v_tos_th text;
  v_tos_en text;
BEGIN
  PERFORM custom_ausiris_demo_set_ctx();

  v_notice_th := $th_notice$
<p><strong>หนังสือแจ้งการคุ้มครองข้อมูลส่วนบุคคล</strong></p>
<p>ออสิริส (Ausiris) ในฐานะผู้ควบคุมข้อมูล ขอแจ้งให้สมาชิกทราบถึงการเก็บรวบรวม ใช้ และเปิดเผยข้อมูลส่วนบุคคลตามพระราชบัญญัติคุ้มครองข้อมูลส่วนบุคคล พ.ศ. 2562 เพื่อบริหารโปรแกรมสมาชิก การออมทอง การซื้อทองรูปพรรณและทองแท่ง และสิทธิประโยชน์สะสมคะแนน</p>
<p><strong>1. ข้อมูลที่เก็บรวบรวม</strong></p>
<ul>
<li>ข้อมูลระบุตัวตน เช่น ชื่อ-นามสกุล หมายเลขโทรศัพท์ อีเมล บัญชี LINE</li>
<li>ข้อมูลสมาชิก เช่น ระดับสมาชิก (Silver / Gold / Platinum) ประวัติคะแนน และการแลกรางวัล</li>
<li>ข้อมูลธุรกรรม เช่น ประวัติซื้อ ออมทอง ทองแท่ง ทองรูปพรรณ ร้านสาขา และช่องทางขาย</li>
<li>ข้อมูลการใช้งานแอปและแคมเปญ เช่น การเปิดดู การคลิกลิงก์ และการตอบสนองโปรโมชัน</li>
</ul>
<p><strong>2. วัตถุประสงค์</strong></p>
<ul>
<li>ยืนยันตัวตน สมัครสมาชิก และให้บริการที่ร้านและช่องทางออนไลน์</li>
<li>คำนวณคะแนน ระดับสมาชิก ภารกิจ และสิทธิแลกรางวัล</li>
<li>บริหารบัญชีออมทองและประวัติการซื้อทอง</li>
<li>วิเคราะห์พฤติกรรมสมาชิกเพื่อปรับปรุงบริการ</li>
<li>ปฏิบัติตามกฎหมายที่เกี่ยวข้อง</li>
</ul>
<p><strong>3. การเปิดเผยข้อมูล</strong></p>
<p>ออสิริสอาจเปิดเผยข้อมูลแก่บริษัทในเครือ พนักงานร้านสาขา ผู้ประมวลผลข้อมูลที่ให้บริการระบบสมาชิก (รวมถึง Rocket Innovation) ผู้ให้บริการชำระเงิน และหน่วยงานของรัฐเมื่อกฎหมายกำหนด ไม่ขายรายชื่อสมาชิกให้บุคคลภายนอกเพื่อการตลาดของบุคคลนั้น</p>
<p><strong>4. ระยะเวลาจัดเก็บ</strong></p>
<p>เก็บข้อมูลตลอดอายุสมาชิก และต่อไปอีกไม่เกิน 10 ปีหลังบัญชีสิ้นสุด เพื่อตรวจสอบบัญชีและปฏิบัติตามกฎหมาย หากกฎหมายกำหนดระยะสั้นกว่านั้น จะใช้ระยะนั้น</p>
<p><strong>5. สิทธิของท่าน</strong></p>
<p>ท่านมีสิทธิขอเข้าถึง แก้ไข ลบ จำกัดการใช้ คัดค้าน ประมวลผลด้วยระบบอัตโนมัติ ขอรับข้อมูลในรูปแบบที่โอนได้ และถอนความยินยอมที่ให้ไว้ (การถอนไม่กระทบการประมวลผลที่ได้ทำไปแล้ว) โดยติดต่อพนักงานร้านหรือผ่านแอปสมาชิก</p>
<p><strong>6. ช่องทางติดต่อ</strong></p>
<p>สอบถามเรื่องข้อมูลส่วนบุคคลได้ที่ร้านออสิริสที่ท่านสมัคร หรือผ่านแอปสมาชิก ข้อความนี้จัดทำสำหรับโปรแกรมสาธิต ไม่ทดแทนหนังสือที่บริษัทยื่นต่อหน่วยงาน</p>
$th_notice$;

  v_notice_en := $en_notice$
<p><strong>Privacy Notice</strong></p>
<p>Ausiris, as data controller, collects, uses, and discloses personal data under the Thai Personal Data Protection Act B.E. 2562 to operate membership, gold savings, jewelry and bar purchases, and the points program.</p>
<p><strong>1. Data we collect</strong></p>
<ul>
<li>Identity data such as name, mobile number, email, and LINE account</li>
<li>Membership data such as tier (Silver / Gold / Platinum), points history, and redemptions</li>
<li>Transaction data such as purchases, gold-saving entries, bars, jewelry, branch, and sales channel</li>
<li>App and campaign activity such as views, link clicks, and campaign response</li>
</ul>
<p><strong>2. Purposes</strong></p>
<ul>
<li>Identify you, open a membership, and serve you in store and online</li>
<li>Calculate points, tier, missions, and reward eligibility</li>
<li>Administer gold-saving accounts and gold purchase history</li>
<li>Review member activity to improve the program</li>
<li>Meet legal duties</li>
</ul>
<p><strong>3. Disclosure</strong></p>
<p>Ausiris may share data with affiliates, store staff, processors that run the membership system (including Rocket Innovation), payment providers, and public authorities when the law requires it. We do not sell member lists to third parties for their own marketing.</p>
<p><strong>4. Retention</strong></p>
<p>We keep data for the life of the membership and up to 10 years after the account ends, for audit and legal duties. A shorter period applies when the law requires it.</p>
<p><strong>5. Your rights</strong></p>
<p>You may request access, correction, deletion, restriction, objection, a portable copy, and withdrawal of consent you previously gave (withdrawal does not undo processing already done). Ask store staff or use the member app.</p>
<p><strong>6. Contact</strong></p>
<p>Questions about personal data: the Ausiris branch where you joined, or the member app. This text is for the demo program. It does not replace a notice filed with a regulator.</p>
$en_notice$;

  v_tos_th := $th_tos$
<p><strong>ข้อกำหนดและเงื่อนไขการใช้บริการสมาชิกออสิริส</strong></p>
<p>เมื่อท่านสมัครสมาชิก ใช้คะแนน แลกรางวัล ออมทอง หรือซื้อทองผ่านร้านและช่องทางที่ออสิริสกำหนด ถือว่าท่านอ่านและยอมรับข้อกำหนดนี้</p>
<p><strong>1. สมาชิกและบัญชี</strong></p>
<ul>
<li>บัญชีผูกกับหมายเลขโทรศัพท์และช่องทางล็อกอินที่ท่านใช้สมัคร ข้อมูลต้องเป็นความจริง</li>
<li>ท่านรับผิดชอบการใช้งานบัญชีของท่าน รวมถึงการเข้าสู่ระบบผ่าน LINE</li>
<li>ออสิริสอาจระงับบัญชีหากพบข้อมูลเท็จ การสวมสิทธิ หรือการใช้ที่ผิดเงื่อนไข</li>
</ul>
<p><strong>2. คะแนน ระดับสมาชิก และรางวัล</strong></p>
<ul>
<li>คะแนนเกิดจากการซื้อและกิจกรรมตามอัตราที่ประกาศในขณะนั้น ระดับสมาชิกเป็น Silver, Gold หรือ Platinum ตามยอดสะสม</li>
<li>คะแนนและคูปองมีอายุและเงื่อนไขการใช้ของตนเอง ออสิริสไม่แปลงคะแนนเป็นเงินสด</li>
<li>การแลกรางวัลใช้ได้ตามสต็อกและเงื่อนไขของรางวัลนั้น</li>
</ul>
<p><strong>3. ออมทอง ทองแท่ง และทองรูปพรรณ</strong></p>
<ul>
<li>บัญชีออมทอง น้ำหนักทอง และราคาอ้างอิงเป็นไปตามหลักเกณฑ์ที่ร้านแจ้ง ณ วันทำรายการ</li>
<li>การรับทอง การขายคืน และการปรับราคาเป็นธุรกรรมแยกจากคะแนนสมาชิก เว้นแต่แคมเปญระบุไว้ชัด</li>
<li>เอกสารใบเสร็จและสลิปออมทองเป็นหลักฐานของรายการนั้น</li>
</ul>
<p><strong>4. แคมเปญและภารกิจ</strong></p>
<p>โปรโมชัน ภารกิจ และของรางวัลมีระยะเวลาและกลุ่มเป้าหมายของตนเอง ออสิริสยกเลิกหรือปรับได้หากพบการใช้ผิดเงื่อนไขหรือเหตุสุดวิสัย</p>
<p><strong>5. การเปลี่ยนแปลง</strong></p>
<p>ออสิริสอาจปรับปรุงข้อกำหนด คะแนน หรือสิทธิประโยชน์ โดยแจ้งผ่านแอป ร้านสาขา หรือช่องทางที่ท่านยินยอมรับข่าวสาร การใช้บริการต่อหลังมีผลบังคับถือเป็นการยอมรับฉบับใหม่</p>
<p><strong>6. กฎหมายที่ใช้บังคับ</strong></p>
<p>ข้อกำหนดนี้อยู่ภายใต้กฎหมายไทย ข้อพิพาทให้อยู่ในเขตอำนาจศาลไทย ข้อความนี้จัดทำสำหรับโปรแกรมสาธิตของออสิริส</p>
$th_tos$;

  v_tos_en := $en_tos$
<p><strong>Ausiris Membership Terms and Conditions</strong></p>
<p>By joining, earning or burning points, redeeming rewards, saving gold, or buying gold through Ausiris stores and channels, you confirm you have read and accept these terms.</p>
<p><strong>1. Membership and account</strong></p>
<ul>
<li>The account is tied to the mobile number and login method you used to join. Details must be accurate.</li>
<li>You are responsible for use of your account, including LINE login.</li>
<li>Ausiris may suspend an account for false data, impersonation, or use outside these terms.</li>
</ul>
<p><strong>2. Points, tiers, and rewards</strong></p>
<ul>
<li>Points come from purchases and activities at the rate then in force. Tiers are Silver, Gold, or Platinum from accumulated spend.</li>
<li>Points and coupons carry their own expiry and use rules. Ausiris does not cash out points.</li>
<li>Redemptions follow stock and the rules of that reward.</li>
</ul>
<p><strong>3. Gold saving, bars, and jewelry</strong></p>
<ul>
<li>Gold-saving balances, weight, and reference prices follow the store rules on the transaction date.</li>
<li>Taking physical gold, selling back, and price adjustments are separate from membership points unless a campaign says otherwise.</li>
<li>Receipts and gold-saving slips are the record of that transaction.</li>
</ul>
<p><strong>4. Campaigns and missions</strong></p>
<p>Promotions, missions, and rewards have their own dates and audiences. Ausiris may cancel or adjust them for misuse or force majeure.</p>
<p><strong>5. Changes</strong></p>
<p>Ausiris may update these terms, points, or benefits through the app, the store, or channels you opted into. Continued use after a change takes effect is acceptance of the new version.</p>
<p><strong>6. Governing law</strong></p>
<p>These terms follow Thai law. Disputes sit in Thai courts. This text is for the Ausiris demo program.</p>
$en_tos$;

  INSERT INTO consent_versions (
    merchant_id, version_code, consent_type, interaction_type,
    title, preview, content, is_mandatory, active_status, order_index, published_at
  )
  VALUES (
    v_mid, 'privacy-v1', 'privacy_policy', 'notice',
    v_notice_title_th, v_notice_preview_th, v_notice_th,
    true, true, 1, now()
  )
  ON CONFLICT (merchant_id, version_code) DO UPDATE
  SET
    consent_type = EXCLUDED.consent_type,
    interaction_type = EXCLUDED.interaction_type,
    title = EXCLUDED.title,
    preview = EXCLUDED.preview,
    content = EXCLUDED.content,
    is_mandatory = EXCLUDED.is_mandatory,
    active_status = true,
    order_index = EXCLUDED.order_index,
    published_at = COALESCE(consent_versions.published_at, now())
  RETURNING id INTO v_notice;

  INSERT INTO consent_versions (
    merchant_id, version_code, consent_type, interaction_type,
    title, preview, content, is_mandatory, active_status, order_index, published_at
  )
  VALUES (
    v_mid, 'tos-v1', 'terms_of_service', 'required',
    v_tos_title_th, v_tos_preview_th, v_tos_th,
    true, true, 2, now()
  )
  ON CONFLICT (merchant_id, version_code) DO UPDATE
  SET
    consent_type = EXCLUDED.consent_type,
    interaction_type = EXCLUDED.interaction_type,
    title = EXCLUDED.title,
    preview = EXCLUDED.preview,
    content = EXCLUDED.content,
    is_mandatory = EXCLUDED.is_mandatory,
    active_status = true,
    order_index = EXCLUDED.order_index,
    published_at = COALESCE(consent_versions.published_at, now())
  RETURNING id INTO v_tos;

  INSERT INTO translations (
    merchant_id, entity_type, entity_id, field_name, language_code, translated_value, updated_at
  )
  SELECT v_mid, 'consent_version', x.entity_id, x.field_name, x.lang, x.val, now()
  FROM (VALUES
    (v_notice, 'title',   'th', v_notice_title_th),
    (v_notice, 'preview', 'th', v_notice_preview_th),
    (v_notice, 'content', 'th', v_notice_th),
    (v_notice, 'title',   'en', v_notice_title_en),
    (v_notice, 'preview', 'en', v_notice_preview_en),
    (v_notice, 'content', 'en', v_notice_en),
    (v_tos,    'title',   'th', v_tos_title_th),
    (v_tos,    'preview', 'th', v_tos_preview_th),
    (v_tos,    'content', 'th', v_tos_th),
    (v_tos,    'title',   'en', v_tos_title_en),
    (v_tos,    'preview', 'en', v_tos_preview_en),
    (v_tos,    'content', 'en', v_tos_en)
  ) AS x(entity_id, field_name, lang, val)
  ON CONFLICT (merchant_id, entity_type, entity_id, field_name, language_code)
  DO UPDATE SET translated_value = EXCLUDED.translated_value, updated_at = now();

  INSERT INTO custom_ausiris_demo_config (kind, code, payload, sort_order)
  VALUES
    ('consent', 'privacy-v1', jsonb_build_object('id', v_notice, 'type', 'privacy_policy'), 40),
    ('consent', 'tos-v1', jsonb_build_object('id', v_tos, 'type', 'terms_of_service'), 41)
  ON CONFLICT (kind, code) DO UPDATE
  SET payload = EXCLUDED.payload, updated_at = now();

  RETURN jsonb_build_object(
    'success', true,
    'notice_id', v_notice,
    'consent_id', v_tos,
    'languages', jsonb_build_array('th', 'en')
  );
END;
$fn$;
