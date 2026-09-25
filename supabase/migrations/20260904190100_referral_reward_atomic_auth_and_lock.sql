-- Harden the atomic referral reward save:
-- 1. bind the selected merchant to the authenticated active admin;
-- 2. serialize all referral read/modify/write saves for one merchant.

alter function public.bff_upsert_referral_reward_atomic(jsonb, jsonb, uuid)
  rename to bff_upsert_referral_reward_atomic_core;

alter function public.bff_upsert_referral_reward_atomic_core(jsonb, jsonb, uuid)
  set search_path = pg_catalog, public;

revoke all on function public.bff_upsert_referral_reward_atomic_core(
  jsonb,
  jsonb,
  uuid
) from public, anon, authenticated;

revoke all on table public.referral_reward_save_requests
  from public, anon, authenticated;

create function public.bff_upsert_referral_reward_atomic(
  p_reward jsonb,
  p_referral jsonb,
  p_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_auth_user_id uuid;
  v_merchant_id uuid;
begin
  v_auth_user_id := auth.uid();
  v_merchant_id := public.get_current_merchant_id();

  if v_auth_user_id is null
    or v_merchant_id is null
    or not exists (
      select 1
      from public.admin_users au
      where au.auth_user_id = v_auth_user_id
        and au.merchant_id = v_merchant_id
        and au.active_status = true
    )
  then
    return public.fn_response_error(
      'Forbidden',
      'Active merchant admin access required',
      'FORBIDDEN'
    );
  end if;

  -- The referral settings BFF is read/modify/write. Lock the aggregate, not
  -- only the idempotency key, so concurrent saves cannot lose an attachment.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'referral-reward-merchant:' || v_merchant_id::text,
      0
    )
  );

  return public.bff_upsert_referral_reward_atomic_core(
    p_reward,
    p_referral,
    p_request_id
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
  'Authenticated merchant-bound wrapper that serializes and atomically saves a referral reward.';
