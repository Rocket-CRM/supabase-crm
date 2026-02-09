-- =====================================================
-- Bulk Import Customers - Schema and RPC
-- =====================================================
-- Extends bulk_import_batches for customer imports and adds
-- bulk_upsert_customers_from_import (validate then insert, single RPC).
-- =====================================================

-- 1. Extend bulk_import_batches for customer imports
ALTER TABLE bulk_import_batches
  ADD COLUMN IF NOT EXISTS import_type TEXT NOT NULL DEFAULT 'purchases',
  ADD COLUMN IF NOT EXISTS imported_users INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS validation_errors JSONB;

COMMENT ON COLUMN bulk_import_batches.import_type IS 'purchases | customers';
COMMENT ON COLUMN bulk_import_batches.imported_users IS 'For customer imports: count of users inserted/updated';
COMMENT ON COLUMN bulk_import_batches.validation_errors IS 'For customer imports: [{row, reason}, ...] when validation fails';

-- 2. bulk_upsert_customers_from_import: validate first, then insert (no separate validate API)
-- Row keys: table-prefixed (user_accounts_tel, user_address_city, user_wallet_points_balance, etc.)
-- Dup match: (merchant_id, tel) OR (merchant_id, line_id). Cap validation errors at p_max_errors (100).
CREATE OR REPLACE FUNCTION bulk_upsert_customers_from_import(
  p_rows JSONB,
  p_merchant_id UUID,
  p_create_wallet_ledger_entry BOOLEAN DEFAULT false,
  p_batch_id UUID DEFAULT NULL,
  p_max_errors INTEGER DEFAULT 100
)
RETURNS TABLE (
  success BOOLEAN,
  valid BOOLEAN,
  imported_count INTEGER,
  updated_count INTEGER,
  error_message TEXT,
  errors JSONB,
  total_error_count INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_row JSONB;
  v_idx INT := 0;
  v_errors JSONB := '[]'::jsonb;
  v_total_errors INT := 0;
  v_tel TEXT;
  v_line_id TEXT;
  v_birth_date TEXT;
  v_points TEXT;
  v_reason TEXT;
  v_user_id UUID;
  v_exists BOOLEAN;
  v_imported INT := 0;
  v_updated INT := 0;
  v_form_id UUID;
  v_balance_before INT;
  v_balance_after INT;
  v_points_val INT;
  v_user_type TEXT;
  v_persona_id UUID;
  v_tier_id UUID;
  v_tier_lock BOOLEAN;
  v_tier_lock_until TIMESTAMPTZ;
  v_channel_email BOOLEAN;
  v_channel_sms BOOLEAN;
  v_channel_line BOOLEAN;
  v_channel_push BOOLEAN;
BEGIN
  -- Resolve USER_PROFILE form_id for this merchant (optional)
  SELECT id INTO v_form_id FROM form_templates
  WHERE merchant_id = p_merchant_id AND code = 'USER_PROFILE' AND status = 'published'
  LIMIT 1;

  -- Validation pass: collect errors, cap at p_max_errors
  FOR v_row IN SELECT * FROM jsonb_array_elements(p_rows)
  LOOP
    v_idx := v_idx + 1;
    v_tel := NULLIF(TRIM(COALESCE(v_row->>'user_accounts_tel', v_row->>'tel')::TEXT), '');
    v_line_id := NULLIF(TRIM(COALESCE(v_row->>'user_accounts_line_id', v_row->>'line_id')::TEXT), '');
    v_birth_date := NULLIF(TRIM(COALESCE(v_row->>'user_accounts_birth_date', v_row->>'birth_date')::TEXT), '');
    v_points := NULLIF(TRIM(COALESCE(v_row->>'user_wallet_points_balance', v_row->>'total_points', v_row->>'points_balance')::TEXT), '');

    -- At least one of tel or line_id
    IF (v_tel IS NULL OR v_tel = '' OR v_tel = '-') AND (v_line_id IS NULL OR v_line_id = '' OR v_line_id = '-') THEN
      v_total_errors := v_total_errors + 1;
      IF jsonb_array_length(v_errors) < p_max_errors THEN
        v_errors := v_errors || jsonb_build_array(jsonb_build_object('row', v_idx, 'reason', 'tel or line_id required'));
      END IF;
      CONTINUE;
    END IF;

    -- Tel must start with + and country code when provided
    IF v_tel IS NOT NULL AND v_tel != '' AND v_tel != '-' AND v_tel !~ '^\+' THEN
      v_total_errors := v_total_errors + 1;
      IF jsonb_array_length(v_errors) < p_max_errors THEN
        v_errors := v_errors || jsonb_build_array(jsonb_build_object('row', v_idx, 'reason', 'tel must start with + and country code (e.g. +66812345678)'));
      END IF;
      CONTINUE;
    END IF;

    -- Optional: user_type must be buyer or seller
    v_user_type := NULLIF(TRIM(LOWER(COALESCE(v_row->>'user_accounts_user_type', v_row->>'user_type')::TEXT)), '');
    IF v_user_type IS NOT NULL AND v_user_type != '' AND v_user_type != '-' AND v_user_type NOT IN ('buyer', 'seller') THEN
      v_total_errors := v_total_errors + 1;
      IF jsonb_array_length(v_errors) < p_max_errors THEN
        v_errors := v_errors || jsonb_build_array(jsonb_build_object('row', v_idx, 'reason', 'user_accounts_user_type must be buyer or seller'));
      END IF;
      CONTINUE;
    END IF;

    -- Optional: persona_id and tier_id must be valid UUID when provided
    IF NULLIF(TRIM(COALESCE(v_row->>'user_accounts_persona_id', '')::TEXT), '') IS NOT NULL AND NULLIF(TRIM(COALESCE(v_row->>'user_accounts_persona_id', '')::TEXT), '') != '-' THEN
      IF NULLIF(TRIM(COALESCE(v_row->>'user_accounts_persona_id', '')::TEXT), '') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' THEN
        v_total_errors := v_total_errors + 1;
        IF jsonb_array_length(v_errors) < p_max_errors THEN
          v_errors := v_errors || jsonb_build_array(jsonb_build_object('row', v_idx, 'reason', 'user_accounts_persona_id must be a valid UUID'));
        END IF;
        CONTINUE;
      END IF;
    END IF;
    IF NULLIF(TRIM(COALESCE(v_row->>'user_accounts_tier_id', '')::TEXT), '') IS NOT NULL AND NULLIF(TRIM(COALESCE(v_row->>'user_accounts_tier_id', '')::TEXT), '') != '-' THEN
      IF NULLIF(TRIM(COALESCE(v_row->>'user_accounts_tier_id', '')::TEXT), '') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' THEN
        v_total_errors := v_total_errors + 1;
        IF jsonb_array_length(v_errors) < p_max_errors THEN
          v_errors := v_errors || jsonb_build_array(jsonb_build_object('row', v_idx, 'reason', 'user_accounts_tier_id must be a valid UUID'));
        END IF;
        CONTINUE;
      END IF;
    END IF;

    -- Optional: birth_date format DD-MM-YYYY
    IF v_birth_date IS NOT NULL AND v_birth_date != '' AND v_birth_date != '-' THEN
      IF v_birth_date !~ '^\d{1,2}-\d{1,2}-\d{4}$' THEN
        v_total_errors := v_total_errors + 1;
        IF jsonb_array_length(v_errors) < p_max_errors THEN
          v_errors := v_errors || jsonb_build_array(jsonb_build_object('row', v_idx, 'reason', 'invalid birth_date format (use DD-MM-YYYY)'));
        END IF;
        CONTINUE;
      END IF;
    END IF;

    -- Optional: points non-negative integer
    IF v_points IS NOT NULL AND v_points != '' AND v_points != '-' THEN
      BEGIN
        v_points_val := (v_points::INTEGER);
        IF v_points_val < 0 THEN
          v_total_errors := v_total_errors + 1;
          IF jsonb_array_length(v_errors) < p_max_errors THEN
            v_errors := v_errors || jsonb_build_array(jsonb_build_object('row', v_idx, 'reason', 'user_wallet_points_balance must be non-negative'));
          END IF;
          CONTINUE;
        END IF;
      EXCEPTION WHEN OTHERS THEN
        v_total_errors := v_total_errors + 1;
        IF jsonb_array_length(v_errors) < p_max_errors THEN
          v_errors := v_errors || jsonb_build_array(jsonb_build_object('row', v_idx, 'reason', 'user_wallet_points_balance must be an integer'));
        END IF;
        CONTINUE;
      END;
    END IF;
  END LOOP;

  -- If any validation errors, return without inserting
  IF v_total_errors > 0 THEN
    RETURN QUERY SELECT false, false, 0, 0, NULL::TEXT, v_errors, v_total_errors;
    RETURN;
  END IF;

  -- Insert pass: single transaction
  BEGIN
    v_idx := 0;
    FOR v_row IN SELECT * FROM jsonb_array_elements(p_rows)
    LOOP
      v_idx := v_idx + 1;
      v_tel := NULLIF(TRIM(COALESCE(v_row->>'user_accounts_tel', v_row->>'tel')::TEXT), '');
      v_line_id := NULLIF(TRIM(COALESCE(v_row->>'user_accounts_line_id', v_row->>'line_id')::TEXT), '');
      IF v_tel = '-' THEN v_tel := NULL; END IF;
      IF v_line_id = '-' THEN v_line_id := NULL; END IF;

      -- Parse optional persona, user_type, tier, lock, channels
      v_persona_id := NULL;
      IF NULLIF(TRIM(COALESCE(v_row->>'user_accounts_persona_id', '')::TEXT), '') IS NOT NULL AND NULLIF(TRIM(COALESCE(v_row->>'user_accounts_persona_id', '')::TEXT), '') != '-' THEN
        v_persona_id := (NULLIF(TRIM(v_row->>'user_accounts_persona_id'), '')::uuid);
      END IF;
      v_tier_id := NULL;
      IF NULLIF(TRIM(COALESCE(v_row->>'user_accounts_tier_id', '')::TEXT), '') IS NOT NULL AND NULLIF(TRIM(COALESCE(v_row->>'user_accounts_tier_id', '')::TEXT), '') != '-' THEN
        v_tier_id := (NULLIF(TRIM(v_row->>'user_accounts_tier_id'), '')::uuid);
      END IF;
      v_user_type := NULLIF(TRIM(LOWER(COALESCE(v_row->>'user_accounts_user_type', v_row->>'user_type')::TEXT)), '');
      IF v_user_type = '' OR v_user_type = '-' THEN v_user_type := NULL; END IF;
      v_tier_lock := LOWER(TRIM(COALESCE(v_row->>'user_accounts_tier_lock_downgrade', '')::TEXT)) IN ('true', '1', 'yes');
      v_tier_lock_until := NULL;
      IF NULLIF(TRIM(COALESCE(v_row->>'user_accounts_tier_locked_downgrade_until', '')::TEXT), '') IS NOT NULL AND NULLIF(TRIM(COALESCE(v_row->>'user_accounts_tier_locked_downgrade_until', '')::TEXT), '') != '-' THEN
        BEGIN
          v_tier_lock_until := (NULLIF(TRIM(v_row->>'user_accounts_tier_locked_downgrade_until'), '')::timestamptz);
        EXCEPTION WHEN OTHERS THEN
          v_tier_lock_until := NULL;
        END;
      END IF;
      v_channel_email := NULL;
      IF NULLIF(TRIM(LOWER(COALESCE(v_row->>'user_accounts_channel_email', '')::TEXT)), '') IS NOT NULL AND NULLIF(TRIM(LOWER(COALESCE(v_row->>'user_accounts_channel_email', '')::TEXT)), '') != '-' THEN
        v_channel_email := LOWER(TRIM(v_row->>'user_accounts_channel_email')) IN ('true', '1', 'yes');
      END IF;
      v_channel_sms := NULL;
      IF NULLIF(TRIM(LOWER(COALESCE(v_row->>'user_accounts_channel_sms', '')::TEXT)), '') IS NOT NULL AND NULLIF(TRIM(LOWER(COALESCE(v_row->>'user_accounts_channel_sms', '')::TEXT)), '') != '-' THEN
        v_channel_sms := LOWER(TRIM(v_row->>'user_accounts_channel_sms')) IN ('true', '1', 'yes');
      END IF;
      v_channel_line := NULL;
      IF NULLIF(TRIM(LOWER(COALESCE(v_row->>'user_accounts_channel_line', '')::TEXT)), '') IS NOT NULL AND NULLIF(TRIM(LOWER(COALESCE(v_row->>'user_accounts_channel_line', '')::TEXT)), '') != '-' THEN
        v_channel_line := LOWER(TRIM(v_row->>'user_accounts_channel_line')) IN ('true', '1', 'yes');
      END IF;
      v_channel_push := NULL;
      IF NULLIF(TRIM(LOWER(COALESCE(v_row->>'user_accounts_channel_push', '')::TEXT)), '') IS NOT NULL AND NULLIF(TRIM(LOWER(COALESCE(v_row->>'user_accounts_channel_push', '')::TEXT)), '') != '-' THEN
        v_channel_push := LOWER(TRIM(v_row->>'user_accounts_channel_push')) IN ('true', '1', 'yes');
      END IF;

      -- Find existing user by (merchant_id, tel) or (merchant_id, line_id)
      SELECT id INTO v_user_id FROM user_accounts u
      WHERE u.merchant_id = p_merchant_id
        AND (
          (v_tel IS NOT NULL AND u.tel IS NOT NULL AND TRIM(u.tel) = v_tel)
          OR (v_line_id IS NOT NULL AND u.line_id IS NOT NULL AND TRIM(u.line_id) = v_line_id)
        )
      LIMIT 1;

      IF v_user_id IS NULL THEN
        -- Insert new user
        v_user_id := gen_random_uuid();
        INSERT INTO user_accounts (
          id, merchant_id, auth_user_id, tel, line_id, email, firstname, lastname, fullname, birth_date, gender, created_at, is_signup_form_complete,
          persona_id, user_type, tier_id, tier_lock_downgrade, tier_locked_downgrade_until, channel_email, channel_sms, channel_line, channel_push
        ) VALUES (
          v_user_id,
          p_merchant_id,
          v_user_id,
          v_tel,
          v_line_id,
          NULLIF(TRIM(COALESCE(v_row->>'user_accounts_email', v_row->>'email')::TEXT), ''),
          NULLIF(TRIM(COALESCE(v_row->>'user_accounts_firstname', v_row->>'firstname')::TEXT), ''),
          NULLIF(TRIM(COALESCE(v_row->>'user_accounts_lastname', v_row->>'lastname')::TEXT), ''),
          NULLIF(TRIM(COALESCE(v_row->>'user_accounts_fullname', v_row->>'fullname')::TEXT), ''),
          CASE
            WHEN NULLIF(TRIM(COALESCE(v_row->>'user_accounts_birth_date', v_row->>'birth_date')::TEXT), '') IS NULL THEN NULL
            WHEN NULLIF(TRIM(COALESCE(v_row->>'user_accounts_birth_date', v_row->>'birth_date')::TEXT), '') ~ '^\d{1,2}-\d{1,2}-\d{4}$' THEN
              TO_DATE(NULLIF(TRIM(COALESCE(v_row->>'user_accounts_birth_date', v_row->>'birth_date')::TEXT), ''), 'DD-MM-YYYY')
            ELSE NULL
          END,
          NULLIF(TRIM(COALESCE(v_row->>'user_accounts_gender', v_row->>'gender')::TEXT), ''),
          COALESCE(
            (v_row->>'user_accounts_created_at')::TIMESTAMPTZ,
            (v_row->>'created_at')::TIMESTAMPTZ,
            NOW()
          ),
          true,
          v_persona_id,
          v_user_type::user_type,
          v_tier_id,
          COALESCE(v_tier_lock, false),
          v_tier_lock_until,
          v_channel_email,
          v_channel_sms,
          v_channel_line,
          v_channel_push
        );
        v_imported := v_imported + 1;
      ELSE
        -- Update existing user
        UPDATE user_accounts SET
          tel = COALESCE(NULLIF(TRIM(v_tel), ''), tel),
          line_id = COALESCE(NULLIF(TRIM(v_line_id), ''), line_id),
          email = COALESCE(NULLIF(TRIM(COALESCE(v_row->>'user_accounts_email', v_row->>'email')::TEXT), ''), email),
          firstname = COALESCE(NULLIF(TRIM(COALESCE(v_row->>'user_accounts_firstname', v_row->>'firstname')::TEXT), ''), firstname),
          lastname = COALESCE(NULLIF(TRIM(COALESCE(v_row->>'user_accounts_lastname', v_row->>'lastname')::TEXT), ''), lastname),
          fullname = COALESCE(NULLIF(TRIM(COALESCE(v_row->>'user_accounts_fullname', v_row->>'fullname')::TEXT), ''), fullname),
          birth_date = CASE
            WHEN NULLIF(TRIM(COALESCE(v_row->>'user_accounts_birth_date', v_row->>'birth_date')::TEXT), '') ~ '^\d{1,2}-\d{1,2}-\d{4}$' THEN
              TO_DATE(NULLIF(TRIM(COALESCE(v_row->>'user_accounts_birth_date', v_row->>'birth_date')::TEXT), ''), 'DD-MM-YYYY')
            ELSE birth_date
          END,
          gender = COALESCE(NULLIF(TRIM(COALESCE(v_row->>'user_accounts_gender', v_row->>'gender')::TEXT), ''), gender),
          persona_id = COALESCE(v_persona_id, persona_id),
          user_type = COALESCE(v_user_type::user_type, user_type),
          tier_id = COALESCE(v_tier_id, tier_id),
          tier_lock_downgrade = CASE WHEN NULLIF(TRIM(COALESCE(v_row->>'user_accounts_tier_lock_downgrade', '')), '') IS NOT NULL AND NULLIF(TRIM(COALESCE(v_row->>'user_accounts_tier_lock_downgrade', '')), '') != '-' THEN v_tier_lock ELSE tier_lock_downgrade END,
          tier_locked_downgrade_until = COALESCE(v_tier_lock_until, tier_locked_downgrade_until),
          channel_email = CASE WHEN NULLIF(TRIM(COALESCE(v_row->>'user_accounts_channel_email', '')), '') IS NOT NULL AND NULLIF(TRIM(COALESCE(v_row->>'user_accounts_channel_email', '')), '') != '-' THEN v_channel_email ELSE channel_email END,
          channel_sms = CASE WHEN NULLIF(TRIM(COALESCE(v_row->>'user_accounts_channel_sms', '')), '') IS NOT NULL AND NULLIF(TRIM(COALESCE(v_row->>'user_accounts_channel_sms', '')), '') != '-' THEN v_channel_sms ELSE channel_sms END,
          channel_line = CASE WHEN NULLIF(TRIM(COALESCE(v_row->>'user_accounts_channel_line', '')), '') IS NOT NULL AND NULLIF(TRIM(COALESCE(v_row->>'user_accounts_channel_line', '')), '') != '-' THEN v_channel_line ELSE channel_line END,
          channel_push = CASE WHEN NULLIF(TRIM(COALESCE(v_row->>'user_accounts_channel_push', '')), '') IS NOT NULL AND NULLIF(TRIM(COALESCE(v_row->>'user_accounts_channel_push', '')), '') != '-' THEN v_channel_push ELSE channel_push END,
          auth_user_id = COALESCE(auth_user_id, id)
        WHERE id = v_user_id;
        v_updated := v_updated + 1;
      END IF;

      -- Upsert user_address (one per user)
      INSERT INTO user_address (user_id, merchant_id, addressline_1, city, district, subdistrict, postcode)
      VALUES (
        v_user_id,
        p_merchant_id,
        NULLIF(TRIM(COALESCE(v_row->>'user_address_addressline_1', v_row->>'addressline_1')::TEXT), ''),
        NULLIF(TRIM(COALESCE(v_row->>'user_address_city', v_row->>'city')::TEXT), ''),
        NULLIF(TRIM(COALESCE(v_row->>'user_address_district', v_row->>'district')::TEXT), ''),
        NULLIF(TRIM(COALESCE(v_row->>'user_address_subdistrict', v_row->>'subdistrict')::TEXT), ''),
        NULLIF(TRIM(COALESCE(v_row->>'user_address_postcode', v_row->>'postcode')::TEXT), '')
      )
      ON CONFLICT (user_id) DO UPDATE SET
        addressline_1 = COALESCE(NULLIF(TRIM(COALESCE(v_row->>'user_address_addressline_1', v_row->>'addressline_1')::TEXT), ''), user_address.addressline_1),
        city = COALESCE(NULLIF(TRIM(COALESCE(v_row->>'user_address_city', v_row->>'city')::TEXT), ''), user_address.city),
        district = COALESCE(NULLIF(TRIM(COALESCE(v_row->>'user_address_district', v_row->>'district')::TEXT), ''), user_address.district),
        subdistrict = COALESCE(NULLIF(TRIM(COALESCE(v_row->>'user_address_subdistrict', v_row->>'subdistrict')::TEXT), ''), user_address.subdistrict),
        postcode = COALESCE(NULLIF(TRIM(COALESCE(v_row->>'user_address_postcode', v_row->>'postcode')::TEXT), ''), user_address.postcode);

      -- Optional: one USER_PROFILE form_submission per user (only if not exists)
      IF v_form_id IS NOT NULL AND NOT (SELECT EXISTS (SELECT 1 FROM form_submissions WHERE form_id = v_form_id AND user_id = v_user_id)) THEN
        INSERT INTO form_submissions (form_id, merchant_id, user_id, status, source)
        VALUES (v_form_id, p_merchant_id, v_user_id, 'draft', 'bulk_import');
      END IF;

      -- user_wallet: set points_balance to CSV value (initial balance)
      v_points_val := COALESCE((NULLIF(TRIM(COALESCE(v_row->>'user_wallet_points_balance', v_row->>'total_points', v_row->>'points_balance')::TEXT), '')::INTEGER), 0);
      IF v_points_val < 0 THEN v_points_val := 0; END IF;

      SELECT COALESCE(points_balance, 0) INTO v_balance_before FROM user_wallet WHERE user_id = v_user_id AND merchant_id = p_merchant_id;
      IF v_balance_before IS NULL THEN v_balance_before := 0; END IF;
      v_balance_after := v_points_val;

      INSERT INTO user_wallet (user_id, merchant_id, points_balance, ticket_balance)
      VALUES (v_user_id, p_merchant_id, v_points_val, 0)
      ON CONFLICT (user_id, merchant_id) DO UPDATE SET
        points_balance = v_points_val;

      -- Optional: wallet_ledger entry (when p_create_wallet_ledger_entry = true)
      IF p_create_wallet_ledger_entry AND v_points_val > 0 THEN
        INSERT INTO wallet_ledger (
          merchant_id, user_id, currency, transaction_type, amount, signed_amount,
          balance_before, balance_after, source_type, source_id, description, created_by
        ) VALUES (
          p_merchant_id, v_user_id, 'points'::currency, 'earn'::currency_transaction_type,
          v_points_val, v_points_val, v_balance_before, v_balance_after,
          'manual'::wallet_transaction_source_type, p_batch_id, 'bulk_import', 'bulk_import'
        );
      END IF;
    END LOOP;

    RETURN QUERY SELECT true, true, v_imported, v_updated, NULL::TEXT, NULL::JSONB, 0;
  EXCEPTION WHEN OTHERS THEN
    RETURN QUERY SELECT false, true, 0, 0, SQLERRM, NULL::JSONB, 0;
  END;
END;
$$;

COMMENT ON FUNCTION bulk_upsert_customers_from_import IS
  'Validates customer import rows (tel or line_id required; tel must start with + and country code; cap 100 errors), then upserts user_accounts (incl. auth_user_id=id for new users, persona_id, user_type, tier_id, tier_lock_downgrade, tier_locked_downgrade_until, channel_*), user_address, optional USER_PROFILE form_submission, user_wallet; optionally inserts wallet_ledger when p_create_wallet_ledger_entry. Duplicate match by (merchant_id, tel) OR (merchant_id, line_id).';
