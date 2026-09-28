-- bff_list_event_promos: applicable_events_count was a correlated subquery per promo
-- that scanned every merchant event with three EXISTS probes on lower(...) text
-- (46 promos x 7k events => ~2.6s for the Syngenta merchant). Compute the
-- (promo, event) pairs once as a set and join the counts in. Output is unchanged.

CREATE INDEX IF NOT EXISTS idx_event_promo_merchant ON public.event_promo (merchant_id);
CREATE INDEX IF NOT EXISTS idx_event_promo_rule_promo ON public.event_promo_rule (promo_id);

CREATE OR REPLACE FUNCTION public.bff_list_event_promos(p_event_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_merchant_id uuid;
  v_event_activity_group text;
  v_event_strategic_market text;
  v_data jsonb;
BEGIN
  v_merchant_id := get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN fn_response_error('Unauthorized', 'Merchant context required', 'UNAUTHORIZED');
  END IF;

  IF p_event_id IS NOT NULL THEN
    SELECT sem.activity_group, sem.strategic_market
    INTO v_event_activity_group, v_event_strategic_market
    FROM syngenta_events_master sem
    WHERE sem.id = p_event_id
      AND sem.merchant_id = v_merchant_id;

    IF NOT FOUND THEN
      RETURN fn_response_error('Not Found', 'Event not found', 'EVENT_NOT_FOUND');
    END IF;
  END IF;

  WITH ev AS (
    SELECT sem.id, sem.activity_group, sem.strategic_market
    FROM syngenta_events_master sem
    WHERE sem.merchant_id = v_merchant_id
  ),
  promo AS (
    SELECT ep.*
    FROM event_promo ep
    WHERE ep.merchant_id = v_merchant_id
      AND (
        p_event_id IS NULL
        OR ep.event_id = p_event_id
        OR EXISTS (
          SELECT 1 FROM event_promo_mapping epm
          WHERE epm.promo_id = ep.id
            AND epm.merchant_id = v_merchant_id
            AND epm.mapping_type = 'event'
            AND epm.event_id = p_event_id
        )
        OR EXISTS (
          SELECT 1 FROM event_promo_mapping epm
          WHERE epm.promo_id = ep.id
            AND epm.merchant_id = v_merchant_id
            AND epm.mapping_type = 'activity_group'
            AND v_event_activity_group IS NOT NULL
            AND lower(epm.activity_group) = lower(v_event_activity_group)
        )
        OR EXISTS (
          SELECT 1 FROM event_promo_mapping epm
          WHERE epm.promo_id = ep.id
            AND epm.merchant_id = v_merchant_id
            AND epm.mapping_type = 'strategic_market'
            AND v_event_strategic_market IS NOT NULL
            AND lower(epm.strategic_market) = lower(v_event_strategic_market)
        )
      )
  ),
  mapping AS (
    SELECT epm.*
    FROM event_promo_mapping epm
    WHERE epm.merchant_id = v_merchant_id
      AND epm.promo_id IN (SELECT id FROM promo)
  ),
  -- Distinct (promo, event) pairs across the four applicability paths.
  applicable_pairs AS (
    SELECT p.id AS promo_id, ev.id AS event_id
    FROM promo p JOIN ev ON ev.id = p.event_id
    UNION
    SELECT m.promo_id, ev.id
    FROM mapping m JOIN ev ON ev.id = m.event_id
    WHERE m.mapping_type = 'event'
    UNION
    SELECT m.promo_id, ev.id
    FROM mapping m
    JOIN ev ON ev.activity_group IS NOT NULL
           AND lower(ev.activity_group) = lower(m.activity_group)
    WHERE m.mapping_type = 'activity_group'
    UNION
    SELECT m.promo_id, ev.id
    FROM mapping m
    JOIN ev ON ev.strategic_market IS NOT NULL
           AND lower(ev.strategic_market) = lower(m.strategic_market)
    WHERE m.mapping_type = 'strategic_market'
  ),
  applicable_counts AS (
    SELECT promo_id, COUNT(*) AS applicable_events_count
    FROM applicable_pairs
    GROUP BY promo_id
  ),
  rule_counts AS (
    SELECT epr.promo_id, COUNT(*) AS rule_count
    FROM event_promo_rule epr
    WHERE epr.merchant_id = v_merchant_id
    GROUP BY epr.promo_id
  ),
  mapping_counts AS (
    SELECT m.promo_id, COUNT(*) AS mapping_count
    FROM mapping m
    GROUP BY m.promo_id
  ),
  claim_counts AS (
    SELECT epc.promo_id, COUNT(*) AS total_claims
    FROM event_promo_claim epc
    WHERE epc.merchant_id = v_merchant_id
    GROUP BY epc.promo_id
  ),
  mappings_json AS (
    SELECT
      m.promo_id,
      jsonb_agg(jsonb_build_object(
        'id', m.id,
        'mapping_type', m.mapping_type,
        'event_id', m.event_id,
        'event_code', sem.event_code,
        'event_name', sem.event_name,
        'activity_group', m.activity_group,
        'event_activity_group', sem.activity_group,
        'strategic_market', m.strategic_market,
        'event_strategic_market', sem.strategic_market
      ) ORDER BY m.mapping_type, COALESCE(sem.event_name, m.activity_group, m.strategic_market)) AS mappings
    FROM mapping m
    LEFT JOIN syngenta_events_master sem
      ON sem.id = m.event_id
     AND sem.merchant_id = v_merchant_id
    GROUP BY m.promo_id
  )
  SELECT jsonb_agg(jsonb_build_object(
    'id', s.id,
    'name', s.name,
    'description', s.description,
    'eval_mode', s.eval_mode,
    'max_claims_per_user', s.max_claims_per_user,
    'max_claims_per_user_total', s.max_claims_per_user_total,
    'max_claims_per_user_per_event', s.max_claims_per_user_per_event,
    'is_active', s.is_active,
    'sort_order', s.sort_order,
    'rule_count', s.rule_count,
    'mapping_count', s.mapping_count,
    'applicable_events_count', s.applicable_events_count,
    'total_claims', s.total_claims,
    'is_applicable_to_event', s.is_applicable_to_event,
    'folder_id', s.folder_id,
    'folder_name', s.folder_name,
    'mappings', s.mappings
  ) ORDER BY s.sort_order, s.name) INTO v_data
  FROM (
    SELECT
      ep.id,
      ep.name,
      ep.description,
      ep.eval_mode,
      ep.max_claims_per_user,
      ep.max_claims_per_user_total,
      ep.max_claims_per_user_per_event,
      ep.is_active,
      ep.sort_order,
      ep.folder_id,
      (SELECT f.name FROM event_promo_folder f WHERE f.id = ep.folder_id) AS folder_name,
      COALESCE(rc.rule_count, 0) AS rule_count,
      COALESCE(mc.mapping_count, 0) AS mapping_count,
      COALESCE(cc.total_claims, 0) AS total_claims,
      COALESCE(ac.applicable_events_count, 0) AS applicable_events_count,
      CASE
        WHEN p_event_id IS NULL THEN false
        ELSE (
          ep.event_id = p_event_id
          OR EXISTS (
            SELECT 1 FROM mapping m
            WHERE m.promo_id = ep.id
              AND m.mapping_type = 'event'
              AND m.event_id = p_event_id
          )
          OR EXISTS (
            SELECT 1 FROM mapping m
            WHERE m.promo_id = ep.id
              AND m.mapping_type = 'activity_group'
              AND v_event_activity_group IS NOT NULL
              AND lower(m.activity_group) = lower(v_event_activity_group)
          )
          OR EXISTS (
            SELECT 1 FROM mapping m
            WHERE m.promo_id = ep.id
              AND m.mapping_type = 'strategic_market'
              AND v_event_strategic_market IS NOT NULL
              AND lower(m.strategic_market) = lower(v_event_strategic_market)
          )
        )
      END AS is_applicable_to_event,
      COALESCE(mj.mappings, '[]'::jsonb) AS mappings
    FROM promo ep
    LEFT JOIN applicable_counts ac ON ac.promo_id = ep.id
    LEFT JOIN rule_counts rc ON rc.promo_id = ep.id
    LEFT JOIN mapping_counts mc ON mc.promo_id = ep.id
    LEFT JOIN claim_counts cc ON cc.promo_id = ep.id
    LEFT JOIN mappings_json mj ON mj.promo_id = ep.id
  ) s;

  RETURN fn_response_success('OK', 'Promos loaded', COALESCE(v_data, '[]'::jsonb));
EXCEPTION WHEN OTHERS THEN
  RETURN fn_response_error('Error', SQLERRM, SQLSTATE);
END;
$function$;
