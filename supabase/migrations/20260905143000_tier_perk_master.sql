-- Tier perks: reusable master data + tier assignments + ladder inheritance at read time

CREATE TABLE IF NOT EXISTS public.tier_perk_master (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    merchant_id uuid NOT NULL REFERENCES public.merchant_master(id) ON DELETE CASCADE,
    icon text NOT NULL DEFAULT '',
    header text NOT NULL,
    description text NOT NULL DEFAULT '',
    active_status boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_tier_perk_master_merchant
    ON public.tier_perk_master (merchant_id);

CREATE TABLE IF NOT EXISTS public.tier_perk_assignments (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    merchant_id uuid NOT NULL REFERENCES public.merchant_master(id) ON DELETE CASCADE,
    tier_id uuid NOT NULL REFERENCES public.tier_master(id) ON DELETE CASCADE,
    perk_id uuid NOT NULL REFERENCES public.tier_perk_master(id) ON DELETE RESTRICT,
    sort_order integer NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT tier_perk_assignments_tier_perk_unique UNIQUE (tier_id, perk_id)
);

CREATE INDEX IF NOT EXISTS idx_tier_perk_assignments_tier
    ON public.tier_perk_assignments (tier_id, sort_order);

CREATE INDEX IF NOT EXISTS idx_tier_perk_assignments_perk
    ON public.tier_perk_assignments (perk_id);

ALTER TABLE public.tier_perk_master ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tier_perk_assignments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated users read tier_perk_master" ON public.tier_perk_master;
CREATE POLICY "Authenticated users read tier_perk_master"
    ON public.tier_perk_master FOR SELECT
    USING (merchant_id = public.get_current_merchant_id());

DROP POLICY IF EXISTS "Admin full access tier_perk_master" ON public.tier_perk_master;
CREATE POLICY "Admin full access tier_perk_master"
    ON public.tier_perk_master FOR ALL
    USING (public.is_current_user_admin())
    WITH CHECK (public.is_current_user_admin());

DROP POLICY IF EXISTS "Authenticated users read tier_perk_assignments" ON public.tier_perk_assignments;
CREATE POLICY "Authenticated users read tier_perk_assignments"
    ON public.tier_perk_assignments FOR SELECT
    USING (merchant_id = public.get_current_merchant_id());

DROP POLICY IF EXISTS "Admin full access tier_perk_assignments" ON public.tier_perk_assignments;
CREATE POLICY "Admin full access tier_perk_assignments"
    ON public.tier_perk_assignments FOR ALL
    USING (public.is_current_user_admin())
    WITH CHECK (public.is_current_user_admin());

-- Ladder position within merchant + user_type (matches admin tier list ordering)
CREATE OR REPLACE FUNCTION public.fn_tier_ladder_position(p_tier_id uuid)
RETURNS integer
LANGUAGE sql
STABLE
AS $$
    WITH ranked AS (
        SELECT
            tm.id,
            ROW_NUMBER() OVER (
                PARTITION BY tm.merchant_id, tm.user_type
                ORDER BY tc.amount NULLS FIRST, tm.tier_name, tm.id
            )::integer AS ladder_position
        FROM public.tier_master tm
        LEFT JOIN public.tier_conditions tc
            ON tc.tier_id = tm.id
           AND tc.condition_type = 'upgrade'::public.tier_conditions_type
           AND tc.active_status IS TRUE
    )
    SELECT r.ladder_position
    FROM ranked r
    WHERE r.id = p_tier_id;
$$;

CREATE OR REPLACE FUNCTION public.fn_tier_perk_row_json(p_perk_id uuid, p_sort_order integer)
RETURNS jsonb
LANGUAGE sql
STABLE
AS $$
    SELECT jsonb_build_object(
        'id', pm.id,
        'icon', pm.icon,
        'header', pm.header,
        'description', pm.description,
        'sort_order', p_sort_order
    )
    FROM public.tier_perk_master pm
    WHERE pm.id = p_perk_id
      AND pm.active_status IS TRUE;
$$;

CREATE OR REPLACE FUNCTION public.fn_tier_own_perks_json(p_tier_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
AS $$
    SELECT COALESCE(
        jsonb_agg(
            public.fn_tier_perk_row_json(tpa.perk_id, tpa.sort_order)
            ORDER BY tpa.sort_order, tpa.created_at, tpa.id
        ),
        '[]'::jsonb
    )
    FROM public.tier_perk_assignments tpa
    JOIN public.tier_perk_master pm ON pm.id = tpa.perk_id AND pm.active_status IS TRUE
    WHERE tpa.tier_id = p_tier_id;
$$;

CREATE OR REPLACE FUNCTION public.fn_tier_inherited_perks_json(p_tier_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
AS $$
    WITH current_tier AS (
        SELECT tm.id, tm.merchant_id, tm.user_type, public.fn_tier_ladder_position(tm.id) AS ladder_pos
        FROM public.tier_master tm
        WHERE tm.id = p_tier_id
    ),
    lower_tiers AS (
        SELECT tm.id AS source_tier_id, tm.tier_name AS source_tier_name, ct.ladder_pos AS current_pos,
               public.fn_tier_ladder_position(tm.id) AS source_pos
        FROM public.tier_master tm
        JOIN current_tier ct
            ON ct.merchant_id = tm.merchant_id
           AND ct.user_type IS NOT DISTINCT FROM tm.user_type
        WHERE public.fn_tier_ladder_position(tm.id) < ct.ladder_pos
    )
    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'source_tier_id', lt.source_tier_id,
                'source_tier_name', lt.source_tier_name,
                'perks', public.fn_tier_own_perks_json(lt.source_tier_id)
            )
            ORDER BY lt.source_pos
        ),
        '[]'::jsonb
    )
    FROM lower_tiers lt
    WHERE jsonb_array_length(public.fn_tier_own_perks_json(lt.source_tier_id)) > 0;
$$;

CREATE OR REPLACE FUNCTION public.fn_tier_composed_perks_json(p_tier_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
AS $$
    WITH inherited AS (
        SELECT DISTINCT ON ((elem->>'id'))
            (elem->>'id')::uuid AS perk_id,
            elem AS perk_json,
            0 AS source_rank,
            COALESCE((elem->>'sort_order')::integer, 0) AS sort_order
        FROM jsonb_array_elements(public.fn_tier_inherited_perks_json(p_tier_id)) grp,
             jsonb_array_elements(grp->'perks') elem
        ORDER BY (elem->>'id'), COALESCE((elem->>'sort_order')::integer, 0)
    ),
    own AS (
        SELECT
            (elem->>'id')::uuid AS perk_id,
            elem AS perk_json,
            1 AS source_rank,
            COALESCE((elem->>'sort_order')::integer, 0) AS sort_order
        FROM jsonb_array_elements(public.fn_tier_own_perks_json(p_tier_id)) elem
    ),
    combined AS (
        SELECT * FROM inherited
        UNION ALL
        SELECT o.*
        FROM own o
        WHERE NOT EXISTS (SELECT 1 FROM inherited i WHERE i.perk_id = o.perk_id)
    ),
    numbered AS (
        SELECT
            c.perk_json - 'sort_order'
            || jsonb_build_object(
                'sort_order',
                row_number() OVER (ORDER BY c.source_rank, c.sort_order, c.perk_id)
            ) AS perk_json,
            row_number() OVER (ORDER BY c.source_rank, c.sort_order, c.perk_id) AS rn
        FROM combined c
    )
    SELECT COALESCE(jsonb_agg(n.perk_json ORDER BY n.rn), '[]'::jsonb)
    FROM numbered n;
$$;

CREATE OR REPLACE FUNCTION public.fn_sync_tier_master_benefits(p_tier_id uuid)
RETURNS void
LANGUAGE sql
AS $$
    UPDATE public.tier_master tm
    SET benefits = public.fn_tier_composed_perks_json(p_tier_id)
    WHERE tm.id = p_tier_id;
$$;

-- Backfill master rows + assignments from legacy JSONB (one master row per legacy line)
DO $$
DECLARE
    v_tier record;
    v_benefit record;
    v_perk_id uuid;
    v_benefits jsonb;
BEGIN
    FOR v_tier IN
        SELECT tm.id, tm.merchant_id, tm.benefits
        FROM public.tier_master tm
        WHERE NOT EXISTS (
            SELECT 1 FROM public.tier_perk_assignments tpa WHERE tpa.tier_id = tm.id
        )
    LOOP
        v_benefits := CASE
            WHEN jsonb_typeof(v_tier.benefits) = 'array' THEN v_tier.benefits
            ELSE '[]'::jsonb
        END;

        FOR v_benefit IN
            SELECT elem, ordinality
            FROM jsonb_array_elements(v_benefits) WITH ORDINALITY AS t(elem, ordinality)
        LOOP
            INSERT INTO public.tier_perk_master (merchant_id, icon, header, description)
            VALUES (
                v_tier.merchant_id,
                COALESCE(v_benefit.elem->>'icon', ''),
                COALESCE(NULLIF(btrim(v_benefit.elem->>'header'), ''), 'Untitled perk'),
                COALESCE(v_benefit.elem->>'description', '')
            )
            RETURNING id INTO v_perk_id;

            INSERT INTO public.tier_perk_assignments (merchant_id, tier_id, perk_id, sort_order)
            VALUES (v_tier.merchant_id, v_tier.id, v_perk_id, v_benefit.ordinality::integer);
        END LOOP;
    END LOOP;
END $$;

UPDATE public.tier_master tm
SET benefits = public.fn_tier_composed_perks_json(tm.id)
WHERE EXISTS (SELECT 1 FROM public.tier_perk_assignments tpa WHERE tpa.tier_id = tm.id);

CREATE OR REPLACE FUNCTION public.get_tier_display_config()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_merchant_id uuid;
  v_result json;
BEGIN
  v_merchant_id := public.get_current_merchant_id();

  IF v_merchant_id IS NULL THEN
    RETURN '[]'::json;
  END IF;

  SELECT json_agg(t)
  INTO v_result
  FROM (
    SELECT
      tm.id AS tier_id,
      tm.tier_name,
      tm.icon,
      tm.color,
      tm.card_design,
      public.fn_tier_composed_perks_json(tm.id) AS benefits,
      public.fn_tier_own_perks_json(tm.id) AS own_benefits,
      public.fn_tier_inherited_perks_json(tm.id) AS inherited_benefits,
      public.fn_tier_persona_ids(tm.id) AS persona_ids,
      public.fn_tier_personas_json(tm.id) AS personas
    FROM public.tier_master tm
    LEFT JOIN public.tier_conditions tcu
      ON tcu.tier_id = tm.id AND tcu.condition_type = 'upgrade' AND tcu.active_status IS TRUE
    WHERE tm.merchant_id = v_merchant_id
    ORDER BY tcu.amount ASC NULLS FIRST, tm.tier_name
  ) t;

  RETURN COALESCE(v_result, '[]'::json);
END;
$function$;

CREATE OR REPLACE FUNCTION public.bff_upsert_tier_display(
    p_tier_id uuid,
    p_display jsonb,
    p_language text DEFAULT 'en'::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_lang text;
    v_merchant_id UUID;
    v_tier_name TEXT;
BEGIN
    v_lang := fn_normalize_ui_language(p_language);
    v_merchant_id := get_current_merchant_id();
    IF v_merchant_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'code', 'NO_MERCHANT_CONTEXT', 'title', fn_admin_envelope_message('error_title', v_lang), 'description', fn_admin_envelope_message('no_merchant_found_title', v_lang));
    END IF;

    SELECT tier_name INTO v_tier_name
    FROM tier_master
    WHERE id = p_tier_id AND merchant_id = v_merchant_id;

    IF v_tier_name IS NULL THEN
        RETURN jsonb_build_object('success', false, 'code', 'NOT_FOUND', 'title', fn_admin_envelope_message('not_found_title', v_lang), 'description', fn_admin_envelope_message('tier_not_found_access_desc', v_lang));
    END IF;

    UPDATE tier_master SET
        icon = COALESCE(p_display->>'icon', icon),
        color = COALESCE(p_display->>'color', color),
        card_design = COALESCE(p_display->'card_design', card_design)
    WHERE id = p_tier_id AND merchant_id = v_merchant_id;

    RETURN jsonb_build_object(
        'success', true,
        'code', 'UPDATED',
        'title', fn_admin_envelope_message('display_updated_title', v_lang),
        'description', fn_admin_envelope_message('display_updated_desc', v_lang, ARRAY[v_tier_name]),
        'data', jsonb_build_object('tier_id', p_tier_id)
    );
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('success', false, 'code', 'ERROR', 'title', fn_admin_envelope_message('error_title', v_lang), 'description', SQLERRM, 'detail', SQLSTATE);
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_user_tier_progress(p_user_id uuid, p_merchant_id uuid)
RETURNS TABLE(
    current_tier_id uuid,
    current_tier_name text,
    current_tier_icon text,
    current_tier_color text,
    current_tier_benefits jsonb,
    current_tier_card_design jsonb,
    next_tier_id uuid,
    next_tier_name text,
    next_tier_icon text,
    next_tier_color text,
    next_tier_benefits jsonb,
    next_tier_card_design jsonb,
    upgrade_progress_percent numeric,
    upgrade_metric_needed metric,
    upgrade_deadline date,
    maintain_progress numeric,
    maintain_metric_needed metric,
    maintain_deadline date
)
LANGUAGE sql
STABLE SECURITY DEFINER
AS $function$
    SELECT
        tp.current_tier_id,
        ct.tier_name       AS current_tier_name,
        ct.icon            AS current_tier_icon,
        ct.color           AS current_tier_color,
        public.fn_tier_composed_perks_json(tp.current_tier_id) AS current_tier_benefits,
        ct.card_design     AS current_tier_card_design,
        tp.next_tier_id,
        nt.tier_name       AS next_tier_name,
        nt.icon            AS next_tier_icon,
        nt.color           AS next_tier_color,
        public.fn_tier_composed_perks_json(tp.next_tier_id) AS next_tier_benefits,
        nt.card_design     AS next_tier_card_design,
        tp.upgrade_progress_percent,
        tp.upgrade_metric_needed,
        tp.upgrade_deadline,
        tp.maintain_progress,
        tp.maintain_metric_needed,
        tp.maintain_deadline
    FROM tier_progress tp
    LEFT JOIN tier_master ct ON ct.id = tp.current_tier_id
    LEFT JOIN tier_master nt ON nt.id = tp.next_tier_id
    WHERE tp.user_id = p_user_id
      AND tp.merchant_id = p_merchant_id;
$function$;

CREATE OR REPLACE FUNCTION public.bff_list_tier_perks(p_language text DEFAULT 'en'::text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_lang text;
    v_merchant_id uuid;
    v_rows jsonb;
BEGIN
    v_lang := fn_normalize_ui_language(p_language);
    v_merchant_id := get_current_merchant_id();
    IF v_merchant_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'code', 'NO_MERCHANT_CONTEXT');
    END IF;

    SELECT COALESCE(jsonb_agg(row ORDER BY row->>'header'), '[]'::jsonb)
    INTO v_rows
    FROM (
        SELECT jsonb_build_object(
            'id', pm.id,
            'icon', pm.icon,
            'header', pm.header,
            'description', pm.description,
            'tiers', COALESCE((
                SELECT jsonb_agg(jsonb_build_object('tier_id', tm.id, 'tier_name', tm.tier_name) ORDER BY tm.tier_name)
                FROM public.tier_perk_assignments tpa
                JOIN public.tier_master tm ON tm.id = tpa.tier_id
                WHERE tpa.perk_id = pm.id
            ), '[]'::jsonb)
        ) AS row
        FROM public.tier_perk_master pm
        WHERE pm.merchant_id = v_merchant_id
          AND pm.active_status IS TRUE
    ) s;

    RETURN jsonb_build_object('success', true, 'data', v_rows);
END;
$function$;

CREATE OR REPLACE FUNCTION public.bff_upsert_tier_perk(
    p_perk jsonb,
    p_language text DEFAULT 'en'::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_lang text;
    v_merchant_id uuid;
    v_perk_id uuid;
    v_tiers jsonb;
BEGIN
    v_lang := fn_normalize_ui_language(p_language);
    v_merchant_id := get_current_merchant_id();
    IF v_merchant_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'code', 'NO_MERCHANT_CONTEXT');
    END IF;

    IF COALESCE(btrim(p_perk->>'header'), '') = '' THEN
        RETURN jsonb_build_object('success', false, 'code', 'VALIDATION', 'description', 'Perk title is required');
    END IF;

    v_perk_id := NULLIF(p_perk->>'id', '')::uuid;

    IF v_perk_id IS NULL THEN
        INSERT INTO public.tier_perk_master (merchant_id, icon, header, description)
        VALUES (
            v_merchant_id,
            COALESCE(p_perk->>'icon', ''),
            btrim(p_perk->>'header'),
            COALESCE(p_perk->>'description', '')
        )
        RETURNING id INTO v_perk_id;
    ELSE
        UPDATE public.tier_perk_master pm
        SET
            icon = COALESCE(p_perk->>'icon', icon),
            header = btrim(p_perk->>'header'),
            description = COALESCE(p_perk->>'description', description),
            updated_at = now()
        WHERE pm.id = v_perk_id
          AND pm.merchant_id = v_merchant_id;

        IF NOT FOUND THEN
            RETURN jsonb_build_object('success', false, 'code', 'NOT_FOUND');
        END IF;

        UPDATE public.tier_master tm
        SET benefits = public.fn_tier_composed_perks_json(tm.id)
        WHERE tm.id IN (
            SELECT tpa.tier_id FROM public.tier_perk_assignments tpa WHERE tpa.perk_id = v_perk_id
        );
    END IF;

    SELECT COALESCE(jsonb_agg(jsonb_build_object('tier_id', tm.id, 'tier_name', tm.tier_name) ORDER BY tm.tier_name), '[]'::jsonb)
    INTO v_tiers
    FROM public.tier_perk_assignments tpa
    JOIN public.tier_master tm ON tm.id = tpa.tier_id
    WHERE tpa.perk_id = v_perk_id;

    RETURN jsonb_build_object(
        'success', true,
        'data', jsonb_build_object(
            'id', v_perk_id,
            'icon', COALESCE(p_perk->>'icon', ''),
            'header', btrim(p_perk->>'header'),
            'description', COALESCE(p_perk->>'description', ''),
            'tiers', v_tiers
        )
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.bff_delete_tier_perk(
    p_perk_id uuid,
    p_language text DEFAULT 'en'::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_merchant_id uuid;
    v_assignment_count integer;
    v_affected_tiers uuid[];
BEGIN
    v_merchant_id := get_current_merchant_id();
    IF v_merchant_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'code', 'NO_MERCHANT_CONTEXT');
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.tier_perk_master pm
        WHERE pm.id = p_perk_id
          AND pm.merchant_id = v_merchant_id
    ) THEN
        RETURN jsonb_build_object('success', false, 'code', 'NOT_FOUND');
    END IF;

    SELECT COUNT(*) INTO v_assignment_count
    FROM public.tier_perk_assignments tpa
    WHERE tpa.perk_id = p_perk_id;

    IF v_assignment_count > 0 THEN
        RETURN jsonb_build_object('success', false, 'code', 'IN_USE', 'description', 'Remove this perk from all tiers before deleting it');
    END IF;

    DELETE FROM public.tier_perk_master pm
    WHERE pm.id = p_perk_id
      AND pm.merchant_id = v_merchant_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'code', 'NOT_FOUND');
    END IF;

    RETURN jsonb_build_object('success', true, 'code', 'DELETED');
END;
$function$;

CREATE OR REPLACE FUNCTION public.bff_assign_tier_perk(
    p_tier_id uuid,
    p_perk_id uuid,
    p_language text DEFAULT 'en'::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_merchant_id uuid;
    v_next_sort integer;
BEGIN
    v_merchant_id := get_current_merchant_id();
    IF v_merchant_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'code', 'NO_MERCHANT_CONTEXT');
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.tier_master tm
        WHERE tm.id = p_tier_id AND tm.merchant_id = v_merchant_id
    ) THEN
        RETURN jsonb_build_object('success', false, 'code', 'NOT_FOUND');
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.tier_perk_master pm
        WHERE pm.id = p_perk_id AND pm.merchant_id = v_merchant_id AND pm.active_status IS TRUE
    ) THEN
        RETURN jsonb_build_object('success', false, 'code', 'NOT_FOUND');
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.tier_perk_assignments tpa
        WHERE tpa.tier_id = p_tier_id AND tpa.perk_id = p_perk_id
    ) THEN
        RETURN jsonb_build_object('success', false, 'code', 'ALREADY_ASSIGNED');
    END IF;

    SELECT COALESCE(MAX(tpa.sort_order), 0) + 1
    INTO v_next_sort
    FROM public.tier_perk_assignments tpa
    WHERE tpa.tier_id = p_tier_id;

    INSERT INTO public.tier_perk_assignments (merchant_id, tier_id, perk_id, sort_order)
    VALUES (v_merchant_id, p_tier_id, p_perk_id, v_next_sort);

    PERFORM public.fn_sync_tier_master_benefits(p_tier_id);

    RETURN jsonb_build_object(
        'success', true,
        'data', jsonb_build_object(
            'tier_id', p_tier_id,
            'own_benefits', public.fn_tier_own_perks_json(p_tier_id),
            'inherited_benefits', public.fn_tier_inherited_perks_json(p_tier_id),
            'benefits', public.fn_tier_composed_perks_json(p_tier_id)
        )
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.bff_unassign_tier_perk(
    p_tier_id uuid,
    p_perk_id uuid,
    p_language text DEFAULT 'en'::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_merchant_id uuid;
    v_remaining_assignments integer;
BEGIN
    v_merchant_id := get_current_merchant_id();
    IF v_merchant_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'code', 'NO_MERCHANT_CONTEXT');
    END IF;

    DELETE FROM public.tier_perk_assignments tpa
    USING public.tier_master tm
    WHERE tpa.tier_id = p_tier_id
      AND tpa.perk_id = p_perk_id
      AND tm.id = tpa.tier_id
      AND tm.merchant_id = v_merchant_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'code', 'NOT_FOUND');
    END IF;

    PERFORM public.fn_sync_tier_master_benefits(p_tier_id);

    SELECT COUNT(*) INTO v_remaining_assignments
    FROM public.tier_perk_assignments tpa
    WHERE tpa.perk_id = p_perk_id;

    RETURN jsonb_build_object(
        'success', true,
        'data', jsonb_build_object(
            'tier_id', p_tier_id,
            'perk_orphaned', v_remaining_assignments = 0,
            'remaining_assignment_count', v_remaining_assignments,
            'own_benefits', public.fn_tier_own_perks_json(p_tier_id),
            'inherited_benefits', public.fn_tier_inherited_perks_json(p_tier_id),
            'benefits', public.fn_tier_composed_perks_json(p_tier_id)
        )
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.bff_reorder_tier_perks(
    p_tier_id uuid,
    p_perk_ids uuid[],
    p_language text DEFAULT 'en'::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_merchant_id uuid;
    v_idx integer;
    v_perk_id uuid;
BEGIN
    v_merchant_id := get_current_merchant_id();
    IF v_merchant_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'code', 'NO_MERCHANT_CONTEXT');
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.tier_master tm
        WHERE tm.id = p_tier_id AND tm.merchant_id = v_merchant_id
    ) THEN
        RETURN jsonb_build_object('success', false, 'code', 'NOT_FOUND');
    END IF;

    v_idx := 0;
    FOREACH v_perk_id IN ARRAY p_perk_ids LOOP
        v_idx := v_idx + 1;
        UPDATE public.tier_perk_assignments tpa
        SET sort_order = v_idx
        WHERE tpa.tier_id = p_tier_id
          AND tpa.perk_id = v_perk_id;
    END LOOP;

    PERFORM public.fn_sync_tier_master_benefits(p_tier_id);

    RETURN jsonb_build_object(
        'success', true,
        'data', jsonb_build_object(
            'own_benefits', public.fn_tier_own_perks_json(p_tier_id),
            'benefits', public.fn_tier_composed_perks_json(p_tier_id)
        )
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.bff_create_and_assign_tier_perk(
    p_tier_id uuid,
    p_perk jsonb,
    p_language text DEFAULT 'en'::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_upsert jsonb;
    v_perk_id uuid;
    v_assign jsonb;
BEGIN
    v_upsert := public.bff_upsert_tier_perk(p_perk, p_language);
    IF COALESCE((v_upsert->>'success')::boolean, false) IS NOT TRUE THEN
        RETURN v_upsert;
    END IF;

    v_perk_id := (v_upsert->'data'->>'id')::uuid;
    v_assign := public.bff_assign_tier_perk(p_tier_id, v_perk_id, p_language);
    RETURN v_assign;
END;
$function$;

GRANT SELECT ON public.tier_perk_master TO authenticated;
GRANT SELECT ON public.tier_perk_assignments TO authenticated;
GRANT ALL ON public.tier_perk_master TO service_role;
GRANT ALL ON public.tier_perk_assignments TO service_role;

GRANT EXECUTE ON FUNCTION public.fn_tier_ladder_position(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_tier_own_perks_json(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_tier_inherited_perks_json(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_tier_composed_perks_json(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.bff_list_tier_perks(text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.bff_upsert_tier_perk(jsonb, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.bff_delete_tier_perk(uuid, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.bff_assign_tier_perk(uuid, uuid, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.bff_unassign_tier_perk(uuid, uuid, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.bff_reorder_tier_perks(uuid, uuid[], text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.bff_create_and_assign_tier_perk(uuid, jsonb, text) TO authenticated, service_role;
