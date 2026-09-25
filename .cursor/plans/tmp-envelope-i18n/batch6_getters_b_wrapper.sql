-- Scope C getters B: extend wrapper with marketplace/form/upload keys (preserve live keys)
CREATE OR REPLACE FUNCTION public.fn_admin_envelope_message(p_key text, p_language text DEFAULT 'en'::text, p_params text[] DEFAULT NULL::text[])
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
DECLARE
  v_lang text := public.fn_normalize_ui_language(p_language);
  v_p1 text := COALESCE(p_params[1], '');
  v_p2 text := COALESCE(p_params[2], '');
  v_hit text;
BEGIN
  v_hit := CASE p_key
    -- preserve existing live wrapper keys
    WHEN 'activity_not_found_title' THEN CASE v_lang WHEN 'th' THEN 'ไม่พบกิจกรรม' ELSE 'Activity not found' END
    WHEN 'activity_created_title' THEN CASE v_lang WHEN 'th' THEN 'สร้างกิจกรรมแล้ว' ELSE 'Activity created' END
    WHEN 'activity_updated_title' THEN CASE v_lang WHEN 'th' THEN 'อัปเดตกิจกรรมแล้ว' ELSE 'Activity updated' END
    WHEN 'matrix_updated_title' THEN CASE v_lang WHEN 'th' THEN 'อัปเดตเมทริกซ์สำเร็จ' ELSE 'Matrix updated successfully' END
    WHEN 'tier_program_config_title' THEN CASE v_lang WHEN 'th' THEN 'การตั้งค่าโปรแกรมระดับสมาชิก' ELSE 'Tier Program Config' END
    WHEN 'tier_program_config_desc' THEN CASE v_lang WHEN 'th' THEN 'โหลดการตั้งค่าโปรแกรมระดับสมาชิกแล้ว' ELSE 'Loaded tier program config' END
    WHEN 'event_not_found_title' THEN CASE v_lang WHEN 'th' THEN 'ไม่พบอีเวนต์' ELSE 'Event not found' END
    WHEN 'event_not_found_desc' THEN CASE v_lang WHEN 'th' THEN 'ไม่พบอีเวนต์รหัส: ' || v_p1 ELSE 'No event found with code: ' || v_p1 END
    WHEN 'agent_not_found_desc' THEN CASE v_lang WHEN 'th' THEN 'ไม่พบเอเจนต์หรือไม่มีสิทธิ์เข้าถึง' ELSE 'Agent not found or access denied' END
    WHEN 'agent_not_found_title' THEN CASE v_lang WHEN 'th' THEN 'ไม่พบเอเจนต์' ELSE 'Agent not found' END
    WHEN 'not_authenticated_desc' THEN CASE v_lang WHEN 'th' THEN 'ยังไม่ได้เข้าสู่ระบบ' ELSE 'Not authenticated' END
    WHEN 'wrong_field_type_title' THEN CASE v_lang WHEN 'th' THEN 'ประเภทฟิลด์ไม่ถูกต้อง' ELSE 'Wrong field type' END
    WHEN 'wrong_field_type_external_code_desc' THEN CASE v_lang WHEN 'th' THEN 'พูลต้องเป็น field_type=external_code' ELSE 'Pool must be field_type=external_code' END
    WHEN 'field_not_found_title' THEN CASE v_lang WHEN 'th' THEN 'ไม่พบฟิลด์' ELSE 'Field not found' END
    WHEN 'package_saved_title' THEN CASE v_lang WHEN 'th' THEN 'บันทึกแพ็กเกจแล้ว' ELSE 'Package saved' END
    WHEN 'earn_conditions_saved_title' THEN CASE v_lang WHEN 'th' THEN 'บันทึกเงื่อนไขการสะสมแล้ว' ELSE 'Earn conditions saved' END
    WHEN 'tier_program_saved_title' THEN CASE v_lang WHEN 'th' THEN 'บันทึกการตั้งค่าโปรแกรมระดับสมาชิกแล้ว' ELSE 'Tier program config saved' END

    -- marketplace order
    WHEN 'unable_determine_merchant_identity_desc' THEN CASE v_lang WHEN 'th' THEN 'ไม่สามารถระบุตัวตนร้านค้าได้' ELSE 'Unable to determine merchant identity' END
    WHEN 'order_number_required_title' THEN CASE v_lang WHEN 'th' THEN 'ต้องระบุหมายเลขคำสั่งซื้อ' ELSE 'Order number required' END
    WHEN 'order_number_required_desc' THEN CASE v_lang WHEN 'th' THEN 'กรุณาระบุ order_sn' ELSE 'Please provide an order_sn' END
    WHEN 'platform_required_title' THEN CASE v_lang WHEN 'th' THEN 'ต้องระบุแพลตฟอร์ม' ELSE 'Platform required' END
    WHEN 'platform_required_desc' THEN CASE v_lang WHEN 'th' THEN 'กรุณาเลือกแพลตฟอร์ม (shopee, tiktok, lazada)' ELSE 'Please select a platform (shopee, tiktok, lazada)' END
    WHEN 'order_not_found_title' THEN CASE v_lang WHEN 'th' THEN 'ไม่พบคำสั่งซื้อ' ELSE 'Order not found' END
    WHEN 'order_not_found_desc' THEN CASE v_lang WHEN 'th' THEN 'ไม่พบคำสั่งซื้อ ' || v_p1 || ' รหัส: ' || v_p2 ELSE 'No ' || v_p1 || ' order found with order_sn: ' || v_p2 END
    WHEN 'order_found_title' THEN CASE v_lang WHEN 'th' THEN 'พบคำสั่งซื้อ' ELSE 'Order found' END

    -- form details
    WHEN 'invalid_mode_new_edit_desc' THEN CASE v_lang WHEN 'th' THEN 'โหมดต้องเป็น "new" หรือ "edit"' ELSE 'Mode must be "new" or "edit"' END
    WHEN 'form_not_found_title' THEN CASE v_lang WHEN 'th' THEN 'ไม่พบฟอร์ม' ELSE 'Form not found' END
    WHEN 'form_not_exist_desc' THEN CASE v_lang WHEN 'th' THEN 'ไม่มีฟอร์มที่ร้องขอ' ELSE 'The requested form does not exist' END
    WHEN 'unauthorized_title' THEN CASE v_lang WHEN 'th' THEN 'ไม่มีสิทธิ์' ELSE 'Unauthorized' END
    WHEN 'form_wrong_merchant_desc' THEN CASE v_lang WHEN 'th' THEN 'ฟอร์มนี้เป็นของร้านค้าอื่น' ELSE 'This form belongs to a different merchant' END

    -- signup codes upload
    WHEN 'field_not_found_desc' THEN CASE v_lang WHEN 'th' THEN 'การตั้งค่าฟิลด์ไม่ใช่ของร้านค้านี้' ELSE 'Field config does not belong to this merchant' END
    WHEN 'target_external_code_required_desc' THEN CASE v_lang WHEN 'th' THEN 'ฟิลด์เป้าหมายต้องเป็น field_type=external_code' ELSE 'Target field must be field_type=external_code' END
    WHEN 'invalid_pool_config_title' THEN CASE v_lang WHEN 'th' THEN 'การตั้งค่าพูลไม่ถูกต้อง' ELSE 'Invalid pool config' END
    WHEN 'invalid_store_binding_desc' THEN CASE v_lang WHEN 'th' THEN 'config.external_code.store_binding ต้องเป็น off|optional|required' ELSE 'config.external_code.store_binding must be off|optional|required' END
    WHEN 'no_codes_provided_title' THEN CASE v_lang WHEN 'th' THEN 'ไม่ได้ระบุรหัส' ELSE 'No codes provided' END
    WHEN 'no_codes_provided_desc' THEN CASE v_lang WHEN 'th' THEN 'p_codes ต้องเป็นอาร์เรย์ที่ไม่ว่าง' ELSE 'p_codes must be a non-empty array' END
    WHEN 'store_binding_validation_failed_title' THEN CASE v_lang WHEN 'th' THEN 'การตรวจสอบการผูกสาขาไม่ผ่าน' ELSE 'Store binding validation failed' END
    WHEN 'store_binding_validation_failed_desc' THEN CASE v_lang WHEN 'th' THEN 'ยังไม่ได้อัปโหลดรหัสใด ๆ กรุณาแก้ไขข้อผิดพลาดแล้วลองใหม่' ELSE 'No codes were uploaded. Fix the errors and retry.' END
    WHEN 'codes_uploaded_title' THEN CASE v_lang WHEN 'th' THEN 'อัปโหลดรหัสแล้ว' ELSE 'Codes uploaded' END
    ELSE NULL
  END;
  IF v_hit IS NOT NULL THEN
    RETURN v_hit;
  END IF;
  RETURN public.fn_admin_envelope_message_core(p_key, p_language, p_params);
END;
$function$;
