-- Grant Rocket Deck eng-bug MCP proxy scopes to CRM Knowledge MCP tokens.

UPDATE public.system_mcp_access_tokens t
SET
  scopes = sub.merged,
  updated_at = now()
FROM (
  SELECT
    id,
    (
      SELECT array_agg(DISTINCT s ORDER BY s)
      FROM unnest(
        t2.scopes || ARRAY['eng_bugs:read', 'eng_bugs:write']::text[]
      ) AS s
    ) AS merged
  FROM public.system_mcp_access_tokens t2
  WHERE t2.is_active IS TRUE
    AND t2.revoked_at IS NULL
    AND 'knowledge:read' = ANY (t2.scopes)
    AND NOT ('eng_bugs:read' = ANY (t2.scopes))
) sub
WHERE t.id = sub.id;

CREATE OR REPLACE FUNCTION public.superadmin_create_mcp_access_token(
  p_token_hash text,
  p_token_prefix text,
  p_label text,
  p_scopes text[] DEFAULT ARRAY[
    'knowledge:read'::text,
    'eng_bugs:read'::text,
    'eng_bugs:write'::text
  ],
  p_allowed_tools text[] DEFAULT NULL::text[],
  p_allowed_feature_slugs text[] DEFAULT NULL::text[],
  p_expires_at timestamp with time zone DEFAULT NULL::timestamp with time zone,
  p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare
  v_admin_user_id uuid;
  v_token_id uuid;
begin
  v_admin_user_id := public.fn_current_platform_superadmin_user_id();

  if v_admin_user_id is null then
    return public.fn_response_error('Forbidden', 'Only platform_superadmin users can create MCP access tokens', 'FORBIDDEN');
  end if;

  if p_token_hash is null or length(btrim(p_token_hash)) < 32 then
    return public.fn_response_error('Invalid token hash', 'Token hash is required', 'INVALID_TOKEN_HASH');
  end if;

  if p_token_prefix is null or length(btrim(p_token_prefix)) < 8 then
    return public.fn_response_error('Invalid token prefix', 'Token prefix is required for display and audit', 'INVALID_TOKEN_PREFIX');
  end if;

  if p_label is null or length(btrim(p_label)) = 0 then
    return public.fn_response_error('Invalid label', 'Label is required', 'INVALID_LABEL');
  end if;

  if p_scopes is null or array_length(p_scopes, 1) is null then
    p_scopes := array[
      'knowledge:read',
      'eng_bugs:read',
      'eng_bugs:write'
    ]::text[];
  end if;

  insert into public.system_mcp_access_tokens (
    token_hash,
    token_prefix,
    label,
    owner_admin_user_id,
    created_by_admin_user_id,
    scopes,
    allowed_tools,
    allowed_feature_slugs,
    expires_at,
    metadata
  ) values (
    p_token_hash,
    btrim(p_token_prefix),
    btrim(p_label),
    v_admin_user_id,
    v_admin_user_id,
    p_scopes,
    p_allowed_tools,
    p_allowed_feature_slugs,
    p_expires_at,
    coalesce(p_metadata, '{}'::jsonb)
  )
  returning id into v_token_id;

  return public.fn_response_success(
    'MCP token created',
    'Token metadata was stored. Show the raw token only once in the client.',
    jsonb_build_object('id', v_token_id, 'token_prefix', btrim(p_token_prefix), 'scopes', p_scopes)
  );
exception
  when unique_violation then
    return public.fn_response_error('Duplicate token', 'Token hash already exists', 'DUPLICATE_TOKEN');
end;
$function$;
