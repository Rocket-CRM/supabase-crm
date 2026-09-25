-- Close out purchase currency bookkeeping when earn calc returns nothing to award.
-- Award routers call calc_currency_for_source; previously only wallet earn writes stamped
-- currency_processed_at, so $0 / sub-minimum purchases stayed "stuck" in recon.

CREATE OR REPLACE FUNCTION public.calc_currency_for_source(
  p_source_type wallet_transaction_source_type,
  p_source_id uuid,
  p_user_id uuid,
  p_merchant_id uuid,
  p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS TABLE(
  currency_type currency,
  component currency_component,
  amount integer,
  target_entity_id uuid,
  description text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_record RECORD;
  v_code_points numeric;
  v_milestone_level integer;
  v_row_count integer;
BEGIN
  CASE p_source_type
    WHEN 'purchase' THEN
      RETURN QUERY
      SELECT
        cft.currency_type,
        cft.component,
        cft.amount,
        cft.target_entity_id,
        'Purchase earn'::text
      FROM calc_currency_for_transaction(p_source_id) cft;

      GET DIAGNOSTICS v_row_count = ROW_COUNT;
      IF v_row_count = 0 THEN
        IF EXISTS (
          SELECT 1
          FROM public.purchase_ledger pl
          WHERE pl.id = p_source_id
            AND pl.merchant_id = p_merchant_id
            AND pl.earn_currency = true
            AND pl.status = 'completed'::purchase_status
            AND pl.currency_processed_at IS NULL
        ) THEN
          PERFORM public.fn_stamp_currency_processed_for_earn(
            'purchase'::wallet_transaction_source_type,
            p_source_id,
            p_merchant_id
          );
        END IF;
      END IF;

    WHEN 'purchase_item' THEN
      RETURN QUERY
      SELECT
        cfpi.currency_type,
        cfpi.component,
        cfpi.amount,
        cfpi.target_entity_id,
        'Purchase item earn'::text
      FROM calc_currency_for_purchase_item(p_source_id) cfpi;

      GET DIAGNOSTICS v_row_count = ROW_COUNT;
      IF v_row_count = 0 THEN
        IF EXISTS (
          SELECT 1
          FROM public.purchase_items_ledger pil
          WHERE pil.id = p_source_id
            AND pil.merchant_id = p_merchant_id
            AND pil.currency_processed_at IS NULL
        ) THEN
          PERFORM public.fn_stamp_currency_processed_for_earn(
            'purchase_item'::wallet_transaction_source_type,
            p_source_id,
            p_merchant_id
          );
        END IF;
      END IF;

    WHEN 'referral' THEN
      FOR v_record IN
        SELECT rio.outcome_type, rio.amount, rio.entity_id
        FROM referral_invitee_outcomes rio
        WHERE rio.merchant_id = p_merchant_id
      LOOP
        CASE v_record.outcome_type::text
          WHEN 'points' THEN
            RETURN QUERY
            SELECT
              'points'::currency,
              'bonus'::currency_component,
              v_record.amount::integer,
              NULL::uuid,
              'Referral signup reward'::text;
          WHEN 'tickets' THEN
            RETURN QUERY
            SELECT
              'ticket'::currency,
              'base'::currency_component,
              v_record.amount::integer,
              v_record.entity_id,
              'Referral signup reward'::text;
        END CASE;
      END LOOP;

    WHEN 'mission' THEN
      v_milestone_level := (p_metadata->>'milestone_level')::integer;
      FOR v_record IN
        SELECT mo.outcome_type, mo.amount, mo.entity_id
        FROM mission_outcomes mo
        WHERE mo.mission_id = p_source_id
          AND (
            (v_milestone_level IS NOT NULL AND mo.milestone_level = v_milestone_level)
            OR (v_milestone_level IS NULL AND mo.milestone_level IS NULL)
          )
          AND mo.outcome_type IN ('points', 'tickets')
      LOOP
        CASE v_record.outcome_type::text
          WHEN 'points' THEN
            RETURN QUERY
            SELECT
              'points'::currency,
              'base'::currency_component,
              v_record.amount::integer,
              NULL::uuid,
              'Mission completion reward'::text;
          WHEN 'tickets' THEN
            RETURN QUERY
            SELECT
              'ticket'::currency,
              'base'::currency_component,
              v_record.amount::integer,
              v_record.entity_id,
              'Mission completion reward'::text;
        END CASE;
      END LOOP;

    WHEN 'code' THEN
      SELECT c.points
      INTO v_code_points
      FROM codes c
      WHERE c.id = p_source_id::bigint;

      IF v_code_points IS NOT NULL AND v_code_points > 0 THEN
        RETURN QUERY
        SELECT
          'points'::currency,
          'base'::currency_component,
          v_code_points::integer,
          NULL::uuid,
          'Code redemption'::text;
      END IF;

    WHEN 'campaign' THEN
      RETURN QUERY
      SELECT
        COALESCE((p_metadata->>'currency_type')::currency, 'points'::currency),
        COALESCE((p_metadata->>'component')::currency_component, 'bonus'::currency_component),
        (p_metadata->>'amount')::integer,
        (p_metadata->>'target_entity_id')::uuid,
        COALESCE(p_metadata->>'description', 'Campaign reward')::text;

    WHEN 'manual' THEN
      FOR v_record IN
        SELECT mcr.currency_type, mcr.amount, mcr.ticket_type_id, mcr.reason
        FROM manual_currency_request_ledger mcr
        WHERE mcr.id = p_source_id
          AND mcr.status IN ('pending', 'processing')
      LOOP
        IF v_record.currency_type = 'points' THEN
          RETURN QUERY
          SELECT
            'points'::currency,
            'adjustment'::currency_component,
            v_record.amount::integer,
            NULL::uuid,
            COALESCE(v_record.reason, 'Manual adjustment')::text;
        ELSIF v_record.currency_type = 'tickets' THEN
          RETURN QUERY
          SELECT
            'ticket'::currency,
            'adjustment'::currency_component,
            v_record.amount::integer,
            v_record.ticket_type_id,
            COALESCE(v_record.reason, 'Manual adjustment')::text;
        END IF;
      END LOOP;

    ELSE
      RETURN;
  END CASE;
END;
$function$;

-- Backfill zero-award bookkeeping only: $0 purchases, or sub-1 THB where the earn
-- pipeline already ran (outbox published) and no wallet row was expected.
UPDATE public.purchase_ledger pl
SET
  currency_processed_at = COALESCE(
    (
      SELECT MIN(o.published_at)
      FROM public.chokepoint_event_outbox o
      WHERE o.topic = 'crm.events.purchase'
        AND o.partition_key = pl.id::text
        AND o.published_at IS NOT NULL
    ),
    pl.created_at
  ),
  currency_error = NULL,
  updated_at = now()
WHERE pl.earn_currency = true
  AND pl.status = 'completed'::purchase_status
  AND pl.currency_processed_at IS NULL
  AND NOT EXISTS (
    SELECT 1
    FROM public.wallet_ledger wl
    WHERE wl.merchant_id = pl.merchant_id
      AND wl.transaction_type = 'earn'::currency_transaction_type
      AND (
        wl.source_id = pl.id
        OR wl.reference_id = pl.id
        OR wl.target_entity_id = pl.id
      )
  )
  AND (
    pl.total_amount = 0
    OR (
      pl.total_amount > 0
      AND pl.total_amount < 1
      AND EXISTS (
        SELECT 1
        FROM public.chokepoint_event_outbox o
        WHERE o.topic = 'crm.events.purchase'
          AND o.partition_key = pl.id::text
          AND o.published_at IS NOT NULL
      )
    )
  );
