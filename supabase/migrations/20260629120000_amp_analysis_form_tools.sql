-- AMP Analysis: form ai_context columns + form/event query RPCs for Sarjanta

ALTER TABLE form_templates
  ADD COLUMN IF NOT EXISTS ai_context text;

ALTER TABLE form_fields
  ADD COLUMN IF NOT EXISTS ai_context text;

COMMENT ON COLUMN form_templates.ai_context IS 'Merchant-authored guidance for AI agents: form purpose, when to use, linked campaigns/events. Not shown to members.';
COMMENT ON COLUMN form_fields.ai_context IS 'Merchant-authored guidance for AI agents: field semantics, units, bucketing, segmentation use. Not shown to members.';

-- ─── Helper: resolve USER_PROFILE form id for a merchant ───────────────────

CREATE OR REPLACE FUNCTION fn_amp_analysis_user_profile_form_id(p_merchant_id uuid)
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO public
AS $$
  SELECT ft.id
  FROM form_templates ft
  WHERE ft.merchant_id = p_merchant_id
    AND ft.code = 'USER_PROFILE'
    AND ft.status = 'published'
  LIMIT 1;
$$;

-- ─── Form catalog (injected into agent system prompt) ───────────────────────

CREATE OR REPLACE FUNCTION fn_amp_analysis_list_forms(p_merchant_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO public
AS $function$
DECLARE
  v_profile_form_id uuid;
BEGIN
  v_profile_form_id := fn_amp_analysis_user_profile_form_id(p_merchant_id);

  RETURN COALESCE((
    SELECT jsonb_agg(form_row ORDER BY form_row->>'name')
    FROM (
      SELECT jsonb_build_object(
        'form_id', ft.id,
        'code', ft.code,
        'name', ft.name,
        'form_category', ft.form_category,
        'description', ft.description,
        'ai_context', ft.ai_context,
        'is_user_profile', (ft.id = v_profile_form_id OR ft.code = 'USER_PROFILE'),
        'aggregation_mode', CASE
          WHEN ft.id = v_profile_form_id OR ft.code = 'USER_PROFILE' THEN 'member_latest'
          ELSE 'submission'
        END,
        'completed_submissions', (
          SELECT COUNT(*)::int
          FROM form_submissions fs
          WHERE fs.form_id = ft.id AND fs.status = 'completed'
        ),
        'unique_members', (
          SELECT COUNT(DISTINCT fs.user_id)::int
          FROM form_submissions fs
          WHERE fs.form_id = ft.id AND fs.status = 'completed' AND fs.user_id IS NOT NULL
        ),
        'fields', COALESCE((
          SELECT jsonb_agg(
            jsonb_build_object(
              'field_id', ff.id,
              'field_key', ff.field_key,
              'label', ff.label,
              'field_type', ff.field_type,
              'ai_context', ff.ai_context,
              'is_required', ff.is_required
            ) ORDER BY ff.order_index
          )
          FROM form_fields ff
          WHERE ff.form_id = ft.id
            AND ff.deleted_at IS NULL
        ), '[]'::jsonb)
      ) AS form_row
      FROM form_templates ft
      WHERE ft.merchant_id = p_merchant_id
        AND ft.status = 'published'
    ) sub
  ), '[]'::jsonb);
END;
$function$;

-- ─── Survey form field breakdown (submission-level) ─────────────────────────

CREATE OR REPLACE FUNCTION fn_amp_analysis_query_form_summary(
  p_merchant_id uuid,
  p_form_id uuid,
  p_field_keys text[] DEFAULT NULL,
  p_start_date timestamptz DEFAULT NULL,
  p_end_date timestamptz DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO public
AS $function$
DECLARE
  v_summary jsonb;
  v_profile_form_id uuid;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM form_templates ft
    WHERE ft.id = p_form_id AND ft.merchant_id = p_merchant_id
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'form_not_found');
  END IF;

  v_profile_form_id := fn_amp_analysis_user_profile_form_id(p_merchant_id);
  IF p_form_id = v_profile_form_id THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'use_query_profile_field',
      'hint', 'USER_PROFILE uses member_latest aggregation. Call fn_amp_analysis_query_profile_field instead.'
    );
  END IF;

  v_summary := get_form_submission_summary(p_form_id, NULL, p_start_date, p_end_date);

  IF p_field_keys IS NOT NULL AND array_length(p_field_keys, 1) > 0 THEN
    v_summary := v_summary || jsonb_build_object(
      'field_summaries', COALESCE((
        SELECT jsonb_agg(elem)
        FROM jsonb_array_elements(v_summary->'field_summaries') elem
        WHERE elem->>'field_key' = ANY (p_field_keys)
      ), '[]'::jsonb)
    );
  END IF;

  RETURN v_summary || jsonb_build_object(
    'aggregation_mode', 'submission',
    'merchant_id', p_merchant_id
  );
END;
$function$;

-- ─── USER_PROFILE field breakdown (latest value per member) ────────────────

CREATE OR REPLACE FUNCTION fn_amp_analysis_query_profile_field(
  p_merchant_id uuid,
  p_field_key text,
  p_bucket_rules jsonb DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO public
AS $function$
DECLARE
  v_form_id uuid;
  v_field_id uuid;
  v_field_type text;
  v_field_label text;
  v_ai_context text;
  v_is_numeric boolean;
  v_result jsonb;
BEGIN
  v_form_id := fn_amp_analysis_user_profile_form_id(p_merchant_id);
  IF v_form_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'user_profile_form_not_found');
  END IF;

  SELECT ff.id, ff.field_type, ff.label, ff.ai_context,
         ff.field_type IN ('number', 'numeric')
           OR (p_field_key = 'area' AND ff.field_type IN ('number', 'free_text', 'normal'))
  INTO v_field_id, v_field_type, v_field_label, v_ai_context, v_is_numeric
  FROM form_fields ff
  WHERE ff.form_id = v_form_id
    AND ff.field_key = p_field_key
    AND ff.deleted_at IS NULL
  LIMIT 1;

  IF v_field_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'field_not_found', 'field_key', p_field_key);
  END IF;

  IF v_is_numeric OR p_field_key = 'area' THEN
    WITH latest AS (
      SELECT DISTINCT ON (fs.user_id)
        fs.user_id,
        CASE
          WHEN fr.text_value ~ '^[0-9]+(\.[0-9]+)?$' THEN fr.text_value::numeric
          ELSE NULL
        END AS num_val
      FROM form_submissions fs
      JOIN form_responses fr ON fr.submission_id = fs.id AND fr.field_id = v_field_id
      WHERE fs.merchant_id = p_merchant_id
        AND fs.form_id = v_form_id
        AND fs.status = 'completed'
        AND fs.user_id IS NOT NULL
      ORDER BY fs.user_id, fs.created_at DESC
    ),
    bucketed AS (
      SELECT
        CASE
          WHEN num_val IS NULL THEN 'unknown'
          WHEN p_bucket_rules IS NOT NULL THEN (
            SELECT br->>'label'
            FROM jsonb_array_elements(p_bucket_rules) br
            WHERE (br->>'min' IS NULL OR num_val >= (br->>'min')::numeric)
              AND (br->>'max' IS NULL OR num_val < (br->>'max')::numeric)
            LIMIT 1
          )
          WHEN num_val < 20 THEN 'small (<20 rai)'
          WHEN num_val < 100 THEN 'medium (20-99 rai)'
          ELSE 'large (100+ rai)'
        END AS bucket,
        COUNT(*) AS member_count
      FROM latest
      GROUP BY 1
    )
    SELECT jsonb_build_object(
      'success', true,
      'aggregation_mode', 'member_latest',
      'form_id', v_form_id,
      'field_key', p_field_key,
      'field_label', v_field_label,
      'field_type', v_field_type,
      'ai_context', v_ai_context,
      'total_members_with_profile', (SELECT COUNT(*) FROM latest),
      'members_with_value', (SELECT COUNT(*) FROM latest WHERE num_val IS NOT NULL),
      'values', (
        SELECT COALESCE(jsonb_agg(
          jsonb_build_object(
            'value', bucket,
            'label', bucket,
            'count', member_count,
            'percentage', ROUND(100.0 * member_count / NULLIF((SELECT COUNT(*) FROM latest), 0), 2)
          ) ORDER BY member_count DESC
        ), '[]'::jsonb)
        FROM bucketed
      )
    ) INTO v_result;
  ELSE
    WITH latest AS (
      SELECT DISTINCT ON (fs.user_id)
        fs.user_id,
        fr.array_value,
        fr.text_value
      FROM form_submissions fs
      JOIN form_responses fr ON fr.submission_id = fs.id AND fr.field_id = v_field_id
      WHERE fs.merchant_id = p_merchant_id
        AND fs.form_id = v_form_id
        AND fs.status = 'completed'
        AND fs.user_id IS NOT NULL
      ORDER BY fs.user_id, fs.created_at DESC
    ),
    expanded AS (
      SELECT
        l.user_id,
        COALESCE(
          NULLIF(trim(val), ''),
          NULLIF(trim(l.text_value), '')
        ) AS value_key
      FROM latest l
      LEFT JOIN LATERAL unnest(
        CASE
          WHEN l.array_value IS NOT NULL AND array_length(l.array_value, 1) > 0 THEN l.array_value
          WHEN l.text_value IS NOT NULL AND l.text_value <> '' THEN ARRAY[l.text_value]
          ELSE ARRAY[]::text[]
        END
      ) AS val ON true
    ),
    counts AS (
      SELECT
        value_key AS value,
        COALESCE(
          (SELECT fo.option_label FROM form_field_options fo
           WHERE fo.field_id = v_field_id AND fo.option_value = value_key LIMIT 1),
          value_key
        ) AS label,
        COUNT(DISTINCT user_id) AS member_count
      FROM expanded
      WHERE value_key IS NOT NULL
      GROUP BY value_key
    )
    SELECT jsonb_build_object(
      'success', true,
      'aggregation_mode', 'member_latest',
      'form_id', v_form_id,
      'field_key', p_field_key,
      'field_label', v_field_label,
      'field_type', v_field_type,
      'ai_context', v_ai_context,
      'total_members_with_profile', (SELECT COUNT(DISTINCT user_id) FROM latest),
      'values', (
        SELECT COALESCE(jsonb_agg(
          jsonb_build_object(
            'value', value,
            'label', label,
            'count', member_count,
            'percentage', ROUND(100.0 * member_count / NULLIF((SELECT COUNT(DISTINCT user_id) FROM latest), 0), 2)
          ) ORDER BY member_count DESC
        ), '[]'::jsonb)
        FROM counts
      )
    ) INTO v_result;
  END IF;

  RETURN v_result;
END;
$function$;

-- ─── Cross-tab: USER_PROFILE field × outcome ───────────────────────────────

CREATE OR REPLACE FUNCTION fn_amp_analysis_cross_tab_profile(
  p_merchant_id uuid,
  p_field_key text,
  p_outcome_type text DEFAULT 'event_attended',
  p_bucket_rules jsonb DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO public
AS $function$
DECLARE
  v_form_id uuid;
  v_field_id uuid;
  v_field_type text;
  v_is_numeric boolean;
BEGIN
  v_form_id := fn_amp_analysis_user_profile_form_id(p_merchant_id);
  IF v_form_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'user_profile_form_not_found');
  END IF;

  SELECT ff.id, ff.field_type,
         ff.field_type IN ('number', 'numeric') OR p_field_key = 'area'
  INTO v_field_id, v_field_type, v_is_numeric
  FROM form_fields ff
  WHERE ff.form_id = v_form_id AND ff.field_key = p_field_key AND ff.deleted_at IS NULL
  LIMIT 1;

  IF v_field_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'field_not_found');
  END IF;

  IF p_outcome_type NOT IN ('event_attended', 'event_registered') THEN
    RETURN jsonb_build_object('success', false, 'error', 'unsupported_outcome_type', 'supported', jsonb_build_array('event_attended', 'event_registered'));
  END IF;

  RETURN (
    WITH latest AS (
      SELECT DISTINCT ON (fs.user_id)
        fs.user_id,
        fr.array_value,
        fr.text_value,
        CASE
          WHEN fr.text_value ~ '^[0-9]+(\.[0-9]+)?$' THEN fr.text_value::numeric
          ELSE NULL
        END AS num_val
      FROM form_submissions fs
      JOIN form_responses fr ON fr.submission_id = fs.id AND fr.field_id = v_field_id
      WHERE fs.merchant_id = p_merchant_id
        AND fs.form_id = v_form_id
        AND fs.status = 'completed'
        AND fs.user_id IS NOT NULL
      ORDER BY fs.user_id, fs.created_at DESC
    ),
    profile_segments AS (
      SELECT l.user_id,
        CASE
          WHEN l.num_val IS NULL THEN 'unknown'
          WHEN p_bucket_rules IS NOT NULL THEN (
            SELECT br->>'label' FROM jsonb_array_elements(p_bucket_rules) br
            WHERE (br->>'min' IS NULL OR l.num_val >= (br->>'min')::numeric)
              AND (br->>'max' IS NULL OR l.num_val < (br->>'max')::numeric)
            LIMIT 1
          )
          WHEN l.num_val < 20 THEN 'small (<20 rai)'
          WHEN l.num_val < 100 THEN 'medium (20-99 rai)'
          ELSE 'large (100+ rai)'
        END AS segment
      FROM latest l
      WHERE v_is_numeric
      UNION ALL
      SELECT l.user_id,
        COALESCE(NULLIF(trim(v), ''), 'unknown') AS segment
      FROM latest l
      CROSS JOIN LATERAL unnest(
        CASE
          WHEN l.array_value IS NOT NULL AND array_length(l.array_value, 1) > 0 THEN l.array_value
          WHEN l.text_value IS NOT NULL AND l.text_value <> '' THEN ARRAY[l.text_value]
          ELSE ARRAY['unknown']::text[]
        END
      ) AS v
      WHERE NOT v_is_numeric
    ),
    event_attendees AS (
      SELECT DISTINCT er.member_id::uuid AS user_id
      FROM syngenta_event_registration_ledger er
      WHERE er.merchant_id = p_merchant_id
        AND er.member_id ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        AND (
          (p_outcome_type = 'event_attended' AND er.attended = true)
          OR (p_outcome_type = 'event_registered' AND er.registered = true)
        )
    ),
    outcomes AS (
      SELECT user_id, true AS has_outcome FROM event_attendees
    )
    SELECT jsonb_build_object(
      'success', true,
      'field_key', p_field_key,
      'outcome_type', p_outcome_type,
      'aggregation_mode', 'member_latest',
      'segments', COALESCE((
        SELECT jsonb_agg(
          jsonb_build_object(
            'segment', ps.segment,
            'members', COUNT(*),
            'with_outcome', COUNT(*) FILTER (WHERE o.has_outcome),
            'outcome_rate_pct', ROUND(
              100.0 * COUNT(*) FILTER (WHERE o.has_outcome) / NULLIF(COUNT(*), 0), 2
            )
          ) ORDER BY COUNT(*) DESC
        )
        FROM profile_segments ps
        LEFT JOIN outcomes o ON o.user_id = ps.user_id
        GROUP BY ps.segment
      ), '[]'::jsonb)
    )
  );
END;
$function$;

-- ─── Event attendance summary ───────────────────────────────────────────────

CREATE OR REPLACE FUNCTION fn_amp_analysis_query_event_attendance(
  p_merchant_id uuid,
  p_event_code text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO public
AS $function$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM syngenta_events_master e WHERE e.merchant_id = p_merchant_id LIMIT 1
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'no_events_for_merchant');
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'events', COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'event_id', e.id,
          'event_code', e.event_code,
          'event_name', e.event_name,
          'date_of_event', e.date_of_event,
          'registered_count', stats.registered_count,
          'attended_count', stats.attended_count,
          'unique_members', stats.unique_members,
          'attendance_rate_pct', ROUND(
            100.0 * stats.attended_count / NULLIF(stats.registered_count, 0), 2
          )
        ) ORDER BY e.date_of_event DESC NULLS LAST
      )
      FROM syngenta_events_master e
      LEFT JOIN LATERAL (
        SELECT
          COUNT(*) FILTER (WHERE er.registered = true) AS registered_count,
          COUNT(*) FILTER (WHERE er.attended = true) AS attended_count,
          COUNT(DISTINCT er.member_id) AS unique_members
        FROM syngenta_event_registration_ledger er
        WHERE er.merchant_id = p_merchant_id
          AND er.event_id = e.id
      ) stats ON true
      WHERE e.merchant_id = p_merchant_id
        AND (p_event_code IS NULL OR e.event_code = p_event_code)
    ), '[]'::jsonb),
    'totals', (
      SELECT jsonb_build_object(
        'registration_rows', COUNT(*),
        'registered', COUNT(*) FILTER (WHERE er.registered = true),
        'attended', COUNT(*) FILTER (WHERE er.attended = true),
        'unique_members', COUNT(DISTINCT er.member_id)
      )
      FROM syngenta_event_registration_ledger er
      WHERE er.merchant_id = p_merchant_id
        AND (p_event_code IS NULL OR er.event_code = p_event_code)
    )
  );
END;
$function$;

-- ─── Inject form catalog into thread context ────────────────────────────────

CREATE OR REPLACE FUNCTION fn_amp_analysis_load_thread_context(p_thread_id uuid, p_merchant_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public
AS $function$
DECLARE
  v_result jsonb;
BEGIN
  SELECT jsonb_build_object(
    'thread', jsonb_build_object(
      'id',              t.id,
      'merchant_id',     t.merchant_id,
      'title',           t.title,
      'context_summary', t.context_summary,
      'created_at',      t.created_at
    ),
    'form_catalog', fn_amp_analysis_list_forms(p_merchant_id),
    'messages', COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'id',           m.id,
          'role',         m.role,
          'content',      m.content,
          'tool_calls',   m.tool_calls,
          'tool_results', m.tool_results,
          'created_at',   m.created_at
        ) ORDER BY m.created_at ASC
      )
      FROM (
        SELECT * FROM amp_analysis_messages
        WHERE thread_id = p_thread_id
        ORDER BY created_at DESC
        LIMIT 20
      ) m
    ), '[]'::jsonb)
  )
  INTO v_result
  FROM amp_analysis_threads t
  WHERE t.id = p_thread_id AND t.merchant_id = p_merchant_id;

  IF v_result IS NULL THEN
    RETURN jsonb_build_object('error', 'thread_not_found');
  END IF;

  RETURN v_result;
END;
$function$;
