-- Allow product_highlight and nav items to bind collection, vendor, or taxonomy_category.

CREATE OR REPLACE FUNCTION public.fn_validate_store_config(p_config jsonb)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
AS $function$
DECLARE
  v_errors jsonb := '[]'::jsonb;
  v_blocks jsonb;
  v_block jsonb;
  v_idx int;
  v_type text;
  v_style text;
  v_slides jsonb;
  v_slide jsonb;
  v_items jsonb;
  v_item jsonb;
  v_j int;
  v_source_type text;
  v_handle text;
  v_limit int;
  v_first_enabled_type text;
  v_first_enabled_order int;
  c_types constant text[] := ARRAY['banner','nav','product_highlight'];
  c_nav_styles constant text[] := ARRAY['card','circle'];
  c_sources constant text[] := ARRAY['collection','vendor','taxonomy_category'];
BEGIN
  IF p_config IS NULL OR jsonb_typeof(p_config) <> 'object' THEN
    RETURN jsonb_build_object('ok', false, 'errors', jsonb_build_array(
      jsonb_build_object('path','config','code','REQUIRED','message','config must be an object')
    ));
  END IF;

  v_blocks := p_config -> 'homepage_blocks';
  IF v_blocks IS NULL OR jsonb_typeof(v_blocks) <> 'array' THEN
    RETURN jsonb_build_object('ok', false, 'errors', jsonb_build_array(
      jsonb_build_object('path','homepage_blocks','code','REQUIRED','message','homepage_blocks must be an array')
    ));
  END IF;

  v_first_enabled_order := NULL;
  FOR v_idx IN 0..coalesce(jsonb_array_length(v_blocks), 0)-1 LOOP
    v_block := v_blocks -> v_idx;
    v_type := v_block ->> 'type';
    IF v_type IS NULL OR NOT (v_type = ANY(c_types)) THEN
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'path', 'homepage_blocks['||v_idx||'].type',
        'code', 'INVALID_ENUM',
        'message', 'must be banner, nav, or product_highlight'
      ));
    END IF;

    IF coalesce((v_block ->> 'enabled')::boolean, false) THEN
      IF v_first_enabled_order IS NULL
         OR coalesce((v_block ->> 'order')::int, v_idx) < v_first_enabled_order THEN
        v_first_enabled_order := coalesce((v_block ->> 'order')::int, v_idx);
        v_first_enabled_type := v_type;
      END IF;
    END IF;

    IF v_type = 'banner' THEN
      v_slides := v_block -> 'slides';
      IF v_slides IS NOT NULL AND jsonb_typeof(v_slides) = 'array' THEN
        IF jsonb_array_length(v_slides) > 10 THEN
          v_errors := v_errors || jsonb_build_array(jsonb_build_object(
            'path', 'homepage_blocks['||v_idx||'].slides',
            'code', 'OUT_OF_RANGE',
            'message', 'at most 10 slides'
          ));
        END IF;
        FOR v_j IN 0..coalesce(jsonb_array_length(v_slides), 0)-1 LOOP
          v_slide := v_slides -> v_j;
          IF coalesce(v_slide ->> 'image_url', '') = '' THEN
            v_errors := v_errors || jsonb_build_array(jsonb_build_object(
              'path', 'homepage_blocks['||v_idx||'].slides['||v_j||'].image_url',
              'code', 'REQUIRED',
              'message', 'image_url is required'
            ));
          END IF;
        END LOOP;
      END IF;
    ELSIF v_type = 'nav' THEN
      v_style := v_block ->> 'style';
      IF v_style IS NOT NULL AND NOT (v_style = ANY(c_nav_styles)) THEN
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'path', 'homepage_blocks['||v_idx||'].style',
          'code', 'INVALID_ENUM',
          'message', 'must be card or circle'
        ));
      END IF;
      v_items := v_block -> 'items';
      IF v_items IS NOT NULL AND jsonb_typeof(v_items) = 'array' THEN
        FOR v_j IN 0..coalesce(jsonb_array_length(v_items), 0)-1 LOOP
          v_item := v_items -> v_j;
          v_source_type := coalesce(v_item ->> 'source_type', 'collection');
          IF v_source_type IS NULL OR NOT (v_source_type = ANY(c_sources)) THEN
            v_errors := v_errors || jsonb_build_array(jsonb_build_object(
              'path', 'homepage_blocks['||v_idx||'].items['||v_j||'].source_type',
              'code', 'INVALID_ENUM',
              'message', 'must be collection, vendor, or taxonomy_category'
            ));
          END IF;
          v_handle := coalesce(v_item ->> 'handle', '');
          IF v_handle = '' THEN
            v_errors := v_errors || jsonb_build_array(jsonb_build_object(
              'path', 'homepage_blocks['||v_idx||'].items['||v_j||'].handle',
              'code', 'REQUIRED',
              'message', 'handle is required'
            ));
          END IF;
        END LOOP;
      END IF;
    ELSIF v_type = 'product_highlight' THEN
      v_source_type := coalesce(v_block #>> '{source,type}', 'collection');
      IF v_source_type IS NULL OR NOT (v_source_type = ANY(c_sources)) THEN
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'path', 'homepage_blocks['||v_idx||'].source.type',
          'code', 'INVALID_ENUM',
          'message', 'must be collection, vendor, or taxonomy_category'
        ));
      END IF;
      v_handle := coalesce(v_block #>> '{source,handle}', '');
      IF v_handle = '' THEN
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'path', 'homepage_blocks['||v_idx||'].source.handle',
          'code', 'REQUIRED',
          'message', 'handle is required'
        ));
      END IF;
      IF (v_block ->> 'limit') IS NOT NULL AND (v_block ->> 'limit') ~ '^[0-9]+$' THEN
        v_limit := (v_block ->> 'limit')::int;
        IF v_limit < 1 OR v_limit > 24 THEN
          v_errors := v_errors || jsonb_build_array(jsonb_build_object(
            'path', 'homepage_blocks['||v_idx||'].limit',
            'code', 'OUT_OF_RANGE',
            'message', 'limit must be 1..24'
          ));
        END IF;
      END IF;
    END IF;
  END LOOP;

  IF v_first_enabled_type IS NOT NULL AND v_first_enabled_type <> 'banner' THEN
    v_errors := v_errors || jsonb_build_array(jsonb_build_object(
      'path', 'homepage_blocks',
      'code', 'BANNER_FIRST',
      'message', 'the first enabled block must be a banner'
    ));
  END IF;

  IF jsonb_array_length(v_errors) > 0 THEN
    RETURN jsonb_build_object('ok', false, 'errors', v_errors);
  END IF;
  RETURN jsonb_build_object('ok', true, 'errors', '[]'::jsonb);
END;
$function$;
