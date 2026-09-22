-- Shopify landing: page-level card grid theme + section layout keys (hero, earn/spend, how it works)

CREATE OR REPLACE FUNCTION public.fn_shopify_landing_default_page_config()
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT jsonb_build_object(
    '_schema_version', '2.0.0',
    'seo', jsonb_build_object(
      'slug', 'rewards',
      'meta_title', '',
      'meta_description', '',
      'og_image_url', ''
    ),
    'theme', jsonb_build_object(
      'section_padding_px', 88,
      'cards', jsonb_build_object(
        'gap_px', 24,
        'border', 'none',
        'fill', 'raised'
      ),
      'import', jsonb_build_object(
        'first_run_dismissed_at', NULL
      )
    )
  );
$function$;

CREATE OR REPLACE FUNCTION public.fn_validate_shopify_landing_page_config(p_config jsonb)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
DECLARE
  v_slug text;
  v_theme jsonb;
  v_pad int;
  v_cards jsonb;
  v_gap int;
  v_border text;
  v_fill text;
BEGIN
  IF p_config IS NULL OR jsonb_typeof(p_config) <> 'object' THEN
    RETURN 'config must be a JSON object';
  END IF;

  IF coalesce(p_config ->> '_schema_version', '') <> '2.0.0' THEN
    RETURN '_schema_version must be 2.0.0';
  END IF;

  v_slug := coalesce(p_config #>> '{seo,slug}', '');
  IF v_slug = '' OR v_slug !~ '^[a-z0-9-]+$' THEN
    RETURN 'seo.slug must be lowercase letters, numbers, and hyphens';
  END IF;

  v_theme := p_config -> 'theme';
  IF v_theme IS NULL OR jsonb_typeof(v_theme) <> 'object' THEN
    RETURN 'theme is required';
  END IF;

  IF v_theme ? 'secondary_color' OR v_theme ? 'accent_color' OR v_theme ? 'text_on_dark'
     OR v_theme ? 'text_on_light' OR v_theme ? 'typography' THEN
    RETURN 'theme uses removed v1 keys; upgrade to v2 palette model';
  END IF;
  IF v_theme ? 'palette' OR v_theme ? 'buttons' THEN
    RETURN 'theme.palette and theme.buttons moved to shopify_brand_scheme; use Brand scheme editor';
  END IF;
  IF v_theme #> '{import,imported_from}' IS NOT NULL AND v_theme #> '{import,imported_from}' <> 'null'::jsonb THEN
    RETURN 'theme.import.imported_from moved to shopify_brand_scheme; use Brand scheme editor';
  END IF;

  v_pad := coalesce((v_theme ->> 'section_padding_px')::int, 88);
  IF v_pad NOT BETWEEN 24 AND 160 THEN
    RETURN 'theme.section_padding_px must be 24–160';
  END IF;

  v_cards := coalesce(v_theme -> 'cards', '{}'::jsonb);
  IF jsonb_typeof(v_cards) <> 'object' THEN
    RETURN 'theme.cards must be an object';
  END IF;

  IF v_cards ? 'gap_px' THEN
    IF (v_cards ->> 'gap_px') !~ '^-?\d+$' THEN
      RETURN 'theme.cards.gap_px must be an integer';
    END IF;
    v_gap := (v_cards ->> 'gap_px')::int;
    IF v_gap NOT BETWEEN 0 AND 48 OR v_gap % 4 <> 0 THEN
      RETURN 'theme.cards.gap_px must be 0–48 in steps of 4';
    END IF;
  END IF;

  v_border := coalesce(v_cards ->> 'border', 'none');
  IF v_border NOT IN ('none', 'line') THEN
    RETURN 'theme.cards.border must be none or line';
  END IF;

  v_fill := coalesce(v_cards ->> 'fill', 'raised');
  IF v_fill NOT IN ('flat', 'raised') THEN
    RETURN 'theme.cards.fill must be flat or raised';
  END IF;

  RETURN NULL;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_shopify_landing_default_section_config(p_block_type text)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
DECLARE
  v_surface jsonb := jsonb_build_object('swatch', 'background', 'custom_hex', NULL, 'gradient', false);
  v_dark jsonb := jsonb_build_object('swatch', 'dark_surface', 'custom_hex', NULL, 'gradient', false);
BEGIN
  CASE p_block_type
    WHEN 'shopify_landing_hero' THEN
      RETURN jsonb_build_object(
        'surface', v_dark,
        'text_hex', NULL,
        'content_align', 'center',
        'side_image_position', 'none',
        'side_image_url', '',
        'background', jsonb_build_object(
          'image_url', '',
          'tint', jsonb_build_object(
            'enabled', false,
            'type', 'solid',
            'color', 'dark',
            'strength_pct', 40
          )
        ),
        'content_card', jsonb_build_object(
          'enabled', true,
          'bg_color', '#1c1c1c',
          'bg_opacity_pct', 85,
          'radius_px', 12,
          'padding_px', 32
        ),
        'guest', jsonb_build_object(
          'headline', 'Earn rewards every time you shop',
          'subtext', 'Join our rewards program to earn points and unlock perks.',
          'intro_override', '',
          'cta', public.fn_shopify_landing_default_cta('Join rewards', true)
        ),
        'member', jsonb_build_object(
          'headline', 'Hello {first_name}',
          'subtext', 'You have {balance} {points_name} · {tier_name}',
          'intro_override', '',
          'cta', public.fn_shopify_landing_default_cta('View my rewards', true)
        )
      );
    WHEN 'shopify_landing_how_it_works' THEN
      RETURN jsonb_build_object(
        'surface', v_surface,
        'text_hex', NULL,
        'title', 'How rewards work',
        'description', 'Join for free, earn on every order, and redeem rewards you actually want.',
        'tile_layout', 'stacked',
        'steps_marker', 'icon',
        'steps', jsonb_build_array(
          jsonb_build_object('icon_url', '', 'heading', 'Join rewards', 'description', 'Create an account in seconds.'),
          jsonb_build_object('icon_url', '', 'heading', 'Earn points', 'description', 'Shop, refer friends, and complete actions.'),
          jsonb_build_object('icon_url', '', 'heading', 'Redeem rewards', 'description', 'Turn points into discounts and perks.')
        ),
        'guest', jsonb_build_object('intro_override', '', 'cta', public.fn_shopify_landing_default_cta('Join rewards', true)),
        'member', jsonb_build_object('intro_override', '', 'cta', public.fn_shopify_landing_default_cta('View my rewards', true))
      );
    WHEN 'shopify_landing_ways_to_earn' THEN
      RETURN jsonb_build_object(
        'surface', v_surface,
        'text_hex', NULL,
        'title', 'Ways to earn',
        'description', '',
        'tile_limit', 12,
        'tile_layout', 'stacked',
        'grid', jsonb_build_object('columns_desktop', 3),
        'guest', jsonb_build_object('intro_override', '', 'cta', public.fn_shopify_landing_default_cta('View all', true)),
        'member', jsonb_build_object('intro_override', '', 'cta', public.fn_shopify_landing_default_cta('View all', true))
      );
    WHEN 'shopify_landing_ways_to_spend' THEN
      RETURN jsonb_build_object(
        'surface', v_surface,
        'text_hex', NULL,
        'title', 'Ways to spend',
        'description', '',
        'tile_limit', 12,
        'tile_layout', 'stacked',
        'grid', jsonb_build_object('columns_desktop', 3),
        'guest', jsonb_build_object('intro_override', '', 'cta', public.fn_shopify_landing_default_cta('View all', true)),
        'member', jsonb_build_object('intro_override', '', 'cta', public.fn_shopify_landing_default_cta('View all', true))
      );
    WHEN 'shopify_landing_referrals' THEN
      RETURN jsonb_build_object(
        'surface', v_surface,
        'text_hex', NULL,
        'title', 'Share rewards with friends',
        'description', 'Invite friends and you both earn bonus points.',
        'layout', 'image_right',
        'side_image_url', '',
        'guest', jsonb_build_object(
          'intro_override', 'Join to refer friends and earn bonus points.',
          'cta', public.fn_shopify_landing_default_cta('Join rewards', true)
        ),
        'member', jsonb_build_object(
          'intro_override', '',
          'cta', public.fn_shopify_landing_default_cta('Copy link', false)
        )
      );
    WHEN 'shopify_landing_vip' THEN
      RETURN jsonb_build_object(
        'surface', v_surface,
        'text_hex', NULL,
        'title', 'VIP tiers',
        'description', 'Unlock more rewards as you shop.',
        'guest', jsonb_build_object('intro_override', '', 'cta', public.fn_shopify_landing_default_cta('Join now', true)),
        'member', jsonb_build_object('intro_override', '', 'cta', public.fn_shopify_landing_default_cta('View my tier', true))
      );
    WHEN 'shopify_landing_faq' THEN
      RETURN jsonb_build_object(
        'surface', v_surface,
        'text_hex', NULL,
        'title', 'FAQ',
        'items', jsonb_build_array(
          jsonb_build_object(
            'question', 'Do points expire?',
            'answer', 'Check your program settings for the points expiry window. Unused points may expire after a period of inactivity.'
          )
        ),
        'guest', jsonb_build_object('intro_override', '', 'cta', public.fn_shopify_landing_default_cta('', false)),
        'member', jsonb_build_object('intro_override', '', 'cta', public.fn_shopify_landing_default_cta('', false))
      );
    ELSE
      RETURN jsonb_build_object('surface', v_surface, 'text_hex', NULL);
  END CASE;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_validate_shopify_landing_section_config(p_block_type text, p_config jsonb)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
DECLARE
  v_surface jsonb;
  v_swatch text;
  v_steps jsonb;
  v_items jsonb;
  v_style text;
  v_hex_key text;
  v_cols int;
BEGIN
  IF p_config IS NULL OR jsonb_typeof(p_config) <> 'object' THEN
    RETURN 'section config must be a JSON object';
  END IF;

  IF p_config ? 'section_style' THEN
    RETURN 'section_style was removed; use surface.swatch';
  END IF;

  v_surface := p_config -> 'surface';
  IF v_surface IS NULL OR jsonb_typeof(v_surface) <> 'object' THEN
    RETURN 'surface is required';
  END IF;

  v_swatch := coalesce(v_surface ->> 'swatch', '');
  IF v_swatch NOT IN ('background', 'dark_surface', 'primary', 'brand', 'extra', 'custom') THEN
    RETURN 'surface.swatch must be background, dark_surface, primary, or custom';
  END IF;
  IF v_swatch = 'custom' AND NOT public.fn_shopify_landing_is_hex(v_surface ->> 'custom_hex') THEN
    RETURN 'surface.custom_hex must be a hex color when swatch is custom';
  END IF;
  IF NOT (v_surface ? 'gradient') OR jsonb_typeof(v_surface -> 'gradient') <> 'boolean' THEN
    RETURN 'surface.gradient must be a boolean';
  END IF;

  FOREACH v_hex_key IN ARRAY ARRAY['text_hex', 'heading_hex'] LOOP
    IF p_config ? v_hex_key
       AND p_config -> v_hex_key IS NOT NULL
       AND p_config -> v_hex_key <> 'null'::jsonb THEN
      IF NOT public.fn_shopify_landing_is_hex(p_config ->> v_hex_key) THEN
        RETURN v_hex_key || ' must be hex or null';
      END IF;
    END IF;
  END LOOP;

  FOREACH v_style IN ARRAY ARRAY[
    p_config #>> '{guest,cta,button_style}',
    p_config #>> '{member,cta,button_style}'
  ] LOOP
    IF v_style IS NOT NULL AND v_style NOT IN ('primary', 'secondary', 'link', 'inherit') THEN
      RETURN 'section CTA button_style must be primary, secondary, link, or inherit';
    END IF;
  END LOOP;

  IF p_block_type = 'shopify_landing_hero' THEN
    IF coalesce(p_config ->> 'content_align', 'center') NOT IN ('start', 'center', 'end') THEN
      RETURN 'content_align must be start, center, or end';
    END IF;
    IF coalesce(p_config ->> 'side_image_position', 'none') NOT IN ('none', 'start', 'end') THEN
      RETURN 'side_image_position must be none, start, or end';
    END IF;
    IF p_config ? 'side_image_url' AND jsonb_typeof(p_config -> 'side_image_url') <> 'string' THEN
      RETURN 'side_image_url must be a string';
    END IF;
  END IF;

  IF p_block_type IN ('shopify_landing_ways_to_earn', 'shopify_landing_ways_to_spend', 'shopify_landing_how_it_works') THEN
    IF coalesce(p_config ->> 'tile_layout', 'stacked') NOT IN ('stacked', 'inline') THEN
      RETURN 'tile_layout must be stacked or inline';
    END IF;
  END IF;

  IF p_block_type IN ('shopify_landing_ways_to_earn', 'shopify_landing_ways_to_spend') THEN
    v_cols := coalesce((p_config #>> '{grid,columns_desktop}')::int, 3);
    IF v_cols NOT IN (2, 3, 4) THEN
      RETURN 'grid.columns_desktop must be 2, 3, or 4';
    END IF;
  END IF;

  IF p_block_type = 'shopify_landing_how_it_works' THEN
    IF coalesce(p_config ->> 'steps_marker', 'icon') NOT IN ('icon', 'number') THEN
      RETURN 'steps_marker must be icon or number';
    END IF;
    v_steps := p_config -> 'steps';
    IF v_steps IS NULL OR jsonb_typeof(v_steps) <> 'array' OR jsonb_array_length(v_steps) <> 3 THEN
      RETURN 'how it works must have exactly 3 steps';
    END IF;
  END IF;

  IF p_block_type = 'shopify_landing_faq' THEN
    v_items := coalesce(p_config -> 'items', '[]'::jsonb);
    IF jsonb_typeof(v_items) <> 'array' OR jsonb_array_length(v_items) > 20 THEN
      RETURN 'FAQ items must be an array of at most 20';
    END IF;
  END IF;

  IF p_block_type = 'shopify_landing_referrals' THEN
    IF coalesce(p_config ->> 'layout', 'image_right') NOT IN ('image_left', 'image_right') THEN
      RETURN 'referrals layout must be image_left or image_right';
    END IF;
  END IF;

  RETURN NULL;
END;
$function$;

UPDATE public.display_block_template
SET config = config || '{"content_align":"center","side_image_position":"none","side_image_url":""}'::jsonb
WHERE block_type = 'shopify_landing_hero' AND block_style = 'default';

UPDATE public.display_block_template
SET config = config || '{"tile_layout":"stacked","steps_marker":"icon"}'::jsonb
WHERE block_type = 'shopify_landing_how_it_works' AND block_style = 'default';

UPDATE public.display_block_template
SET config = config || '{"tile_layout":"stacked","grid":{"columns_desktop":3}}'::jsonb
WHERE block_type = 'shopify_landing_ways_to_earn' AND block_style = 'default';

UPDATE public.display_block_template
SET config = config || '{"tile_layout":"stacked","grid":{"columns_desktop":3}}'::jsonb
WHERE block_type = 'shopify_landing_ways_to_spend' AND block_style = 'default';
