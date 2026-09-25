-- Tier entry rewards: per-tier welcome grants on upgrade (once per member per line)

ALTER TYPE public.wallet_transaction_source_type ADD VALUE IF NOT EXISTS 'tier_entry_reward';

CREATE TABLE IF NOT EXISTS public.tier_entry_rewards (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    merchant_id uuid NOT NULL REFERENCES public.merchant_master(id) ON DELETE CASCADE,
    tier_id uuid NOT NULL REFERENCES public.tier_master(id) ON DELETE CASCADE,
    sort_order integer NOT NULL DEFAULT 1,
    reward_kind text NOT NULL,
    points_amount integer,
    description text,
    reward_id uuid REFERENCES public.reward_master(id) ON DELETE RESTRICT,
    quantity integer,
    active_status boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT tier_entry_rewards_kind_check CHECK (
        reward_kind IN ('points', 'reward')
    ),
    CONSTRAINT tier_entry_rewards_payload_check CHECK (
        (
            reward_kind = 'points'
            AND points_amount IS NOT NULL
            AND points_amount > 0
            AND reward_id IS NULL
            AND quantity IS NULL
        )
        OR (
            reward_kind = 'reward'
            AND reward_id IS NOT NULL
            AND COALESCE(quantity, 1) >= 1
            AND points_amount IS NULL
        )
    )
);

CREATE INDEX IF NOT EXISTS idx_tier_entry_rewards_tier
    ON public.tier_entry_rewards (merchant_id, tier_id, sort_order);

CREATE TABLE IF NOT EXISTS public.tier_entry_reward_grants (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    merchant_id uuid NOT NULL REFERENCES public.merchant_master(id) ON DELETE CASCADE,
    tier_id uuid NOT NULL REFERENCES public.tier_master(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES public.user_accounts(id) ON DELETE CASCADE,
    tier_entry_reward_id uuid NOT NULL REFERENCES public.tier_entry_rewards(id) ON DELETE CASCADE,
    granted_at timestamptz NOT NULL DEFAULT now(),
    grant_status text NOT NULL DEFAULT 'granted',
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT tier_entry_reward_grants_status_check CHECK (
        grant_status IN ('pending', 'granted', 'failed')
    ),
    CONSTRAINT tier_entry_reward_grants_unique
        UNIQUE (merchant_id, tier_id, user_id, tier_entry_reward_id)
);

CREATE INDEX IF NOT EXISTS idx_tier_entry_reward_grants_tier_user
    ON public.tier_entry_reward_grants (tier_id, user_id);

DROP TRIGGER IF EXISTS trg_tier_entry_rewards_updated_at ON public.tier_entry_rewards;
CREATE TRIGGER trg_tier_entry_rewards_updated_at
    BEFORE UPDATE ON public.tier_entry_rewards
    FOR EACH ROW
    EXECUTE FUNCTION public.trigger_set_updated_at();

ALTER TABLE public.tier_entry_rewards ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tier_entry_reward_grants ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "merchant_isolation" ON public.tier_entry_rewards;
CREATE POLICY "merchant_isolation" ON public.tier_entry_rewards
    FOR ALL
    USING (merchant_id = public.get_current_merchant_id())
    WITH CHECK (merchant_id = public.get_current_merchant_id());

DROP POLICY IF EXISTS "merchant_isolation" ON public.tier_entry_reward_grants;
CREATE POLICY "merchant_isolation" ON public.tier_entry_reward_grants
    FOR ALL
    USING (merchant_id = public.get_current_merchant_id())
    WITH CHECK (merchant_id = public.get_current_merchant_id());

COMMENT ON TABLE public.tier_entry_rewards IS
    'Per-tier welcome package. Granted on upgrade into the tier, once per member per line.';
COMMENT ON TABLE public.tier_entry_reward_grants IS
    'Idempotency log for tier entry rewards. UNIQUE (merchant, tier, user, line) enforces once-ever.';

CREATE OR REPLACE FUNCTION public.fn_grant_tier_entry_rewards(
    p_user_id uuid,
    p_merchant_id uuid,
    p_to_tier_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_row public.tier_entry_rewards%ROWTYPE;
    v_grant_id uuid;
    v_result jsonb;
    v_dedup text;
    v_description text;
BEGIN
    IF p_user_id IS NULL OR p_merchant_id IS NULL OR p_to_tier_id IS NULL THEN
        RETURN;
    END IF;

    FOR v_row IN
        SELECT *
        FROM public.tier_entry_rewards ter
        WHERE ter.merchant_id = p_merchant_id
          AND ter.tier_id = p_to_tier_id
          AND ter.active_status IS TRUE
        ORDER BY ter.sort_order, ter.created_at, ter.id
    LOOP
        v_grant_id := NULL;
        v_result := NULL;
        v_dedup := format('tier_entry:%s:%s:%s', p_to_tier_id, p_user_id, v_row.id);

        BEGIN
            INSERT INTO public.tier_entry_reward_grants (
                merchant_id,
                tier_id,
                user_id,
                tier_entry_reward_id,
                grant_status,
                granted_at,
                metadata
            )
            VALUES (
                p_merchant_id,
                p_to_tier_id,
                p_user_id,
                v_row.id,
                'pending',
                now(),
                '{}'::jsonb
            )
            ON CONFLICT ON CONSTRAINT tier_entry_reward_grants_unique
            DO UPDATE SET
                grant_status = 'pending',
                metadata = '{}'::jsonb
            WHERE public.tier_entry_reward_grants.grant_status = 'failed'
            RETURNING id INTO v_grant_id;

            IF v_grant_id IS NULL THEN
                CONTINUE;
            END IF;

            IF v_row.reward_kind = 'points' THEN
                v_description := COALESCE(
                    NULLIF(btrim(v_row.description), ''),
                    format('Tier entry reward (%s points)', v_row.points_amount)
                );
                v_result := public.fn_dispatch_outcome(
                    p_user_id := p_user_id,
                    p_merchant_id := p_merchant_id,
                    p_outcome_type := 'points',
                    p_entity_id := NULL,
                    p_amount := v_row.points_amount,
                    p_source_type := 'tier_entry_reward',
                    p_source_id := v_row.id,
                    p_metadata := jsonb_build_object(
                        'description', v_description,
                        'tier_id', p_to_tier_id
                    ),
                    p_dedup_key := v_dedup
                );
            ELSE
                v_result := public.fn_dispatch_outcome(
                    p_user_id := p_user_id,
                    p_merchant_id := p_merchant_id,
                    p_outcome_type := 'reward',
                    p_entity_id := v_row.reward_id,
                    p_amount := COALESCE(v_row.quantity, 1),
                    p_source_type := 'tier_entry_reward',
                    p_source_id := v_row.id,
                    p_metadata := jsonb_build_object(
                        'description', 'Tier entry reward',
                        'tier_id', p_to_tier_id
                    ),
                    p_dedup_key := v_dedup
                );
            END IF;

            IF COALESCE((v_result->>'success')::boolean, false) THEN
                UPDATE public.tier_entry_reward_grants
                SET grant_status = 'granted',
                    granted_at = now(),
                    metadata = COALESCE(v_result, '{}'::jsonb)
                WHERE id = v_grant_id;
            ELSE
                UPDATE public.tier_entry_reward_grants
                SET grant_status = 'failed',
                    metadata = COALESCE(v_result, jsonb_build_object('error', 'dispatch failed'))
                WHERE id = v_grant_id;
            END IF;
        EXCEPTION WHEN OTHERS THEN
            IF v_grant_id IS NOT NULL THEN
                UPDATE public.tier_entry_reward_grants
                SET grant_status = 'failed',
                    metadata = jsonb_build_object('error', SQLERRM)
                WHERE id = v_grant_id;
            END IF;
        END;
    END LOOP;
END;
$function$;

CREATE OR REPLACE FUNCTION public.apply_tier_change(
    p_user_id uuid,
    p_merchant_id uuid,
    p_to_tier_id uuid,
    p_change_type text DEFAULT 'upgrade'::text,
    p_pending_id uuid DEFAULT NULL::uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_result jsonb;
  v_as_of date := (timezone('Asia/Bangkok', now()))::date;
BEGIN
  v_result := public.apply_tier_change_core(
    p_user_id, p_merchant_id, p_to_tier_id, p_change_type, p_pending_id
  );

  -- Core calls ensure_tier_progress which is already mode-aware for custom.
  -- Re-upsert custom progress explicitly so bar numbers win over any standard crumbs.
  IF public.fn_loyalty_is_custom_tier(p_merchant_id) THEN
    PERFORM public.fn_loyalty_cache_upsert_tier_progress(
      p_merchant_id, ARRAY[p_user_id], v_as_of
    );
    -- Clear standard maintain deadlines on tracking when present
    IF to_regclass('public.tier_evaluation_tracking') IS NOT NULL THEN
      UPDATE public.tier_evaluation_tracking tet
      SET maintain_deadline = NULL,
          updated_at = now()
      WHERE tet.user_id = p_user_id
        AND tet.merchant_id = p_merchant_id;
    END IF;
  END IF;

  IF COALESCE((v_result->>'success')::boolean, false)
     AND COALESCE((v_result->>'skipped')::boolean, false) IS NOT TRUE
     AND p_change_type = 'upgrade'
     AND p_to_tier_id IS NOT NULL THEN
    BEGIN
      PERFORM public.fn_grant_tier_entry_rewards(p_user_id, p_merchant_id, p_to_tier_id);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'tier entry rewards failed for user % tier %: %',
        p_user_id, p_to_tier_id, SQLERRM;
    END;
  END IF;

  RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.bff_get_tier_entry_rewards(
    p_tier_id uuid,
    p_language text DEFAULT 'en'::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_lang text;
    v_merchant_id uuid;
    v_rewards jsonb;
    v_catalog jsonb;
BEGIN
    v_lang := fn_normalize_ui_language(p_language);
    v_merchant_id := get_current_merchant_id();
    IF v_merchant_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'code', 'NO_MERCHANT_CONTEXT',
            'title', fn_admin_envelope_message('error_title', v_lang),
            'description', fn_admin_envelope_message('no_merchant_found_title', v_lang)
        );
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.tier_master tm
        WHERE tm.id = p_tier_id AND tm.merchant_id = v_merchant_id
    ) THEN
        RETURN jsonb_build_object(
            'success', false,
            'code', 'NOT_FOUND',
            'title', fn_admin_envelope_message('not_found_title', v_lang),
            'description', fn_admin_envelope_message('tier_not_found_access_desc', v_lang)
        );
    END IF;

    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'id', ter.id,
                'reward_kind', ter.reward_kind,
                'points_amount', ter.points_amount,
                'description', ter.description,
                'reward_id', ter.reward_id,
                'reward_name', rm.name,
                'shopify_discount_type', rm.shopify_discount_type,
                'quantity', ter.quantity,
                'sort_order', ter.sort_order,
                'redeemed_count', COALESCE(g.granted_count, 0)
            )
            ORDER BY ter.sort_order, ter.created_at, ter.id
        ),
        '[]'::jsonb
    )
    INTO v_rewards
    FROM public.tier_entry_rewards ter
    LEFT JOIN public.reward_master rm
        ON rm.id = ter.reward_id AND rm.merchant_id = ter.merchant_id
    LEFT JOIN LATERAL (
        SELECT COUNT(*)::integer AS granted_count
        FROM public.tier_entry_reward_grants gr
        WHERE gr.tier_entry_reward_id = ter.id
          AND gr.grant_status = 'granted'
    ) g ON TRUE
    WHERE ter.merchant_id = v_merchant_id
      AND ter.tier_id = p_tier_id
      AND ter.active_status IS TRUE;

    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'id', r.id,
                'name', r.name,
                'shopify_discount_type', r.shopify_discount_type,
                'visibility', r.visibility,
                'assign_promocode', r.assign_promocode
            )
            ORDER BY r.name
        ),
        '[]'::jsonb
    )
    INTO v_catalog
    FROM public.reward_master r
    WHERE r.merchant_id = v_merchant_id
      AND r.active_status IS TRUE
      AND COALESCE(r.visibility::text, 'user') IS DISTINCT FROM 'user_only';

    RETURN jsonb_build_object(
        'success', true,
        'data', jsonb_build_object(
            'tier_id', p_tier_id,
            'rewards', v_rewards,
            'catalog', v_catalog
        )
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.bff_upsert_tier_entry_rewards(
    p_tier_id uuid,
    p_rewards jsonb,
    p_language text DEFAULT 'en'::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_lang text;
    v_merchant_id uuid;
    v_elem jsonb;
    v_id uuid;
    v_kind text;
    v_points integer;
    v_description text;
    v_reward_id uuid;
    v_quantity integer;
    v_sort integer := 0;
    v_keep uuid[] := ARRAY[]::uuid[];
    v_new_id uuid;
BEGIN
    v_lang := fn_normalize_ui_language(p_language);
    v_merchant_id := get_current_merchant_id();
    IF v_merchant_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'code', 'NO_MERCHANT_CONTEXT',
            'title', fn_admin_envelope_message('error_title', v_lang),
            'description', fn_admin_envelope_message('no_merchant_found_title', v_lang)
        );
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.tier_master tm
        WHERE tm.id = p_tier_id AND tm.merchant_id = v_merchant_id
    ) THEN
        RETURN jsonb_build_object(
            'success', false,
            'code', 'NOT_FOUND',
            'title', fn_admin_envelope_message('not_found_title', v_lang),
            'description', fn_admin_envelope_message('tier_not_found_access_desc', v_lang)
        );
    END IF;

    IF p_rewards IS NULL OR jsonb_typeof(p_rewards) <> 'array' THEN
        RETURN jsonb_build_object(
            'success', false,
            'code', 'VALIDATION_ERROR',
            'title', fn_admin_envelope_message('error_title', v_lang),
            'description', 'Entry rewards payload must be an array'
        );
    END IF;

    FOR v_elem IN SELECT value FROM jsonb_array_elements(p_rewards)
    LOOP
        v_sort := v_sort + 1;
        v_kind := NULLIF(btrim(v_elem->>'reward_kind'), '');
        v_id := NULLIF(v_elem->>'id', '')::uuid;
        v_points := NULL;
        v_description := NULL;
        v_reward_id := NULL;
        v_quantity := NULL;

        IF v_kind = 'points' THEN
            BEGIN
                v_points := (v_elem->>'points_amount')::integer;
            EXCEPTION WHEN OTHERS THEN
                v_points := NULL;
            END;
            v_description := NULLIF(btrim(v_elem->>'description'), '');
            IF v_points IS NULL OR v_points <= 0 THEN
                RETURN jsonb_build_object(
                    'success', false,
                    'code', 'VALIDATION_ERROR',
                    'title', fn_admin_envelope_message('error_title', v_lang),
                    'description', 'Points amount must be greater than zero'
                );
            END IF;
        ELSIF v_kind = 'reward' THEN
            v_reward_id := NULLIF(v_elem->>'reward_id', '')::uuid;
            BEGIN
                v_quantity := COALESCE(NULLIF(v_elem->>'quantity', '')::integer, 1);
            EXCEPTION WHEN OTHERS THEN
                v_quantity := 1;
            END;
            IF v_reward_id IS NULL THEN
                RETURN jsonb_build_object(
                    'success', false,
                    'code', 'VALIDATION_ERROR',
                    'title', fn_admin_envelope_message('error_title', v_lang),
                    'description', 'Reward is required'
                );
            END IF;
            IF v_quantity < 1 THEN
                RETURN jsonb_build_object(
                    'success', false,
                    'code', 'VALIDATION_ERROR',
                    'title', fn_admin_envelope_message('error_title', v_lang),
                    'description', 'Quantity must be at least 1'
                );
            END IF;
            IF NOT EXISTS (
                SELECT 1
                FROM public.reward_master rm
                WHERE rm.id = v_reward_id
                  AND rm.merchant_id = v_merchant_id
                  AND rm.active_status IS TRUE
                  AND COALESCE(rm.visibility::text, 'user') IS DISTINCT FROM 'user_only'
            ) THEN
                RETURN jsonb_build_object(
                    'success', false,
                    'code', 'VALIDATION_ERROR',
                    'title', fn_admin_envelope_message('error_title', v_lang),
                    'description', 'Reward must be active, belong to this merchant, and be pushable (not user-only)'
                );
            END IF;
        ELSE
            RETURN jsonb_build_object(
                'success', false,
                'code', 'VALIDATION_ERROR',
                'title', fn_admin_envelope_message('error_title', v_lang),
                'description', 'Each entry reward must be points or a catalog reward'
            );
        END IF;

        IF v_id IS NOT NULL THEN
            UPDATE public.tier_entry_rewards
            SET sort_order = v_sort,
                reward_kind = v_kind,
                points_amount = v_points,
                description = v_description,
                reward_id = v_reward_id,
                quantity = v_quantity,
                active_status = true
            WHERE id = v_id
              AND merchant_id = v_merchant_id
              AND tier_id = p_tier_id;
            IF NOT FOUND THEN
                RETURN jsonb_build_object(
                    'success', false,
                    'code', 'NOT_FOUND',
                    'title', fn_admin_envelope_message('not_found_title', v_lang),
                    'description', 'Entry reward line was not found on this tier'
                );
            END IF;
            v_keep := array_append(v_keep, v_id);
        ELSE
            INSERT INTO public.tier_entry_rewards (
                merchant_id,
                tier_id,
                sort_order,
                reward_kind,
                points_amount,
                description,
                reward_id,
                quantity,
                active_status
            )
            VALUES (
                v_merchant_id,
                p_tier_id,
                v_sort,
                v_kind,
                v_points,
                v_description,
                v_reward_id,
                v_quantity,
                true
            )
            RETURNING id INTO v_new_id;
            v_keep := array_append(v_keep, v_new_id);
        END IF;
    END LOOP;

    DELETE FROM public.tier_entry_rewards
    WHERE merchant_id = v_merchant_id
      AND tier_id = p_tier_id
      AND (cardinality(v_keep) = 0 OR id <> ALL (v_keep));

    RETURN public.bff_get_tier_entry_rewards(p_tier_id, p_language);
END;
$function$;

GRANT SELECT ON public.tier_entry_rewards TO authenticated;
GRANT SELECT ON public.tier_entry_reward_grants TO authenticated;
GRANT ALL ON public.tier_entry_rewards TO service_role;
GRANT ALL ON public.tier_entry_reward_grants TO service_role;

GRANT EXECUTE ON FUNCTION public.fn_grant_tier_entry_rewards(uuid, uuid, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.bff_get_tier_entry_rewards(uuid, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.bff_upsert_tier_entry_rewards(uuid, jsonb, text) TO authenticated, service_role;
