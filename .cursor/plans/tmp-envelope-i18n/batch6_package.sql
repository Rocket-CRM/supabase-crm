-- bff_upsert_package_with_items + drop old
CREATE OR REPLACE FUNCTION public.bff_upsert_package_with_items(
  p_id uuid DEFAULT NULL::uuid,
  p_name text DEFAULT NULL::text,
  p_description text DEFAULT NULL::text,
  p_validity_days integer DEFAULT NULL::integer,
  p_validity_date timestamp with time zone DEFAULT NULL::timestamp with time zone,
  p_price numeric DEFAULT NULL::numeric,
  p_points_price numeric DEFAULT NULL::numeric,
  p_image text[] DEFAULT NULL::text[],
  p_active_status boolean DEFAULT true,
  p_items jsonb DEFAULT '[]'::jsonb,
  p_language text DEFAULT 'en'::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  v_lang text;
  v_merchant_id uuid;
  v_package_id uuid;
  v_parent_created boolean := false;
  v_parent_updated boolean := false;
  v_children_created integer := 0;
  v_children_updated integer := 0;
  v_children_deleted integer := 0;
  v_children_skipped integer := 0;
  v_keep_ids uuid[] := ARRAY[]::uuid[];
  v_item jsonb;
  v_item_id uuid;
  v_reward_id uuid;
BEGIN
  v_lang := fn_normalize_ui_language(p_language);
  v_merchant_id := get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'title', fn_admin_envelope_message('no_merchant_title', v_lang), 'description', null, 'data', null);
  END IF;

  IF p_id IS NULL THEN
    v_package_id := gen_random_uuid();
    INSERT INTO package_master (id, merchant_id, name, description, image, validity_days, validity_date, price, points_price, active_status)
    VALUES (v_package_id, v_merchant_id, p_name, p_description, p_image, p_validity_days, p_validity_date, p_price, p_points_price, p_active_status);
    v_parent_created := true;
  ELSE
    v_package_id := p_id;
    UPDATE package_master
    SET name = COALESCE(p_name, name),
        description = COALESCE(p_description, description),
        image = COALESCE(p_image, image),
        validity_days = p_validity_days,
        validity_date = p_validity_date,
        price = p_price,
        points_price = p_points_price,
        active_status = COALESCE(p_active_status, active_status),
        updated_at = now()
    WHERE id = v_package_id AND merchant_id = v_merchant_id;
    IF NOT FOUND THEN
      RETURN jsonb_build_object('success', false, 'title', fn_admin_envelope_message('package_not_found_title', v_lang), 'description', null, 'data', null);
    END IF;
    v_parent_updated := true;
  END IF;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_item_id := (v_item->>'id')::uuid;
    v_reward_id := (v_item->>'reward_id')::uuid;

    IF v_reward_id IS NULL THEN
      v_children_skipped := v_children_skipped + 1;
      CONTINUE;
    END IF;

    IF v_item_id IS NOT NULL THEN
      UPDATE package_items
      SET reward_id = v_reward_id,
          qty = COALESCE((v_item->>'qty')::integer, qty),
          is_mandatory = COALESCE((v_item->>'is_mandatory')::boolean, is_mandatory),
          is_elective = COALESCE((v_item->>'is_elective')::boolean, is_elective),
          elective_group = v_item->>'elective_group',
          elective_max_picks = (v_item->>'elective_max_picks')::integer,
          ranking = COALESCE((v_item->>'ranking')::smallint, ranking)
      WHERE id = v_item_id AND package_id = v_package_id AND merchant_id = v_merchant_id;
      IF FOUND THEN
        v_keep_ids := array_append(v_keep_ids, v_item_id);
        v_children_updated := v_children_updated + 1;
      ELSE
        v_children_skipped := v_children_skipped + 1;
      END IF;
    ELSE
      v_item_id := gen_random_uuid();
      INSERT INTO package_items (id, merchant_id, package_id, reward_id, qty, is_mandatory, is_elective, elective_group, elective_max_picks, ranking)
      VALUES (
        v_item_id, v_merchant_id, v_package_id, v_reward_id,
        COALESCE((v_item->>'qty')::integer, 1),
        COALESCE((v_item->>'is_mandatory')::boolean, true),
        COALESCE((v_item->>'is_elective')::boolean, false),
        v_item->>'elective_group',
        (v_item->>'elective_max_picks')::integer,
        COALESCE((v_item->>'ranking')::smallint, 0)
      );
      v_keep_ids := array_append(v_keep_ids, v_item_id);
      v_children_created := v_children_created + 1;
    END IF;
  END LOOP;

  IF array_length(v_keep_ids, 1) IS NOT NULL THEN
    DELETE FROM package_items WHERE package_id = v_package_id AND merchant_id = v_merchant_id AND id != ALL(v_keep_ids);
  ELSE
    DELETE FROM package_items WHERE package_id = v_package_id AND merchant_id = v_merchant_id;
  END IF;
  GET DIAGNOSTICS v_children_deleted = ROW_COUNT;

  RETURN jsonb_build_object(
    'success', true,
    'title', CASE WHEN v_parent_created
      THEN fn_admin_envelope_message('package_created_title', v_lang)
      ELSE fn_admin_envelope_message('package_updated_title', v_lang) END,
    'description', null,
    'data', jsonb_build_object(
      'parent_id', v_package_id,
      'parent_created', v_parent_created,
      'parent_updated', v_parent_updated,
      'children_created', v_children_created,
      'children_updated', v_children_updated,
      'children_deleted', v_children_deleted,
      'children_skipped', v_children_skipped
    )
  );
END;
$function$;

DROP FUNCTION IF EXISTS public.bff_upsert_package_with_items(uuid, text, text, integer, timestamptz, numeric, numeric, text[], boolean, jsonb);
