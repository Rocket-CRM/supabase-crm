-- Customer 360 / Front Line member search: identifiers on btree equality paths; names on merchant_search_trgm.
-- Deploy before dropping idx_user_accounts_merchant (see scripts/ops/user_accounts_index_cleanup_steps_2_4.sql).

CREATE OR REPLACE FUNCTION public.bff_admin_search_members(
  p_query text,
  p_limit integer DEFAULT 20,
  p_store_id uuid DEFAULT NULL::uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_merchant_id uuid;
  v_results jsonb;
  v_search text;
  v_compact text;
  v_digits text;
  v_phone_core text;
  v_limit int;
  v_is_identifier boolean;
BEGIN
  v_merchant_id := get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN fn_response_error('Unauthorized', 'Merchant context required');
  END IF;

  IF NOT (
    check_admin_permission('customer-360', 'read')
    OR check_admin_permission('front_line', 'read')
  ) THEN
    RETURN fn_response_error(
      'Permission denied',
      'customer-360.read or front_line.read required'
    );
  END IF;

  v_search := lower(trim(COALESCE(p_query, '')));
  -- POSIX class, hyphen last. Do not use [\s\-+]: extra backslashes make a \\ to + range.
  v_compact := lower(regexp_replace(v_search, '[[:space:]+-]+', '', 'g'));
  v_digits := regexp_replace(v_search, '[^0-9]', '', 'g');
  v_is_identifier := length(v_digits) >= 2 AND v_compact = regexp_replace(v_compact, '[^0-9]', '', 'g');

  IF v_is_identifier THEN
    IF length(v_digits) < 2 THEN
      RETURN jsonb_build_object('success', true, 'data', '[]'::jsonb);
    END IF;
  ELSIF length(v_search) < 3 THEN
    RETURN jsonb_build_object('success', true, 'data', '[]'::jsonb);
  END IF;

  IF v_is_identifier AND length(v_digits) >= 2 THEN
    v_phone_core := CASE
      WHEN v_digits LIKE '66%' AND length(v_digits) >= 4 THEN substring(v_digits from 3)
      WHEN v_digits LIKE '0%' THEN substring(v_digits from 2)
      ELSE v_digits
    END;
    IF v_phone_core = '' THEN
      v_phone_core := NULL;
    END IF;
  ELSE
    v_phone_core := NULL;
  END IF;

  IF p_store_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM store_master sm
    WHERE sm.id = p_store_id AND sm.merchant_id = v_merchant_id
  ) THEN
    RETURN fn_response_error('Store not found', 'Store does not belong to current merchant', 'STORE_NOT_FOUND');
  END IF;

  v_limit := LEAST(GREATEST(COALESCE(p_limit, 20), 1), 100);

  SELECT COALESCE(jsonb_agg(row_to_json(r)::jsonb), '[]'::jsonb)
  INTO v_results
  FROM (
    SELECT
      h.user_id,
      h.fullname,
      h.firstname,
      h.lastname,
      h.email,
      h.tel,
      h.image,
      tm.tier_name,
      tm.color AS tier_color,
      tm.icon AS tier_icon,
      h.persona_id,
      COALESCE(pm.persona_name, CASE WHEN pm.id IS NULL THEN pgm.group_name END) AS persona_name,
      h.user_type,
      h.birth_date,
      NULL::text AS nationality,
      h.external_user_id,
      h.member_code,
      COALESCE(uw.points_balance, 0)::numeric AS points_balance,
      h.is_freeze
    FROM (
      SELECT
        ua.id AS user_id,
        ua.fullname,
        ua.firstname,
        ua.lastname,
        ua.email,
        ua.tel,
        ua.image,
        ua.persona_id,
        ua.user_type::text AS user_type,
        ua.birth_date,
        ua.external_user_id,
        ua.member_code,
        ua.tier_id,
        ua.merchant_id,
        COALESCE(ua.is_freeze, false) AS is_freeze,
        ua.created_at,
        CASE
          WHEN ua.member_code IS NOT NULL AND lower(ua.member_code) = v_search THEN 0
          WHEN v_compact <> '' AND ua.id_card IS NOT NULL
            AND upper(regexp_replace(btrim(ua.id_card), '[\s-]+', '', 'g')) = upper(v_compact) THEN 1
          WHEN ua.member_code = v_digits THEN 2
          WHEN ua.tel IN (
            v_search,
            v_compact,
            '0' || COALESCE(v_phone_core, ''),
            '+66' || COALESCE(v_phone_core, ''),
            '66' || COALESCE(v_phone_core, '')
          ) THEN 3
          WHEN ua.fullname ILIKE v_search || '%' THEN 5
          ELSE 7
        END AS rank_ord
      FROM user_accounts ua
      WHERE ua.merchant_id = v_merchant_id
        AND ua.deleted_at IS NULL
        AND (
          CASE
            WHEN v_is_identifier THEN (
              (length(v_digits) = 8 AND ua.member_code = v_digits)
              OR ua.tel IN (
                v_search,
                v_compact,
                '0' || COALESCE(v_phone_core, v_digits),
                '+66' || COALESCE(v_phone_core, v_digits),
                '66' || COALESCE(v_phone_core, v_digits)
              )
              OR (
                length(v_compact) >= 8
                AND ua.id_card IS NOT NULL
                AND upper(regexp_replace(btrim(ua.id_card), '[\s-]+', '', 'g')) = upper(v_compact)
              )
            )
            ELSE public.fn_member_search_text(
              ua.fullname, ua.firstname, ua.lastname, ua.email, ua.tel,
              ua.member_code, ua.external_user_id, ua.id_card
            ) ILIKE ('%' || v_search || '%')
          END
        )
        AND (
          p_store_id IS NULL
          OR EXISTS (
            SELECT 1 FROM purchase_ledger pl
            WHERE pl.merchant_id = v_merchant_id
              AND pl.user_id = ua.id
              AND pl.store_id = p_store_id
          )
          OR EXISTS (
            SELECT 1 FROM reward_redemptions_ledger rrl
            WHERE rrl.merchant_id = v_merchant_id
              AND rrl.user_id = ua.id
              AND (rrl.redeemed_store_id = p_store_id OR rrl.used_store_id = p_store_id)
          )
        )
      ORDER BY rank_ord, ua.fullname NULLS LAST, ua.created_at DESC
      LIMIT v_limit
    ) h
    LEFT JOIN tier_master tm
      ON tm.id = h.tier_id AND tm.merchant_id = h.merchant_id
    LEFT JOIN persona_master pm
      ON pm.id = h.persona_id AND pm.merchant_id = h.merchant_id
    LEFT JOIN persona_group_master pgm
      ON pgm.id = COALESCE(pm.group_id, h.persona_id) AND pgm.merchant_id = h.merchant_id
    LEFT JOIN user_wallet uw
      ON uw.user_id = h.user_id AND uw.merchant_id = h.merchant_id
    ORDER BY h.rank_ord, h.fullname NULLS LAST, h.created_at DESC
  ) r;

  RETURN jsonb_build_object('success', true, 'data', v_results);
EXCEPTION WHEN OTHERS THEN
  RETURN fn_response_error('Search failed', SQLERRM, 'SEARCH_FAILED');
END;
$function$;
