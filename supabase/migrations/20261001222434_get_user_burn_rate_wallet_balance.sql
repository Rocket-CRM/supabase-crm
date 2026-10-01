-- Checkout burn preview: use user_wallet.points_balance (same as chokepoint) instead of
-- raw wallet_ledger sum, which overcounts for migrated merchants missing expiry ledger rows.

CREATE OR REPLACE FUNCTION public.get_user_burn_rate()
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_merchant_id UUID;
    v_user_id UUID;
    v_account_id UUID;
    v_tier_id UUID;
    v_tier_name TEXT;
    v_resolved JSONB;
    v_effective_rate NUMERIC;
    v_multiplier NUMERIC := 1.0;
    v_available_points NUMERIC;
    v_factors JSON;
    v_source TEXT;
    v_is_enabled BOOLEAN;
BEGIN
    v_merchant_id := public.get_current_merchant_id();
    IF v_merchant_id IS NULL THEN
        RETURN json_build_object('error', 'no_merchant_context');
    END IF;

    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RETURN json_build_object('error', 'no_user_context');
    END IF;

    SELECT ua.id, ua.tier_id, tm.tier_name
    INTO v_account_id, v_tier_id, v_tier_name
    FROM user_accounts ua
    LEFT JOIN tier_master tm ON tm.id = ua.tier_id AND tm.merchant_id = ua.merchant_id
    WHERE ua.auth_user_id = v_user_id
      AND ua.merchant_id = v_merchant_id;

    v_resolved := public.fn_resolve_burn_rate(v_merchant_id, v_tier_id);
    v_effective_rate := COALESCE((v_resolved->>'effective_rate')::numeric, 0);
    v_source := v_resolved->>'source';
    v_is_enabled := COALESCE((v_resolved->>'is_enabled')::boolean, false);

    IF NOT v_is_enabled THEN
        RETURN json_build_object(
            'effective_rate', 0,
            'base_rate', 0,
            'multiplier', 1.0,
            'is_enabled', false,
            'tier_name', COALESCE(v_tier_name, 'none'),
            'available_points', 0,
            'max_discount', 0,
            'source', v_source,
            'merchant_default_rate', (v_resolved->>'merchant_default_rate')::numeric,
            'tier_override_rate', (v_resolved->>'tier_override_rate')::numeric,
            'factors', json_build_array()
        );
    END IF;

    IF v_source = 'tier_override' THEN
        v_factors := json_build_array(
            json_build_object(
                'source', 'tier',
                'name', v_tier_name,
                'value', v_effective_rate,
                'type', 'override'
            )
        );
    ELSE
        v_factors := json_build_array(
            json_build_object(
                'source', 'merchant',
                'name', 'default_burn_rate',
                'value', v_effective_rate,
                'type', 'base'
            )
        );
    END IF;

    SELECT COALESCE(uw.points_balance, 0)
    INTO v_available_points
    FROM user_wallet uw
    WHERE uw.user_id = v_account_id
      AND uw.merchant_id = v_merchant_id;

    RETURN json_build_object(
        'effective_rate', v_effective_rate * v_multiplier,
        'base_rate', v_effective_rate,
        'multiplier', v_multiplier,
        'is_enabled', true,
        'tier_name', COALESCE(v_tier_name, 'none'),
        'available_points', GREATEST(v_available_points, 0),
        'max_discount', GREATEST(v_available_points * v_effective_rate * v_multiplier, 0),
        'source', v_source,
        'merchant_default_rate', (v_resolved->>'merchant_default_rate')::numeric,
        'tier_override_rate', (v_resolved->>'tier_override_rate')::numeric,
        'factors', v_factors
    );
END;
$function$;
