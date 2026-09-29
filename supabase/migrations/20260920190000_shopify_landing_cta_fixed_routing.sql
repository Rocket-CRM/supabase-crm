-- Shopify landing: fixed CTA routing + heading_hex validation + primary swatch.
--
-- Section buttons are no longer routable by merchants. The storefront routes every
-- section CTA by section + audience (guest -> log in / sign up, member -> the drawer
-- page for that section's feature). Merchants keep show / text / button_style.
-- Consequences:
--   * section CTA objects drop link_type / page / url / url_param (stripped on save)
--   * page config drops cta_defaults (stripped on save; readers ignore it)
--   * validator: surface.swatch accepts 'primary' (admin has sent it since
--     20260920100900; brand/extra remain accepted as pre-upgrade input) and
--     heading_hex is validated like text_hex.

-- 1. Section CTA defaults: label / visibility / style only.
CREATE OR REPLACE FUNCTION public.fn_shopify_landing_default_cta(p_text text, p_show boolean DEFAULT true)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT jsonb_build_object(
    'show', p_show,
    'text', p_text,
    'button_style', 'primary'
  );
$$;

-- 2. Section CTA upgrade: strip routing keys, normalise button_style.
CREATE OR REPLACE FUNCTION public.fn_shopify_landing_upgrade_section_cta(p_cta jsonb)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
  IF p_cta IS NULL OR jsonb_typeof(p_cta) <> 'object' THEN
    RETURN p_cta;
  END IF;
  RETURN (p_cta - 'link_type' - 'page' - 'url' - 'url_param')
    || jsonb_build_object(
      'button_style',
      public.fn_shopify_landing_upgrade_cta_button_style(p_cta ->> 'button_style')
    );
END;
$$;

-- 3. Section validator: allow 'primary' swatch, validate heading_hex.
CREATE OR REPLACE FUNCTION public.fn_validate_shopify_landing_section_config(p_block_type text, p_config jsonb)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_surface jsonb;
  v_swatch text;
  v_steps jsonb;
  v_items jsonb;
  v_style text;
  v_hex_key text;
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

  IF p_block_type = 'shopify_landing_how_it_works' THEN
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
$$;

-- 4. Page config: no cta_defaults.
CREATE OR REPLACE FUNCTION public.fn_shopify_landing_default_page_config()
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
AS $$
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
      'import', jsonb_build_object(
        'first_run_dismissed_at', NULL
      )
    )
  );
$$;

CREATE OR REPLACE FUNCTION public.fn_shopify_landing_upgrade_page_config(p_config jsonb)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_out jsonb;
  v_theme jsonb;
  v_buttons jsonb;
  v_on_light text;
  v_radius int;
  v_sec_width int;
BEGIN
  IF p_config IS NULL OR jsonb_typeof(p_config) <> 'object' THEN
    RETURN public.fn_shopify_landing_default_page_config();
  END IF;
  IF coalesce(p_config ->> '_schema_version', '1.0.0') >= '2.0.0' THEN
    RETURN p_config - 'cta_defaults';
  END IF;

  v_theme := coalesce(p_config -> 'theme', '{}'::jsonb);
  v_on_light := coalesce(v_theme ->> 'text_on_light', '#0D0D0D');
  v_radius := coalesce((v_theme -> 'buttons' -> 'primary' ->> 'radius_px')::int, 8);
  v_sec_width := coalesce((v_theme -> 'buttons' -> 'secondary' ->> 'border_width_px')::int, 1);

  v_buttons := jsonb_build_object(
    'primary', public.fn_shopify_landing_v2_upgrade_button_role(v_theme -> 'buttons' -> 'primary', NULL),
    'secondary', public.fn_shopify_landing_v2_upgrade_button_role(
      v_theme -> 'buttons' -> 'secondary',
      to_jsonb('transparent'::text)
    ),
    'radius_px', v_radius
  );
  v_buttons := jsonb_set(
    v_buttons,
    '{secondary,border_width_px}',
    to_jsonb(v_sec_width),
    true
  );

  v_out := (p_config - 'cta_defaults')
    || jsonb_build_object(
      '_schema_version', '2.0.0',
      'theme', jsonb_build_object(
        'palette', jsonb_build_object(
          'background', coalesce(v_theme ->> 'secondary_color', '#FFFFFF'),
          'heading', v_on_light,
          'text', v_on_light,
          'link', v_on_light,
          'link_hover', v_on_light,
          'border', NULL,
          'shadow', NULL,
          'dark_surface', '#1C1C1C',
          'extra', NULL
        ),
        'buttons', v_buttons,
        'section_padding_px', coalesce((v_theme ->> 'section_padding_px')::int, 88),
        'import', jsonb_build_object(
          'first_run_dismissed_at', NULL,
          'imported_from', NULL
        )
      )
    );

  v_out := v_out #- '{theme,secondary_color}'
               #- '{theme,accent_color}'
               #- '{theme,text_on_dark}'
               #- '{theme,text_on_light}'
               #- '{theme,typography}';
  RETURN v_out;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_validate_shopify_landing_page_config(p_config jsonb)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_slug text;
  v_theme jsonb;
  v_pad int;
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

  RETURN NULL;
END;
$$;
