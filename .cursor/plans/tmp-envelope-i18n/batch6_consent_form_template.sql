CREATE OR REPLACE FUNCTION public.bff_get_consent_form_template(p_mode text DEFAULT 'new'::text, p_language text DEFAULT 'en'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_lang text;
    v_merchant_id UUID;
    v_user_id UUID;
    v_result JSONB;
    v_notices JSONB;
    v_consents JSONB;
    v_channels JSONB;
    v_topics JSONB;
    v_channel_email BOOLEAN := false;
    v_channel_line BOOLEAN := false;
    v_channel_sms BOOLEAN := false;
    v_channel_push BOOLEAN := false;
BEGIN
    v_lang := fn_normalize_ui_language(p_language);
    v_merchant_id := get_current_merchant_id();

    IF v_merchant_id IS NULL THEN
        RETURN jsonb_build_object(
          'success', false,
          'title', fn_admin_envelope_message('no_merchant_title', v_lang),
          'description', null
        );
    END IF;

    -- For edit mode, get user and their channel preferences
    IF p_mode = 'edit' THEN
        SELECT id,
               COALESCE(channel_email, false),
               COALESCE(channel_line, false),
               COALESCE(channel_sms, false),
               COALESCE(channel_push, false)
        INTO v_user_id, v_channel_email, v_channel_line, v_channel_sms, v_channel_push
        FROM user_accounts
        WHERE id = auth.uid() AND merchant_id = v_merchant_id;

        IF v_user_id IS NULL THEN
            RETURN jsonb_build_object(
              'success', false,
              'title', fn_admin_envelope_message('user_not_found_title', v_lang),
              'description', null
            );
        END IF;
    END IF;

    -- 1. Get Privacy Notices (display only, no action needed)
    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id', cv.id,
            'type', cv.consent_type::text,
            'version_code', cv.version_code,
            'title', cv.title,
            'content', cv.content,
            'is_mandatory', cv.is_mandatory,
            'requires_action', false
        ) ORDER BY cv.created_at
    ), '[]'::jsonb) INTO v_notices
    FROM consent_versions cv
    WHERE cv.merchant_id = v_merchant_id
        AND cv.consent_type = 'privacy_policy'
        AND cv.active_status = true;

    -- 2. Get Consents (requires accept/reject)
    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id', cv.id,
            'type', cv.consent_type::text,
            'version_code', cv.version_code,
            'title', cv.title,
            'content', cv.content,
            'is_mandatory', cv.is_mandatory,
            'requires_action', true,
            'accepted', CASE
                WHEN p_mode = 'edit' AND v_user_id IS NOT NULL THEN COALESCE(
                    (SELECT ucl.action = 'accepted'
                     FROM user_consent_ledger ucl
                     WHERE ucl.user_id = v_user_id
                         AND ucl.consent_version_id = cv.id
                     ORDER BY ucl.created_at DESC
                     LIMIT 1),
                    false
                )
                ELSE false
            END
        ) ORDER BY cv.is_mandatory DESC, cv.created_at
    ), '[]'::jsonb) INTO v_consents
    FROM consent_versions cv
    WHERE cv.merchant_id = v_merchant_id
        AND cv.consent_type IN ('terms_of_service', 'marketing')
        AND cv.active_status = true;

    -- 3. Get Communication Channels
    v_channels := jsonb_build_array(
        jsonb_build_object(
            'key', 'channel_email',
            'label', 'Email',
            'enabled', v_channel_email
        ),
        jsonb_build_object(
            'key', 'channel_line',
            'label', 'LINE',
            'enabled', v_channel_line
        ),
        jsonb_build_object(
            'key', 'channel_sms',
            'label', 'SMS',
            'enabled', v_channel_sms
        ),
        jsonb_build_object(
            'key', 'channel_push',
            'label', 'Push Notification',
            'enabled', v_channel_push
        )
    );

    -- 4. Get Communication Topics
    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id', ct.id,
            'name', ct.topic_name,
            'description', ct.description,
            'opted_in', CASE
                WHEN p_mode = 'edit' AND v_user_id IS NOT NULL THEN COALESCE(
                    (SELECT ucp.opted_in
                     FROM user_communication_preferences ucp
                     WHERE ucp.user_id = v_user_id AND ucp.topic_id = ct.id),
                    false
                )
                ELSE false
            END
        ) ORDER BY ct.created_at
    ), '[]'::jsonb) INTO v_topics
    FROM communication_topics ct
    WHERE ct.merchant_id = v_merchant_id
        AND ct.active_status = true;

    -- Build final result
    RETURN jsonb_build_object(
        'success', true,
        'mode', p_mode,
        'notices', v_notices,
        'consents', v_consents,
        'channels', v_channels,
        'topics', v_topics,
        'timestamp', NOW()
    );
END;
$function$;

DROP FUNCTION IF EXISTS public.bff_get_consent_form_template(text);
