-- Replay qualifying ticket earns onto tickets_earned missions whose
-- earn_source_type is NULL (admin does not send a wallet source filter).
-- Inactive missions are flipped only inside this transaction so
-- fn_update_mission_progress can run; original is_active is restored
-- before commit. Idempotent via mission_progress_events.trigger_id.

DO $bf$
DECLARE
  r record;
  v_inc jsonb;
  v_res jsonb;
  v_saved jsonb;
  v_applied int := 0;
  v_skipped_empty int := 0;
  v_dup int := 0;
BEGIN
  SELECT COALESCE(jsonb_agg(jsonb_build_object('id', s.id, 'is_active', s.is_active)), '[]'::jsonb)
  INTO v_saved
  FROM (
    SELECT DISTINCT m.id, m.is_active
    FROM mission m
    JOIN mission_conditions c ON c.mission_id = m.id
    WHERE c.condition_type = 'tickets_earned'
      AND c.earn_source_type IS NULL
  ) s;

  IF jsonb_array_length(v_saved) = 0 THEN
    RETURN;
  END IF;

  UPDATE mission m
  SET is_active = true
  WHERE m.id IN (SELECT (e->>'id')::uuid FROM jsonb_array_elements(v_saved) e)
    AND m.is_active IS DISTINCT FROM true;

  FOR r IN
    SELECT m.id AS mission_id,
           m.merchant_id,
           wl.user_id,
           wl.id AS ledger_id,
           wl.amount,
           wl.target_entity_id,
           wl.source_type::text AS source_type,
           wl.currency::text AS currency,
           wl.transaction_type::text AS transaction_type
    FROM mission m
    JOIN mission_conditions c ON c.mission_id = m.id
    JOIN wallet_ledger wl
      ON wl.merchant_id = m.merchant_id
     AND wl.currency = 'ticket'
     AND wl.transaction_type = 'earn'
     AND (
       c.ticket_type_id IS NULL
       OR cardinality(c.ticket_type_id) = 0
       OR wl.target_entity_id = ANY (c.ticket_type_id)
     )
    WHERE c.condition_type = 'tickets_earned'
      AND c.earn_source_type IS NULL
      AND NOT EXISTS (
        SELECT 1
        FROM mission_progress_events e
        WHERE e.user_id = wl.user_id
          AND e.mission_id = m.id
          AND e.trigger_id = wl.id
      )
    ORDER BY wl.created_at, wl.id
  LOOP
    v_inc := fn_evaluate_mission_conditions(
      r.mission_id,
      r.merchant_id,
      r.user_id,
      'tickets_earned',
      jsonb_build_object(
        'amount', r.amount,
        'target_entity_id', r.target_entity_id,
        'source_type', r.source_type,
        'currency', r.currency,
        'transaction_type', r.transaction_type
      )
    );

    IF v_inc IS NULL OR v_inc = '{}'::jsonb THEN
      v_skipped_empty := v_skipped_empty + 1;
      CONTINUE;
    END IF;

    v_res := fn_update_mission_progress(
      r.user_id,
      r.mission_id,
      r.merchant_id,
      v_inc,
      'tickets_earned',
      r.ledger_id
    );

    IF COALESCE(v_res->>'success', 'false') <> 'true' THEN
      RAISE EXCEPTION 'backfill update failed user=% mission=% ledger=% res=%',
        r.user_id, r.mission_id, r.ledger_id, v_res;
    END IF;

    IF v_res->>'reason' IN ('cannot_progress', 'inactive', 'exclusivity_locked') THEN
      RAISE EXCEPTION 'backfill blocked user=% mission=% ledger=% res=%',
        r.user_id, r.mission_id, r.ledger_id, v_res;
    END IF;

    IF v_res->>'reason' = 'duplicate_event' THEN
      v_dup := v_dup + 1;
    ELSE
      v_applied := v_applied + 1;
    END IF;
  END LOOP;

  UPDATE mission m
  SET is_active = (e->>'is_active')::boolean
  FROM jsonb_array_elements(v_saved) e
  WHERE m.id = (e->>'id')::uuid;

  RAISE NOTICE 'tickets_earned backfill applied=% duplicate=% empty_eval=%',
    v_applied, v_dup, v_skipped_empty;
END
$bf$;
