-- Return icon_url on admin earn channel reads (was saved to DB but omitted from JSON).

CREATE OR REPLACE FUNCTION public.bff_admin_get_earn_channels(p_language text DEFAULT 'en'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_lang text;
  v_merchant_id UUID;
  v_channels    jsonb;
  v_registry    jsonb;
  v_options     jsonb;
BEGIN
  v_lang := fn_normalize_ui_language(p_language);
  v_merchant_id := get_current_merchant_id();

  IF v_merchant_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false, 'code', 'NO_MERCHANT_CONTEXT',
      'title', fn_admin_envelope_message('no_merchant_title', v_lang),
      'description', fn_admin_envelope_message('could_not_resolve_merchant_desc', v_lang)
    );
  END IF;

  SELECT jsonb_agg(
    jsonb_build_object(
      'id',                    c.id,
      'override_id',           c.override_id,
      'registry_id',           c.registry_id,
      'channel_code',          c.channel_code,
      'active',                c.active,
      'display_order',         c.display_order,
      'channel_type',          c.channel_type,
      'method_type',           c.method_type,
      'default_award_scope',   c.default_award_scope,
      'is_system',             c.is_system,
      'source',                c.source,
      'source_status',         c.source_status,
      'source_ref',            c.source_ref,
      'is_computed_default',   c.is_computed_default,
      'can_hide',              c.can_hide,
      'can_delete',            c.can_delete,
      'can_reset',             (NOT c.is_computed_default AND c.registry_id IS NOT NULL AND NOT COALESCE(c.is_system, false)),
      'can_customize_copy',    c.can_customize_copy,
      'can_customize_assets',  c.can_customize_assets,
      'can_customize_method',  c.can_customize_method,
      'can_customize_button',  c.can_customize_button,
      'button_show',           COALESCE((c.button_action->>'show')::boolean, false),
      'button_label',          c.button_action->>'label',
      'button_config_mode',    c.config->>'mode',
      'button_config_value',   c.config->>'value',
      'seller_reference',      COALESCE(c.config->'seller_reference', jsonb_build_object('enabled', false, 'required', false)),
      'receipt_selection',     COALESCE(c.config->'receipt_selection', jsonb_build_object('mode', 'none')),
      'receipt_number',       COALESCE(c.config->'receipt_number', jsonb_build_object('enabled', false, 'required', false)),
      'purchase_date',        COALESCE(c.config->'purchase_date', jsonb_build_object('enabled', false, 'required', false)),
      'config',                COALESCE(c.config, '{}'::jsonb),
      'channel_name',          c.channel_name,
      'headline',              c.headline,
      'description',           c.description,
      'icon_url',                c.icon_url,
      'banner_urls',           c.banner_urls,
      'howto_banners',         c.howto_banners,
      'howto_description',     c.howto_description,
      'stores_banner',         CASE
                                 WHEN c.stores_banner IS NULL THEN '[]'::jsonb
                                 WHEN c.stores_banner LIKE '[%' THEN c.stores_banner::jsonb
                                 ELSE jsonb_build_array(c.stores_banner)
                               END,
      'marketplace_platforms', c.marketplace_platforms,
      'created_at',            c.created_at,
      'updated_at',            c.updated_at
    )
    ORDER BY c.display_order ASC, c.channel_code ASC
  )
  INTO v_channels
  FROM public.fn_get_effective_earn_channels(v_merchant_id, NULL, true) c;

  SELECT jsonb_agg(
    jsonb_build_object(
      'id',                    r.id,
      'channel_code',          r.channel_code,
      'subtype',               r.subtype,
      'type',                  r.type,
      'display_name',          r.display_name,
      'default_earn_method',   COALESCE(r.default_method_type, r.ui_component),
      'allowed_earn_methods',  r.allowed_earn_methods,
      'sort_order',            r.sort_order,
      'availability_rule',     r.availability_rule,
      'capabilities',          r.capabilities
    )
    ORDER BY r.type ASC, r.sort_order ASC
  )
  INTO v_registry
  FROM earn_channel_registry r
  WHERE COALESCE(r.is_active, true) = true;

  v_options := jsonb_build_object(
    'channel_type', jsonb_build_array(
      jsonb_build_object('label', 'Purchase',  'value', 'purchase'),
      jsonb_build_object('label', 'Campaign',  'value', 'campaign'),
      jsonb_build_object('label', 'Lifecycle', 'value', 'lifecycle'),
      jsonb_build_object('label', 'Custom',    'value', 'custom')
    ),
    'method_type', jsonb_build_array(
      jsonb_build_object('label', 'Receipt Upload',   'value', 'receipt_upload'),
      jsonb_build_object('label', 'QR Scan',          'value', 'qr_scan'),
      jsonb_build_object('label', 'Marketplace Code', 'value', 'marketplace_code'),
      jsonb_build_object('label', 'External Link',    'value', 'external_link'),
      jsonb_build_object('label', 'Account Link',     'value', 'account_link'),
      jsonb_build_object('label', 'Mission',          'value', 'mission'),
      jsonb_build_object('label', 'Form',             'value', 'form'),
      jsonb_build_object('label', 'Check-in',         'value', 'checkin'),
      jsonb_build_object('label', 'Social',           'value', 'social'),
      jsonb_build_object('label', 'Referral',         'value', 'referral'),
      jsonb_build_object('label', 'Info Card',        'value', 'info_card'),
      jsonb_build_object('label', 'Generic Card',     'value', 'generic_card')
    ),
    'marketplace_platforms', jsonb_build_array(
      jsonb_build_object('label', 'Shopee',      'value', 'shopee'),
      jsonb_build_object('label', 'Lazada',      'value', 'lazada'),
      jsonb_build_object('label', 'TikTok Shop', 'value', 'tiktok')
    ),
    'default_award_scope', jsonb_build_array(
      jsonb_build_object('label', 'Per Purchase',  'value', 'purchase'),
      jsonb_build_object('label', 'Per Line Item', 'value', 'purchase_item')
    )
  );

  RETURN jsonb_build_object(
    'success',  true,
    'channels', COALESCE(v_channels, '[]'::jsonb),
    'registry', COALESCE(v_registry, '[]'::jsonb),
    'options',  v_options
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'success', false, 'code', 'ERROR',
    'title', fn_admin_envelope_message('unexpected_error_title', v_lang),
    'description', SQLERRM, 'detail', SQLSTATE
  );
END;
$function$;
