-- =====================================================
-- Shopify Merchant Upsert Function
-- =====================================================
-- Purpose: Find or create merchant with Shopify credentials
-- Used by: Shopify app onboarding flow
-- Security: No merchant context needed (pre-authentication)
-- =====================================================

CREATE OR REPLACE FUNCTION shopify_upsert_merchant_with_credentials(
    p_merchant_code text,
    p_merchant_name text,
    p_shopify_credentials jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_merchant_id uuid;
    v_existing_merchant record;
    v_credentials_exist boolean := false;
    v_is_new boolean := false;
    v_credential_id uuid;
BEGIN
    -- Validate inputs
    IF p_merchant_code IS NULL OR p_merchant_code = '' THEN
        RETURN jsonb_build_object(
            'success', false,
            'error_code', 'INVALID_MERCHANT_CODE',
            'error_message', 'merchant_code is required'
        );
    END IF;

    IF p_shopify_credentials IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'error_code', 'INVALID_CREDENTIALS',
            'error_message', 'shopify_credentials is required'
        );
    END IF;

    -- Check if merchant already exists
    SELECT id, merchant_code, name
    INTO v_existing_merchant
    FROM merchant_master
    WHERE merchant_code = p_merchant_code;

    IF v_existing_merchant.id IS NOT NULL THEN
        -- Merchant exists
        v_merchant_id := v_existing_merchant.id;
        v_is_new := false;

        -- Check if credentials exist
        SELECT EXISTS (
            SELECT 1
            FROM merchant_credentials
            WHERE merchant_id = v_merchant_id
            AND service_name = 'shopify_app'
            AND is_active = true
        ) INTO v_credentials_exist;

        -- Update credentials if they exist, create if they don't
        IF v_credentials_exist THEN
            UPDATE merchant_credentials
            SET 
                credentials = p_shopify_credentials,
                updated_at = NOW()
            WHERE merchant_id = v_merchant_id
            AND service_name = 'shopify_app'
            AND is_active = true;
        ELSE
            INSERT INTO merchant_credentials (
                merchant_id,
                service_name,
                credentials,
                environment,
                is_active
            ) VALUES (
                v_merchant_id,
                'shopify_app',
                p_shopify_credentials,
                'production',
                true
            );
        END IF;

    ELSE
        -- Create new merchant
        INSERT INTO merchant_master (
            merchant_code,
            name,
            auth_methods
        ) VALUES (
            p_merchant_code,
            p_merchant_name,
            ARRAY['line', 'tel']
        )
        RETURNING id INTO v_merchant_id;

        -- Create credentials
        INSERT INTO merchant_credentials (
            merchant_id,
            service_name,
            credentials,
            environment,
            is_active
        ) VALUES (
            v_merchant_id,
            'shopify_app',
            p_shopify_credentials,
            'production',
            true
        )
        RETURNING id INTO v_credential_id;

        v_is_new := true;
        v_credentials_exist := true;
    END IF;

    -- Return success response
    RETURN jsonb_build_object(
        'success', true,
        'is_new', v_is_new,
        'merchant_id', v_merchant_id,
        'merchant_code', p_merchant_code,
        'merchant_name', COALESCE(v_existing_merchant.name, p_merchant_name),
        'credentials_exist', v_credentials_exist,
        'message', CASE 
            WHEN v_is_new THEN 'Merchant created with Shopify credentials'
            ELSE 'Merchant found, credentials updated'
        END
    );

EXCEPTION
    WHEN unique_violation THEN
        RETURN jsonb_build_object(
            'success', false,
            'error_code', 'MERCHANT_CODE_EXISTS',
            'error_message', 'Merchant code already exists'
        );
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', false,
            'error_code', 'UNEXPECTED_ERROR',
            'error_message', SQLERRM
        );
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION shopify_upsert_merchant_with_credentials TO anon, authenticated, service_role;

-- =====================================================
-- Example Usage
-- =====================================================
-- SELECT shopify_upsert_merchant_with_credentials(
--     'quickstart-ef112207.myshopify.com',
--     'QuickStart Store',
--     '{
--         "api_key": "c1d554532c476865b0ec50a97fce37f0",
--         "api_secret": "shpss_REDACTED",
--         "shop_domain": "quickstart-ef112207.myshopify.com",
--         "access_token": "shpua_REDACTED"
--     }'::jsonb
-- );
