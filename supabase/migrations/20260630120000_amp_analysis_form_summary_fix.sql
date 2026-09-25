-- Lightweight survey form summary for AMP Analysis (avoids get_form_submission_summary timeout/bloat)

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
  v_form_name text;
  v_profile_form_id uuid;
  v_total_submissions integer;
  v_field_summaries jsonb := '[]'::jsonb;
  v_field record;
  v_field_summary jsonb;
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

  SELECT ft.name INTO v_form_name
  FROM form_templates ft
  WHERE ft.id = p_form_id;

  SELECT COUNT(*) INTO v_total_submissions
  FROM form_submissions fs
  WHERE fs.form_id = p_form_id
    AND fs.merchant_id = p_merchant_id
    AND fs.status = 'completed'
    AND (p_start_date IS NULL OR fs.created_at >= p_start_date)
    AND (p_end_date IS NULL OR fs.created_at <= p_end_date);

  FOR v_field IN
    SELECT ff.id, ff.field_key, ff.label, ff.field_type::text AS field_type
    FROM form_fields ff
    WHERE ff.form_id = p_form_id
      AND ff.deleted_at IS NULL
      AND (p_field_keys IS NULL OR ff.field_key = ANY (p_field_keys))
    ORDER BY ff.order_index
  LOOP
    IF v_field.field_type IN ('multi_select', 'multi-select') THEN
      SELECT jsonb_build_object(
        'field_key', v_field.field_key,
        'field_label', v_field.label,
        'field_type', v_field.field_type,
        'total_responses', cnt.total_responses,
        'values', COALESCE(vals.values, '[]'::jsonb)
      )
      INTO v_field_summary
      FROM (
        SELECT COUNT(DISTINCT fs.id) AS total_responses
        FROM form_submissions fs
        JOIN form_responses fr ON fr.submission_id = fs.id AND fr.field_id = v_field.id
        WHERE fs.form_id = p_form_id
          AND fs.merchant_id = p_merchant_id
          AND fs.status = 'completed'
          AND (fr.text_value IS NOT NULL OR fr.array_value IS NOT NULL)
          AND (p_start_date IS NULL OR fs.created_at >= p_start_date)
          AND (p_end_date IS NULL OR fs.created_at <= p_end_date)
      ) cnt
      CROSS JOIN LATERAL (
        SELECT jsonb_agg(
          jsonb_build_object(
            'value', t.value_key,
            'label', COALESCE(
              (SELECT fo.option_label FROM form_field_options fo
               WHERE fo.field_id = v_field.id AND fo.option_value = t.value_key LIMIT 1),
              t.value_key
            ),
            'count', t.cnt,
            'percentage', ROUND(100.0 * t.cnt / NULLIF(v_total_submissions, 0), 2)
          ) ORDER BY t.cnt DESC
        ) AS values
        FROM (
          SELECT value_key, COUNT(*) AS cnt
          FROM (
            SELECT COALESCE(NULLIF(trim(fr.text_value), ''), fr.array_value::text) AS value_key
            FROM form_submissions fs
            JOIN form_responses fr ON fr.submission_id = fs.id AND fr.field_id = v_field.id
            WHERE fs.form_id = p_form_id
              AND fs.merchant_id = p_merchant_id
              AND fs.status = 'completed'
              AND (fr.text_value IS NOT NULL OR fr.array_value IS NOT NULL)
              AND (p_start_date IS NULL OR fs.created_at >= p_start_date)
              AND (p_end_date IS NULL OR fs.created_at <= p_end_date)
          ) raw
          WHERE value_key IS NOT NULL
          GROUP BY value_key
          ORDER BY cnt DESC
          LIMIT 30
        ) t
      ) vals;
    ELSIF v_field.field_type IN ('number', 'numeric') THEN
      SELECT jsonb_build_object(
        'field_key', v_field.field_key,
        'field_label', v_field.label,
        'field_type', v_field.field_type,
        'total_responses', cnt.total_responses,
        'values', COALESCE(vals.values, '[]'::jsonb)
      )
      INTO v_field_summary
      FROM (
        SELECT COUNT(DISTINCT fs.id) AS total_responses
        FROM form_submissions fs
        JOIN form_responses fr ON fr.submission_id = fs.id AND fr.field_id = v_field.id
        WHERE fs.form_id = p_form_id
          AND fs.merchant_id = p_merchant_id
          AND fs.status = 'completed'
          AND fr.text_value IS NOT NULL
          AND fr.text_value ~ '^[0-9]+(\.[0-9]+)?$'
          AND (p_start_date IS NULL OR fs.created_at >= p_start_date)
          AND (p_end_date IS NULL OR fs.created_at <= p_end_date)
      ) cnt
      CROSS JOIN LATERAL (
        SELECT jsonb_agg(
          jsonb_build_object(
            'value', t.value_key,
            'label', t.value_key,
            'count', t.cnt,
            'percentage', ROUND(100.0 * t.cnt / NULLIF(v_total_submissions, 0), 2)
          ) ORDER BY t.cnt DESC
        ) AS values
        FROM (
          SELECT fr.text_value AS value_key, COUNT(*) AS cnt
          FROM form_submissions fs
          JOIN form_responses fr ON fr.submission_id = fs.id AND fr.field_id = v_field.id
          WHERE fs.form_id = p_form_id
            AND fs.merchant_id = p_merchant_id
            AND fs.status = 'completed'
            AND fr.text_value IS NOT NULL
            AND (p_start_date IS NULL OR fs.created_at >= p_start_date)
            AND (p_end_date IS NULL OR fs.created_at <= p_end_date)
          GROUP BY fr.text_value
          ORDER BY cnt DESC
          LIMIT 30
        ) t
      ) vals;
    ELSE
      SELECT jsonb_build_object(
        'field_key', v_field.field_key,
        'field_label', v_field.label,
        'field_type', v_field.field_type,
        'total_responses', cnt.total_responses,
        'values', COALESCE(vals.values, '[]'::jsonb)
      )
      INTO v_field_summary
      FROM (
        SELECT COUNT(DISTINCT fs.id) AS total_responses
        FROM form_submissions fs
        JOIN form_responses fr ON fr.submission_id = fs.id AND fr.field_id = v_field.id
        WHERE fs.form_id = p_form_id
          AND fs.merchant_id = p_merchant_id
          AND fs.status = 'completed'
          AND fr.text_value IS NOT NULL
          AND (p_start_date IS NULL OR fs.created_at >= p_start_date)
          AND (p_end_date IS NULL OR fs.created_at <= p_end_date)
      ) cnt
      CROSS JOIN LATERAL (
        SELECT jsonb_agg(
          jsonb_build_object(
            'value', t.value_key,
            'label', COALESCE(
              (SELECT fo.option_label FROM form_field_options fo
               WHERE fo.field_id = v_field.id AND fo.option_value = t.value_key LIMIT 1),
              t.value_key
            ),
            'count', t.cnt,
            'percentage', ROUND(100.0 * t.cnt / NULLIF(v_total_submissions, 0), 2)
          ) ORDER BY t.cnt DESC
        ) AS values
        FROM (
          SELECT fr.text_value AS value_key, COUNT(*) AS cnt
          FROM form_submissions fs
          JOIN form_responses fr ON fr.submission_id = fs.id AND fr.field_id = v_field.id
          WHERE fs.form_id = p_form_id
            AND fs.merchant_id = p_merchant_id
            AND fs.status = 'completed'
            AND fr.text_value IS NOT NULL
            AND (p_start_date IS NULL OR fs.created_at >= p_start_date)
            AND (p_end_date IS NULL OR fs.created_at <= p_end_date)
          GROUP BY fr.text_value
          ORDER BY cnt DESC
          LIMIT 30
        ) t
      ) vals;
    END IF;

    v_field_summaries := v_field_summaries || v_field_summary;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'form_id', p_form_id,
    'form_name', v_form_name,
    'total_submissions', v_total_submissions,
    'aggregation_mode', 'submission',
    'merchant_id', p_merchant_id,
    'filters', jsonb_build_object(
      'field_keys', COALESCE(to_jsonb(p_field_keys), 'null'::jsonb),
      'start_date', p_start_date,
      'end_date', p_end_date
    ),
    'field_summaries', v_field_summaries
  );
END;
$function$;
