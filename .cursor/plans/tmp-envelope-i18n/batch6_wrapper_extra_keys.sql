
    WHEN 'form_saved_with_full_desc' THEN CASE v_lang WHEN 'th' THEN 'บันทึกแล้ว พร้อมกลุ่ม ' || v_p1 || ' ฟิลด์ ' || v_p2 || ' เงื่อนไข ' || v_p3 || ' และลิมิต ' || v_p4 ELSE 'Saved with ' || v_p1 || ' groups, ' || v_p2 || ' fields, ' || v_p3 || ' conditions, ' || v_p4 || ' limits' END
    WHEN 'basic_currency_created_title' THEN CASE v_lang WHEN 'th' THEN 'สร้างการตั้งค่าสกุลเงินพื้นฐานแล้ว' ELSE 'Basic Currency Config Created' END
