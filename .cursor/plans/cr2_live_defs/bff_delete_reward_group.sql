CREATE OR REPLACE FUNCTION public.bff_delete_reward_group(p_group_id uuid, p_language text DEFAULT 'en'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_lang text;
    v_merchant_id UUID;
    v_group_name TEXT;
    v_rewards_updated INT;
BEGIN
    v_lang := fn_normalize_ui_language(p_language);
    v_merchant_id := get_current_merchant_id();
    IF v_merchant_id IS NULL THEN
        RETURN fn_response_error(
          fn_admin_envelope_message('no_merchant_title', v_lang),
          'No merchant context found',
          'NO_MERCHANT_CONTEXT'
        );
    END IF;

    SELECT name INTO v_group_name
    FROM reward_group
    WHERE id = p_group_id AND merchant_id = v_merchant_id;

    IF v_group_name IS NULL THEN
        RETURN fn_response_error(
          fn_admin_envelope_message('not_found_title', v_lang),
          'Reward group not found or access denied',
          'NOT_FOUND'
        );
    END IF;

    UPDATE reward_master
    SET reward_group_ids = array_remove(reward_group_ids, p_group_id)
    WHERE merchant_id = v_merchant_id
      AND reward_group_ids @> ARRAY[p_group_id];
    GET DIAGNOSTICS v_rewards_updated = ROW_COUNT;

    DELETE FROM transaction_limits
    WHERE entity_id = p_group_id
      AND entity_type = 'reward_group'
      AND merchant_id = v_merchant_id;

    DELETE FROM reward_group
    WHERE id = p_group_id AND merchant_id = v_merchant_id;

    RETURN jsonb_build_object(
        'success', true,
        'code', 'DELETED',
        'title', fn_admin_envelope_message('reward_group_deleted_title', v_lang),
        'description', format('Reward group "%s" deleted. %s rewards updated.', v_group_name, v_rewards_updated),
        'rewards_updated', v_rewards_updated
    );

EXCEPTION WHEN OTHERS THEN
    RETURN fn_response_error(
      fn_admin_envelope_message('error_title', v_lang),
      SQLERRM,
      'ERROR'
    );
END;
$function$
