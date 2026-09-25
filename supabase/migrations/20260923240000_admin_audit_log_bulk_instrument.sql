-- Phase 5 bulk rollout: inferred audit logging on admin write BFFs without explicit hooks.

CREATE TABLE IF NOT EXISTS public.admin_audit_log_exempt (
  function_name text PRIMARY KEY,
  reason text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO admin_audit_log_exempt (function_name, reason) VALUES
  ('fn_log_admin_action', 'logger'),
  ('fn_log_admin_bff_write', 'logger'),
  ('bff_admin_list_audit_log', 'read-only list')
ON CONFLICT (function_name) DO NOTHING;

CREATE OR REPLACE FUNCTION public.fn_admin_audit_infer_action(p_source text)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  n text;
  verb text;
  entity text;
  action text;
BEGIN
  n := regexp_replace(p_source, '^cs_bff_', '');
  n := regexp_replace(n, '^bff_admin_', '');
  n := regexp_replace(n, '^bff_', '');

  IF p_source IN (
    'bff_upsert_reward_with_conditions_and_limits',
    'bff_approve_receipt_upload'
  ) THEN
    RETURN NULL;
  END IF;

  IF n ~ '^upsert_' THEN
    verb := 'update';
    entity := regexp_replace(n, '^upsert_', '');
    entity := split_part(entity, '_', 1);
  ELSIF n ~ '^delete_' OR n ~ '_delete_' THEN
    verb := 'delete';
    entity := coalesce(nullif(regexp_replace(n, '.*(delete)_(.+)$', '\2'), n), split_part(n, '_', 1));
    entity := split_part(entity, '_', 1);
  ELSIF n ~ '^create_' OR n ~ '_create_' THEN
    verb := 'create';
    entity := split_part(regexp_replace(n, '^create_', ''), '_', 1);
    IF entity = '' THEN entity := split_part(n, '_', 1); END IF;
  ELSIF n ~ 'adjust_currency' OR n = 'adjust_currency' THEN
    RETURN jsonb_build_object('action', 'currency.adjust', 'entity_type', 'member');
  ELSIF n ~ 'adjust_member_tier' OR n ~ 'adjust.*tier' THEN
    RETURN jsonb_build_object('action', 'tier.adjust', 'entity_type', 'member');
  ELSIF n ~ 'approve' THEN
    verb := 'approve';
    entity := coalesce(nullif(split_part(n, '_', 1), ''), 'record');
  ELSIF n ~ 'reject' THEN
    verb := 'reject';
    entity := 'receipt';
  ELSIF n ~ '^set_' THEN
    verb := 'update';
    entity := regexp_replace(n, '^set_', '');
    entity := split_part(entity, '_', 1);
  ELSIF n ~ '^update_' THEN
    verb := 'update';
    entity := regexp_replace(n, '^update_', '');
    entity := split_part(entity, '_', 1);
  ELSE
    verb := 'write';
    entity := split_part(n, '_', 1);
  END IF;

  IF entity IS NULL OR entity = '' THEN
    entity := 'record';
  END IF;

  entity := regexp_replace(entity, 's$', '');
  action := entity || '.' || verb;

  RETURN jsonb_build_object('action', action, 'entity_type', entity);
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_log_admin_bff_write(
  p_source text,
  p_payload jsonb DEFAULT '{}'::jsonb,
  p_entity_id uuid DEFAULT NULL,
  p_entity_type text DEFAULT NULL,
  p_related jsonb DEFAULT '{}'::jsonb,
  p_reason text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_meta jsonb;
  v_action text;
  v_entity_type text;
BEGIN
  IF EXISTS (SELECT 1 FROM admin_audit_log_exempt e WHERE e.function_name = p_source) THEN
    RETURN;
  END IF;

  v_meta := fn_admin_audit_infer_action(p_source);
  IF v_meta IS NULL THEN
    RETURN;
  END IF;

  v_action := v_meta->>'action';
  v_entity_type := COALESCE(p_entity_type, v_meta->>'entity_type');

  PERFORM fn_log_admin_action(
    v_action,
    v_entity_type,
    p_entity_id,
    COALESCE(p_payload, '{}'::jsonb),
    NULL,
    NULL,
    COALESCE(p_related, '{}'::jsonb),
    p_reason,
    p_source
  );
END;
$$;

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
    'RETURN jsonb_build_object\(\s*\n\s*''success'', true,',
    hook || 'RETURN jsonb_build_object(' || E'\n    ''success'', true,',
    'g'
  );

  patched := regexp_replace(
    patched,
    'RETURN fn_response_success\(',
    hook || 'RETURN fn_response_success(',
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
  skipped integer := 0;
BEGIN
  FOR r IN
    SELECT p.oid, p.proname
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND (
        (p.proname LIKE 'bff\_%' AND p.proname NOT LIKE 'bff\_user\_%')
        OR p.proname LIKE 'cs\_bff\_%'
      )
      AND pg_get_functiondef(p.oid) ~* '(INSERT INTO|UPDATE |DELETE FROM)'
      AND NOT EXISTS (SELECT 1 FROM admin_audit_log_exempt e WHERE e.function_name = p.proname)
  LOOP
    def := pg_get_functiondef(r.oid);
    IF def LIKE '%fn_log_admin_action(%' OR def LIKE '%fn_log_admin_bff_write(%' THEN
      skipped := skipped + 1;
      CONTINUE;
    END IF;

    patched := fn_admin_audit_patch_function_def(def, r.proname);
    IF patched IS DISTINCT FROM def THEN
      BEGIN
        EXECUTE patched;
        applied := applied + 1;
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'admin_audit patch failed for %: %', r.proname, SQLERRM;
      END;
    ELSE
      skipped := skipped + 1;
    END IF;
  END LOOP;

  RAISE NOTICE 'admin_audit bulk instrument: applied=%, skipped=%', applied, skipped;
END $$;
