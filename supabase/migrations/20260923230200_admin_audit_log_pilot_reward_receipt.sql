-- Phase 4 pilot: reward upsert + receipt approve/reject (dynamic patch from live definitions).
-- Idempotent: skips when fn_log_admin_action is already present.

DO $$
DECLARE
  v_oid oid;
  def text;
BEGIN
  SELECT p.oid INTO v_oid
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'bff_upsert_reward_with_conditions_and_limits'
  ORDER BY pg_get_function_identity_arguments(p.oid) DESC
  LIMIT 1;

  def := pg_get_functiondef(v_oid);

  IF def NOT LIKE '%fn_log_admin_action%' THEN
    def := replace(def,
      'v_reward_group_ids UUID[];',
      'v_reward_group_ids UUID[]; v_before jsonb; v_after jsonb; v_payload jsonb;'
    );
    def := replace(def,
      E'    ELSE\n        v_reward_id := p_reward_id;',
      E'    ELSE\n        v_reward_id := p_reward_id;\n        SELECT to_jsonb(rm.*) INTO v_before FROM reward_master rm WHERE rm.id = v_reward_id AND rm.merchant_id = v_merchant_id;'
    );
    def := replace(def,
      E'    RETURN jsonb_build_object(\n        ''success'', true,',
      E'    SELECT to_jsonb(rm.*) INTO v_after FROM reward_master rm WHERE rm.id = v_reward_id;\n    v_payload := jsonb_strip_nulls(jsonb_build_object(''name'', p_name, ''reward_id'', v_reward_id));\n    PERFORM public.fn_log_admin_action(\n      CASE WHEN v_parent_created THEN ''reward.create'' ELSE ''reward.update'' END,\n      ''reward'', v_reward_id, v_payload, v_before, v_after, ''{}''::jsonb, NULL, ''bff_upsert_reward_with_conditions_and_limits''\n    );\n    RETURN jsonb_build_object(\n        ''success'', true,'
    );
    EXECUTE def;
  END IF;
END $$;

DO $$
DECLARE
  v_oid oid;
  def text;
BEGIN
  SELECT p.oid INTO v_oid
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'bff_approve_receipt_upload'
  LIMIT 1;

  def := pg_get_functiondef(v_oid);

  IF def NOT LIKE '%fn_log_admin_action%' THEN
    def := replace(def,
      'v_seller_id UUID;',
      'v_seller_id UUID; v_audit_payload jsonb;'
    );

    def := replace(def,
      E'    RETURN jsonb_build_object(\n      ''success'', true,\n      ''title'', fn_member_envelope_message(''receipt_rejected_title'', v_lang),',
      E'    v_audit_payload := jsonb_strip_nulls(jsonb_build_object(''receipt_upload_id'', p_receipt_upload_id, ''reject_reason'', p_reject_reason));\n    PERFORM public.fn_log_admin_action(''receipt.reject'', ''receipt'', p_receipt_upload_id, v_audit_payload, NULL, NULL, ''{}''::jsonb, p_reject_reason, ''bff_approve_receipt_upload'');\n    RETURN jsonb_build_object(\n      ''success'', true,\n      ''title'', fn_member_envelope_message(''receipt_rejected_title'', v_lang),'
    );

    def := replace(def,
      E'      RETURN jsonb_build_object(\n        ''success'', true,\n        ''title'', fn_member_envelope_message(''receipt_approved_title'', v_lang),\n        ''description'', ''Receipt approved for '' || COALESCE(v_user_name, ''user'') ||',
      E'      v_audit_payload := jsonb_strip_nulls(jsonb_build_object(''receipt_upload_id'', p_receipt_upload_id, ''user_id'', v_target_user_id, ''net_amount'', v_net_amount, ''store_id'', p_store_id, ''deferred_crm_confirm'', true));\n      PERFORM public.fn_log_admin_action(''receipt.approve'', ''receipt'', p_receipt_upload_id, v_audit_payload, NULL, NULL, jsonb_build_object(''deferred_crm'', true), p_notes, ''bff_approve_receipt_upload'');\n      RETURN jsonb_build_object(\n        ''success'', true,\n        ''title'', fn_member_envelope_message(''receipt_approved_title'', v_lang),\n        ''description'', ''Receipt approved for '' || COALESCE(v_user_name, ''user'') ||'
    );

    def := replace(def,
      E'    RETURN jsonb_build_object(\n      ''success'', true,\n      ''title'', fn_member_envelope_message(''receipt_approved_title'', v_lang),\n      ''description'', ''Purchase '' || v_resolved_transaction_number || '' created for '' || COALESCE(v_user_name, ''user'') ||',
      E'    v_audit_payload := jsonb_strip_nulls(jsonb_build_object(''receipt_upload_id'', p_receipt_upload_id, ''user_id'', v_target_user_id, ''net_amount'', v_net_amount, ''store_id'', p_store_id, ''purchase_id'', v_purchase_result->>''transaction_id''));\n    PERFORM public.fn_log_admin_action(''receipt.approve'', ''receipt'', p_receipt_upload_id, v_audit_payload, NULL, NULL, jsonb_build_object(''purchase_id'', (v_purchase_result->>''transaction_id'')::uuid), p_notes, ''bff_approve_receipt_upload'');\n    RETURN jsonb_build_object(\n      ''success'', true,\n      ''title'', fn_member_envelope_message(''receipt_approved_title'', v_lang),\n      ''description'', ''Purchase '' || v_resolved_transaction_number || '' created for '' || COALESCE(v_user_name, ''user'') ||'
    );

    EXECUTE def;
  END IF;
END $$;
