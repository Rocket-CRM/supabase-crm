-- Patch pass 5: success object without trailing comma; non-envelope success returns.

CREATE OR REPLACE FUNCTION public.fn_admin_audit_patch_function_def(p_def text, p_fname text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  patched text;
  hook text;
BEGIN
  IF p_def IS NULL OR p_def = '' THEN
    RETURN p_def;
  END IF;
  IF p_def LIKE '%fn_log_admin_action(%' OR p_def LIKE '%fn_log_admin_bff_write(%' THEN
    RETURN p_def;
  END IF;

  hook := format(E'PERFORM public.fn_log_admin_bff_write(%L);\n  ', p_fname);
  patched := p_def;

  patched := regexp_replace(
    patched,
    'RETURN jsonb_build_object\(\s*''success''\s*,\s*true\s*,',
    hook || 'RETURN jsonb_build_object(' || E'\n    ''success'', true,',
    'g'
  );

  patched := regexp_replace(
    patched,
    'RETURN jsonb_build_object\(\s*''success''\s*,\s*true\s*\)',
    hook || 'RETURN jsonb_build_object(''success'', true)',
    'g'
  );

  patched := regexp_replace(
    patched,
    'RETURN public\.fn_response_success\(',
    hook || 'RETURN public.fn_response_success(',
    'g'
  );

  patched := regexp_replace(
    patched,
    'RETURN fn_response_success\(',
    hook || 'RETURN fn_response_success(',
    'gi'
  );

  patched := regexp_replace(
    patched,
    'return fn_response_success\(',
    hook || 'return fn_response_success(',
    'gi'
  );

  patched := regexp_replace(
    patched,
    'RETURN jsonb_build_object\(\s*\n\s*''id''\s*,\s*v_key_id',
    hook || 'RETURN jsonb_build_object(' || E'\n    ''id'', v_key_id',
    'g'
  );

  IF patched = p_def THEN
    RETURN p_def;
  END IF;

  RETURN patched;
END;
$$;

DO $$
DECLARE
  r record;
  def text;
  patched text;
  applied integer := 0;
BEGIN
  FOR r IN
    SELECT p.oid, p.proname
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN (
        'bff_admin_create_member',
        'bff_admin_update_admin_user_stores',
        'bff_create_merchant_api_key',
        'bff_delete_agent',
        'bff_revoke_merchant_api_key',
        'bff_set_upload_receipt_config',
        'bff_upsert_expiry_reminder_settings',
        'bff_upsert_receipt_ocr_set_rule',
        'bff_upsert_referral_settings',
        'bff_upsert_tier_entry_rewards'
      )
      AND pg_get_functiondef(p.oid) NOT LIKE '%fn_log_admin_action(%'
      AND pg_get_functiondef(p.oid) NOT LIKE '%fn_log_admin_bff_write(%'
  LOOP
    def := pg_get_functiondef(r.oid);
    patched := fn_admin_audit_patch_function_def(def, r.proname);
    IF patched IS DISTINCT FROM def THEN
      BEGIN
        EXECUTE patched;
        applied := applied + 1;
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'admin_audit patch v5 failed for %: %', r.proname, SQLERRM;
      END;
    END IF;
  END LOOP;
  RAISE NOTICE 'admin_audit patch v5 applied=%', applied;
END $$;
