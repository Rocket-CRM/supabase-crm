-- Migration C — backup flat brand columns, drop legacy wrappers and columns.
-- Preconditions: Migration B live; no function reads MDS flat brand columns.

-- ---------------------------------------------------------------------------
-- Fix bff_get_user_history_menu (B patch missed combined SELECT form)
-- ---------------------------------------------------------------------------
DO $patch$
DECLARE
  v_def text;
  v_new text;
BEGIN
  SELECT pg_get_functiondef(oid) INTO v_def
  FROM pg_proc
  WHERE proname = 'bff_get_user_history_menu'
    AND pronamespace = 'public'::regnamespace;

  v_new := replace(
    v_def,
    E'SELECT mds.user_history_menu, mds.primary_color INTO v_menu_override, v_primary_color FROM merchant_display_settings mds WHERE mds.merchant_id = v_merchant_id;',
    E'SELECT mds.user_history_menu INTO v_menu_override FROM merchant_display_settings mds WHERE mds.merchant_id = v_merchant_id;' || E'\n  SELECT public.fn_brand_scheme_merged(v_merchant_id) #>> ''{tokens,primary}'' INTO v_primary_color;'
  );

  IF v_new <> v_def THEN
    EXECUTE v_new;
  END IF;
END;
$patch$;

-- ---------------------------------------------------------------------------
-- Backup flat columns (retain 30 days per plan)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.merchant_display_settings_brand_backup (
  merchant_id uuid NOT NULL,
  primary_color text,
  secondary_color text,
  border_radius_cards text,
  border_radius_buttons text,
  border_radius_inputs text,
  border_radius_modals text,
  border_radius_button_small text,
  backed_up_at timestamptz NOT NULL DEFAULT now()
);

TRUNCATE public.merchant_display_settings_brand_backup;

INSERT INTO public.merchant_display_settings_brand_backup (
  merchant_id,
  primary_color,
  secondary_color,
  border_radius_cards,
  border_radius_buttons,
  border_radius_inputs,
  border_radius_modals,
  border_radius_button_small,
  backed_up_at
)
SELECT
  mds.merchant_id,
  mds.primary_color,
  mds.secondary_color,
  mds.border_radius_cards,
  mds.border_radius_buttons,
  mds.border_radius_inputs,
  mds.border_radius_modals,
  mds.border_radius_button_small,
  now()
FROM public.merchant_display_settings mds;

-- ---------------------------------------------------------------------------
-- Drop legacy admin wrappers
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.admin_get_shopify_brand_scheme();
DROP FUNCTION IF EXISTS public.admin_upsert_shopify_brand_scheme(jsonb);

-- ---------------------------------------------------------------------------
-- Drop flat brand columns
-- ---------------------------------------------------------------------------
ALTER TABLE public.merchant_display_settings
  DROP COLUMN IF EXISTS primary_color,
  DROP COLUMN IF EXISTS secondary_color,
  DROP COLUMN IF EXISTS border_radius_cards,
  DROP COLUMN IF EXISTS border_radius_buttons,
  DROP COLUMN IF EXISTS border_radius_inputs,
  DROP COLUMN IF EXISTS border_radius_modals,
  DROP COLUMN IF EXISTS border_radius_button_small;

-- ---------------------------------------------------------------------------
-- Drop migration staging tables
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS public.tmp_brand_unification_snapshot;
DROP TABLE IF EXISTS public.tmp_brand_migration_inputs;
