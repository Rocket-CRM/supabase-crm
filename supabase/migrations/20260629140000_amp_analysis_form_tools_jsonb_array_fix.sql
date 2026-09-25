-- Fix jsonb[] vs text[] unnest in profile field RPCs (form_responses.array_value is jsonb[])

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
  v_field_label text;
  v_field_type text;
  v_ai_context text;
  v_is_numeric boolean;
  v_result jsonb;
BEGIN
  v_form_id := fn_amp_analysis_user_profile_form_id(p_merchant_id);
  IF v_form_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'user_profile_form_not_found');
  END IF;

  SELECT ff.id, ff.label, ff.field_type, ff.ai_context,
         ff.field_type IN ('number', 'numeric') OR p_field_key = 'area'
  INTO v_field_id, v_field_label, v_field_type, v_ai_context, v_is_numeric
  FROM form_fields ff
  WHERE ff.form_id = v_form_id AND ff.field_key = p_field_key AND ff.deleted_at IS NULL
  LIMIT 1;

  IF v_field_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'field_not_found');
  END IF;

  IF v_is_numeric THEN
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
            SELECT br->>'label' FROM jsonb_array_elements(p_bucket_rules) br
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
        COALESCE(NULLIF(trim(val), ''), NULLIF(trim(l.text_value), '')) AS value_key
      FROM latest l
      LEFT JOIN LATERAL unnest(
        CASE
          WHEN l.array_value IS NOT NULL AND array_length(l.array_value, 1) > 0 THEN
            (SELECT array_agg(COALESCE(elem #>> '{}', elem::text)) FROM unnest(l.array_value) AS elem)
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
          WHEN l.array_value IS NOT NULL AND array_length(l.array_value, 1) > 0 THEN
            (SELECT array_agg(COALESCE(elem #>> '{}', elem::text)) FROM unnest(l.array_value) AS elem)
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
    ),
    segment_stats AS (
      SELECT
        ps.segment,
        COUNT(*) AS members,
        COUNT(*) FILTER (WHERE o.has_outcome) AS with_outcome
      FROM profile_segments ps
      LEFT JOIN outcomes o ON o.user_id = ps.user_id
      GROUP BY ps.segment
    )
    SELECT jsonb_build_object(
      'success', true,
      'field_key', p_field_key,
      'outcome_type', p_outcome_type,
      'aggregation_mode', 'member_latest',
      'segments', COALESCE((
        SELECT jsonb_agg(
          jsonb_build_object(
            'segment', s.segment,
            'members', s.members,
            'with_outcome', s.with_outcome,
            'outcome_rate_pct', ROUND(100.0 * s.with_outcome / NULLIF(s.members, 0), 2)
          ) ORDER BY s.members DESC
        )
        FROM segment_stats s
      ), '[]'::jsonb)
    )
  );
END;
$function$;
