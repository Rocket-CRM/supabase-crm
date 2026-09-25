-- Phase 5 (earn channels): remove legacy SQL-side Upstash from bff_get_earn_channels.
-- Member cache is loyalty-cache-api Redis + Vercel Data Cache; purge via trg_cache_purge_earn_channel.

CREATE OR REPLACE FUNCTION public.bff_get_earn_channels(
  p_language text DEFAULT NULL::text,
  p_surface text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  v_merchant_id   UUID;
  v_language      TEXT;
  v_surface       TEXT;
  v_page_icon     TEXT;
  v_default_icon  TEXT := 'https://wkevmsedchftztoolkmi.supabase.co/storage/v1/object/public/default%20images/Earn%20page%20default%20icon.svg';
  v_channels      JSONB;
BEGIN
  v_merchant_id := get_current_merchant_id();

  IF v_merchant_id IS NULL THEN
    RAISE EXCEPTION 'No merchant context found';
  END IF;

  SELECT language_code INTO v_language
  FROM merchant_languages
  WHERE merchant_id = v_merchant_id AND is_default = true
  LIMIT 1;

  v_language := COALESCE(p_language, v_language, 'en');
  v_surface  := NULLIF(lower(trim(p_surface)), '');

  SELECT COALESCE(ui_config->>'earn_channel_page_icon', v_default_icon)
  INTO v_page_icon
  FROM merchant_display_settings
  WHERE merchant_id = v_merchant_id;

  v_page_icon := COALESCE(v_page_icon, v_default_icon);

  SELECT jsonb_agg(
    jsonb_build_object(
      'id',                    c.id,
      'channel_code',          c.channel_code,
      'channel_type',          c.channel_type,
      'earn_method',           c.method_type,
      'channel_name',          c.channel_name,
      'headline',              c.headline,
      'description',           c.description,
      'howto_description',     c.howto_description,
      'banner_urls',           c.banner_urls,
      'icon_url', COALESCE(
        c.icon_url,
        (
          SELECT r.default_icon_url
          FROM public.earn_channel_registry r
          WHERE r.channel_code = c.channel_code
            AND COALESCE(r.is_active, true) = true
          LIMIT 1
        )
      ),
      'display_order',         c.display_order,
      'default_award_scope',  c.default_award_scope,
      'config',               COALESCE(c.config, '{}'::jsonb),
      'seller_reference',     COALESCE(c.config->'seller_reference', jsonb_build_object('enabled', false, 'required', false)),
      'receipt_selection',    COALESCE(c.config->'receipt_selection', jsonb_build_object('mode', 'none')),
      'receipt_number',      COALESCE(c.config->'receipt_number', jsonb_build_object('enabled', false, 'required', false)),
      'purchase_date',       COALESCE(c.config->'purchase_date', jsonb_build_object('enabled', false, 'required', false)),
      'button_show',           COALESCE((c.button_action->>'show')::boolean, false),
      'button_label',          c.button_action->>'label',
      'button_config_mode',    c.config->>'mode',
      'button_config_value',   c.config->>'value',
      'howto_banners',         c.howto_banners,
      'stores_banner',         c.stores_banner,
      'marketplace_platforms', c.marketplace_platforms
    )
    ORDER BY c.display_order ASC, c.channel_name ASC, c.channel_code ASC
  )
  INTO v_channels
  FROM public.fn_get_effective_earn_channels(v_merchant_id, v_language, false) c
  WHERE c.active = true
    AND (
      v_surface IS DISTINCT FROM 'shopify'
      OR (
        c.channel_type <> 'campaign'
        AND NOT (c.channel_type = 'purchase' AND c.channel_code <> 'shopify_store')
      )
    );

  RETURN jsonb_build_object(
    'page_icon',  v_page_icon,
    'channels',   COALESCE(v_channels, '[]'::jsonb),
    'language',   v_language,
    'cache_hit',  false
  );
END;
$function$;
