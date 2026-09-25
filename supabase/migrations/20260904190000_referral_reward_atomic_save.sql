-- Save a referral-owned reward and its referral attachment in one transaction.
-- A successful response guarantees both records exist; any attachment failure
-- rolls the reward write back. The request id makes client retries idempotent.

create table if not exists public.referral_reward_save_requests (
  merchant_id uuid not null
    references public.merchant_master(id) on delete cascade,
  request_id uuid not null,
  reward_id uuid not null
    references public.reward_master(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (merchant_id, request_id)
);

create index if not exists referral_reward_save_requests_reward_idx
  on public.referral_reward_save_requests (reward_id);

alter table public.referral_reward_save_requests enable row level security;
revoke all on table public.referral_reward_save_requests from anon, authenticated;

create or replace function public.bff_upsert_referral_reward_atomic(
  p_reward jsonb,
  p_referral jsonb,
  p_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_merchant_id uuid;
  v_existing_reward_id uuid;
  v_reward_result jsonb;
  v_reward_id uuid;
  v_current_result jsonb;
  v_settings jsonb;
  v_attach_result jsonb;
  v_attach_config jsonb;
  v_outcomes jsonb;
  v_offer jsonb;
  v_previous_friend_reward_id uuid;
  v_discount_value numeric;
  v_min_spend numeric;
begin
  if not exists (
    select 1
    from public.admin_users au
    where au.auth_user_id = auth.uid()
      and au.active_status = true
  ) then
    return public.fn_response_error(
      'Forbidden',
      'Admin access required',
      'FORBIDDEN'
    );
  end if;

  v_merchant_id := public.get_current_merchant_id();
  if v_merchant_id is null then
    return public.fn_response_error(
      'No merchant',
      'No merchant context',
      'NO_MERCHANT'
    );
  end if;

  if p_reward is null or jsonb_typeof(p_reward) <> 'object' then
    return public.fn_response_error(
      'Invalid reward',
      'p_reward object required',
      'INVALID_REWARD'
    );
  end if;

  if p_referral is null
    or jsonb_typeof(p_referral) <> 'object'
    or coalesce(p_referral->>'party', '') not in ('referrer', 'friend')
  then
    return public.fn_response_error(
      'Invalid referral',
      'Referral party must be referrer or friend',
      'INVALID_REFERRAL'
    );
  end if;

  if p_request_id is null then
    return public.fn_response_error(
      'Invalid request',
      'Request id required',
      'INVALID_REQUEST_ID'
    );
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(v_merchant_id::text || ':' || p_request_id::text, 0)
  );

  select requests.reward_id
  into v_existing_reward_id
  from public.referral_reward_save_requests requests
  where requests.merchant_id = v_merchant_id
    and requests.request_id = p_request_id;

  if v_existing_reward_id is not null then
    return public.fn_response_success(
      'Referral reward saved',
      'This referral reward was already saved.',
      jsonb_build_object(
        'reward_id', v_existing_reward_id,
        'operation', 'replayed',
        'referral_attached', true
      )
    );
  end if;

  -- The exception block is a PostgreSQL subtransaction. Raising after either
  -- nested BFF returns an error rolls back the reward and referral writes.
  begin
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
      p_redeem_window_start =>
        nullif(p_reward->>'p_redeem_window_start', '')::timestamptz,
      p_redeem_window_end =>
        nullif(p_reward->>'p_redeem_window_end', '')::timestamptz,
      p_stock_control =>
        coalesce((p_reward->>'p_stock_control')::boolean, false),
      p_assign_promocode =>
        coalesce((p_reward->>'p_assign_promocode')::boolean, false),
      p_use_expire_mode =>
        nullif(p_reward->>'p_use_expire_mode', '')::public.reward_expire_mode,
      p_use_expire_date =>
        nullif(p_reward->>'p_use_expire_date', '')::timestamptz,
      p_use_expire_ttl =>
        nullif(p_reward->>'p_use_expire_ttl', '')::numeric,
      p_fulfillment_method =>
        nullif(p_reward->>'p_fulfillment_method', '')::public.reward_fulfillment_method,
      p_allowed_tier => p_reward->'p_allowed_tier',
      p_allowed_persona => p_reward->'p_allowed_persona',
      p_allowed_tags => p_reward->'p_allowed_tags',
      p_allowed_birthmonth => p_reward->'p_allowed_birthmonth',
      p_fallback_points =>
        nullif(p_reward->>'p_fallback_points', '')::numeric,
      p_require_points_match =>
        coalesce((p_reward->>'p_require_points_match')::boolean, false),
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
      p_language => coalesce(nullif(p_reward->>'p_language', ''), 'en')
    );

    if not coalesce((v_reward_result->>'success')::boolean, false) then
      raise exception using
        errcode = 'P0001',
        message = coalesce(
          v_reward_result->>'description',
          'Reward save failed'
        );
    end if;

    v_reward_id := nullif(v_reward_result->>'reward_id', '')::uuid;
    if v_reward_id is null then
      raise exception using
        errcode = 'P0001',
        message = 'Reward save returned no reward id';
    end if;

    if p_reward ? 'p_shopify_free_product_id'
      or p_reward ? 'p_shopify_free_product_amount'
      or p_reward ? 'p_shopify_free_product_sync_price'
    then
      update public.reward_master rm
      set
        shopify_free_product_id = case
          when p_reward ? 'p_shopify_free_product_id'
            then nullif(p_reward->>'p_shopify_free_product_id', '')
          else rm.shopify_free_product_id
        end,
        shopify_free_product_amount = case
          when p_reward ? 'p_shopify_free_product_amount'
            then nullif(p_reward->>'p_shopify_free_product_amount', '')::numeric
          else rm.shopify_free_product_amount
        end,
        shopify_free_product_sync_price = case
          when p_reward ? 'p_shopify_free_product_sync_price'
            then coalesce(
              (p_reward->>'p_shopify_free_product_sync_price')::boolean,
              true
            )
          else rm.shopify_free_product_sync_price
        end
      where rm.id = v_reward_id
        and rm.merchant_id = v_merchant_id;
    end if;

    v_current_result := public.bff_get_referral_settings();
    if not coalesce((v_current_result->>'success')::boolean, false) then
      raise exception using
        errcode = 'P0001',
        message = coalesce(
          v_current_result->>'description',
          'Failed to load referral settings'
        );
    end if;

    v_settings := coalesce(v_current_result->'data', '{}'::jsonb);

    if p_referral->>'party' = 'referrer' then
      v_outcomes := coalesce(
        v_settings->'purchase_referrer_outcomes',
        '[]'::jsonb
      );

      if not exists (
        select 1
        from jsonb_array_elements(v_outcomes) outcome
        where outcome->>'entity_id' = v_reward_id::text
      ) then
        v_outcomes := v_outcomes || jsonb_build_array(
          jsonb_build_object(
            'id', null,
            'party', 'inviter',
            'outcome_type', 'reward',
            'entity_id', v_reward_id,
            'amount', null,
            'valid_for_days', null
          )
        );
      end if;

      v_attach_config := jsonb_build_object(
        'program_active', true,
        'purchase_enabled', true,
        'platform_shopify', true,
        'purchase_referrer_outcomes', v_outcomes
      );
    else
      v_offer := coalesce(v_settings->'friend_offer', '{}'::jsonb);
      v_previous_friend_reward_id :=
        nullif(v_offer->>'reward_id', '')::uuid;

      v_discount_value := case
        when nullif(p_referral->>'discountValue', '') is not null
          then (p_referral->>'discountValue')::numeric
        when nullif(v_offer->>'value', '') is not null
          then (v_offer->>'value')::numeric
        else null
      end;
      v_min_spend := case
        when nullif(p_referral->>'minSpend', '') is not null
          then (p_referral->>'minSpend')::numeric
        when nullif(v_offer->>'min_spend', '') is not null
          then (v_offer->>'min_spend')::numeric
        else null
      end;

      v_attach_config := jsonb_build_object(
        'program_active', true,
        'purchase_enabled', true,
        'platform_shopify', true,
        'friend_offer',
          v_offer || jsonb_build_object(
            'reward_id', v_reward_id,
            'shopify_discount_type',
              coalesce(
                nullif(p_referral->>'discountType', ''),
                v_offer->>'shopify_discount_type'
              ),
            'discount_type',
              case
                when p_referral->>'discountType' = 'percentage'
                  then 'percent'
                else 'amount'
              end,
            'value', v_discount_value,
            'min_spend', v_min_spend
          ),
        'shopify_mother_discount_id',
          coalesce(
            nullif(p_referral->>'shopifyDiscountId', ''),
            v_settings#>>'{shopify,mother_discount_id}'
          )
      );
    end if;

    v_attach_result := public.bff_upsert_referral_settings(v_attach_config);
    if not coalesce((v_attach_result->>'success')::boolean, false) then
      raise exception using
        errcode = 'P0001',
        message = coalesce(
          v_attach_result->>'description',
          'Failed to attach reward to referral settings'
        );
    end if;

    insert into public.referral_reward_save_requests (
      merchant_id,
      request_id,
      reward_id
    )
    values (
      v_merchant_id,
      p_request_id,
      v_reward_id
    );
  exception
    when others then
      return public.fn_response_error(
        'Referral reward not saved',
        sqlerrm,
        'REFERRAL_REWARD_SAVE_FAILED'
      );
  end;

  return public.fn_response_success(
    'Referral reward saved',
    'Reward saved and attached to Referral.',
    jsonb_build_object(
      'reward_id', v_reward_id,
      'operation', lower(coalesce(v_reward_result->>'code', 'saved')),
      'referral_attached', true,
      'previous_friend_reward_id', v_previous_friend_reward_id
    )
  );
end;
$function$;

revoke all on function public.bff_upsert_referral_reward_atomic(
  jsonb,
  jsonb,
  uuid
) from public, anon;
grant execute on function public.bff_upsert_referral_reward_atomic(
  jsonb,
  jsonb,
  uuid
) to authenticated;

comment on function public.bff_upsert_referral_reward_atomic(
  jsonb,
  jsonb,
  uuid
) is
  'Atomically saves a referral-owned reward and attaches it to referral settings; request UUID makes retries idempotent.';
