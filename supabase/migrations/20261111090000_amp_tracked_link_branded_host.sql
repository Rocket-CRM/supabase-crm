-- AMP tracked links use the merchant's branded member-app host
-- (https://{merchant}.rocket-loyalty.app/t/{token}, proxied by loyalty-user to
-- link-redirect) instead of the raw Supabase Edge URL. Host label follows
-- fn_referral_share_hop: first DNS label of merchant_code.

CREATE OR REPLACE FUNCTION public.fn_amp_create_tracked_link(p_url text, p_merchant_id uuid, p_workflow_id uuid, p_node_id uuid, p_user_id uuid, p_channel text, p_resource_id uuid, p_label text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_token text;
  v_host text;
BEGIN
  IF p_url IS NULL
     OR p_url !~* '^https?://'
     OR p_url ILIKE '%/functions/v1/link-redirect/%'
     OR p_url ~* '^https://[a-z0-9-]+\.rocket-loyalty\.app/t/[0-9a-f]{16}' THEN
    RETURN NULL;
  END IF;

  -- LINE-owned hosts break when wrapped: LIFF only initialises when the first
  -- navigation targets liff.line.me, and the redirect injects ?rct= into the
  -- LIFF app URL.
  IF p_url ~* '^https?://([a-z0-9-]+\.)*(liff\.line\.me|line\.me|lin\.ee)([/:?#]|$)' THEN
    RETURN NULL;
  END IF;

  v_token := substr(md5(gen_random_uuid()::text || clock_timestamp()::text), 1, 16);

  INSERT INTO amp_tracked_link (token, merchant_id, workflow_id, node_id, resource_id, user_id, destination_url, channel, link_label)
  VALUES (v_token, p_merchant_id, p_workflow_id, p_node_id, p_resource_id, p_user_id, p_url, p_channel, NULLIF(p_label, ''));

  SELECT NULLIF(split_part(btrim(mm.merchant_code), '.', 1), '')
  INTO v_host
  FROM public.merchant_master mm
  WHERE mm.id = p_merchant_id;

  IF v_host IS NULL THEN
    RETURN 'https://wkevmsedchftztoolkmi.supabase.co/functions/v1/link-redirect/' || v_token;
  END IF;

  RETURN format('https://%s.rocket-loyalty.app/t/%s', v_host, v_token);
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_amp_wrap_tracked_links(p_messages jsonb, p_merchant_id uuid, p_workflow_id uuid, p_node_id uuid, p_user_id uuid, p_channel text, p_resource_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_wrapped jsonb;
  v_tokens jsonb;
BEGIN
  IF p_messages IS NULL OR p_merchant_id IS NULL THEN
    RETURN jsonb_build_object('messages', p_messages, 'tokens', '[]'::jsonb);
  END IF;

  v_wrapped := fn_amp_wrap_links_walk(p_messages, p_merchant_id, p_workflow_id, p_node_id, p_user_id, p_channel, p_resource_id, 0);

  SELECT COALESCE(jsonb_agg(DISTINCT m[1]), '[]'::jsonb)
  INTO v_tokens
  FROM regexp_matches(v_wrapped::text, '(?:link-redirect|rocket-loyalty\.app/t)/([0-9a-f]{16})', 'g') AS m;

  RETURN jsonb_build_object('messages', v_wrapped, 'tokens', v_tokens);
END;
$function$;
