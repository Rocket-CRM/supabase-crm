-- =============================================================================
-- Future Park street addresses were being erased by ordinary profile saves.
--
-- Why: `bff_save_user_profile` writes user_address with a full-replace upsert.
-- It fires whenever any address value is non-null, but the v_* values come only
-- from what the submitted form carried, so every address key the form did not
-- include arrives as NULL and is written over the stored value:
--
--   addressline_1 = EXCLUDED.addressline_1   -- NULL when not on the form
--   country_code  = EXCLUDED.country_code    -- NULL when not on the form
--
-- Future Park is the merchant that actually hits this: `user_field_config` has
-- addressline_1 and country_code inactive while city/district/subdistrict/
-- postcode are active AND required. `bff_get_user_profile_template` drops
-- inactive keys from the template, so the member form always submits the four
-- geo fields and never submits street or country. Every profile save therefore
-- fired the upsert and wrote NULL over both.
--
-- Confirmed live (2026-11-02): 502 Future Park rows with NULL addressline_1,
-- 503 with NULL country_code; the affected user_accounts.updated_at cluster in
-- 02:52–03:47, i.e. staff/member profile edits after cutover — not the address
-- migration, which had written the streets correctly.
--
-- Fix: guard each column on whether that key was actually submitted, the same
-- contract `bff_admin_update_member_profile` already uses for the admin surface:
--
--   city          = CASE WHEN 'city'          = ANY(v_submitted_default_keys) THEN EXCLUDED.city          ELSE user_address.city          END
--   ...
--   addressline_1 = CASE WHEN 'addressline_1' = ANY(v_submitted_default_keys) THEN EXCLUDED.addressline_1 ELSE user_address.addressline_1 END
--
-- A key absent from the form leaves the stored value untouched. A key present
-- with an empty value still clears it, so members can still delete a field they
-- were shown. New rows are unaffected: on insert every column writes v_* as
-- before, which is correct because there is nothing to preserve.
--
-- Merchant-agnostic on purpose: this is the RPC's save contract, so every
-- merchant with a partially-configured address block stops losing data, not
-- just Future Park. `user_field_config` is left alone — activating
-- addressline_1 there would make the street required on every member save.
--
-- Scope of change: this function body only. No schema, no RLS, no Edge redeploy.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.bff_save_user_profile(p_data jsonb, p_language text DEFAULT 'en'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_lang text;
    v_merchant_id UUID;
    v_auth_user_id UUID;
    v_user_id UUID;
    v_is_new_user BOOLEAN := false;
    v_user_profile_form_id UUID;
    v_submission_id UUID;

    v_email TEXT; v_tel TEXT; v_firstname TEXT; v_lastname TEXT; v_fullname TEXT;
    v_birth_date DATE; v_id_card TEXT; v_id_document_type TEXT; v_line_id TEXT; v_gender TEXT;
    v_external_user_id TEXT; v_user_stage TEXT; v_persona_id UUID;
    v_city TEXT; v_district TEXT; v_subdistrict TEXT; v_postcode TEXT;
    v_addressline_1 TEXT; v_country_code TEXT;
    v_channel_email BOOLEAN := false; v_channel_sms BOOLEAN := false;
    v_channel_line BOOLEAN := false; v_channel_push BOOLEAN := false;

    v_field JSONB; v_group JSONB; v_consent JSONB; v_option JSONB;
    v_field_key TEXT; v_field_value JSONB; v_field_id UUID;

    v_flat_data JSONB; v_validation_result JSONB; v_conflict_user_id UUID;
    v_submitted_default_keys TEXT[] := ARRAY[]::TEXT[];
    v_submitted_custom_keys TEXT[] := ARRAY[]::TEXT[];

    v_external_code_field RECORD;
    v_external_code_value TEXT;
    v_signup_code_parts TEXT[];
    v_acquisition_source TEXT;

    v_changes JSONB;
    v_row public.user_accounts;
BEGIN
    v_lang := fn_normalize_ui_language(p_language);
    v_merchant_id := get_current_merchant_id();
    IF v_merchant_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'title', fn_member_envelope_message('no_merchant_title', v_lang), 'description', null, 'data', null);
    END IF;

    v_auth_user_id := auth.uid();
    v_acquisition_source := NULLIF(TRIM(p_data->>'acquisition_source'), '');
    IF v_auth_user_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'title', fn_member_envelope_message('auth_required_title', v_lang), 'description', null, 'data', null);
    END IF;

    IF EXISTS (
      SELECT 1 FROM user_accounts
      WHERE id = v_auth_user_id AND merchant_id = v_merchant_id
    ) THEN
      p_data := fn_strip_locked_profile_payload(v_merchant_id, p_data);
    END IF;

    FOR v_field IN SELECT * FROM jsonb_array_elements(COALESCE(p_data->'default_fields_config'->0->'fields', '[]'::jsonb)) LOOP
        v_field_key := v_field->>'field_key';
        v_field_value := v_field->'value';
        v_submitted_default_keys := array_append(v_submitted_default_keys, v_field_key);
        CASE v_field_key
            WHEN 'email' THEN v_email := NULLIF(v_field_value #>> '{}', '');
            WHEN 'phone' THEN v_tel := NULLIF(v_field_value #>> '{}', '');
            WHEN 'firstname' THEN v_firstname := NULLIF(v_field_value #>> '{}', '');
            WHEN 'lastname' THEN v_lastname := NULLIF(v_field_value #>> '{}', '');
            WHEN 'fullname' THEN v_fullname := NULLIF(v_field_value #>> '{}', '');
            WHEN 'birth_date' THEN BEGIN v_birth_date := NULLIF(v_field_value #>> '{}', '')::DATE; EXCEPTION WHEN OTHERS THEN v_birth_date := NULL; END;
            WHEN 'id_card' THEN
                v_id_card := NULLIF(v_field_value #>> '{}', '');
                v_id_document_type := COALESCE(
                  NULLIF(v_field->>'id_document_type', ''),
                  v_id_document_type
                );
            WHEN 'id_document_type' THEN v_id_document_type := NULLIF(v_field_value #>> '{}', '');
            WHEN 'line_id' THEN v_line_id := NULLIF(v_field_value #>> '{}', '');
            WHEN 'gender' THEN v_gender := NULLIF(v_field_value #>> '{}', '');
            WHEN 'external_user_id' THEN v_external_user_id := NULLIF(v_field_value #>> '{}', '');
            WHEN 'user_stage' THEN v_user_stage := NULLIF(v_field_value #>> '{}', '');
            WHEN 'city' THEN v_city := NULLIF(v_field_value #>> '{}', '');
            WHEN 'district' THEN v_district := NULLIF(v_field_value #>> '{}', '');
            WHEN 'subdistrict' THEN v_subdistrict := NULLIF(v_field_value #>> '{}', '');
            WHEN 'postcode' THEN v_postcode := NULLIF(v_field_value #>> '{}', '');
            WHEN 'addressline_1' THEN v_addressline_1 := NULLIF(v_field_value #>> '{}', '');
            WHEN 'country_code' THEN v_country_code := NULLIF(v_field_value #>> '{}', '');
            ELSE NULL;
        END CASE;
    END LOOP;

    IF v_fullname IS NULL AND (v_firstname IS NOT NULL OR v_lastname IS NOT NULL) THEN
        v_fullname := TRIM(CONCAT_WS(' ', v_firstname, v_lastname));
        IF NOT ('fullname' = ANY(v_submitted_default_keys)) THEN
            v_submitted_default_keys := array_append(v_submitted_default_keys, 'fullname');
        END IF;
    END IF;

    IF p_data->'persona'->'selected_persona_id' IS NOT NULL
       AND p_data->'persona'->'selected_persona_id' != 'null'::jsonb THEN
        v_persona_id := (p_data->'persona'->>'selected_persona_id')::UUID;
    END IF;

    FOR v_consent IN SELECT * FROM jsonb_array_elements(p_data->'pdpa') LOOP
        IF v_consent->>'id' = 'channels' AND jsonb_array_length(COALESCE(v_consent->'options', '[]'::jsonb)) > 0 THEN
            FOR v_option IN SELECT * FROM jsonb_array_elements(v_consent->'options') LOOP
                CASE v_option->>'id'
                    WHEN 'email' THEN v_channel_email := COALESCE((v_option->>'selected')::boolean, false);
                    WHEN 'sms'   THEN v_channel_sms   := COALESCE((v_option->>'selected')::boolean, false);
                    WHEN 'line'  THEN v_channel_line  := COALESCE((v_option->>'selected')::boolean, false);
                    WHEN 'push'  THEN v_channel_push  := COALESCE((v_option->>'selected')::boolean, false);
                    ELSE NULL;
                END CASE;
            END LOOP;
        END IF;
    END LOOP;

    SELECT id INTO v_user_profile_form_id
    FROM form_templates
    WHERE merchant_id = v_merchant_id AND code = 'USER_PROFILE' AND status = 'published';

    IF v_user_profile_form_id IS NOT NULL AND jsonb_array_length(COALESCE(p_data->'custom_fields_config', '[]'::jsonb)) > 0 THEN
        v_flat_data := '{}'::jsonb;
        FOR v_group IN SELECT * FROM jsonb_array_elements(p_data->'custom_fields_config') LOOP
            FOR v_field IN SELECT * FROM jsonb_array_elements(v_group->'fields') LOOP
                v_submitted_custom_keys := array_append(v_submitted_custom_keys, v_field->>'field_key');
                v_flat_data := v_flat_data || jsonb_build_object(v_field->>'field_key', v_field->'value');
            END LOOP;
        END LOOP;
        v_validation_result := validate_form_submission(v_user_profile_form_id, v_flat_data, v_persona_id, v_submitted_custom_keys);
        IF NOT (v_validation_result->>'is_valid')::BOOLEAN THEN
            RETURN jsonb_build_object('success', false, 'title', fn_member_envelope_message('validation_failed_title', v_lang), 'description', 'Some required fields are invalid', 'data', jsonb_build_object('errors', v_validation_result->'errors'));
        END IF;
    END IF;

    SELECT id INTO v_user_id FROM user_accounts WHERE id = v_auth_user_id AND merchant_id = v_merchant_id;

    IF v_email IS NOT NULL THEN
        SELECT id INTO v_conflict_user_id FROM user_accounts WHERE merchant_id = v_merchant_id AND lower(email) = lower(v_email) AND id IS DISTINCT FROM v_user_id;
        IF v_conflict_user_id IS NOT NULL THEN RETURN jsonb_build_object('success', false, 'title', fn_member_envelope_message('email_in_use_title', v_lang), 'description', 'This email is already registered to another account', 'data', null); END IF;
    END IF;
    IF v_tel IS NOT NULL THEN
        SELECT id INTO v_conflict_user_id FROM user_accounts WHERE merchant_id = v_merchant_id AND tel = v_tel AND id IS DISTINCT FROM v_user_id;
        IF v_conflict_user_id IS NOT NULL THEN RETURN jsonb_build_object('success', false, 'title', fn_member_envelope_message('phone_in_use_title', v_lang), 'description', 'This phone number is already registered to another account', 'data', null); END IF;
    END IF;
    IF v_line_id IS NOT NULL THEN
        SELECT id INTO v_conflict_user_id FROM user_accounts WHERE merchant_id = v_merchant_id AND line_id = v_line_id AND id IS DISTINCT FROM v_user_id;
        IF v_conflict_user_id IS NOT NULL THEN RETURN jsonb_build_object('success', false, 'title', fn_member_envelope_message('line_in_use_title', v_lang), 'description', 'This LINE account is already linked to another user', 'data', null); END IF;
    END IF;

    IF v_user_id IS NULL THEN
        v_is_new_user := true;
        v_changes := jsonb_strip_nulls(jsonb_build_object(
          'email',            v_email,
          'tel',              v_tel,
          'firstname',        v_firstname,
          'lastname',         v_lastname,
          'fullname',         v_fullname,
          'birth_date',       v_birth_date,
          'id_card',          v_id_card,
          'id_document_type', v_id_document_type,
          'line_id',          v_line_id,
          'gender',           v_gender,
          'external_user_id', v_external_user_id,
          'user_stage',       v_user_stage,
          'persona_id',       v_persona_id,
          'acquisition_source', v_acquisition_source
        )) || jsonb_build_object(
          'id',                      v_auth_user_id,
          'auth_user_id',            v_auth_user_id,
          'channel_email',           v_channel_email,
          'channel_sms',             v_channel_sms,
          'channel_line',            v_channel_line,
          'channel_push',            v_channel_push,
          'is_signup_form_complete', true
        );
        v_row := public.chokepoint_post_user_event(
          p_event_type := 'create',
          p_merchant_id := v_merchant_id,
          p_changes := v_changes,
          p_actor := jsonb_build_object('actor_id', v_auth_user_id, 'actor_type', 'user')
        );
        v_user_id := v_row.id;
    ELSE
        v_changes := '{}'::jsonb;
        IF 'email'            = ANY(v_submitted_default_keys) THEN v_changes := v_changes || jsonb_build_object('email',     v_email);     END IF;
        IF 'phone'            = ANY(v_submitted_default_keys) AND v_tel IS NOT NULL THEN v_changes := v_changes || jsonb_build_object('tel', v_tel); END IF;
        IF 'firstname'        = ANY(v_submitted_default_keys) THEN v_changes := v_changes || jsonb_build_object('firstname', v_firstname); END IF;
        IF 'lastname'         = ANY(v_submitted_default_keys) THEN v_changes := v_changes || jsonb_build_object('lastname',  v_lastname);  END IF;
        IF 'fullname'         = ANY(v_submitted_default_keys) THEN v_changes := v_changes || jsonb_build_object('fullname',  v_fullname);  END IF;
        IF 'birth_date'       = ANY(v_submitted_default_keys) THEN v_changes := v_changes || jsonb_build_object('birth_date', v_birth_date); END IF;
        IF 'id_card'          = ANY(v_submitted_default_keys) THEN
          v_changes := v_changes || jsonb_build_object('id_card', v_id_card);
          IF v_id_document_type IS NOT NULL OR 'id_document_type' = ANY(v_submitted_default_keys) THEN
            v_changes := v_changes || jsonb_build_object('id_document_type', v_id_document_type);
          END IF;
        ELSIF 'id_document_type' = ANY(v_submitted_default_keys) THEN
          v_changes := v_changes || jsonb_build_object('id_document_type', v_id_document_type);
        END IF;
        IF 'line_id'          = ANY(v_submitted_default_keys) AND v_line_id IS NOT NULL THEN v_changes := v_changes || jsonb_build_object('line_id', v_line_id); END IF;
        IF 'gender'           = ANY(v_submitted_default_keys) THEN v_changes := v_changes || jsonb_build_object('gender',           v_gender);           END IF;
        IF 'external_user_id' = ANY(v_submitted_default_keys) THEN v_changes := v_changes || jsonb_build_object('external_user_id', v_external_user_id); END IF;
        IF 'user_stage'       = ANY(v_submitted_default_keys) THEN v_changes := v_changes || jsonb_build_object('user_stage',       v_user_stage);       END IF;
        IF v_persona_id IS NOT NULL THEN v_changes := v_changes || jsonb_build_object('persona_id', v_persona_id); END IF;
        IF v_acquisition_source IS NOT NULL THEN v_changes := v_changes || jsonb_build_object('acquisition_source', v_acquisition_source); END IF;

        v_changes := v_changes || jsonb_build_object(
          'channel_email',           v_channel_email,
          'channel_sms',             v_channel_sms,
          'channel_line',            v_channel_line,
          'channel_push',            v_channel_push,
          'is_signup_form_complete', true
        );

        IF EXISTS (SELECT 1 FROM user_accounts WHERE id = v_user_id AND auth_user_id IS NULL) THEN
          v_changes := v_changes || jsonb_build_object('auth_user_id', v_auth_user_id);
        END IF;

        PERFORM public.chokepoint_post_user_event(
          p_event_type := 'update',
          p_merchant_id := v_merchant_id,
          p_user_id := v_user_id,
          p_changes := v_changes,
          p_actor := jsonb_build_object('actor_id', v_auth_user_id, 'actor_type', 'user')
        );
    END IF;

    FOR v_external_code_field IN
        SELECT ufc.id AS field_config_id, ufc.field_key
        FROM user_field_config ufc
        WHERE ufc.merchant_id = v_merchant_id
          AND ufc.field_type = 'external_code'
          AND ufc.active_status = true
          AND ufc.field_key = ANY(v_submitted_default_keys)
    LOOP
        v_external_code_value := NULL;
        IF EXISTS (
      SELECT 1 FROM user_accounts
      WHERE id = v_auth_user_id AND merchant_id = v_merchant_id
    ) THEN
      p_data := fn_strip_locked_profile_payload(v_merchant_id, p_data);
    END IF;

    FOR v_field IN SELECT * FROM jsonb_array_elements(COALESCE(p_data->'default_fields_config'->0->'fields', '[]'::jsonb)) LOOP
            IF v_field->>'field_key' = v_external_code_field.field_key THEN
                v_external_code_value := NULLIF(v_field->'value' #>> '{}', '');
                EXIT;
            END IF;
        END LOOP;
        IF v_external_code_value IS NULL THEN CONTINUE; END IF;
        PERFORM fn_consume_signup_code(v_user_id, v_external_code_field.field_config_id, v_external_code_value);
    END LOOP;

    -- Address: only columns whose field_key came in on this submission are
    -- written. A key absent from the form (inactive in user_field_config, so
    -- omitted from the template) leaves the stored value untouched instead of
    -- being overwritten with NULL. A key present but blank still clears.
    IF v_city IS NOT NULL OR v_district IS NOT NULL OR v_subdistrict IS NOT NULL
       OR v_postcode IS NOT NULL OR v_addressline_1 IS NOT NULL OR v_country_code IS NOT NULL THEN
        INSERT INTO user_address (
            user_id, merchant_id, city, district, subdistrict, postcode, addressline_1, country_code, created_at
        ) VALUES (
            v_user_id, v_merchant_id, v_city, v_district, v_subdistrict, v_postcode, v_addressline_1, v_country_code, NOW()
        )
        ON CONFLICT (user_id, merchant_id) DO UPDATE SET
            city          = CASE WHEN 'city'          = ANY(v_submitted_default_keys) THEN EXCLUDED.city          ELSE user_address.city          END,
            district      = CASE WHEN 'district'      = ANY(v_submitted_default_keys) THEN EXCLUDED.district      ELSE user_address.district      END,
            subdistrict   = CASE WHEN 'subdistrict'   = ANY(v_submitted_default_keys) THEN EXCLUDED.subdistrict   ELSE user_address.subdistrict   END,
            postcode      = CASE WHEN 'postcode'      = ANY(v_submitted_default_keys) THEN EXCLUDED.postcode      ELSE user_address.postcode      END,
            addressline_1 = CASE WHEN 'addressline_1' = ANY(v_submitted_default_keys) THEN EXCLUDED.addressline_1 ELSE user_address.addressline_1 END,
            country_code  = CASE WHEN 'country_code'  = ANY(v_submitted_default_keys) THEN EXCLUDED.country_code  ELSE user_address.country_code  END;
    END IF;

    IF v_user_profile_form_id IS NOT NULL AND jsonb_array_length(COALESCE(p_data->'custom_fields_config', '[]'::jsonb)) > 0 THEN
        SELECT id INTO v_submission_id FROM form_submissions WHERE form_id = v_user_profile_form_id AND user_id = v_user_id;
        IF v_submission_id IS NULL THEN
            INSERT INTO form_submissions (form_id, merchant_id, user_id, status, submitted_at, created_at)
            VALUES (v_user_profile_form_id, v_merchant_id, v_user_id, 'completed', NOW(), NOW())
            RETURNING id INTO v_submission_id;
        ELSE
            UPDATE form_submissions SET submitted_at = NOW() WHERE id = v_submission_id;
        END IF;
        FOR v_group IN SELECT * FROM jsonb_array_elements(p_data->'custom_fields_config') LOOP
            FOR v_field IN SELECT * FROM jsonb_array_elements(v_group->'fields') LOOP
                v_field_key := v_field->>'field_key';
                v_field_value := v_field->'value';
                IF v_field_value IS NULL OR v_field_value = 'null'::jsonb THEN CONTINUE; END IF;
                SELECT id INTO v_field_id FROM form_fields
                WHERE field_key = v_field_key AND deleted_at IS NULL
                  AND group_id IN (SELECT id FROM form_field_groups WHERE form_id = v_user_profile_form_id);
                IF v_field_id IS NOT NULL THEN
                    INSERT INTO form_responses (submission_id, field_id, text_value, array_value, object_value, created_at)
                    VALUES (
                        v_submission_id, v_field_id,
                        CASE
                            WHEN jsonb_typeof(v_field_value) = 'string'  THEN v_field_value #>> '{}'
                            WHEN jsonb_typeof(v_field_value) = 'number'  THEN v_field_value::text
                            WHEN jsonb_typeof(v_field_value) = 'boolean' THEN v_field_value::text
                            ELSE NULL END,
                        CASE WHEN jsonb_typeof(v_field_value) = 'array'  THEN ARRAY(SELECT jsonb_array_elements(v_field_value)) ELSE NULL END,
                        CASE WHEN jsonb_typeof(v_field_value) = 'object' THEN v_field_value ELSE NULL END,
                        NOW()
                    )
                    ON CONFLICT (submission_id, field_id) DO UPDATE SET
                        text_value   = EXCLUDED.text_value,
                        array_value  = EXCLUDED.array_value,
                        object_value = EXCLUDED.object_value;
                END IF;
            END LOOP;
        END LOOP;
    END IF;

    FOR v_consent IN SELECT * FROM jsonb_array_elements(p_data->'pdpa') LOOP
        IF v_consent->>'id' IN ('channels', 'topics') THEN CONTINUE; END IF;
        IF v_consent ? 'isAccepted' THEN
            BEGIN
                INSERT INTO user_consent_ledger (user_id, merchant_id, consent_version_id, action, created_at)
                VALUES (v_user_id, v_merchant_id, (v_consent->>'id')::UUID,
                    CASE WHEN (v_consent->>'isAccepted')::boolean THEN 'accepted'::consent_action ELSE 'withdrawn'::consent_action END,
                    NOW());
            EXCEPTION WHEN invalid_text_representation THEN NULL; END;
        END IF;
    END LOOP;

    FOR v_consent IN SELECT * FROM jsonb_array_elements(p_data->'pdpa') LOOP
        IF v_consent->>'id' = 'topics' AND jsonb_array_length(COALESCE(v_consent->'options', '[]'::jsonb)) > 0 THEN
            FOR v_option IN SELECT * FROM jsonb_array_elements(v_consent->'options') LOOP
                BEGIN
                    INSERT INTO user_communication_preferences (user_id, merchant_id, topic_id, opted_in, created_at, updated_at)
                    VALUES (v_user_id, v_merchant_id, (v_option->>'id')::UUID, COALESCE((v_option->>'selected')::boolean, false), NOW(), NOW())
                    ON CONFLICT (user_id, topic_id) DO UPDATE SET opted_in = EXCLUDED.opted_in, updated_at = NOW();
                EXCEPTION WHEN invalid_text_representation THEN NULL; END;
            END LOOP;
        END IF;
    END LOOP;

    PERFORM public.fn_log_admin_bff_write('bff_save_user_profile');
  RETURN jsonb_build_object(
    'success', true, 'title', fn_member_envelope_message('profile_saved_title', v_lang), 'description', null,
        'data', jsonb_build_object('user_id', v_user_id, 'is_new_user', v_is_new_user, 'is_signup_form_complete', true)
    );

EXCEPTION
    WHEN raise_exception THEN
        IF SQLERRM LIKE 'ID_DOCUMENT:%' THEN
            RETURN jsonb_build_object(
                'success', false,
                'title', fn_member_envelope_message('id_document_failed_title', v_lang),
                'description', COALESCE(NULLIF(split_part(SQLERRM, ':', 3), ''), SQLERRM),
                'data', jsonb_build_object(
                  'error_code', COALESCE(NULLIF(split_part(SQLERRM, ':', 2), ''), 'ID_DOCUMENT_INVALID'),
                  'field_key', 'id_card'
                )
            );
        END IF;
        IF SQLERRM LIKE 'SIGNUP_CODE:%' THEN
            v_signup_code_parts := string_to_array(SQLERRM, ':');
            RETURN jsonb_build_object('success', false, 'title', fn_member_envelope_message('code_validation_failed_title', v_lang), 'description', COALESCE(v_signup_code_parts[3], 'The signup code could not be validated'), 'data', jsonb_build_object('error_code', COALESCE(v_signup_code_parts[2], 'SIGNUP_CODE_ERROR')));
        END IF;
        RETURN jsonb_build_object('success', false, 'title', fn_member_envelope_message('profile_save_failed_title', v_lang), 'description', SQLERRM, 'data', null);
    WHEN unique_violation THEN
        RETURN jsonb_build_object(
            'success', false, 'title', fn_member_envelope_message('duplicate_title', v_lang),
            'description', CASE
                WHEN SQLERRM LIKE '%idx_user_email_unique_per_merchant%' THEN 'This email is already registered to another account'
                WHEN SQLERRM LIKE '%demo_mock_users_phone_merchant_key%' THEN 'This phone number is already registered to another account'
                ELSE SQLERRM
            END,
            'data', null
        );
    WHEN OTHERS THEN
        RETURN jsonb_build_object('success', false, 'title', fn_member_envelope_message('profile_save_failed_title', v_lang), 'description', SQLERRM, 'data', null);
END;
$function$;
