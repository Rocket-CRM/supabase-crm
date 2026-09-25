CREATE OR REPLACE FUNCTION public.bff_upsert_contract_with_levels(
  p_group_id uuid DEFAULT NULL::uuid,
  p_group_name text DEFAULT NULL::text,
  p_contract_type text DEFAULT NULL::text,
  p_company_name text DEFAULT NULL::text,
  p_contact_person text DEFAULT NULL::text,
  p_contact_email text DEFAULT NULL::text,
  p_contract_start date DEFAULT NULL::date,
  p_contract_end date DEFAULT NULL::date,
  p_contract_status text DEFAULT 'active'::text,
  p_active_status boolean DEFAULT true,
  p_levels jsonb DEFAULT '[]'::jsonb,
  p_language text DEFAULT 'en'::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  v_lang text;
  v_merchant_id uuid;
  v_group_id uuid;
  v_parent_created boolean := false;
  v_parent_updated boolean := false;
  v_levels_created integer := 0;
  v_levels_updated integer := 0;
  v_entitlements_created integer := 0;
  v_entitlements_updated integer := 0;
  v_entitlements_deleted integer := 0;
  v_level jsonb;
  v_persona jsonb;
  v_persona_id uuid;
  v_keep_persona_ids uuid[] := ARRAY[]::uuid[];
  v_entitlement jsonb;
  v_ent_id uuid;
  v_keep_ent_ids uuid[] := ARRAY[]::uuid[];
BEGIN
  v_lang := fn_normalize_ui_language(p_language);
  v_merchant_id := get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'title', fn_admin_envelope_message('no_merchant_title', v_lang), 'description', null, 'data', null);
  END IF;

  IF p_group_id IS NULL THEN
    v_group_id := gen_random_uuid();
    INSERT INTO persona_group_master (id, merchant_id, group_name, contract_type, company_name, contact_person, contact_email, contract_start, contract_end, contract_status, active_status)
    VALUES (v_group_id, v_merchant_id, p_group_name, p_contract_type, p_company_name, p_contact_person, p_contact_email, p_contract_start, p_contract_end, p_contract_status, p_active_status);
    v_parent_created := true;
  ELSE
    v_group_id := p_group_id;
    UPDATE persona_group_master
    SET group_name = COALESCE(p_group_name, group_name),
        contract_type = COALESCE(p_contract_type, contract_type),
        company_name = p_company_name,
        contact_person = p_contact_person,
        contact_email = p_contact_email,
        contract_start = p_contract_start,
        contract_end = p_contract_end,
        contract_status = COALESCE(p_contract_status, contract_status),
        active_status = COALESCE(p_active_status, active_status),
        updated_at = now()
    WHERE id = v_group_id AND merchant_id = v_merchant_id;
    IF NOT FOUND THEN
      RETURN jsonb_build_object('success', false, 'title', fn_admin_envelope_message('contract_group_not_found_title', v_lang), 'description', null, 'data', null);
    END IF;
    v_parent_updated := true;
  END IF;

  FOR v_level IN SELECT * FROM jsonb_array_elements(p_levels)
  LOOP
    v_persona := v_level->'persona';
    v_persona_id := (v_persona->>'id')::uuid;

    IF v_persona_id IS NOT NULL THEN
      UPDATE persona_master
      SET persona_name = COALESCE(v_persona->>'persona_name', persona_name),
          active_status = COALESCE((v_persona->>'active_status')::boolean, active_status),
          updated_at = now()
      WHERE id = v_persona_id AND group_id = v_group_id AND merchant_id = v_merchant_id;
      IF FOUND THEN
        v_keep_persona_ids := array_append(v_keep_persona_ids, v_persona_id);
        v_levels_updated := v_levels_updated + 1;
      ELSE
        CONTINUE;
      END IF;
    ELSE
      v_persona_id := gen_random_uuid();
      INSERT INTO persona_master (id, merchant_id, group_id, persona_name, active_status)
      VALUES (v_persona_id, v_merchant_id, v_group_id, v_persona->>'persona_name', COALESCE((v_persona->>'active_status')::boolean, true));
      v_keep_persona_ids := array_append(v_keep_persona_ids, v_persona_id);
      v_levels_created := v_levels_created + 1;
    END IF;

    v_keep_ent_ids := ARRAY[]::uuid[];
    FOR v_entitlement IN SELECT * FROM jsonb_array_elements(COALESCE(v_level->'entitlements', '[]'::jsonb))
    LOOP
      v_ent_id := (v_entitlement->>'id')::uuid;

      IF v_ent_id IS NOT NULL THEN
        UPDATE persona_entitlement
        SET entitlement_type = COALESCE(v_entitlement->>'entitlement_type', entitlement_type),
            package_id = (v_entitlement->>'package_id')::uuid,
            reward_id = (v_entitlement->>'reward_id')::uuid,
            qty = (v_entitlement->>'qty')::integer,
            category = v_entitlement->>'category',
            benefit_type = v_entitlement->>'benefit_type',
            value = (v_entitlement->>'value')::numeric,
            active_status = COALESCE((v_entitlement->>'active_status')::boolean, active_status),
            ranking = COALESCE((v_entitlement->>'ranking')::smallint, ranking)
        WHERE id = v_ent_id AND persona_id = v_persona_id AND merchant_id = v_merchant_id;
        IF FOUND THEN
          v_keep_ent_ids := array_append(v_keep_ent_ids, v_ent_id);
          v_entitlements_updated := v_entitlements_updated + 1;
        END IF;
      ELSE
        v_ent_id := gen_random_uuid();
        INSERT INTO persona_entitlement (id, merchant_id, persona_id, entitlement_type, package_id, reward_id, qty, category, benefit_type, value, active_status, ranking)
        VALUES (
          v_ent_id, v_merchant_id, v_persona_id,
          v_entitlement->>'entitlement_type',
          (v_entitlement->>'package_id')::uuid,
          (v_entitlement->>'reward_id')::uuid,
          (v_entitlement->>'qty')::integer,
          v_entitlement->>'category',
          v_entitlement->>'benefit_type',
          (v_entitlement->>'value')::numeric,
          COALESCE((v_entitlement->>'active_status')::boolean, true),
          COALESCE((v_entitlement->>'ranking')::smallint, 0)
        );
        v_keep_ent_ids := array_append(v_keep_ent_ids, v_ent_id);
        v_entitlements_created := v_entitlements_created + 1;
      END IF;
    END LOOP;

    WITH deleted AS (
      DELETE FROM persona_entitlement
      WHERE persona_id = v_persona_id AND merchant_id = v_merchant_id
        AND (array_length(v_keep_ent_ids, 1) IS NULL OR id != ALL(v_keep_ent_ids))
      RETURNING id
    )
    SELECT count(*) INTO v_entitlements_deleted FROM deleted;

  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'title', CASE WHEN v_parent_created
      THEN fn_admin_envelope_message('contract_created_title', v_lang)
      ELSE fn_admin_envelope_message('contract_updated_title', v_lang) END,
    'description', null,
    'data', jsonb_build_object(
      'group_id', v_group_id,
      'parent_created', v_parent_created,
      'parent_updated', v_parent_updated,
      'levels_created', v_levels_created,
      'levels_updated', v_levels_updated,
      'entitlements_created', v_entitlements_created,
      'entitlements_updated', v_entitlements_updated,
      'entitlements_deleted', v_entitlements_deleted
    )
  );
END;
$function$;

DROP FUNCTION IF EXISTS public.bff_upsert_contract_with_levels(uuid, text, text, text, text, text, date, date, text, boolean, jsonb);
