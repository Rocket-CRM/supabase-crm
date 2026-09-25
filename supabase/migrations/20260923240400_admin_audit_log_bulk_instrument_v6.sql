-- Patch pass 6: delegate-to-get success returns and non-envelope id returns.

CREATE OR REPLACE FUNCTION public.fn_admin_audit_patch_function_def(p_def text, p_fname text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  patched text;
  hook text;
BEGIN
  IF p_def IS NULL OR p_def = '' THEN RETURN p_def; END IF;
  IF p_def LIKE '%fn_log_admin_action(%' OR p_def LIKE '%fn_log_admin_bff_write(%' THEN RETURN p_def; END IF;

  hook := format(E'PERFORM public.fn_log_admin_bff_write(%L);\n  ', p_fname);
  patched := p_def;

  patched := regexp_replace(patched, 'RETURN jsonb_build_object\(\s*''success''\s*,\s*true\s*,', hook || 'RETURN jsonb_build_object(' || E'\n    ''success'', true,', 'gi');
  patched := regexp_replace(patched, 'RETURN jsonb_build_object\(\s*''success''\s*,\s*true\s*\)', hook || 'RETURN jsonb_build_object(''success'', true)', 'gi');
  patched := regexp_replace(patched, 'RETURN (public\.)?fn_response_success\(', hook || 'RETURN fn_response_success(', 'gi');
  patched := regexp_replace(patched, 'return (public\.)?fn_response_success\(', hook || 'return fn_response_success(', 'gi');
  patched := regexp_replace(patched, 'RETURN jsonb_build_object\(\s*\n\s*''id''\s*,\s*v_key_id', hook || 'RETURN jsonb_build_object(' || E'\n    ''id'', v_key_id', 'gi');
  patched := regexp_replace(patched, 'RETURN jsonb_build_object\(\s*\n\s*''id''\s*,\s*p_key_id', hook || 'RETURN jsonb_build_object(' || E'\n    ''id'', p_key_id', 'gi');
  patched := regexp_replace(patched, '(\n)([ \t]*RETURN (public\.)?bff_get_)', E'\\1' || hook || E'\\1\\2', 'gi');
  patched := regexp_replace(patched, '(\n)([ \t]*RETURN v_result;)', E'\\1' || hook || E'\\1\\2', 'gi');

  IF patched = p_def THEN RETURN p_def; END IF;
  RETURN patched;
END;
$$;

DO $$
DECLARE r record; def text; patched text; applied int := 0;
BEGIN
  FOR r IN
    SELECT p.oid, p.proname FROM pg_proc p
    WHERE p.oid::regprocedure::text IN (
      'bff_upsert_receipt_ocr_set_rule(uuid,jsonb,boolean)',
      'bff_upsert_referral_settings(jsonb)',
      'bff_revoke_merchant_api_key(uuid)',
      'bff_set_upload_receipt_config(text,boolean,text)',
      'bff_upsert_tier_entry_rewards(uuid,jsonb,text)',
      'bff_admin_create_member(text,text,text,text,text,date,text,text,text,uuid,text,text,text,text,text,jsonb,text,text)',
      'bff_upsert_expiry_reminder_settings(time without time zone,text,text)'
    )
  LOOP
    def := pg_get_functiondef(r.oid);
    IF def LIKE '%fn_log_admin_action(%' OR def LIKE '%fn_log_admin_bff_write(%' THEN CONTINUE; END IF;
    patched := fn_admin_audit_patch_function_def(def, r.proname);
    IF patched IS DISTINCT FROM def THEN EXECUTE patched; applied := applied + 1; END IF;
  END LOOP;
  RAISE NOTICE 'admin_audit patch v6 applied=%', applied;
END $$;
