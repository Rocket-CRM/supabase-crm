-- Widget (page_key rewards) copy for points → saved balance flow.
INSERT INTO ui_translations (merchant_id, page_key, field_key, language_code, translated_value)
SELECT NULL, v.page_key, v.field_key, v.language_code, v.translated_value
FROM (VALUES
  ('rewards', 'points_redeem_confirm_title', 'en', 'Use {points} points for ฿{amount} off?'),
  ('rewards', 'points_redeem_confirm_title', 'th', 'ใช้ {points} คะแนน เป็นส่วนลด ฿{amount}?'),
  ('rewards', 'points_redeem_confirm_body', 'en', 'Points are deducted when you confirm. If you don''t complete this order, the discount is saved for your next one.'),
  ('rewards', 'points_redeem_confirm_body', 'th', 'ระบบจะตัดคะแนนทันทีเมื่อยืนยัน หากไม่ได้สั่งซื้อหรือสั่งซื้อไม่สำเร็จ ส่วนลดจะเก็บไว้ใช้กับคำสั่งซื้อถัดไป'),
  ('rewards', 'points_redeem_confirm_confirm', 'en', 'Confirm'),
  ('rewards', 'points_redeem_confirm_confirm', 'th', 'ยืนยัน'),
  ('rewards', 'points_balance_checkout_line', 'en', '฿{amount} will be applied at checkout'),
  ('rewards', 'points_balance_checkout_line', 'th', 'ส่วนลด ฿{amount} จะถูกใช้ตอนชำระเงิน'),
  ('rewards', 'points_redeem_toast_title', 'en', 'Points discount saved'),
  ('rewards', 'points_redeem_toast_title', 'th', 'บันทึกส่วนลดจากคะแนนแล้ว')
) AS v(page_key, field_key, language_code, translated_value)
WHERE NOT EXISTS (
  SELECT 1 FROM ui_translations u
  WHERE u.merchant_id IS NULL
    AND u.page_key = v.page_key
    AND u.field_key = v.field_key
    AND u.language_code = v.language_code
);
