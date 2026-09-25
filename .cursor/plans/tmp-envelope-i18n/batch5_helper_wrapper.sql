
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
    ELSE NULL
  END;
  IF v_hit IS NOT NULL THEN RETURN v_hit; END IF;
  RETURN public.fn_admin_envelope_message_core(p_key, p_language, p_params);
END;
$function$;
