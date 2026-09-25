-- Scope C upserts: extend fn_admin_envelope_message (preserve existing + add upsert keys)
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
  v_p3 text := COALESCE(p_params[3], '');
  v_p4 text := COALESCE(p_params[4], '');
  v_hit text;
BEGIN
  v_hit := CASE p_key
    WHEN 'activity_not_found_title' THEN CASE v_lang WHEN 'th' THEN 'ไม่พบกิจกรรม' ELSE 'Activity not found' END
    WHEN 'activity_created_title' THEN CASE v_lang WHEN 'th' THEN 'สร้างกิจกรรมแล้ว' ELSE 'Activity created' END
    WHEN 'activity_updated_title' THEN CASE v_lang WHEN 'th' THEN 'อัปเดตกิจกรรมแล้ว' ELSE 'Activity updated' END
    WHEN 'matrix_updated_title' THEN CASE v_lang WHEN 'th' THEN 'อัปเดตเมทริกซ์สำเร็จ' ELSE 'Matrix updated successfully' END
    WHEN 'tier_program_config_title' THEN CASE v_lang WHEN 'th' THEN 'การตั้งค่าโปรแกรมระดับสมาชิก' ELSE 'Tier Program Config' END
    WHEN 'tier_program_config_desc' THEN CASE v_lang WHEN 'th' THEN 'โหลดการตั้งค่าโปรแกรมระดับสมาชิกแล้ว' ELSE 'Loaded tier program config' END
    WHEN 'event_not_found_title' THEN CASE v_lang WHEN 'th' THEN 'ไม่พบอีเวนต์' ELSE 'Event not found' END
    WHEN 'event_not_found_desc' THEN CASE v_lang WHEN 'th' THEN 'ไม่พบอีเวนต์รหัส: ' || v_p1 ELSE 'No event found with code: ' || v_p1 END

    -- package
    WHEN 'package_created_title' THEN CASE v_lang WHEN 'th' THEN 'สร้างแพ็กเกจแล้ว' ELSE 'Package created' END
    WHEN 'package_updated_title' THEN CASE v_lang WHEN 'th' THEN 'อัปเดตแพ็กเกจแล้ว' ELSE 'Package updated' END

    -- earn conditions group
    WHEN 'missing_merchant_id_desc' THEN CASE v_lang WHEN 'th' THEN 'ไม่มี merchant_id' ELSE 'Missing merchant_id' END
    WHEN 'conditions_group_created_title' THEN CASE v_lang WHEN 'th' THEN 'สร้างกลุ่มเงื่อนไขแล้ว' ELSE 'Conditions Group Created' END
    WHEN 'conditions_group_updated_title' THEN CASE v_lang WHEN 'th' THEN 'อัปเดตกลุ่มเงื่อนไขแล้ว' ELSE 'Conditions Group Updated' END
    WHEN 'conditions_group_action_desc' THEN CASE v_lang WHEN 'th' THEN 'กลุ่มเงื่อนไข "' || v_p1 || '" ' || v_p2 || ' พร้อมเงื่อนไข ' || v_p3 || ' รายการ' ELSE 'Conditions group "' || v_p1 || '" ' || v_p2 || ' with ' || v_p3 || ' conditions' END

    -- tier program config
    WHEN 'invalid_metric_title' THEN CASE v_lang WHEN 'th' THEN 'เมตริกไม่ถูกต้อง' ELSE 'Invalid Metric' END
    WHEN 'metric_required_desc' THEN CASE v_lang WHEN 'th' THEN 'ต้องระบุเมตริก' ELSE 'metric is required' END
    WHEN 'invalid_period_type_title' THEN CASE v_lang WHEN 'th' THEN 'ประเภทช่วงเวลาไม่ถูกต้อง' ELSE 'Invalid Period Type' END
    WHEN 'period_type_must_be_desc' THEN CASE v_lang WHEN 'th' THEN 'period_type ต้องเป็น calendar_year หรือ rolling' ELSE 'period_type must be calendar_year or rolling' END
    WHEN 'invalid_start_month_title' THEN CASE v_lang WHEN 'th' THEN 'เดือนเริ่มต้นไม่ถูกต้อง' ELSE 'Invalid Start Month' END
    WHEN 'calendar_year_month_desc' THEN CASE v_lang WHEN 'th' THEN 'calendar_year ต้องมี period_start_month ระหว่าง 1 ถึง 12' ELSE 'calendar_year requires period_start_month between 1 and 12' END
    WHEN 'invalid_rolling_months_title' THEN CASE v_lang WHEN 'th' THEN 'จำนวนเดือนแบบ rolling ไม่ถูกต้อง' ELSE 'Invalid Rolling Months' END
    WHEN 'rolling_months_range_desc' THEN CASE v_lang WHEN 'th' THEN 'rolling ต้องมี rolling_months ระหว่าง 1 ถึง 36' ELSE 'rolling requires rolling_months between 1 and 36' END
    WHEN 'invalid_upgrade_timing_title' THEN CASE v_lang WHEN 'th' THEN 'จังหวะอัปเกรดไม่ถูกต้อง' ELSE 'Invalid Upgrade Timing' END
    WHEN 'upgrade_timing_must_be_desc' THEN CASE v_lang WHEN 'th' THEN 'upgrade_timing ต้องเป็น immediate หรือ end_of_month' ELSE 'upgrade_timing must be immediate or end_of_month' END
    WHEN 'invalid_maintain_mode_title' THEN CASE v_lang WHEN 'th' THEN 'โหมดรักษาระดับไม่ถูกต้อง' ELSE 'Invalid Maintain Mode' END
    WHEN 'maintain_mode_must_be_desc' THEN CASE v_lang WHEN 'th' THEN 'maintain_mode ต้องเป็น lifetime หรือ period' ELSE 'maintain_mode must be lifetime or period' END
    WHEN 'program_saved_title' THEN CASE v_lang WHEN 'th' THEN 'บันทึกโปรแกรมแล้ว' ELSE 'Program Saved' END
    WHEN 'tier_program_config_saved_desc' THEN CASE v_lang WHEN 'th' THEN 'บันทึกการตั้งค่าโปรแกรมระดับสมาชิกแล้ว' ELSE 'Tier program config saved' END

    -- contract
    WHEN 'contract_created_title' THEN CASE v_lang WHEN 'th' THEN 'สร้างสัญญาแล้ว' ELSE 'Contract created' END
    WHEN 'contract_updated_title' THEN CASE v_lang WHEN 'th' THEN 'อัปเดตสัญญาแล้ว' ELSE 'Contract updated' END
    WHEN 'contract_group_not_found_title' THEN CASE v_lang WHEN 'th' THEN 'ไม่พบกลุ่มสัญญา' ELSE 'Contract group not found' END

    -- earn factor group
    WHEN 'invalid_perspective_desc' THEN CASE v_lang WHEN 'th' THEN 'perspective ไม่ถูกต้อง: "' || v_p1 || '" ต้องเป็น buyer หรือ seller' ELSE 'Invalid perspective: "' || v_p1 || '". Must be one of: buyer, seller.' END
    WHEN 'earn_factor_group_not_found_desc' THEN CASE v_lang WHEN 'th' THEN 'ไม่พบกลุ่ม earn factor หรือไม่มีสิทธิ์เข้าถึง' ELSE 'Earn factor group not found or access denied' END
    WHEN 'earn_factor_group_created_title' THEN CASE v_lang WHEN 'th' THEN 'สร้างกลุ่ม Earn Factor แล้ว' ELSE 'Earn Factor Group Created' END
    WHEN 'earn_factor_group_updated_title' THEN CASE v_lang WHEN 'th' THEN 'อัปเดตกลุ่ม Earn Factor แล้ว' ELSE 'Earn Factor Group Updated' END
    WHEN 'earn_factor_group_action_desc' THEN CASE v_lang WHEN 'th' THEN 'กลุ่ม earn factor "' || v_p1 || '" ' || v_p2 || ' พร้อมปัจจัย ' || v_p3 || ' รายการ' ELSE 'Earn factor group "' || v_p1 || '" ' || v_p2 || ' with ' || v_p3 || ' factors' END

    -- reward group
    WHEN 'invalid_configuration_title' THEN CASE v_lang WHEN 'th' THEN 'การตั้งค่าไม่ถูกต้อง' ELSE 'Invalid configuration' END
    WHEN 'conflicting_group_limits_desc' THEN CASE v_lang WHEN 'th' THEN 'Max Distinct Reward (' || v_p1 || ') ต้องไม่เกิน Group Quantity Limit (' || v_p2 || ') ต่อผู้ใช้ ผู้ใช้ไม่สามารถเลือกรางวัลประเภทต่างกันได้มากกว่าจำนวนสิทธิ์แลกทั้งหมด' ELSE 'Max Distinct Reward (' || v_p1 || ') cannot exceed Group Quantity Limit (' || v_p2 || ') per user. A user cannot pick more distinct reward types than the total number of redemptions allowed.' END
    WHEN 'reward_group_not_found_desc' THEN CASE v_lang WHEN 'th' THEN 'ไม่พบกลุ่มรางวัล หรือไม่มีสิทธิ์เข้าถึง' ELSE 'Reward group not found or access denied' END
    WHEN 'invalid_metric_scope_desc' THEN CASE v_lang WHEN 'th' THEN 'ลิมิต Max Distinct Reward ต้องใช้ scope = user' ELSE 'Max Distinct Reward limits must use scope = user.' END
    WHEN 'reward_group_created_title' THEN CASE v_lang WHEN 'th' THEN 'สร้างกลุ่มรางวัลแล้ว' ELSE 'Reward Group Created' END
    WHEN 'reward_group_updated_title' THEN CASE v_lang WHEN 'th' THEN 'อัปเดตกลุ่มรางวัลแล้ว' ELSE 'Reward Group Updated' END
    WHEN 'reward_group_action_desc' THEN CASE v_lang WHEN 'th' THEN 'กลุ่มรางวัล "' || v_p1 || '" ' || v_p2 || ' พร้อมลิมิต ' || v_p3 || ' รายการ' ELSE 'Reward group "' || v_p1 || '" ' || v_p2 || ' with ' || v_p3 || ' limits' END

    -- amp workflow
    WHEN 'workflow_not_found_desc' THEN CASE v_lang WHEN 'th' THEN 'ไม่พบเวิร์กโฟลว์ หรือไม่มีสิทธิ์เข้าถึง' ELSE 'Workflow not found or access denied' END
    WHEN 'workflow_created_title' THEN CASE v_lang WHEN 'th' THEN 'สร้างเวิร์กโฟลว์แล้ว' ELSE 'Workflow Created' END
    WHEN 'workflow_updated_title' THEN CASE v_lang WHEN 'th' THEN 'อัปเดตเวิร์กโฟลว์แล้ว' ELSE 'Workflow Updated' END
    WHEN 'workflow_action_desc' THEN CASE v_lang WHEN 'th' THEN 'เวิร์กโฟลว์ "' || v_p1 || '" ' || v_p2 || ' พร้อมโหนด ' || v_p3 || ' และทริกเกอร์ ' || v_p4 ELSE 'Workflow "' || v_p1 || '" ' || v_p2 || ' with ' || v_p3 || ' nodes and ' || v_p4 || ' triggers' END

    -- tier with conditions
    WHEN 'unsupported_fields_title' THEN CASE v_lang WHEN 'th' THEN 'ฟิลด์ที่ไม่รองรับ' ELSE 'Unsupported Fields' END
    WHEN 'unsupported_fields_desc' THEN CASE v_lang WHEN 'th' THEN 'ฟิลด์เหล่านี้ไม่ได้ตั้งค่าระดับต่อระดับแล้ว: ' || v_p1 || '. เมตริก ช่วงเวลา จังหวะอัปเกรด และ maintain_mode อยู่ในค่าตั้งโปรแกรมระดับ; ยอด maintain เท่ากับยอดอัปเกรด; ลำดับบันไดและระดับเริ่มต้นคำนวณจากยอดอัปเกรด' ELSE 'These fields are no longer set per tier: ' || v_p1 || '. Metric, period, upgrade timing and maintain_mode belong to the tier program config; maintain amount equals the tier upgrade amount; ladder order and entry tier are derived from upgrade amounts.' END
    WHEN 'invalid_personas_title' THEN CASE v_lang WHEN 'th' THEN 'เพอร์โซนาไม่ถูกต้อง' ELSE 'Invalid Personas' END
    WHEN 'persona_ids_array_desc' THEN CASE v_lang WHEN 'th' THEN 'persona_ids ต้องเป็นอาร์เรย์' ELSE 'persona_ids must be an array' END
    WHEN 'invalid_persona_title' THEN CASE v_lang WHEN 'th' THEN 'เพอร์โซนาไม่ถูกต้อง' ELSE 'Invalid Persona' END
    WHEN 'personas_not_found_inactive_desc' THEN CASE v_lang WHEN 'th' THEN 'ไม่พบเพอร์โซนาอย่างน้อยหนึ่งรายการ หรือไม่ได้เปิดใช้งาน' ELSE 'One or more personas were not found or inactive' END
    WHEN 'tier_program_not_configured_title' THEN CASE v_lang WHEN 'th' THEN 'ยังไม่ได้ตั้งค่าโปรแกรมระดับสมาชิก' ELSE 'Tier Program Not Configured' END
    WHEN 'tier_program_not_configured_desc' THEN CASE v_lang WHEN 'th' THEN 'ตั้งค่าโปรแกรมระดับสมาชิก (เมตริกและช่วงเวลา) ก่อนบันทึกเกณฑ์ระดับ' ELSE 'Set up the tier program (metric and period) before saving tier thresholds.' END
    WHEN 'tier_created_title' THEN CASE v_lang WHEN 'th' THEN 'สร้างระดับสมาชิกแล้ว' ELSE 'Tier Created' END
    WHEN 'tier_updated_title' THEN CASE v_lang WHEN 'th' THEN 'อัปเดตระดับสมาชิกแล้ว' ELSE 'Tier Updated' END
    WHEN 'tier_action_desc' THEN CASE v_lang WHEN 'th' THEN 'ระดับ "' || v_p1 || '" ' || v_p2 || ' สำเร็จ' ELSE 'Tier "' || v_p1 || '" ' || v_p2 || ' successfully' END

    -- reward
    WHEN 'reward_not_found_desc' THEN CASE v_lang WHEN 'th' THEN 'ไม่พบรางวัล หรือไม่มีสิทธิ์เข้าถึง' ELSE 'Reward not found or access denied' END
    WHEN 'reward_created_title' THEN CASE v_lang WHEN 'th' THEN 'สร้างรางวัลแล้ว' ELSE 'Reward Created' END
    WHEN 'reward_updated_title' THEN CASE v_lang WHEN 'th' THEN 'อัปเดตรางวัลแล้ว' ELSE 'Reward Updated' END
    WHEN 'reward_action_desc' THEN CASE v_lang WHEN 'th' THEN 'รางวัล "' || v_p1 || '" ' || v_p2 || ' พร้อมราคา ' || v_p3 || ' ระดับ และลิมิต ' || v_p4 || ' รายการ' ELSE 'Reward "' || v_p1 || '" ' || v_p2 || ' with ' || v_p3 || ' price tiers and ' || v_p4 || ' limits' END

    -- form upsert
    WHEN 'form_created_title' THEN CASE v_lang WHEN 'th' THEN 'สร้างฟอร์มแล้ว' ELSE 'Form created' END
    WHEN 'form_updated_title' THEN CASE v_lang WHEN 'th' THEN 'อัปเดตฟอร์มสำเร็จ' ELSE 'Form updated successfully' END
    WHEN 'form_not_found_title' THEN CASE v_lang WHEN 'th' THEN 'ไม่พบฟอร์ม' ELSE 'Form not found' END
    WHEN 'form_not_found_merchant_desc' THEN CASE v_lang WHEN 'th' THEN 'ไม่พบฟอร์ม หรือสังกัดร้านค้าอื่น' ELSE 'Form not found or belongs to different merchant' END
    WHEN 'form_not_exist_desc' THEN CASE v_lang WHEN 'th' THEN 'ไม่มีฟอร์มที่ร้องขอ' ELSE 'The requested form does not exist' END
    WHEN 'invalid_payload_title' THEN CASE v_lang WHEN 'th' THEN 'เพย์โหลดไม่ถูกต้อง' ELSE 'Invalid payload' END
    WHEN 'missing_form_object_desc' THEN CASE v_lang WHEN 'th' THEN 'ไม่มีอ็อบเจ็กต์ form ในเพย์โหลด' ELSE 'Missing form object in payload' END
    WHEN 'unauthorized_title' THEN CASE v_lang WHEN 'th' THEN 'ไม่มีสิทธิ์' ELSE 'Unauthorized' END
    WHEN 'error_saving_form_title' THEN CASE v_lang WHEN 'th' THEN 'บันทึกฟอร์มไม่สำเร็จ' ELSE 'Error saving form' END
    WHEN 'form_saved_with_desc' THEN CASE v_lang WHEN 'th' THEN 'บันทึกแล้ว พร้อมฟิลด์ ' || v_p1 || ' กลุ่ม ' || v_p2 || ' และเงื่อนไข ' || v_p3 ELSE 'Saved with ' || v_p1 || ' fields, ' || v_p2 || ' groups, ' || v_p3 || ' conditions' END

    -- basic currency
    WHEN 'basic_currency_updated_title' THEN CASE v_lang WHEN 'th' THEN 'อัปเดตการตั้งค่าสกุลเงินพื้นฐานแล้ว' ELSE 'Basic Currency Config Updated' END
    WHEN 'basic_currency_config_saved_desc' THEN CASE v_lang WHEN 'th' THEN 'บันทึกการตั้งค่า ' || v_p1 || ' พื้นฐานแล้ว' ELSE 'Basic ' || v_p1 || ' config saved' END


    -- Scope C getters/lists
    WHEN 'agent_not_found_desc' THEN CASE v_lang WHEN 'th' THEN 'ไม่พบเอเจนต์หรือไม่มีสิทธิ์เข้าถึง' ELSE 'Agent not found or access denied' END
    WHEN 'agent_not_found_short_desc' THEN CASE v_lang WHEN 'th' THEN 'ไม่พบเอเจนต์' ELSE 'Agent not found' END
    WHEN 'not_authenticated_title' THEN CASE v_lang WHEN 'th' THEN 'ยังไม่ได้ยืนยันตัวตน' ELSE 'Not authenticated' END
    WHEN 'user_not_found_title' THEN CASE v_lang WHEN 'th' THEN 'ไม่พบผู้ใช้' ELSE 'User not found' END
    WHEN 'invalid_mode_new_edit_desc' THEN CASE v_lang WHEN 'th' THEN 'โหมดต้องเป็น "new" หรือ "edit"' ELSE 'Mode must be "new" or "edit"' END
    WHEN 'form_wrong_merchant_desc' THEN CASE v_lang WHEN 'th' THEN 'ฟอร์มนี้เป็นของร้านค้าอื่น' ELSE 'This form belongs to a different merchant' END
    WHEN 'unable_determine_merchant_identity_desc' THEN CASE v_lang WHEN 'th' THEN 'ไม่สามารถระบุตัวตนร้านค้าได้' ELSE 'Unable to determine merchant identity' END
    WHEN 'order_number_required_title' THEN CASE v_lang WHEN 'th' THEN 'ต้องระบุหมายเลขคำสั่งซื้อ' ELSE 'Order number required' END
    WHEN 'order_number_required_desc' THEN CASE v_lang WHEN 'th' THEN 'กรุณาระบุ order_sn' ELSE 'Please provide an order_sn' END
    WHEN 'platform_required_title' THEN CASE v_lang WHEN 'th' THEN 'ต้องระบุแพลตฟอร์ม' ELSE 'Platform required' END
    WHEN 'platform_required_desc' THEN CASE v_lang WHEN 'th' THEN 'กรุณาเลือกแพลตฟอร์ม (shopee, tiktok, lazada)' ELSE 'Please select a platform (shopee, tiktok, lazada)' END
    WHEN 'order_not_found_title' THEN CASE v_lang WHEN 'th' THEN 'ไม่พบคำสั่งซื้อ' ELSE 'Order not found' END
    WHEN 'order_not_found_desc' THEN CASE v_lang WHEN 'th' THEN 'ไม่พบคำสั่งซื้อ ' || v_p1 || ' รหัส: ' || v_p2 ELSE 'No ' || v_p1 || ' order found with order_sn: ' || v_p2 END
    WHEN 'order_found_title' THEN CASE v_lang WHEN 'th' THEN 'พบคำสั่งซื้อ' ELSE 'Order found' END
    WHEN 'insufficient_permissions_desc' THEN CASE v_lang WHEN 'th' THEN 'สิทธิ์ไม่เพียงพอ' ELSE 'Insufficient permissions' END
    WHEN 'wrong_field_type_title' THEN CASE v_lang WHEN 'th' THEN 'ประเภทฟิลด์ไม่ถูกต้อง' ELSE 'Wrong field type' END
    WHEN 'pool_external_code_required_desc' THEN CASE v_lang WHEN 'th' THEN 'พูลต้องเป็น field_type=external_code' ELSE 'Pool must be field_type=external_code' END
    WHEN 'field_not_found_title' THEN CASE v_lang WHEN 'th' THEN 'ไม่พบฟิลด์' ELSE 'Field not found' END
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
