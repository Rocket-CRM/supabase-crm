-- Native leaderboard rows: personal_row uses user_accounts.id + campaign user_key_field
CREATE OR REPLACE FUNCTION public.api_get_leaderboard_rows(p_merchant_code text, p_path text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_merchant_id uuid;
  v_path text;
  v_campaign record;
  v_name text;
  v_columns jsonb;
  v_rank_field text;
  v_direction text;
  v_top_x integer;
  v_user_id uuid;
  v_user_key text;
  v_account_id uuid;
  v_key_field text;
  v_participating boolean;
  v_sql text;
  v_rows jsonb;
  v_personal_row jsonb;
BEGIN
  IF p_merchant_code IS NULL OR trim(p_merchant_code) = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Merchant code is required');
  END IF;

  SELECT id INTO v_merchant_id
  FROM merchant_master
  WHERE merchant_code = p_merchant_code;

  IF v_merchant_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Merchant not found');
  END IF;

  v_path := fn_leaderboard_normalize_path(p_path);
  IF v_path = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Path is required');
  END IF;

  SELECT
    cl.campaign_code,
    cl.source_kind,
    cl.datawh_table_code,
    cl.requires_participation,
    cl.rank_config,
    cl.top_x,
    cl.active_status,
    cl.user_key_field
  INTO v_campaign
  FROM campaign_leaderboard cl
  WHERE cl.merchant_id = v_merchant_id
    AND cl.path = v_path
    AND cl.active_status = true;

  IF v_campaign.campaign_code IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Leaderboard campaign not found');
  END IF;

  IF COALESCE(v_campaign.source_kind, 'legacy') <> 'native' THEN
    RETURN jsonb_build_object('success', false, 'error', 'This leaderboard is not a native source');
  END IF;

  v_user_id := get_current_user_id();

  IF v_campaign.requires_participation THEN
    IF v_user_id IS NULL THEN
      RETURN jsonb_build_object(
        'success', false,
        'code', 'participation_required',
        'error', 'Sign in and participate to view this leaderboard'
      );
    END IF;
    v_user_key := v_user_id::text;

    SELECT EXISTS (
      SELECT 1
      FROM campaign_participation cp
      WHERE cp.merchant_id = v_merchant_id
        AND cp.campaign_code = v_campaign.campaign_code
        AND (cp.userid = v_user_key OR cp.userid_text = v_user_key)
    ) INTO v_participating;

    IF NOT v_participating THEN
      RETURN jsonb_build_object(
        'success', false,
        'code', 'participation_required',
        'error', 'Participate to view this leaderboard'
      );
    END IF;
  END IF;

  v_name := fn_leaderboard_normalize_relation_name(v_campaign.datawh_table_code);
  IF v_name IS NULL OR NOT fn_leaderboard_relation_exists(v_name) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Leaderboard source view is missing or not allowed');
  END IF;

  v_columns := fn_leaderboard_relation_columns(v_name);
  IF NOT EXISTS (
    SELECT 1 FROM jsonb_array_elements(v_columns) col WHERE lower(col->>'name') = 'merchant_id'
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Leaderboard source is missing merchant_id');
  END IF;

  v_key_field := NULLIF(trim(COALESCE(v_campaign.user_key_field, 'user_id')), '');

  IF v_user_id IS NOT NULL AND v_key_field IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM jsonb_array_elements(v_columns) col WHERE col->>'name' = v_key_field
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Member key field is not on the source view');
  END IF;

  v_rank_field := NULLIF(trim(COALESCE(v_campaign.rank_config->>'field', '')), '');
  IF v_rank_field IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM jsonb_array_elements(v_columns) col WHERE col->>'name' = v_rank_field
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Ranked field is not on the source view');
  END IF;

  v_direction := CASE WHEN lower(COALESCE(v_campaign.rank_config->>'direction', 'desc')) = 'asc' THEN 'ASC' ELSE 'DESC' END;
  v_top_x := LEAST(GREATEST(COALESCE(v_campaign.top_x, 10), 1), 5000);

  IF v_rank_field IS NULL THEN
    v_sql := format(
      'SELECT COALESCE(jsonb_agg(to_jsonb(t)), ''[]''::jsonb) FROM (
         SELECT * FROM public.%I WHERE merchant_id = $1 LIMIT $2
       ) t',
      v_name
    );
  ELSE
    v_sql := format(
      'SELECT COALESCE(jsonb_agg(to_jsonb(t)), ''[]''::jsonb) FROM (
         SELECT * FROM public.%I
         WHERE merchant_id = $1
         ORDER BY %I %s NULLS LAST
         LIMIT $2
       ) t',
      v_name,
      v_rank_field,
      v_direction
    );
  END IF;

  EXECUTE v_sql INTO v_rows USING v_merchant_id, v_top_x;

  v_personal_row := NULL;
  IF v_user_id IS NOT NULL AND v_key_field IS NOT NULL THEN
    SELECT ua.id
    INTO v_account_id
    FROM user_accounts ua
    WHERE ua.merchant_id = v_merchant_id
      AND (ua.id = v_user_id OR ua.auth_user_id = v_user_id)
    ORDER BY CASE WHEN ua.id = v_user_id THEN 0 ELSE 1 END
    LIMIT 1;

    v_account_id := COALESCE(v_account_id, v_user_id);

    v_sql := format(
      'SELECT to_jsonb(t) FROM public.%I t WHERE t.merchant_id = $1 AND t.%I::text = $2 LIMIT 1',
      v_name,
      v_key_field
    );
    EXECUTE v_sql INTO v_personal_row USING v_merchant_id, v_account_id::text;
    IF v_personal_row IS NULL AND v_account_id IS DISTINCT FROM v_user_id THEN
      EXECUTE v_sql INTO v_personal_row USING v_merchant_id, v_user_id::text;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'data', COALESCE(v_rows, '[]'::jsonb),
    'personal_row', v_personal_row
  );
END;
$function$;
