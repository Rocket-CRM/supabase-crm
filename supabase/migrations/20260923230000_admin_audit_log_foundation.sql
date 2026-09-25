-- Admin audit log foundation (Phase 2): table, helpers, read BFF, partition cron, permission seed.

-- ---------------------------------------------------------------------------
-- 1) Append-only partitioned log
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.admin_audit_log (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  merchant_id uuid NOT NULL,
  actor_admin_id uuid NOT NULL,
  action text NOT NULL,
  entity_type text NOT NULL,
  entity_id uuid,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  changes jsonb NOT NULL DEFAULT '{}'::jsonb,
  related jsonb NOT NULL DEFAULT '{}'::jsonb,
  reason text,
  source text,
  context jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (id, created_at)
) PARTITION BY RANGE (created_at);

CREATE INDEX IF NOT EXISTS admin_audit_log_merchant_created_idx
  ON public.admin_audit_log (merchant_id, created_at DESC);

CREATE INDEX IF NOT EXISTS admin_audit_log_merchant_entity_idx
  ON public.admin_audit_log (merchant_id, entity_type, entity_id, created_at DESC);

ALTER TABLE public.admin_audit_log ENABLE ROW LEVEL SECURITY;

-- No policies: reads/writes go through SECURITY DEFINER BFFs and fn_log_admin_action.

CREATE OR REPLACE FUNCTION public.trg_admin_audit_log_append_only()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'admin_audit_log is append-only';
  END IF;
  IF TG_OP = 'UPDATE' AND COALESCE(current_setting('admin_audit_log.scrub', true), '') <> 'allow' THEN
    RAISE EXCEPTION 'admin_audit_log is append-only';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS admin_audit_log_no_update ON public.admin_audit_log;
CREATE TRIGGER admin_audit_log_no_update
  BEFORE UPDATE OR DELETE ON public.admin_audit_log
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_admin_audit_log_append_only();

-- ---------------------------------------------------------------------------
-- 2) Partition helpers (24-month retention)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_admin_audit_log_ensure_partitions(
  p_months_ahead integer DEFAULT 2,
  p_retention_months integer DEFAULT 24
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_part_start timestamptz;
  v_part_end timestamptz;
  v_part_name text;
  v_drop_end date;
  r record;
  i integer;
BEGIN
  FOR i IN 0..GREATEST(p_months_ahead, 0) LOOP
    v_part_start := date_trunc('month', now()) + (i || ' months')::interval;
    v_part_end := v_part_start + interval '1 month';
    v_part_name := format('admin_audit_log_%s', to_char(v_part_start, 'YYYY_MM'));
    IF to_regclass('public.' || v_part_name) IS NULL THEN
      EXECUTE format(
        'CREATE TABLE public.%I PARTITION OF public.admin_audit_log FOR VALUES FROM (%L) TO (%L)',
        v_part_name,
        v_part_start,
        v_part_end
      );
    END IF;
  END LOOP;

  v_drop_end := (date_trunc('month', now()) - (p_retention_months || ' months')::interval)::date;
  FOR r IN
    SELECT c.relname AS part_name
    FROM pg_inherits i
    JOIN pg_class c ON c.oid = i.inhrelid
    JOIN pg_class p ON p.oid = i.inhparent
    WHERE p.relname = 'admin_audit_log'
      AND c.relname ~ '^admin_audit_log_[0-9]{4}_[0-9]{2}$'
  LOOP
    IF to_date(substring(r.part_name from 17), 'YYYY_MM') < v_drop_end THEN
      EXECUTE format('DROP TABLE IF EXISTS public.%I', r.part_name);
    END IF;
  END LOOP;
END;
$$;

SELECT public.fn_admin_audit_log_ensure_partitions(3, 24);

SELECT cron.unschedule(jobid)
FROM cron.job
WHERE jobname = 'admin-audit-log-partitions';

SELECT cron.schedule(
  'admin-audit-log-partitions',
  '5 0 1 * *',
  $$SELECT public.fn_admin_audit_log_ensure_partitions(3, 24);$$
);

-- ---------------------------------------------------------------------------
-- 3) JSON diff + redaction + logger
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_jsonb_redact_secrets(p_value jsonb)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  k text;
  v jsonb;
  out jsonb := '{}'::jsonb;
BEGIN
  IF p_value IS NULL OR jsonb_typeof(p_value) <> 'object' THEN
    RETURN COALESCE(p_value, 'null'::jsonb);
  END IF;
  FOR k, v IN SELECT * FROM jsonb_each(p_value) LOOP
    IF k ~* '(password|token|otp|secret|api_key)' THEN
      CONTINUE;
    END IF;
    IF jsonb_typeof(v) = 'object' THEN
      out := out || jsonb_build_object(k, public.fn_jsonb_redact_secrets(v));
    ELSIF jsonb_typeof(v) = 'array' THEN
      out := out || jsonb_build_object(
        k,
        (
          SELECT COALESCE(jsonb_agg(
            CASE
              WHEN jsonb_typeof(elem) = 'object' THEN public.fn_jsonb_redact_secrets(elem)
              ELSE elem
            END
          ), '[]'::jsonb)
          FROM jsonb_array_elements(v) AS elem
        )
      );
    ELSE
      out := out || jsonb_build_object(k, v);
    END IF;
  END LOOP;
  RETURN out;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_jsonb_diff(
  p_before jsonb,
  p_after jsonb,
  p_ignore_keys text[] DEFAULT ARRAY['updated_at', 'created_at']
)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  k text;
  v_before jsonb;
  v_after jsonb;
  out jsonb := '{}'::jsonb;
BEGIN
  IF p_before IS NULL OR p_after IS NULL THEN
    RETURN '{}'::jsonb;
  END IF;
  IF jsonb_typeof(p_before) <> 'object' OR jsonb_typeof(p_after) <> 'object' THEN
    RETURN '{}'::jsonb;
  END IF;
  FOR k, v_after IN SELECT * FROM jsonb_each(p_after) LOOP
    IF p_ignore_keys IS NOT NULL AND k = ANY (p_ignore_keys) THEN
      CONTINUE;
    END IF;
    v_before := p_before -> k;
    IF v_before IS DISTINCT FROM v_after THEN
      out := out || jsonb_build_object(k, jsonb_build_object('from', v_before, 'to', v_after));
    END IF;
  END LOOP;
  RETURN out;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_resolve_admin_audit_actor(
  p_merchant_id uuid,
  p_verified_actor_admin_id uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_iss text;
  v_role text;
  v_admin_id uuid;
BEGIN
  IF p_merchant_id IS NULL THEN
    RETURN NULL;
  END IF;

  v_role := COALESCE(current_setting('request.jwt.claims', true)::json->>'role', '');
  IF v_role = 'service_role' THEN
    IF p_verified_actor_admin_id IS NULL THEN
      RETURN NULL;
    END IF;
    SELECT au.id INTO v_admin_id
    FROM admin_users au
    WHERE au.id = p_verified_actor_admin_id
      AND au.merchant_id = p_merchant_id
      AND au.active_status = true
    LIMIT 1;
    RETURN v_admin_id;
  END IF;

  v_iss := COALESCE(auth.jwt()->>'iss', '');
  -- Member custom tokens use issuer "supabase"; admin Supabase Auth uses .../auth/v1
  IF v_iss = 'supabase' OR v_iss = '' THEN
    RETURN NULL;
  END IF;
  IF v_iss NOT LIKE '%/auth/v1' THEN
    RETURN NULL;
  END IF;

  SELECT au.id INTO v_admin_id
  FROM admin_users au
  WHERE au.auth_user_id = auth.uid()
    AND au.merchant_id = p_merchant_id
    AND au.active_status = true
  LIMIT 1;

  RETURN v_admin_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_log_admin_action(
  p_action text,
  p_entity_type text,
  p_entity_id uuid,
  p_payload jsonb DEFAULT '{}'::jsonb,
  p_before jsonb DEFAULT NULL,
  p_after jsonb DEFAULT NULL,
  p_related jsonb DEFAULT '{}'::jsonb,
  p_reason text DEFAULT NULL,
  p_source text DEFAULT NULL,
  p_verified_actor_admin_id uuid DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_merchant_id uuid;
  v_actor_admin_id uuid;
  v_payload jsonb;
  v_changes jsonb;
  v_context jsonb;
  v_cap integer := 65536;
BEGIN
  v_merchant_id := get_current_merchant_id();
  v_actor_admin_id := fn_resolve_admin_audit_actor(v_merchant_id, p_verified_actor_admin_id);
  IF v_actor_admin_id IS NULL THEN
    RETURN;
  END IF;

  v_payload := public.fn_jsonb_redact_secrets(COALESCE(p_payload, '{}'::jsonb));
  IF octet_length(v_payload::text) > v_cap THEN
    v_payload := jsonb_build_object(
      '_truncated', true,
      '_original_bytes', octet_length(v_payload::text),
      '_keys', (SELECT COALESCE(jsonb_agg(k), '[]'::jsonb) FROM jsonb_object_keys(v_payload) AS k)
    );
  END IF;

  v_changes := public.fn_jsonb_diff(
    public.fn_jsonb_redact_secrets(p_before),
    public.fn_jsonb_redact_secrets(p_after)
  );

  v_context := jsonb_strip_nulls(jsonb_build_object(
    'ip', nullif(current_setting('request.headers', true)::json->>'x-forwarded-for', ''),
    'user_agent', nullif(current_setting('request.headers', true)::json->>'user-agent', ''),
    'request_id', nullif(current_setting('request.headers', true)::json->>'x-request-id', '')
  ));

  PERFORM fn_admin_audit_log_ensure_partitions(1, 24);

  INSERT INTO admin_audit_log (
    merchant_id,
    actor_admin_id,
    action,
    entity_type,
    entity_id,
    payload,
    changes,
    related,
    reason,
    source,
    context
  ) VALUES (
    v_merchant_id,
    v_actor_admin_id,
    p_action,
    p_entity_type,
    p_entity_id,
    v_payload,
    COALESCE(v_changes, '{}'::jsonb),
    COALESCE(p_related, '{}'::jsonb),
    p_reason,
    p_source,
    COALESCE(v_context, '{}'::jsonb)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_scrub_admin_audit_log_for_member(
  p_merchant_id uuid,
  p_user_id uuid
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_count integer := 0;
BEGIN
  IF p_merchant_id IS NULL OR p_user_id IS NULL THEN
    RETURN 0;
  END IF;
  PERFORM set_config('admin_audit_log.scrub', 'allow', true);
  UPDATE admin_audit_log
  SET payload = jsonb_build_object('_scrubbed_member', p_user_id),
      changes = '{}'::jsonb
  WHERE merchant_id = p_merchant_id
    AND entity_type = 'member'
    AND entity_id = p_user_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  PERFORM set_config('admin_audit_log.scrub', '', true);
  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_log_admin_action(text, text, uuid, jsonb, jsonb, jsonb, jsonb, text, text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_log_admin_action(text, text, uuid, jsonb, jsonb, jsonb, jsonb, text, text, uuid)
  TO postgres, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 4) Read BFF
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.bff_admin_list_audit_log(
  p_filters jsonb DEFAULT '{}'::jsonb,
  p_limit integer DEFAULT 50,
  p_cursor timestamptz DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_merchant_id uuid;
  v_limit integer;
  v_rows jsonb;
  v_next_cursor timestamptz;
  v_entity_type text;
  v_entity_id uuid;
  v_actor_admin_id uuid;
  v_action text;
  v_from timestamptz;
  v_to timestamptz;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM admin_users au
    WHERE au.auth_user_id = auth.uid() AND au.active_status = true
  ) THEN
    RETURN fn_response_error('Forbidden', 'Admin access required', 'FORBIDDEN');
  END IF;

  v_merchant_id := get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN fn_response_error('No merchant context', 'Unable to determine merchant', 'NO_MERCHANT_CONTEXT');
  END IF;

  IF NOT check_admin_permission('audit_log', 'read') THEN
    RETURN fn_response_error('Forbidden', 'audit_log.read required', 'FORBIDDEN');
  END IF;

  v_limit := LEAST(GREATEST(COALESCE(p_limit, 50), 1), 100);
  v_entity_type := NULLIF(p_filters->>'entity_type', '');
  v_entity_id := NULLIF(p_filters->>'entity_id', '')::uuid;
  v_actor_admin_id := NULLIF(p_filters->>'actor_admin_id', '')::uuid;
  v_action := NULLIF(p_filters->>'action', '');
  v_from := NULLIF(p_filters->>'from', '')::timestamptz;
  v_to := NULLIF(p_filters->>'to', '')::timestamptz;

  SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::jsonb)
  INTO v_rows
  FROM (
    SELECT
      l.id,
      l.merchant_id,
      l.actor_admin_id,
      au.email AS actor_email,
      COALESCE(au.name, au.email) AS actor_name,
      l.action,
      l.entity_type,
      l.entity_id,
      l.payload,
      l.changes,
      l.related,
      l.reason,
      l.source,
      l.context,
      l.created_at
    FROM admin_audit_log l
    LEFT JOIN admin_users au ON au.id = l.actor_admin_id
    WHERE l.merchant_id = v_merchant_id
      AND (p_cursor IS NULL OR l.created_at < p_cursor)
      AND (v_entity_type IS NULL OR l.entity_type = v_entity_type)
      AND (v_entity_id IS NULL OR l.entity_id = v_entity_id)
      AND (v_actor_admin_id IS NULL OR l.actor_admin_id = v_actor_admin_id)
      AND (v_action IS NULL OR l.action = v_action)
      AND (v_from IS NULL OR l.created_at >= v_from)
      AND (v_to IS NULL OR l.created_at <= v_to)
    ORDER BY l.created_at DESC
    LIMIT v_limit
  ) t;

  SELECT (elem->>'created_at')::timestamptz
  INTO v_next_cursor
  FROM jsonb_array_elements(v_rows) WITH ORDINALITY AS e(elem, ord)
  ORDER BY ord DESC
  LIMIT 1;

  RETURN fn_response_success(
    'Audit log',
    NULL,
    jsonb_build_object(
      'entries', v_rows,
      'next_cursor', v_next_cursor
    )
  );
EXCEPTION WHEN OTHERS THEN
  RETURN fn_response_error('Error loading audit log', SQLERRM, SQLSTATE);
END;
$$;

REVOKE ALL ON FUNCTION public.bff_admin_list_audit_log(jsonb, integer, timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.bff_admin_list_audit_log(jsonb, integer, timestamptz)
  TO postgres, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 5) Permission: audit_log.read for roles that can read customer-360
-- ---------------------------------------------------------------------------
INSERT INTO admin_role_permissions (id, role_id, resource, actions)
SELECT gen_random_uuid(), arp.role_id, 'audit_log', ARRAY['read']::text[]
FROM admin_role_permissions arp
WHERE arp.resource = 'customer-360'
  AND 'read' = ANY (arp.actions)
  AND NOT EXISTS (
    SELECT 1 FROM admin_role_permissions x
    WHERE x.role_id = arp.role_id AND x.resource = 'audit_log'
  );
