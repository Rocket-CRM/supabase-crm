-- Widget header colours derive from brand scheme (angle-only merchant input).
-- Landing sections: allow heading_hex alongside text_hex (body).

-- ---------------------------------------------------------------------------
-- Landing section config upgrade: heading_hex
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_shopify_landing_upgrade_section_config(p_block_type text, p_config jsonb)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
AS $function$
DECLARE
  v_out jsonb;
  v_surface jsonb;
  v_swatch text;
BEGIN
  IF p_config IS NULL OR jsonb_typeof(p_config) <> 'object' THEN
    RETURN public.fn_shopify_landing_default_section_config(p_block_type);
  END IF;

  IF p_config ? 'surface' AND NOT (p_config ? 'section_style') THEN
    v_out := p_config;
  ELSE
    v_surface := coalesce(
      p_config -> 'surface',
      public.fn_shopify_landing_section_style_to_surface(p_config ->> 'section_style')
    );
    v_out := (p_config - 'section_style')
      || jsonb_build_object(
        'surface', v_surface,
        'text_hex', coalesce(p_config -> 'text_hex', 'null'::jsonb),
        'heading_hex', coalesce(p_config -> 'heading_hex', 'null'::jsonb)
      );
    IF NOT (v_out ? 'text_hex') OR v_out -> 'text_hex' = 'null'::jsonb THEN
      v_out := jsonb_set(v_out, '{text_hex}', 'null'::jsonb, true);
    END IF;
    IF NOT (v_out ? 'heading_hex') OR v_out -> 'heading_hex' = 'null'::jsonb THEN
      v_out := jsonb_set(v_out, '{heading_hex}', 'null'::jsonb, true);
    END IF;
  END IF;

  v_swatch := v_out #>> '{surface,swatch}';
  IF v_swatch = 'brand' THEN
    v_out := jsonb_set(v_out, '{surface,swatch}', to_jsonb('primary'::text), true);
  ELSIF v_swatch = 'extra' THEN
    v_out := jsonb_set(v_out, '{surface,swatch}', to_jsonb('primary'::text), true);
  END IF;

  IF v_out ? 'guest' THEN
    v_out := jsonb_set(
      v_out,
      '{guest}',
      coalesce(v_out -> 'guest', '{}'::jsonb)
        || jsonb_build_object(
          'cta',
          public.fn_shopify_landing_upgrade_section_cta(v_out #> '{guest,cta}')
        ),
      true
    );
  END IF;
  IF v_out ? 'member' THEN
    v_out := jsonb_set(
      v_out,
      '{member}',
      coalesce(v_out -> 'member', '{}'::jsonb)
        || jsonb_build_object(
          'cta',
          public.fn_shopify_landing_upgrade_section_cta(v_out #> '{member,cta}')
        ),
      true
    );
  END IF;

  RETURN v_out;
END;
$function$;

-- ---------------------------------------------------------------------------
-- Widget config validation: header colours derive from brand scheme
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_validate_widget_config_core(p_widget_type text, p_config jsonb)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
AS $function$
DECLARE
  v_errors jsonb := '[]'::jsonb;
  v_mode text;
  v_bg_type text;
  v_brand_type text;
  v_items jsonb;
  v_item jsonb;
  v_idx int;
  v_carousel jsonb;
  v_angle int;
  c_mode constant text[] := ARRAY['light','dark'];
  c_bg_type constant text[] := ARRAY['solid','gradient','image'];
  c_coins_layout constant text[] := ARRAY['default','overlay','below'];
  c_brand_type constant text[] := ARRAY['text','image','none'];
  c_brand_pos constant text[] := ARRAY['left','center','right'];
  c_transition constant text[] := ARRAY['fade','slide'];
BEGIN
  IF p_widget_type IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'errors', jsonb_build_array(jsonb_build_object('path','widget_type','code','REQUIRED','message','widget_type is required')));
  END IF;

  IF p_config ? 'point' THEN
    v_errors := v_errors || jsonb_build_array(jsonb_build_object('path','point','code','DEPRECATED','message','point is sourced from merchant_display_settings.points_unit_label/points_symbol_*; do not include it here'));
  END IF;

  v_mode := p_config #>> '{theme,mode}';
  IF v_mode IS NOT NULL AND NOT (v_mode = ANY(c_mode)) THEN
    v_errors := v_errors || jsonb_build_array(jsonb_build_object('path','theme.mode','code','INVALID_ENUM','message','must be one of light, dark'));
  END IF;

  v_bg_type := p_config #>> '{header,background,type}';
  IF v_bg_type IS NOT NULL THEN
    IF NOT (v_bg_type = ANY(c_bg_type)) THEN
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('path','header.background.type','code','INVALID_ENUM','message','must be one of solid, gradient, image'));
    ELSIF v_bg_type = 'solid' THEN
      IF (p_config #>> '{header,background,solid,color}') IS NOT NULL
         AND (p_config #>> '{header,background,solid,color}') !~ '^#[0-9A-Fa-f]{6}$' THEN
        v_errors := v_errors || jsonb_build_array(jsonb_build_object('path','header.background.solid.color','code','INVALID_HEX','message','must be 6-digit hex or null'));
      END IF;
    ELSIF v_bg_type = 'gradient' THEN
      IF (p_config #>> '{header,background,gradient,from}') IS NOT NULL
         AND (p_config #>> '{header,background,gradient,from}') !~ '^#[0-9A-Fa-f]{6}$' THEN
        v_errors := v_errors || jsonb_build_array(jsonb_build_object('path','header.background.gradient.from','code','INVALID_HEX','message','must be 6-digit hex when set'));
      END IF;
      IF (p_config #>> '{header,background,gradient,to}') IS NOT NULL
         AND (p_config #>> '{header,background,gradient,to}') !~ '^#[0-9A-Fa-f]{6}$' THEN
        v_errors := v_errors || jsonb_build_array(jsonb_build_object('path','header.background.gradient.to','code','INVALID_HEX','message','must be 6-digit hex when set'));
      END IF;
      IF (p_config #>> '{header,background,gradient,angle}') IS NOT NULL
         AND (p_config #>> '{header,background,gradient,angle}') ~ '^[0-9]+$' THEN
        v_angle := (p_config #>> '{header,background,gradient,angle}')::int;
        IF v_angle NOT BETWEEN 0 AND 360 THEN
          v_errors := v_errors || jsonb_build_array(jsonb_build_object('path','header.background.gradient.angle','code','OUT_OF_RANGE','message','must be 0..360'));
        END IF;
      END IF;
    ELSIF v_bg_type = 'image' THEN
      v_items := p_config #> '{header,background,image,items}';
      IF v_items IS NULL OR jsonb_typeof(v_items) <> 'array' THEN
        v_errors := v_errors || jsonb_build_array(jsonb_build_object('path','header.background.image.items','code','REQUIRED','message','must be array'));
      ELSE
        IF jsonb_array_length(v_items) < 1 OR jsonb_array_length(v_items) > 10 THEN
          v_errors := v_errors || jsonb_build_array(jsonb_build_object('path','header.background.image.items','code','OUT_OF_RANGE','message','must contain 1 to 10 items'));
        END IF;
        FOR v_idx IN 0..jsonb_array_length(v_items)-1 LOOP
          v_item := v_items -> v_idx;
          IF coalesce(v_item ->> 'url','') = '' THEN
            v_errors := v_errors || jsonb_build_array(jsonb_build_object('path','header.background.image.items['||v_idx||'].url','code','REQUIRED','message','url is required'));
          END IF;
          IF coalesce(v_item ->> 'alt','') = '' THEN
            v_errors := v_errors || jsonb_build_array(jsonb_build_object('path','header.background.image.items['||v_idx||'].alt','code','REQUIRED','message','alt text is required'));
          END IF;
          IF (v_item ->> 'size_kb') IS NOT NULL AND (v_item ->> 'size_kb') ~ '^[0-9]+$' AND (v_item ->> 'size_kb')::int > 1024 THEN
            v_errors := v_errors || jsonb_build_array(jsonb_build_object('path','header.background.image.items['||v_idx||'].size_kb','code','OUT_OF_RANGE','message','size_kb must be <= 1024'));
          END IF;
        END LOOP;
        v_carousel := p_config #> '{header,background,image,carousel}';
        IF v_carousel IS NOT NULL THEN
          IF (v_carousel ->> 'interval_ms') IS NOT NULL AND (v_carousel ->> 'interval_ms') ~ '^[0-9]+$' THEN
            IF (v_carousel ->> 'interval_ms')::int NOT BETWEEN 1000 AND 30000 THEN
              v_errors := v_errors || jsonb_build_array(jsonb_build_object('path','header.background.image.carousel.interval_ms','code','OUT_OF_RANGE','message','must be 1000..30000'));
            END IF;
          END IF;
          IF (v_carousel ->> 'transition') IS NOT NULL AND NOT ((v_carousel ->> 'transition') = ANY(c_transition)) THEN
            v_errors := v_errors || jsonb_build_array(jsonb_build_object('path','header.background.image.carousel.transition','code','INVALID_ENUM','message','must be one of fade, slide'));
          END IF;
        END IF;
      END IF;
    END IF;
  END IF;

  IF (p_config #>> '{header,coins_layout}') IS NOT NULL AND NOT ((p_config #>> '{header,coins_layout}') = ANY(c_coins_layout)) THEN
    v_errors := v_errors || jsonb_build_array(jsonb_build_object('path','header.coins_layout','code','INVALID_ENUM','message','must be one of default, overlay, below'));
  END IF;

  v_brand_type := p_config #>> '{header,brand_mark,type}';
  IF v_brand_type IS NOT NULL THEN
    IF NOT (v_brand_type = ANY(c_brand_type)) THEN
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('path','header.brand_mark.type','code','INVALID_ENUM','message','must be one of text, image, none'));
    ELSIF v_brand_type = 'text' THEN
      IF char_length(coalesce(p_config #>> '{header,brand_mark,text}','')) NOT BETWEEN 1 AND 40 THEN
        v_errors := v_errors || jsonb_build_array(jsonb_build_object('path','header.brand_mark.text','code','OUT_OF_RANGE','message','text must be 1..40 chars'));
      END IF;
    ELSIF v_brand_type = 'image' THEN
      IF coalesce(p_config #>> '{header,brand_mark,image_url}','') = '' THEN
        v_errors := v_errors || jsonb_build_array(jsonb_build_object('path','header.brand_mark.image_url','code','REQUIRED','message','image_url required'));
      END IF;
    END IF;
    IF (p_config #>> '{header,brand_mark,position}') IS NOT NULL AND NOT ((p_config #>> '{header,brand_mark,position}') = ANY(c_brand_pos)) THEN
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('path','header.brand_mark.position','code','INVALID_ENUM','message','must be one of left, center, right'));
    END IF;
  END IF;

  IF jsonb_array_length(v_errors) > 0 THEN
    RETURN jsonb_build_object('ok', false, 'errors', v_errors);
  END IF;
  RETURN jsonb_build_object('ok', true, 'errors', '[]'::jsonb);
END;
$function$;

-- ---------------------------------------------------------------------------
-- Widget config: drop free header hex; bump schema tag
-- ---------------------------------------------------------------------------
UPDATE public.merchant_widget_settings m
SET config = jsonb_set(
      jsonb_set(
        m.config,
        '{header,background}',
        (
          (m.config #> '{header,background}')
          - 'solid'
          || jsonb_build_object(
            'solid', jsonb_build_object('color', null),
            'gradient',
            coalesce(m.config #> '{header,background,gradient}', '{}'::jsonb)
              - 'from'
              - 'to'
              || jsonb_build_object(
                'angle',
                coalesce(
                  (m.config #>> '{header,background,gradient,angle}')::int,
                  90
                )
              )
          )
        ),
        true
      ),
      '{_schema_version}',
      '"1.1.0"'::jsonb,
      true
    ),
    updated_at = now()
WHERE m.widget_type = 'shopify';

UPDATE public.widget_config_template t
SET config_default = jsonb_set(
      jsonb_set(
        t.config_default,
        '{header,background}',
        (
          (t.config_default #> '{header,background}')
          - 'solid'
          || jsonb_build_object(
            'solid', jsonb_build_object('color', null),
            'gradient',
            coalesce(t.config_default #> '{header,background,gradient}', '{}'::jsonb)
              - 'from'
              - 'to'
              || jsonb_build_object('angle', 90)
          )
        ),
        true
      ),
      '{_schema_version}',
      '"1.1.0"'::jsonb,
      true
    ),
    updated_at = now()
WHERE t.widget_type = 'shopify';

SELECT public.fn_invalidate_widget_settings_cache(merchant_id, 'shopify')
FROM public.merchant_widget_settings
WHERE widget_type = 'shopify';
