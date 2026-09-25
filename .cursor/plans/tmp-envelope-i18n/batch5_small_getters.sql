-- batch5 helper keys + small getters/upserts

-- First append keys via a patch that only adds new WHEN branches using CREATE OR REPLACE of full helper is heavy;
-- instead we add keys with a DO block that recreates from current... better: just CREATE OR REPLACE helper with ELSE fallback for unknown;
-- For new keys we need them in helper. Use execute to add via migration that only updates the ELSE... can't.
-- So include only the new keys by re-applying a slim extension using plpgsql replace - not possible.
-- We'll call a separate migration for keys then functions.

CREATE OR REPLACE FUNCTION public.bff_amp_preview_condition(p_groups jsonb, p_groups_operator text DEFAULT 'and'::text, p_language text DEFAULT 'en'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_lang text;
  v_merchant_id UUID;
BEGIN
  v_lang := fn_normalize_ui_language(p_language);
  v_merchant_id := get_current_merchant_id();

  IF v_merchant_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'code', 'NO_MERCHANT_CONTEXT',
      'title', fn_admin_envelope_message('error_title', v_lang),
      'description', fn_admin_envelope_message('no_merchant_found_title', v_lang));
  END IF;

  RETURN fn_amp_preview_condition(v_merchant_id, p_groups, p_groups_operator);
END;
$function$;

DROP FUNCTION IF EXISTS public.bff_amp_preview_condition(jsonb, text);

CREATE OR REPLACE FUNCTION public.bff_get_tier_program_config(p_user_type user_type DEFAULT NULL::user_type, p_language text DEFAULT 'en'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_lang text;
  v_merchant_id uuid;
  v_data jsonb;
BEGIN
  v_lang := fn_normalize_ui_language(p_language);
  v_merchant_id := public.get_current_merchant_id();

  IF v_merchant_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'code', 'NO_MERCHANT_CONTEXT',
      'title', fn_admin_envelope_message('error_title', v_lang),
      'description', fn_admin_envelope_message('no_merchant_found_title', v_lang));
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'id', c.id,
           'user_type', c.user_type,
           'program_start_date', c.program_start_date,
           'metric', c.metric,
           'period_type', c.period_type,
           'period_start_month', c.period_start_month,
           'rolling_months', c.rolling_months,
           'upgrade_timing', c.upgrade_timing,
           'maintain_mode', c.maintain_mode
         ) ORDER BY c.user_type), '[]'::jsonb)
  INTO v_data
  FROM public.tier_program_config c
  WHERE c.merchant_id = v_merchant_id
    AND (p_user_type IS NULL OR c.user_type = p_user_type);

  RETURN jsonb_build_object('success', true, 'code', 'OK',
    'title', fn_admin_envelope_message('tier_program_config_title', v_lang),
    'description', fn_admin_envelope_message('tier_program_config_desc', v_lang),
    'data', v_data);
END;
$function$;

DROP FUNCTION IF EXISTS public.bff_get_tier_program_config(user_type);

CREATE OR REPLACE FUNCTION public.bff_get_activity_matrix(p_activity_id uuid, p_language text DEFAULT 'en'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_lang text;
  v_merchant_id UUID;
  v_activity RECORD;
  v_matrix JSONB;
BEGIN
  v_lang := fn_normalize_ui_language(p_language);
  v_merchant_id := get_current_merchant_id();

  SELECT
    activity_name, activity_code, description, field_definitions, primary_dimension,
    icon_url, banner_urls, howto_banner, howto_description, label, header
  INTO v_activity
  FROM activity_master
  WHERE id = p_activity_id
    AND merchant_id = v_merchant_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false,
      'title', fn_admin_envelope_message('activity_not_found_title', v_lang),
      'description', null,
      'data', null
    );
  END IF;

  SELECT jsonb_agg(
    jsonb_build_object(
      'id', acc.id,
      'primary_value', acc.primary_value,
      'secondary_field', acc.secondary_field,
      'secondary_value', acc.secondary_value,
      'points_amount', acc.points_amount,
      'ticket_type_id', acc.ticket_type_id,
      'ticket_amount', acc.ticket_amount
    )
    ORDER BY acc.primary_value, acc.secondary_field, acc.secondary_value
  )
  INTO v_matrix
  FROM activity_currency_config acc
  WHERE acc.activity_id = p_activity_id
    AND acc.active_status = true;

  RETURN jsonb_build_object(
    'success', true,
    'title', null,
    'description', null,
    'data', jsonb_build_object(
      'activity_id', p_activity_id,
      'activity_code', v_activity.activity_code,
      'activity_name', v_activity.activity_name,
      'description', v_activity.description,
      'field_definitions', v_activity.field_definitions,
      'primary_dimension', v_activity.primary_dimension,
      'icon_url', v_activity.icon_url,
      'banner_urls', v_activity.banner_urls,
      'howto_banner', v_activity.howto_banner,
      'howto_description', v_activity.howto_description,
      'label', v_activity.label,
      'header', v_activity.header,
      'matrix', COALESCE(v_matrix, '[]'::jsonb)
    )
  );
END;
$function$;

DROP FUNCTION IF EXISTS public.bff_get_activity_matrix(uuid);

CREATE OR REPLACE FUNCTION public.bff_get_activity_uploads(p_status_filter text DEFAULT NULL::text, p_activity_id uuid DEFAULT NULL::uuid, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0, p_language text DEFAULT 'en'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_lang text;
  v_merchant_id UUID;
  v_uploads     JSONB;
  v_total_count INTEGER;
BEGIN
  v_lang := fn_normalize_ui_language(p_language);
  v_merchant_id := get_current_merchant_id();

  SELECT jsonb_agg(
    jsonb_build_object(
      'upload_id',          aul.id,
      'user_id',            aul.user_id,
      'user_name',          ua.fullname,
      'user_phone',         ua.tel,
      'activity_id',        aul.activity_id,
      'activity_name',      am.activity_name,
      'image_url',          aul.image_url,
      'field_values',       COALESCE(aul.field_values, '{}'::jsonb),
      'field_definitions',  COALESCE(am.field_definitions, '{}'::jsonb),
      'status',             aul.status,
      'submitted_at',       aul.submitted_at,
      'approved_at',        aul.approved_at,
      'approved_by_name',   adm.name,
      'points_awarded',     aul.points_awarded,
      'tickets_awarded',    aul.tickets_awarded,
      'rejection_reason',   aul.rejection_reason,
      'edit_version',       aul.edit_version,
      'edit_history',       COALESCE(aul.edit_history, '[]'::jsonb)
    )
    ORDER BY aul.submitted_at DESC
  )
  INTO v_uploads
  FROM activity_upload_ledger aul
  JOIN activity_master am ON aul.activity_id = am.id
  LEFT JOIN user_accounts ua ON aul.user_id = ua.id
  LEFT JOIN admin_users adm ON aul.approved_by = adm.id
  WHERE aul.merchant_id = v_merchant_id
    AND (p_status_filter IS NULL OR aul.status = p_status_filter)
    AND (p_activity_id  IS NULL OR aul.activity_id = p_activity_id)
  LIMIT p_limit
  OFFSET p_offset;

  SELECT COUNT(*) INTO v_total_count
  FROM activity_upload_ledger
  WHERE merchant_id = v_merchant_id
    AND (p_status_filter IS NULL OR status = p_status_filter)
    AND (p_activity_id  IS NULL OR activity_id = p_activity_id);

  RETURN jsonb_build_object(
    'success', true,
    'title',   NULL,
    'description', NULL,
    'data', jsonb_build_object(
      'uploads',     COALESCE(v_uploads, '[]'::jsonb),
      'total_count', v_total_count,
      'limit',       p_limit,
      'offset',      p_offset
    )
  );
END;
$function$;

DROP FUNCTION IF EXISTS public.bff_get_activity_uploads(text, uuid, integer, integer);

CREATE OR REPLACE FUNCTION public.bff_get_event_details(p_event_code text, p_language text DEFAULT 'en'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
AS $function$
DECLARE
    v_lang text;
    v_merchant_id UUID;
    v_event RECORD;
BEGIN
    v_lang := fn_normalize_ui_language(p_language);
    v_merchant_id := get_current_merchant_id();

    IF v_merchant_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'title', fn_admin_envelope_message('no_merchant_title', v_lang),
            'description', null,
            'data', null
        );
    END IF;

    SELECT
        e.*,
        ft.code as form_code,
        ft.id as form_id,
        ft.name as form_name
    INTO v_event
    FROM syngenta_events_master e
    LEFT JOIN form_templates ft ON ft.id = e.form_id
    WHERE e.merchant_id = v_merchant_id
      AND e.event_code = p_event_code;

    IF v_event.id IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'title', fn_admin_envelope_message('event_not_found_title', v_lang),
            'description', fn_admin_envelope_message('event_not_found_desc', v_lang, ARRAY[p_event_code]),
            'data', null
        );
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'title', null,
        'description', null,
        'data', jsonb_build_object(
            'id', v_event.id,
            'event_code', v_event.event_code,
            'event_name', v_event.event_name,
            'date_of_event', v_event.date_of_event,
            'owner_name', v_event.owner_name,
            'owner_email', v_event.owner_email,
            'coordinator_name', v_event.coordinator_name,
            'coordinator_email', v_event.coordinator_email,
            'province', v_event.province,
            'district', v_event.district,
            'subdistrict', v_event.subdistrict,
            'planned_activity', v_event.planned_activity,
            'planned_attended', v_event.planned_attended,
            'opened', v_event.opened,
            'opened_at', v_event.opened_at,
            'form', CASE
                WHEN v_event.form_id IS NOT NULL THEN
                    jsonb_build_object(
                        'id', v_event.form_id,
                        'code', v_event.form_code,
                        'name', v_event.form_name
                    )
                ELSE NULL
            END
        )
    );
END;
$function$;

DROP FUNCTION IF EXISTS public.bff_get_event_details(text);

CREATE OR REPLACE FUNCTION public.bff_upsert_activity_master(
  p_activity_id uuid, p_activity_code text, p_activity_name text, p_field_definitions jsonb, p_primary_dimension text,
  p_description text DEFAULT NULL::text, p_icon_url text DEFAULT NULL::text, p_banner_urls text[] DEFAULT NULL::text[],
  p_howto_banner text DEFAULT NULL::text, p_howto_description text DEFAULT NULL::text, p_label text DEFAULT NULL::text,
  p_header text DEFAULT NULL::text, p_active_status boolean DEFAULT true, p_language text DEFAULT 'en'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_lang text;
  v_merchant_id UUID;
  v_activity_id UUID;
  v_parent_created BOOLEAN := false;
  v_parent_updated BOOLEAN := false;
BEGIN
  v_lang := fn_normalize_ui_language(p_language);
  v_merchant_id := get_current_merchant_id();

  IF v_merchant_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'title', fn_admin_envelope_message('merchant_context_required_title', v_lang),
      'description', null,
      'data', null
    );
  END IF;

  IF p_activity_id IS NULL THEN
    INSERT INTO activity_master (
      merchant_id, activity_code, activity_name, description, field_definitions, primary_dimension,
      icon_url, banner_urls, howto_banner, howto_description, label, header, active_status
    ) VALUES (
      v_merchant_id, p_activity_code, p_activity_name, p_description, p_field_definitions, p_primary_dimension,
      p_icon_url, p_banner_urls, p_howto_banner, p_howto_description, p_label, p_header, p_active_status
    )
    RETURNING id INTO v_activity_id;
    v_parent_created := true;
  ELSE
    UPDATE activity_master
    SET
      activity_code = p_activity_code,
      activity_name = p_activity_name,
      description = p_description,
      field_definitions = p_field_definitions,
      primary_dimension = p_primary_dimension,
      icon_url = p_icon_url,
      banner_urls = p_banner_urls,
      howto_banner = p_howto_banner,
      howto_description = p_howto_description,
      label = p_label,
      header = p_header,
      active_status = p_active_status,
      updated_at = NOW()
    WHERE id = p_activity_id
      AND merchant_id = v_merchant_id
    RETURNING id INTO v_activity_id;

    IF NOT FOUND THEN
      RETURN jsonb_build_object(
        'success', false,
        'title', fn_admin_envelope_message('activity_not_found_title', v_lang),
        'description', null,
        'data', null
      );
    END IF;
    v_parent_updated := true;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'title', CASE WHEN v_parent_created
      THEN fn_admin_envelope_message('activity_created_title', v_lang)
      ELSE fn_admin_envelope_message('activity_updated_title', v_lang) END,
    'description', null,
    'data', jsonb_build_object(
      'activity_id', v_activity_id,
      'parent_created', v_parent_created,
      'parent_updated', v_parent_updated
    )
  );
END;
$function$;

DROP FUNCTION IF EXISTS public.bff_upsert_activity_master(uuid, text, text, jsonb, text, text, text, text[], text, text, text, text, boolean);

CREATE OR REPLACE FUNCTION public.bff_upsert_activity_currency_matrix(p_activity_id uuid, p_matrix_configs jsonb, p_language text DEFAULT 'en'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_lang text;
  v_merchant_id UUID;
  v_config JSONB;
  v_config_id UUID;
  v_created INTEGER := 0;
  v_updated INTEGER := 0;
  v_deleted INTEGER := 0;
  v_skipped INTEGER := 0;
  v_ids_to_keep UUID[] := ARRAY[]::UUID[];
BEGIN
  v_lang := fn_normalize_ui_language(p_language);
  v_merchant_id := get_current_merchant_id();

  IF v_merchant_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'title', fn_admin_envelope_message('merchant_context_required_title', v_lang), 'description', null, 'data', null);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM activity_master WHERE id = p_activity_id AND merchant_id = v_merchant_id) THEN
    RETURN jsonb_build_object('success', false, 'title', fn_admin_envelope_message('activity_not_found_title', v_lang), 'description', null, 'data', null);
  END IF;

  FOR v_config IN SELECT * FROM jsonb_array_elements(p_matrix_configs)
  LOOP
    v_config_id := (v_config->>'id')::UUID;

    IF v_config->>'primary_value' IS NULL OR v_config->>'secondary_field' IS NULL OR v_config->>'secondary_value' IS NULL THEN
      v_skipped := v_skipped + 1;
      CONTINUE;
    END IF;

    IF v_config_id IS NOT NULL THEN
      UPDATE activity_currency_config
      SET primary_value = v_config->>'primary_value', secondary_field = v_config->>'secondary_field', secondary_value = v_config->>'secondary_value',
          points_amount = COALESCE((v_config->>'points_amount')::NUMERIC, 0), ticket_type_id = (v_config->>'ticket_type_id')::UUID,
          ticket_amount = COALESCE((v_config->>'ticket_amount')::NUMERIC, 0), active_status = COALESCE((v_config->>'active_status')::BOOLEAN, true), updated_at = NOW()
      WHERE id = v_config_id AND merchant_id = v_merchant_id AND activity_id = p_activity_id;

      IF FOUND THEN
        v_updated := v_updated + 1;
        v_ids_to_keep := array_append(v_ids_to_keep, v_config_id);
      ELSE
        v_skipped := v_skipped + 1;
      END IF;
    ELSE
      INSERT INTO activity_currency_config (merchant_id, activity_id, primary_value, secondary_field, secondary_value, points_amount, ticket_type_id, ticket_amount, active_status)
      VALUES (v_merchant_id, p_activity_id, v_config->>'primary_value', v_config->>'secondary_field', v_config->>'secondary_value',
              COALESCE((v_config->>'points_amount')::NUMERIC, 0), (v_config->>'ticket_type_id')::UUID, COALESCE((v_config->>'ticket_amount')::NUMERIC, 0), COALESCE((v_config->>'active_status')::BOOLEAN, true))
      ON CONFLICT (activity_id, primary_value, secondary_field, secondary_value)
      DO UPDATE SET points_amount = EXCLUDED.points_amount, ticket_type_id = EXCLUDED.ticket_type_id, ticket_amount = EXCLUDED.ticket_amount, active_status = EXCLUDED.active_status, updated_at = NOW()
      RETURNING id INTO v_config_id;

      v_created := v_created + 1;
      v_ids_to_keep := array_append(v_ids_to_keep, v_config_id);
    END IF;
  END LOOP;

  DELETE FROM activity_currency_config
  WHERE activity_id = p_activity_id AND merchant_id = v_merchant_id AND id != ALL(v_ids_to_keep);
  GET DIAGNOSTICS v_deleted = ROW_COUNT;

  RETURN jsonb_build_object('success', true, 'title', fn_admin_envelope_message('matrix_updated_title', v_lang), 'description', null,
    'data', jsonb_build_object('activity_id', p_activity_id, 'children_created', v_created, 'children_updated', v_updated, 'children_deleted', v_deleted, 'children_skipped', v_skipped));
END;
$function$;

DROP FUNCTION IF EXISTS public.bff_upsert_activity_currency_matrix(uuid, jsonb);
