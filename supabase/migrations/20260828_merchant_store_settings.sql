-- Online store display settings (headless /store homepage + chrome).
-- Sibling to merchant_widget_settings. Does not touch loyalty display_settings.

CREATE TABLE IF NOT EXISTS public.store_config_template (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  template_key text NOT NULL UNIQUE DEFAULT 'online_store',
  config_default jsonb NOT NULL,
  schema_version text NOT NULL DEFAULT '1.0.0',
  storage_bucket text NOT NULL DEFAULT 'images',
  storage_path_template text NOT NULL DEFAULT 'store/{merchant_id}/',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.merchant_store_settings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id uuid NOT NULL REFERENCES public.merchant_master(id) ON DELETE CASCADE,
  config jsonb NOT NULL DEFAULT '{}'::jsonb,
  active_status boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (merchant_id)
);

CREATE TABLE IF NOT EXISTS public.merchant_store_overlays (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id uuid NOT NULL REFERENCES public.merchant_master(id) ON DELETE CASCADE,
  source_type text NOT NULL,
  shopify_gid text,
  shopify_handle text NOT NULL,
  header text,
  description text,
  image_url text,
  icon_url text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT merchant_store_overlays_source_type_chk
    CHECK (source_type IN ('collection', 'vendor', 'taxonomy_category')),
  CONSTRAINT merchant_store_overlays_handle_chk
    CHECK (char_length(shopify_handle) BETWEEN 1 AND 255),
  UNIQUE (merchant_id, source_type, shopify_handle)
);

CREATE INDEX IF NOT EXISTS merchant_store_overlays_merchant_idx
  ON public.merchant_store_overlays (merchant_id);

ALTER TABLE public.store_config_template ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.merchant_store_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.merchant_store_overlays ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS store_config_template_read ON public.store_config_template;
CREATE POLICY store_config_template_read ON public.store_config_template
  FOR SELECT USING (true);

DROP POLICY IF EXISTS merchant_store_settings_isolation ON public.merchant_store_settings;
CREATE POLICY merchant_store_settings_isolation ON public.merchant_store_settings
  USING (merchant_id = public.get_current_merchant_id())
  WITH CHECK (merchant_id = public.get_current_merchant_id());

DROP POLICY IF EXISTS merchant_store_overlays_isolation ON public.merchant_store_overlays;
CREATE POLICY merchant_store_overlays_isolation ON public.merchant_store_overlays
  USING (merchant_id = public.get_current_merchant_id())
  WITH CHECK (merchant_id = public.get_current_merchant_id());

INSERT INTO public.store_config_template (
  template_key, schema_version, storage_bucket, storage_path_template, config_default
) VALUES (
  'online_store',
  '1.0.0',
  'images',
  'store/{merchant_id}/',
  '{
    "_schema_version": "1.0.0",
    "integrations": { "gtm_id": null, "chatwoot_id": null },
    "chrome": {
      "announcement_enabled": false,
      "announcement_text": "",
      "company_name_override": null,
      "privacy_consent_type": "privacy_policy"
    },
    "homepage_blocks": [
      {
        "id": "00000000-0000-0000-0000-000000000001",
        "type": "banner",
        "enabled": true,
        "order": 1,
        "slides": []
      }
    ]
  }'::jsonb
)
ON CONFLICT (template_key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.fn_store_config_default()
RETURNS jsonb
LANGUAGE sql
STABLE
AS $function$
  SELECT config_default FROM public.store_config_template WHERE template_key = 'online_store';
$function$;

CREATE OR REPLACE FUNCTION public.fn_store_config_with_defaults(p_config jsonb)
RETURNS jsonb
LANGUAGE sql
STABLE
AS $function$
  SELECT public.fn_store_config_default() || coalesce(p_config, '{}'::jsonb);
$function$;

CREATE OR REPLACE FUNCTION public.fn_resolve_store_storage(p_merchant_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $function$
DECLARE
  v_template public.store_config_template;
  v_merchant_code text;
  v_path text;
BEGIN
  SELECT * INTO v_template FROM public.store_config_template WHERE template_key = 'online_store';
  IF v_template.template_key IS NULL THEN
    RETURN NULL;
  END IF;
  SELECT merchant_code INTO v_merchant_code FROM public.merchant_master WHERE id = p_merchant_id;
  v_path := v_template.storage_path_template;
  v_path := replace(v_path, '{merchant_id}', coalesce(p_merchant_id::text, ''));
  v_path := replace(v_path, '{merchant_code}', coalesce(v_merchant_code, ''));
  RETURN jsonb_build_object(
    'bucket', v_template.storage_bucket,
    'path_prefix', v_path,
    'public', true,
    'max_file_size_kb', 1024,
    'allowed_mime_types', jsonb_build_array('image/jpeg','image/png','image/webp','image/svg+xml')
  );
END;
$function$;

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
          v_handle := coalesce(v_item ->> 'handle', '');
          IF v_handle = '' THEN
            v_errors := v_errors || jsonb_build_array(jsonb_build_object(
              'path', 'homepage_blocks['||v_idx||'].items['||v_j||'].handle',
              'code', 'REQUIRED',
              'message', 'collection handle is required'
            ));
          END IF;
        END LOOP;
      END IF;
    ELSIF v_type = 'product_highlight' THEN
      v_source_type := coalesce(v_block #>> '{source,type}', 'collection');
      IF v_source_type <> 'collection' THEN
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'path', 'homepage_blocks['||v_idx||'].source.type',
          'code', 'INVALID_ENUM',
          'message', 'v1 supports collection only'
        ));
      END IF;
      v_handle := coalesce(v_block #>> '{source,handle}', '');
      IF v_handle = '' THEN
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'path', 'homepage_blocks['||v_idx||'].source.handle',
          'code', 'REQUIRED',
          'message', 'collection handle is required'
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

CREATE OR REPLACE FUNCTION public.fn_invalidate_store_home_cache(p_merchant_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
BEGIN
  BEGIN
    PERFORM extensions.ui_cache_del('merchant:' || p_merchant_id::text || ':store_home');
    PERFORM extensions.ui_cache_del('merchant:' || p_merchant_id::text || ':store_legal');
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;
END;
$function$;

CREATE OR REPLACE FUNCTION public.trigger_validate_store_settings_config()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
  v_validation jsonb;
BEGIN
  v_validation := public.fn_validate_store_config(NEW.config);
  IF NOT (v_validation->>'ok')::boolean THEN
    RAISE EXCEPTION 'store config invalid: %', v_validation::text USING ERRCODE = '22P02';
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.trigger_invalidate_store_home_cache_on_settings()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
  PERFORM public.fn_invalidate_store_home_cache(COALESCE(NEW.merchant_id, OLD.merchant_id));
  RETURN COALESCE(NEW, OLD);
END;
$function$;

CREATE OR REPLACE FUNCTION public.trigger_invalidate_store_home_cache_on_overlays()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
  PERFORM public.fn_invalidate_store_home_cache(COALESCE(NEW.merchant_id, OLD.merchant_id));
  RETURN COALESCE(NEW, OLD);
END;
$function$;

CREATE OR REPLACE FUNCTION public.update_merchant_store_settings_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.update_merchant_store_overlays_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS merchant_store_settings_validate_config ON public.merchant_store_settings;
CREATE TRIGGER merchant_store_settings_validate_config
  BEFORE INSERT OR UPDATE OF config ON public.merchant_store_settings
  FOR EACH ROW EXECUTE FUNCTION public.trigger_validate_store_settings_config();

DROP TRIGGER IF EXISTS merchant_store_settings_set_updated_at ON public.merchant_store_settings;
CREATE TRIGGER merchant_store_settings_set_updated_at
  BEFORE UPDATE ON public.merchant_store_settings
  FOR EACH ROW EXECUTE FUNCTION public.update_merchant_store_settings_updated_at();

DROP TRIGGER IF EXISTS merchant_store_settings_invalidate_cache ON public.merchant_store_settings;
CREATE TRIGGER merchant_store_settings_invalidate_cache
  AFTER INSERT OR UPDATE OR DELETE ON public.merchant_store_settings
  FOR EACH ROW EXECUTE FUNCTION public.trigger_invalidate_store_home_cache_on_settings();

DROP TRIGGER IF EXISTS merchant_store_overlays_set_updated_at ON public.merchant_store_overlays;
CREATE TRIGGER merchant_store_overlays_set_updated_at
  BEFORE UPDATE ON public.merchant_store_overlays
  FOR EACH ROW EXECUTE FUNCTION public.update_merchant_store_overlays_updated_at();

DROP TRIGGER IF EXISTS merchant_store_overlays_invalidate_cache ON public.merchant_store_overlays;
CREATE TRIGGER merchant_store_overlays_invalidate_cache
  AFTER INSERT OR UPDATE OR DELETE ON public.merchant_store_overlays
  FOR EACH ROW EXECUTE FUNCTION public.trigger_invalidate_store_home_cache_on_overlays();

CREATE OR REPLACE FUNCTION public.fn_store_overlays_payload(p_merchant_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
AS $function$
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id', o.id,
    'source_type', o.source_type,
    'shopify_gid', o.shopify_gid,
    'shopify_handle', o.shopify_handle,
    'header', o.header,
    'description', o.description,
    'image_url', o.image_url,
    'icon_url', o.icon_url
  ) ORDER BY o.source_type, o.shopify_handle), '[]'::jsonb)
  FROM public.merchant_store_overlays o
  WHERE o.merchant_id = p_merchant_id;
$function$;

CREATE OR REPLACE FUNCTION public.admin_get_store_settings()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  v_merchant_id uuid;
  v_row public.merchant_store_settings;
  v_template public.store_config_template;
  v_config jsonb;
  v_existed boolean := false;
BEGIN
  v_merchant_id := public.get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN public.fn_response_error('Unauthorized','No merchant context','UNAUTHORIZED');
  END IF;

  SELECT * INTO v_template FROM public.store_config_template WHERE template_key = 'online_store';
  IF v_template.template_key IS NULL THEN
    RETURN public.fn_response_error('Not found','No online store template','NOT_FOUND');
  END IF;

  SELECT * INTO v_row FROM public.merchant_store_settings WHERE merchant_id = v_merchant_id;
  IF v_row.id IS NULL THEN
    v_config := v_template.config_default;
  ELSE
    v_existed := true;
    v_config := public.fn_store_config_with_defaults(v_row.config);
  END IF;

  RETURN public.fn_response_success(
    'OK',
    'Store settings loaded',
    jsonb_build_object(
      'schema_version', v_template.schema_version,
      'exists', v_existed,
      'id', v_row.id,
      'active_status', coalesce(v_row.active_status, true),
      'config', v_config,
      'overlays', public.fn_store_overlays_payload(v_merchant_id),
      'resolved', public.fn_resolve_widget_merchant_display(v_merchant_id),
      'storage', public.fn_resolve_store_storage(v_merchant_id),
      'updated_at', v_row.updated_at
    )
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_upsert_store_settings(p_config jsonb, p_active_status boolean DEFAULT true)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  v_merchant_id uuid;
  v_row public.merchant_store_settings;
  v_validation jsonb;
BEGIN
  v_merchant_id := public.get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN public.fn_response_error('Unauthorized','No merchant context','UNAUTHORIZED');
  END IF;

  v_validation := public.fn_validate_store_config(p_config);
  IF NOT (v_validation->>'ok')::boolean THEN
    RETURN public.fn_response_error(
      'Validation failed',
      'Store config has invalid fields',
      'VALIDATION',
      jsonb_build_object('errors', v_validation->'errors')
    );
  END IF;

  INSERT INTO public.merchant_store_settings (merchant_id, config, active_status)
  VALUES (v_merchant_id, coalesce(p_config, '{}'::jsonb), coalesce(p_active_status, true))
  ON CONFLICT (merchant_id) DO UPDATE SET
    config = EXCLUDED.config,
    active_status = EXCLUDED.active_status,
    updated_at = now()
  RETURNING * INTO v_row;

  RETURN public.fn_response_success(
    'Saved',
    'Store settings saved',
    jsonb_build_object(
      'id', v_row.id,
      'active_status', v_row.active_status,
      'config', v_row.config,
      'updated_at', v_row.updated_at
    )
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_list_store_overlays()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  v_merchant_id uuid;
BEGIN
  v_merchant_id := public.get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN public.fn_response_error('Unauthorized','No merchant context','UNAUTHORIZED');
  END IF;
  RETURN public.fn_response_success(
    'OK',
    'Overlays loaded',
    jsonb_build_object('overlays', public.fn_store_overlays_payload(v_merchant_id))
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_upsert_store_overlay(
  p_source_type text,
  p_shopify_handle text,
  p_shopify_gid text DEFAULT NULL,
  p_header text DEFAULT NULL,
  p_description text DEFAULT NULL,
  p_image_url text DEFAULT NULL,
  p_icon_url text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  v_merchant_id uuid;
  v_row public.merchant_store_overlays;
  v_handle text;
BEGIN
  v_merchant_id := public.get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN public.fn_response_error('Unauthorized','No merchant context','UNAUTHORIZED');
  END IF;
  IF p_source_type IS NULL OR p_source_type NOT IN ('collection','vendor','taxonomy_category') THEN
    RETURN public.fn_response_error('Validation failed','source_type must be collection, vendor, or taxonomy_category','VALIDATION');
  END IF;
  v_handle := lower(btrim(coalesce(p_shopify_handle, '')));
  IF v_handle = '' THEN
    RETURN public.fn_response_error('Validation failed','shopify_handle is required','VALIDATION');
  END IF;

  INSERT INTO public.merchant_store_overlays (
    merchant_id, source_type, shopify_handle, shopify_gid, header, description, image_url, icon_url
  ) VALUES (
    v_merchant_id, p_source_type, v_handle, nullif(p_shopify_gid, ''),
    nullif(p_header, ''), nullif(p_description, ''), nullif(p_image_url, ''), nullif(p_icon_url, '')
  )
  ON CONFLICT (merchant_id, source_type, shopify_handle) DO UPDATE SET
    shopify_gid = COALESCE(EXCLUDED.shopify_gid, public.merchant_store_overlays.shopify_gid),
    header = EXCLUDED.header,
    description = EXCLUDED.description,
    image_url = EXCLUDED.image_url,
    icon_url = EXCLUDED.icon_url,
    updated_at = now()
  RETURNING * INTO v_row;

  RETURN public.fn_response_success(
    'Saved',
    'Overlay saved',
    jsonb_build_object(
      'id', v_row.id,
      'source_type', v_row.source_type,
      'shopify_handle', v_row.shopify_handle,
      'shopify_gid', v_row.shopify_gid,
      'header', v_row.header,
      'description', v_row.description,
      'image_url', v_row.image_url,
      'icon_url', v_row.icon_url
    )
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_delete_store_overlay(p_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  v_merchant_id uuid;
  v_deleted int;
BEGIN
  v_merchant_id := public.get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN public.fn_response_error('Unauthorized','No merchant context','UNAUTHORIZED');
  END IF;
  DELETE FROM public.merchant_store_overlays
  WHERE id = p_id AND merchant_id = v_merchant_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  IF v_deleted = 0 THEN
    RETURN public.fn_response_error('Not found','Overlay not found','NOT_FOUND');
  END IF;
  RETURN public.fn_response_success('Deleted','Overlay deleted', jsonb_build_object('id', p_id));
END;
$function$;

CREATE OR REPLACE FUNCTION public.api_get_store_home_config_cached(p_merchant_code text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  v_merchant_id uuid;
  v_cache_key text;
  v_cached text;
  v_row public.merchant_store_settings;
  v_template public.store_config_template;
  v_config jsonb;
  v_payload jsonb;
BEGIN
  IF coalesce(p_merchant_code, '') = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'merchant_code required');
  END IF;
  SELECT id INTO v_merchant_id FROM public.merchant_master WHERE merchant_code = p_merchant_code;
  IF v_merchant_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'merchant not found');
  END IF;

  v_cache_key := 'merchant:' || v_merchant_id::text || ':store_home';
  BEGIN SELECT extensions.ui_cache_get(v_cache_key) INTO v_cached; EXCEPTION WHEN OTHERS THEN v_cached := NULL; END;
  IF v_cached IS NOT NULL THEN RETURN v_cached::jsonb; END IF;

  SELECT * INTO v_template FROM public.store_config_template WHERE template_key = 'online_store';
  IF v_template.template_key IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'unknown template');
  END IF;

  SELECT * INTO v_row FROM public.merchant_store_settings
  WHERE merchant_id = v_merchant_id AND active_status = true;

  IF v_row.id IS NULL THEN
    v_config := v_template.config_default;
  ELSE
    BEGIN
      v_config := public.fn_store_config_with_defaults(v_row.config);
    EXCEPTION WHEN OTHERS THEN
      v_config := v_template.config_default;
    END;
  END IF;

  v_payload := jsonb_build_object(
    'ok', true,
    'schema_version', v_template.schema_version,
    'config', v_config,
    'overlays', public.fn_store_overlays_payload(v_merchant_id),
    'resolved', public.fn_resolve_widget_merchant_display(v_merchant_id)
  );

  BEGIN PERFORM extensions.ui_cache_set(v_cache_key, v_payload::text, 'EX', 300); EXCEPTION WHEN OTHERS THEN NULL; END;
  RETURN v_payload;
END;
$function$;

CREATE OR REPLACE FUNCTION public.bff_get_store_home_config()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  v_merchant_id uuid;
  v_code text;
BEGIN
  v_merchant_id := public.get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'No merchant context');
  END IF;
  SELECT merchant_code INTO v_code FROM public.merchant_master WHERE id = v_merchant_id;
  RETURN public.api_get_store_home_config_cached(v_code);
END;
$function$;

CREATE OR REPLACE FUNCTION public.api_get_consent_documents_cached(
  p_merchant_code text,
  p_language text DEFAULT 'en'::text,
  p_consent_type text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  v_merchant_id uuid;
  v_cache_key text;
  v_cached text;
  v_items jsonb;
  v_payload jsonb;
BEGIN
  IF coalesce(p_merchant_code, '') = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'merchant_code required');
  END IF;
  SELECT id INTO v_merchant_id FROM public.merchant_master WHERE merchant_code = p_merchant_code;
  IF v_merchant_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'merchant not found');
  END IF;

  v_cache_key := 'merchant:' || v_merchant_id::text || ':store_legal:' || coalesce(p_language,'en') || ':' || coalesce(p_consent_type,'all');
  BEGIN SELECT extensions.ui_cache_get(v_cache_key) INTO v_cached; EXCEPTION WHEN OTHERS THEN v_cached := NULL; END;
  IF v_cached IS NOT NULL THEN RETURN v_cached::jsonb; END IF;

  SELECT coalesce(jsonb_agg(
    jsonb_build_object(
      'id', cv.id,
      'consent_type', cv.consent_type,
      'version_code', cv.version_code,
      'interaction_type', cv.interaction_type,
      'title', coalesce(
        (SELECT t.translated_value FROM translations t
         WHERE t.entity_type = 'consent_version' AND t.entity_id = cv.id
           AND t.field_name = 'title' AND t.language_code = p_language),
        cv.title
      ),
      'content', coalesce(
        (SELECT t.translated_value FROM translations t
         WHERE t.entity_type = 'consent_version' AND t.entity_id = cv.id
           AND t.field_name = 'content' AND t.language_code = p_language),
        cv.content
      ),
      'order_index', cv.order_index
    ) ORDER BY cv.order_index
  ), '[]'::jsonb) INTO v_items
  FROM consent_versions cv
  WHERE cv.merchant_id = v_merchant_id
    AND cv.active_status = true
    AND (p_consent_type IS NULL OR cv.consent_type = p_consent_type);

  v_payload := jsonb_build_object(
    'ok', true,
    'consent_items', v_items,
    'language', p_language
  );
  BEGIN PERFORM extensions.ui_cache_set(v_cache_key, v_payload::text, 'EX', 300); EXCEPTION WHEN OTHERS THEN NULL; END;
  RETURN v_payload;
END;
$function$;

GRANT SELECT ON public.store_config_template TO anon, authenticated, service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.merchant_store_settings TO authenticated, service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.merchant_store_overlays TO authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.fn_store_config_default() TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_store_config_with_defaults(jsonb) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_resolve_store_storage(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_validate_store_config(jsonb) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_invalidate_store_home_cache(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_store_overlays_payload(uuid) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_get_store_settings() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_upsert_store_settings(jsonb, boolean) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_list_store_overlays() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_upsert_store_overlay(text, text, text, text, text, text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_delete_store_overlay(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.api_get_store_home_config_cached(text) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.bff_get_store_home_config() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.api_get_consent_documents_cached(text, text, text) TO anon, authenticated, service_role;
