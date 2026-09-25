-- CR3 added p_allow_member_mark_used on a new overload; the prior signature was not dropped.
-- PostgREST / nested PLpgSQL calls without that arg matched both overloads ("function is not unique").

DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT pg_get_function_identity_arguments(p.oid) AS identity_args
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'bff_upsert_reward_with_conditions_and_limits'
      AND pg_get_function_identity_arguments(p.oid) NOT LIKE '%allow_member_mark_used%'
  LOOP
    EXECUTE format(
      'DROP FUNCTION public.bff_upsert_reward_with_conditions_and_limits(%s)',
      r.identity_args
    );
  END LOOP;
END $$;

-- Forward admin flag from slot/referral JSON (admin already sends p_allow_member_mark_used).
CREATE OR REPLACE FUNCTION public.bff_upsert_campaign_reward_atomic(
  p_reward jsonb,
  p_slot jsonb,
  p_request_id uuid,
  p_language text DEFAULT 'en'::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_merchant_id uuid;
  v_existing_reward_id uuid;
  v_reward_result jsonb;
  v_reward_id uuid;
  v_attach_result jsonb;
BEGIN
  PERFORM public.fn_normalize_ui_language(COALESCE(p_language, p_reward->>'p_language', 'en'));

  IF NOT EXISTS (
    SELECT 1 FROM public.admin_users au
    WHERE au.auth_user_id = auth.uid() AND au.active_status = true
  ) THEN
    RETURN public.fn_response_error('Forbidden', 'Admin access required', 'FORBIDDEN');
  END IF;

  v_merchant_id := public.get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN public.fn_response_error('No merchant', 'No merchant context', 'NO_MERCHANT');
  END IF;

  IF p_reward IS NULL OR jsonb_typeof(p_reward) <> 'object' THEN
    RETURN public.fn_response_error('Invalid reward', 'p_reward object required', 'INVALID_REWARD');
  END IF;

  IF p_slot IS NULL OR jsonb_typeof(p_slot) <> 'object' THEN
    RETURN public.fn_response_error('Invalid slot', 'p_slot object required', 'INVALID_SLOT');
  END IF;

  IF p_request_id IS NULL THEN
    RETURN public.fn_response_error('Invalid request', 'Request id required', 'INVALID_REQUEST_ID');
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtextextended(v_merchant_id::text || ':' || p_request_id::text, 0)
  );

  SELECT requests.reward_id
  INTO v_existing_reward_id
  FROM public.referral_reward_save_requests requests
  WHERE requests.merchant_id = v_merchant_id
    AND requests.request_id = p_request_id;

  IF v_existing_reward_id IS NOT NULL THEN
    RETURN public.fn_response_success(
      'Campaign reward saved',
      'This campaign reward was already saved.',
      jsonb_build_object(
        'reward_id', v_existing_reward_id,
        'operation', 'replayed',
        'slot', p_slot,
        'attached', true
      )
    );
  END IF;

  BEGIN
    v_reward_result := public.bff_upsert_reward_with_conditions_and_limits(
      p_reward_id => nullif(p_reward->>'p_reward_id', '')::uuid,
      p_name => p_reward->>'p_name',
      p_description_headline => p_reward->>'p_description_headline',
      p_description_body => p_reward->>'p_description_body',
      p_description_tc => p_reward->>'p_description_tc',
      p_description_slip => p_reward->>'p_description_slip',
      p_image => p_reward->'p_image',
      p_category_id => p_reward->'p_category_id',
      p_visibility => nullif(p_reward->>'p_visibility', '')::public.reward_visibility,
      p_redeem_window_start => nullif(p_reward->>'p_redeem_window_start', '')::timestamptz,
      p_redeem_window_end => nullif(p_reward->>'p_redeem_window_end', '')::timestamptz,
      p_stock_control => coalesce((p_reward->>'p_stock_control')::boolean, false),
      p_assign_promocode => coalesce((p_reward->>'p_assign_promocode')::boolean, false),
      p_use_expire_mode => nullif(p_reward->>'p_use_expire_mode', '')::public.reward_expire_mode,
      p_use_expire_date => nullif(p_reward->>'p_use_expire_date', '')::timestamptz,
      p_use_expire_ttl => nullif(p_reward->>'p_use_expire_ttl', '')::numeric,
      p_fulfillment_method => nullif(p_reward->>'p_fulfillment_method', '')::public.reward_fulfillment_method,
      p_allowed_tier => p_reward->'p_allowed_tier',
      p_allowed_persona => p_reward->'p_allowed_persona',
      p_allowed_tags => p_reward->'p_allowed_tags',
      p_allowed_birthmonth => p_reward->'p_allowed_birthmonth',
      p_fallback_points => nullif(p_reward->>'p_fallback_points', '')::numeric,
      p_require_points_match => coalesce((p_reward->>'p_require_points_match')::boolean, false),
      p_points_conditions => p_reward->'p_points_conditions',
      p_transaction_limits => p_reward->'p_transaction_limits',
      p_external_id_shopify => p_reward->>'p_external_id_shopify',
      p_online_store => p_reward->'p_online_store',
      p_reward_group_ids => p_reward->'p_reward_group_ids',
      p_shopify_discount_type => p_reward->>'p_shopify_discount_type',
      p_shopify_discount_label => p_reward->>'p_shopify_discount_label',
      p_variant_config => p_reward->'p_variant_config',
      p_physical_draw_name => p_reward->>'p_physical_draw_name',
      p_physical_draw_description => p_reward->>'p_physical_draw_description',
      p_allow_member_mark_used =>
        CASE
          WHEN p_reward ? 'p_allow_member_mark_used' THEN (p_reward->>'p_allow_member_mark_used')::boolean
          ELSE NULL
        END,
      p_language => coalesce(nullif(p_reward->>'p_language', ''), nullif(p_language, ''), 'en')
    );

    IF NOT coalesce((v_reward_result->>'success')::boolean, false) THEN
      RAISE EXCEPTION USING errcode = 'P0001', message = coalesce(v_reward_result->>'description', 'Reward save failed');
    END IF;

    v_reward_id := coalesce(
      nullif(v_reward_result#>>'{data,reward_id}', '')::uuid,
      nullif(v_reward_result->>'reward_id', '')::uuid
    );
    IF v_reward_id IS NULL THEN
      RAISE EXCEPTION USING errcode = 'P0001', message = 'Reward save returned no reward id';
    END IF;

    IF p_reward ? 'p_shopify_free_product_id'
      OR p_reward ? 'p_shopify_free_product_amount'
      OR p_reward ? 'p_shopify_free_product_sync_price'
    THEN
      UPDATE public.reward_master rm
      SET
        shopify_free_product_id = CASE
          WHEN p_reward ? 'p_shopify_free_product_id' THEN nullif(p_reward->>'p_shopify_free_product_id', '')
          ELSE rm.shopify_free_product_id
        END,
        shopify_free_product_amount = CASE
          WHEN p_reward ? 'p_shopify_free_product_amount' THEN nullif(p_reward->>'p_shopify_free_product_amount', '')::numeric
          ELSE rm.shopify_free_product_amount
        END,
        shopify_free_product_sync_price = CASE
          WHEN p_reward ? 'p_shopify_free_product_sync_price' THEN coalesce((p_reward->>'p_shopify_free_product_sync_price')::boolean, true)
          ELSE rm.shopify_free_product_sync_price
        END
      WHERE rm.id = v_reward_id AND rm.merchant_id = v_merchant_id;
    END IF;

    v_attach_result := public.fn_campaign_reward_slot_attach(p_slot, v_reward_id);
    IF NOT coalesce((v_attach_result->>'success')::boolean, false) THEN
      RAISE EXCEPTION USING errcode = 'P0001', message = coalesce(v_attach_result->>'description', 'Failed to attach reward');
    END IF;

    INSERT INTO public.referral_reward_save_requests (merchant_id, request_id, reward_id, slot)
    VALUES (v_merchant_id, p_request_id, v_reward_id, p_slot);
  EXCEPTION
    WHEN others THEN
      RETURN public.fn_response_error('Campaign reward not saved', SQLERRM, 'CAMPAIGN_REWARD_SAVE_FAILED');
  END;

  RETURN public.fn_response_success(
    'Campaign reward saved',
    'Reward saved and attached to the campaign slot.',
    jsonb_build_object(
      'reward_id', v_reward_id,
      'operation', lower(coalesce(v_reward_result->>'code', 'saved')),
      'slot', p_slot,
      'attached', true,
      'previous_reward_id', v_attach_result#>'{data,previous_reward_id}'
    )
  );
END;
$function$;
