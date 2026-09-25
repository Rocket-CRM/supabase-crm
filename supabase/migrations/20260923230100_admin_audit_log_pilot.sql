-- Phase 4 pilot: member create, reward upsert, receipt approve/reject (audit hooks).

-- bff_admin_create_member (canonical overload)
CREATE OR REPLACE FUNCTION public.bff_admin_create_member(p_phone text, p_firstname text DEFAULT NULL::text, p_lastname text DEFAULT NULL::text, p_fullname text DEFAULT NULL::text, p_email text DEFAULT NULL::text, p_birth_date date DEFAULT NULL::date, p_external_user_id text DEFAULT NULL::text, p_member_code text DEFAULT NULL::text, p_user_type text DEFAULT 'buyer'::text, p_persona_id uuid DEFAULT NULL::uuid, p_id_card text DEFAULT NULL::text, p_line_id text DEFAULT NULL::text, p_gender text DEFAULT NULL::text, p_acquisition_source text DEFAULT NULL::text, p_id_document_type text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET statement_timeout TO '15s'
AS $function$
DECLARE
  v_merchant_id uuid;
  v_auth_user_id uuid;
  v_admin_user_id uuid;
  v_phone text;
  v_firstname text;
  v_lastname text;
  v_fullname text;
  v_user_type public.user_type;
  v_conflict_user_id uuid;
  v_row public.user_accounts;
  v_changes jsonb := '{}'::jsonb;
BEGIN
  v_auth_user_id := auth.uid();
  IF v_auth_user_id IS NULL THEN
    RETURN fn_response_error('Authentication required', 'Admin login required', 'AUTH_REQUIRED');
  END IF;

  v_merchant_id := get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN fn_response_error('No merchant context', 'Merchant context required', 'NO_MERCHANT');
  END IF;

  IF NOT (
    check_admin_permission('customer-360', 'create')
    OR check_admin_permission('grower_registration', 'create')
    OR check_admin_permission('event', 'create')
  ) THEN
    RETURN fn_response_error(
      'Permission denied',
      'customer-360.create, grower_registration.create, or event.create required',
      'FORBIDDEN'
    );
  END IF;

  SELECT au.id INTO v_admin_user_id
  FROM admin_users au
  WHERE au.auth_user_id = v_auth_user_id AND au.merchant_id = v_merchant_id AND au.active_status = true
  LIMIT 1;
  IF v_admin_user_id IS NULL THEN
    RETURN fn_response_error('Forbidden', 'Admin access required', 'FORBIDDEN');
  END IF;

  v_phone := NULLIF(trim(COALESCE(fn_normalize_thai_phone(p_phone), p_phone, '')), '');
  IF v_phone IS NULL THEN
    RETURN fn_response_error('Phone required', 'Phone number is required', 'PHONE_REQUIRED');
  END IF;

  v_firstname := NULLIF(trim(COALESCE(p_firstname, '')), '');
  v_lastname  := NULLIF(trim(COALESCE(p_lastname, '')), '');
  v_fullname  := NULLIF(trim(COALESCE(p_fullname, '')), '');
  IF v_fullname IS NULL THEN
    v_fullname := NULLIF(trim(CONCAT_WS(' ', v_firstname, v_lastname)), '');
  END IF;

  BEGIN
    v_user_type := COALESCE(NULLIF(p_user_type, ''), 'buyer')::public.user_type;
  EXCEPTION WHEN OTHERS THEN
    RETURN fn_response_error('Invalid user type', 'user_type must be a valid user_type enum value', 'INVALID_USER_TYPE');
  END;

  IF p_persona_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM persona_master pm WHERE pm.id = p_persona_id AND pm.merchant_id = v_merchant_id
  ) THEN
    RETURN fn_response_error('Persona not found', 'Persona does not belong to current merchant', 'PERSONA_NOT_FOUND');
  END IF;

  SELECT ua.id INTO v_conflict_user_id FROM user_accounts ua WHERE ua.merchant_id = v_merchant_id AND ua.tel = v_phone LIMIT 1;
  IF v_conflict_user_id IS NOT NULL THEN
    RETURN fn_response_error('Phone already in use', 'This phone number is already registered', 'PHONE_EXISTS', jsonb_build_object('user_id', v_conflict_user_id));
  END IF;
  IF p_email IS NOT NULL AND NULLIF(trim(p_email), '') IS NOT NULL THEN
    SELECT ua.id INTO v_conflict_user_id FROM user_accounts ua WHERE ua.merchant_id = v_merchant_id AND lower(ua.email) = lower(trim(p_email)) LIMIT 1;
    IF v_conflict_user_id IS NOT NULL THEN
      RETURN fn_response_error('Email already in use', 'This email is already registered', 'EMAIL_EXISTS', jsonb_build_object('user_id', v_conflict_user_id));
    END IF;
  END IF;
  IF p_external_user_id IS NOT NULL AND NULLIF(trim(p_external_user_id), '') IS NOT NULL THEN
    SELECT ua.id INTO v_conflict_user_id FROM user_accounts ua WHERE ua.merchant_id = v_merchant_id AND ua.external_user_id = trim(p_external_user_id) LIMIT 1;
    IF v_conflict_user_id IS NOT NULL THEN
      RETURN fn_response_error('External user ID already in use', 'This external user ID is already registered', 'EXTERNAL_USER_ID_EXISTS', jsonb_build_object('user_id', v_conflict_user_id));
    END IF;
  END IF;
  IF p_member_code IS NOT NULL AND NULLIF(trim(p_member_code), '') IS NOT NULL THEN
    SELECT ua.id INTO v_conflict_user_id FROM user_accounts ua WHERE ua.merchant_id = v_merchant_id AND ua.member_code = trim(p_member_code) LIMIT 1;
    IF v_conflict_user_id IS NOT NULL THEN
      RETURN fn_response_error('Member code already in use', 'This member code is already registered', 'MEMBER_CODE_EXISTS', jsonb_build_object('user_id', v_conflict_user_id));
    END IF;
  END IF;
  IF p_line_id IS NOT NULL AND NULLIF(trim(p_line_id), '') IS NOT NULL THEN
    SELECT ua.id INTO v_conflict_user_id FROM user_accounts ua WHERE ua.merchant_id = v_merchant_id AND ua.line_id = trim(p_line_id) LIMIT 1;
    IF v_conflict_user_id IS NOT NULL THEN
      RETURN fn_response_error('LINE already in use', 'This LINE account is already linked to another member', 'LINE_ID_EXISTS', jsonb_build_object('user_id', v_conflict_user_id));
    END IF;
  END IF;

  v_changes := jsonb_strip_nulls(jsonb_build_object(
    'tel',              v_phone,
    'firstname',        v_firstname,
    'lastname',         v_lastname,
    'fullname',         v_fullname,
    'email',            NULLIF(trim(COALESCE(p_email, '')), ''),
    'birth_date',       p_birth_date,
    'external_user_id', NULLIF(trim(COALESCE(p_external_user_id, '')), ''),
    'member_code',      NULLIF(trim(COALESCE(p_member_code, '')), ''),
    'user_type',        v_user_type::text,
    'persona_id',       p_persona_id,
    'id_card',          NULLIF(trim(COALESCE(p_id_card, '')), ''),
    'id_document_type', NULLIF(trim(COALESCE(p_id_document_type, '')), ''),
    'line_id',          NULLIF(trim(COALESCE(p_line_id, '')), ''),
    'gender',           NULLIF(trim(COALESCE(p_gender, '')), ''),
    'acquisition_source', NULLIF(trim(COALESCE(p_acquisition_source, '')), '')
  )) || jsonb_build_object(
    'user_stage',              'lead',
    'is_signup_form_complete', true,
    'is_active',               true
  );

  BEGIN
    v_row := public.chokepoint_post_user_event(
      p_event_type := 'create',
      p_merchant_id := v_merchant_id,
      p_changes := v_changes,
      p_actor := jsonb_build_object('actor_id', v_admin_user_id, 'actor_type', 'admin')
    );
  EXCEPTION
    WHEN unique_violation THEN
      RETURN fn_response_error('Duplicate member', SQLERRM, 'DUPLICATE_MEMBER');
    WHEN OTHERS THEN
      IF SQLERRM LIKE 'ID_DOCUMENT:%' THEN
        RETURN fn_response_error(
          'ID document validation failed',
          COALESCE(NULLIF(split_part(SQLERRM, ':', 3), ''), SQLERRM),
          COALESCE(NULLIF(split_part(SQLERRM, ':', 2), ''), 'ID_DOCUMENT_INVALID'),
          jsonb_build_object('field_key', 'id_card')
        );
      END IF;
      RETURN fn_response_error('Create member failed', SQLERRM, 'CREATE_MEMBER_FAILED');
  END;

  PERFORM public.fn_log_admin_action(
    'member.create',
    'member',
    v_row.id,
    v_changes,
    NULL,
    to_jsonb(v_row),
    '{}'::jsonb,
    NULL,
    'bff_admin_create_member'
  );

  RETURN fn_response_success(
    'Member created',
    'Member was created successfully',
    jsonb_build_object(
      'user_id', v_row.id, 'merchant_id', v_merchant_id, 'tel', v_phone,
      'fullname', v_fullname, 'admin_user_id', v_admin_user_id,
      'id_card', v_row.id_card, 'id_document_type', v_row.id_document_type
    )
  );
END;
$function$;
