-- cache_purge_triggers_v1 — unified invalidation → loyalty-cache-api POST /v1/purge
-- See docs/LOYALTY_CACHE_REDIS_AT_RENDER_PLAN.md

CREATE OR REPLACE FUNCTION public.fn_cache_purge_emit(p_merchant_id uuid, p_scopes text[])
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions, net, vault
AS $$
DECLARE
  v_sent   text := COALESCE(current_setting('cache_purge.sent', true), '');
  v_scope  text;
  v_tag    text;
  v_new    text[] := '{}';
  v_code   text;
  v_url    text;
  v_secret text;
BEGIN
  IF p_scopes IS NULL OR array_length(p_scopes, 1) IS NULL THEN RETURN; END IF;

  FOREACH v_scope IN ARRAY p_scopes LOOP
    v_tag := COALESCE(p_merchant_id::text, 'global') || ':' || v_scope;
    IF position(',' || v_tag || ',' IN ',' || v_sent || ',') = 0 THEN
      v_new  := v_new || v_scope;
      v_sent := CASE WHEN v_sent = '' THEN v_tag ELSE v_sent || ',' || v_tag END;
    END IF;
  END LOOP;
  IF array_length(v_new, 1) IS NULL THEN RETURN; END IF;
  PERFORM set_config('cache_purge.sent', v_sent, true);

  IF p_merchant_id IS NOT NULL THEN
    SELECT merchant_code INTO v_code FROM public.merchant_master WHERE id = p_merchant_id;
    IF v_code IS NULL THEN RETURN; END IF;
  END IF;

  SELECT decrypted_secret INTO v_url    FROM vault.decrypted_secrets WHERE name = 'loyalty_cache_purge_url'    LIMIT 1;
  SELECT decrypted_secret INTO v_secret FROM vault.decrypted_secrets WHERE name = 'loyalty_cache_purge_secret' LIMIT 1;
  IF v_url IS NULL OR v_secret IS NULL THEN
    RAISE WARNING 'fn_cache_purge_emit: vault secrets missing'; RETURN;
  END IF;

  PERFORM net.http_post(
    url                  := v_url,
    body                 := jsonb_build_object('merchant_code', v_code, 'scopes', to_jsonb(v_new)),
    params               := '{}'::jsonb,
    headers              := jsonb_build_object('Content-Type', 'application/json', 'x-purge-secret', v_secret),
    timeout_milliseconds := 5000
  );
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'fn_cache_purge_emit failed: %', SQLERRM;
END;
$$;

CREATE OR REPLACE FUNCTION public.trigger_cache_purge()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_scopes text[] := string_to_array(TG_ARGV[0], ',');
  v_col    text   := COALESCE(TG_ARGV[1], 'merchant_id');
  v_new_id uuid;
  v_old_id uuid;
BEGIN
  IF TG_OP IN ('INSERT', 'UPDATE') THEN v_new_id := (to_jsonb(NEW) ->> v_col)::uuid; END IF;
  IF TG_OP IN ('UPDATE', 'DELETE') THEN v_old_id := (to_jsonb(OLD) ->> v_col)::uuid; END IF;
  IF v_new_id IS NOT NULL THEN PERFORM public.fn_cache_purge_emit(v_new_id, v_scopes); END IF;
  IF v_old_id IS NOT NULL AND v_old_id IS DISTINCT FROM v_new_id THEN
    PERFORM public.fn_cache_purge_emit(v_old_id, v_scopes);
  END IF;
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.trigger_cache_purge_translations()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_type text;
  v_mid  uuid;
  v_scopes text[];
BEGIN
  IF TG_OP = 'DELETE' THEN v_type := OLD.entity_type; v_mid := OLD.merchant_id;
  ELSE                     v_type := NEW.entity_type; v_mid := NEW.merchant_id; END IF;

  v_scopes := CASE v_type
    WHEN 'reward'             THEN ARRAY['rewards', 'shopify_landing']
    WHEN 'reward_category'    THEN ARRAY['rewards']
    WHEN 'display_block_item' THEN ARRAY['display_blocks', 'bootstrap', 'language_pack', 'shopify_landing']
    WHEN 'earn_channel'       THEN ARRAY['earn_channels']
    WHEN 'consent_version'    THEN ARRAY['consent', 'store_home']
    ELSE NULL END;
  IF v_scopes IS NULL OR v_mid IS NULL THEN RETURN NULL; END IF;
  PERFORM public.fn_cache_purge_emit(v_mid, v_scopes);
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.trigger_cache_purge_global()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.fn_cache_purge_emit(NULL, string_to_array(TG_ARGV[0], ','));
  RETURN NULL;
END;
$$;

-- Per-table purge triggers (deferred to commit)
CREATE CONSTRAINT TRIGGER trg_cache_purge_reward_master
  AFTER INSERT OR UPDATE OR DELETE ON public.reward_master
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION public.trigger_cache_purge('rewards,shopify_landing');

CREATE CONSTRAINT TRIGGER trg_cache_purge_reward_category
  AFTER INSERT OR UPDATE OR DELETE ON public.reward_category
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION public.trigger_cache_purge('rewards');

CREATE CONSTRAINT TRIGGER trg_cache_purge_reward_group
  AFTER INSERT OR UPDATE OR DELETE ON public.reward_group
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION public.trigger_cache_purge('rewards');

CREATE CONSTRAINT TRIGGER trg_cache_purge_reward_group_member
  AFTER INSERT OR UPDATE OR DELETE ON public.reward_group_member
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION public.trigger_cache_purge('rewards');

CREATE CONSTRAINT TRIGGER trg_cache_purge_transaction_limits
  AFTER INSERT OR UPDATE OR DELETE ON public.transaction_limits
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION public.trigger_cache_purge('rewards');

CREATE CONSTRAINT TRIGGER trg_cache_purge_translations
  AFTER INSERT OR UPDATE OR DELETE ON public.translations
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION public.trigger_cache_purge_translations();

CREATE CONSTRAINT TRIGGER trg_cache_purge_earn_channel
  AFTER INSERT OR UPDATE OR DELETE ON public.earn_channel
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION public.trigger_cache_purge('earn_channels');

CREATE CONSTRAINT TRIGGER trg_cache_purge_checkin
  AFTER INSERT OR UPDATE OR DELETE ON public.checkin
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION public.trigger_cache_purge('earn_channels');

CREATE CONSTRAINT TRIGGER trg_cache_purge_feature_config
  AFTER INSERT OR UPDATE OR DELETE ON public.feature_config
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION public.trigger_cache_purge('earn_channels');

CREATE CONSTRAINT TRIGGER trg_cache_purge_form_templates
  AFTER INSERT OR UPDATE OR DELETE ON public.form_templates
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION public.trigger_cache_purge('earn_channels');

CREATE CONSTRAINT TRIGGER trg_cache_purge_merchant_credentials
  AFTER INSERT OR UPDATE OR DELETE ON public.merchant_credentials
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION public.trigger_cache_purge('earn_channels');

CREATE CONSTRAINT TRIGGER trg_cache_purge_mission
  AFTER INSERT OR UPDATE OR DELETE ON public.mission
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION public.trigger_cache_purge('earn_channels');

CREATE CONSTRAINT TRIGGER trg_cache_purge_workflow_master
  AFTER INSERT OR UPDATE OR DELETE ON public.workflow_master
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION public.trigger_cache_purge('earn_channels');

CREATE CONSTRAINT TRIGGER trg_cache_purge_workflow_node
  AFTER INSERT OR UPDATE OR DELETE ON public.workflow_node
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION public.trigger_cache_purge('earn_channels');

CREATE CONSTRAINT TRIGGER trg_cache_purge_workflow_trigger
  AFTER INSERT OR UPDATE OR DELETE ON public.workflow_trigger
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION public.trigger_cache_purge('earn_channels');

CREATE CONSTRAINT TRIGGER trg_cache_purge_display_settings
  AFTER INSERT OR UPDATE OR DELETE ON public.display_settings
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION public.trigger_cache_purge('display_blocks,bootstrap,language_pack,shopify_landing');

CREATE CONSTRAINT TRIGGER trg_cache_purge_merchant_display_settings
  AFTER INSERT OR UPDATE OR DELETE ON public.merchant_display_settings
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION public.trigger_cache_purge('bootstrap,earn_channels,widget,shopify_landing');

CREATE CONSTRAINT TRIGGER trg_cache_purge_ui_translations
  AFTER INSERT OR UPDATE OR DELETE ON public.ui_translations
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION public.trigger_cache_purge('bootstrap,language_pack');

CREATE CONSTRAINT TRIGGER trg_cache_purge_merchant_languages
  AFTER INSERT OR UPDATE OR DELETE ON public.merchant_languages
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION public.trigger_cache_purge('all');

CREATE CONSTRAINT TRIGGER trg_cache_purge_merchant_master
  AFTER INSERT OR UPDATE OR DELETE ON public.merchant_master
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION public.trigger_cache_purge('all', 'id');

CREATE CONSTRAINT TRIGGER trg_cache_purge_tier_master
  AFTER INSERT OR UPDATE OR DELETE ON public.tier_master
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION public.trigger_cache_purge('tier_display,widget');

CREATE CONSTRAINT TRIGGER trg_cache_purge_earn_factor
  AFTER INSERT OR UPDATE OR DELETE ON public.earn_factor
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION public.trigger_cache_purge('widget');

CREATE CONSTRAINT TRIGGER trg_cache_purge_consent_versions
  AFTER INSERT OR UPDATE OR DELETE ON public.consent_versions
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION public.trigger_cache_purge('consent,store_home');

CREATE CONSTRAINT TRIGGER trg_cache_purge_merchant_widget_settings
  AFTER INSERT OR UPDATE OR DELETE ON public.merchant_widget_settings
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION public.trigger_cache_purge('widget');

CREATE CONSTRAINT TRIGGER trg_cache_purge_merchant_shopify_landing_page_settings
  AFTER INSERT OR UPDATE OR DELETE ON public.merchant_shopify_landing_page_settings
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION public.trigger_cache_purge('shopify_landing');

CREATE CONSTRAINT TRIGGER trg_cache_purge_referral_program
  AFTER INSERT OR UPDATE OR DELETE ON public.referral_program
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION public.trigger_cache_purge('shopify_landing');

CREATE CONSTRAINT TRIGGER trg_cache_purge_merchant_store_settings
  AFTER INSERT OR UPDATE OR DELETE ON public.merchant_store_settings
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION public.trigger_cache_purge('store_home');

CREATE CONSTRAINT TRIGGER trg_cache_purge_merchant_store_overlays
  AFTER INSERT OR UPDATE OR DELETE ON public.merchant_store_overlays
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION public.trigger_cache_purge('store_home');

CREATE CONSTRAINT TRIGGER trg_cache_purge_earn_channel_registry
  AFTER INSERT OR UPDATE OR DELETE ON public.earn_channel_registry
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION public.trigger_cache_purge_global('earn_channels');

CREATE CONSTRAINT TRIGGER trg_cache_purge_display_block_template
  AFTER INSERT OR UPDATE OR DELETE ON public.display_block_template
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION public.trigger_cache_purge_global('display_blocks,bootstrap,language_pack,shopify_landing');

CREATE CONSTRAINT TRIGGER trg_cache_purge_widget_config_template
  AFTER INSERT OR UPDATE OR DELETE ON public.widget_config_template
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION public.trigger_cache_purge_global('widget');

CREATE CONSTRAINT TRIGGER trg_cache_purge_store_config_template
  AFTER INSERT OR UPDATE OR DELETE ON public.store_config_template
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION public.trigger_cache_purge_global('store_home');
