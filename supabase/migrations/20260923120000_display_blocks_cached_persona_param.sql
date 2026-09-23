-- Persona override for Render cache-api (guest pooler has no auth.uid()).
-- Drop 3-arg overload first — CREATE OR REPLACE would leave ambiguous PostgREST signatures.

DROP FUNCTION IF EXISTS public.api_get_display_blocks_cached(text, text, text);

CREATE OR REPLACE FUNCTION public.api_get_display_blocks_cached(
  p_page text DEFAULT NULL::text,
  p_language text DEFAULT NULL::text,
  p_merchant_code text DEFAULT NULL::text,
  p_persona_id text DEFAULT NULL::text
)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_merchant_id UUID;
  v_user_id UUID;
  v_user_persona_id TEXT;
  v_default_language TEXT;
  v_language TEXT;
  v_cache_key TEXT;
  v_cached_result TEXT;
  v_cached_data JSONB;
  v_blocks JSONB := '[]'::JSONB;
  v_translated_blocks JSONB;
  v_page_filter TEXT;
  r RECORD;
  v_enriched JSONB;
  v_err TEXT;
  v_block JSONB;
BEGIN
  v_user_id := auth.uid();

  IF p_merchant_code IS NOT NULL THEN
    SELECT id INTO v_merchant_id
    FROM merchant_master
    WHERE merchant_code = p_merchant_code;
  ELSE
    v_merchant_id := get_current_merchant_id();
  END IF;

  IF v_merchant_id IS NULL THEN
    RETURN json_build_object('error', 'No merchant context', 'data', '[]'::json);
  END IF;

  IF p_persona_id IS NOT NULL THEN
    v_user_persona_id := p_persona_id;
  ELSE
    SELECT persona_id::TEXT INTO v_user_persona_id
    FROM user_accounts WHERE id = v_user_id;
    v_user_persona_id := COALESCE(v_user_persona_id, 'guest');
  END IF;

  SELECT language_code INTO v_default_language
  FROM merchant_languages
  WHERE merchant_id = v_merchant_id AND is_default = true
  LIMIT 1;
  v_default_language := COALESCE(v_default_language, 'en');
  v_language := COALESCE(p_language, v_default_language);

  v_page_filter := COALESCE(p_page, 'all_pages');
  v_cache_key := 'merchant:' || v_merchant_id::TEXT ||
                 ':display_blocks:' || v_page_filter ||
                 ':persona:' || v_user_persona_id ||
                 ':all_languages';

  BEGIN
    v_cached_result := extensions.display_blocks_cache_get(v_cache_key);
    IF v_cached_result IS NOT NULL THEN
      v_cached_data := v_cached_result::JSONB;
      v_translated_blocks := fn_extract_display_block_translations(
        v_cached_data->'blocks', v_language, v_default_language
      );
      RETURN json_build_object(
        'data', fn_overlay_profile_card_user_values(v_translated_blocks, v_user_id, v_merchant_id),
        'cache_hit', true,
        'language', v_language,
        'default_language', v_default_language,
        'page', v_page_filter,
        'timestamp', NOW()
      );
    END IF;
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  FOR r IN
    SELECT ds.id, ds.block_type, ds.block_style, ds."order", ds.page,
           ds.active_status, ds.persona_ids,
           COALESCE(ds.config, dbt.config) AS cfg
    FROM display_settings ds
    LEFT JOIN display_block_template dbt
      ON dbt.block_type = ds.block_type
     AND dbt.block_style = ds.block_style
    WHERE ds.merchant_id = v_merchant_id
      AND (p_page IS NULL OR ds.page = p_page::display_page_type)
      AND ds.active_status = true
      AND (ds.persona_ids IS NULL OR ds.persona_ids = '{}' OR v_user_persona_id = ANY(ds.persona_ids))
    ORDER BY ds.page::text, ds."order"
  LOOP
    v_err := NULL;
    BEGIN
      v_enriched := fn_build_display_config_with_translations(r.id, r.cfg, v_merchant_id, v_default_language);
    EXCEPTION WHEN OTHERS THEN
      v_enriched := r.cfg;
      v_err := SQLSTATE || ': ' || SQLERRM;
    END;

    v_block := jsonb_build_object(
      'id', r.id,
      'block_type', r.block_type,
      'block_style', r.block_style,
      'order', r."order",
      'page', r.page,
      'active_status', r.active_status,
      'persona_ids', r.persona_ids,
      'config', v_enriched
    );
    IF v_err IS NOT NULL THEN
      v_block := v_block || jsonb_build_object('enrichment_error', v_err);
    END IF;
    v_blocks := v_blocks || jsonb_build_array(v_block);
  END LOOP;

  BEGIN
    PERFORM extensions.display_blocks_cache_set(
      v_cache_key,
      jsonb_build_object('blocks', v_blocks, 'default_language', v_default_language)::TEXT,
      300
    );
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  v_translated_blocks := fn_extract_display_block_translations(v_blocks, v_language, v_default_language);

  RETURN json_build_object(
    'data', fn_overlay_profile_card_user_values(v_translated_blocks, v_user_id, v_merchant_id),
    'cache_hit', false,
    'language', v_language,
    'default_language', v_default_language,
    'page', v_page_filter,
    'timestamp', NOW()
  );
END;
$function$;
