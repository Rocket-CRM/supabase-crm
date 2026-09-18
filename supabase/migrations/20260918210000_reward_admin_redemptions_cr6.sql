-- CR6: Admin reward redemption list (counts on bff_list_rewards), paginated tab BFF, async CSV export.
-- Ledger index: existing rrl_reward_idx (reward_id, redeemed_at DESC) + rrl_merchant_redeemed_idx.

CREATE OR REPLACE FUNCTION public.fn_reward_admin_ledger_reportable(
  p_success boolean,
  p_cancelled boolean,
  p_redeemed_status boolean,
  p_package_assignment_id uuid,
  p_source_type public.wallet_transaction_source_type
)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT
    COALESCE(p_success, false) = true
    AND COALESCE(p_cancelled, false) = false
    AND COALESCE(p_redeemed_status, true) = true
    AND p_package_assignment_id IS NULL
    AND COALESCE(p_source_type::text, '') NOT IN ('package_assignment', 'persona_entitlement');
$$;

CREATE OR REPLACE FUNCTION public.bff_list_rewards(p_include_inactive boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_merchant_id uuid;
  v_result jsonb;
BEGIN
  v_merchant_id := get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'No merchant context');
  END IF;

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'id', r.id,
        'name', r.name,
        'category_id', r.category_id,
        'visibility', r.visibility,
        'redeem_window_start', r.redeem_window_start,
        'redeem_window_end', r.redeem_window_end,
        'require_points_match', r.require_points_match,
        'points', jsonb_build_object('fallback', COALESCE(r.fallback_points, 0)),
        'stock_control', r.stock_control,
        'active_status', r.active_status,
        'shopify_discount_type', r.shopify_discount_type,
        'is_featured', COALESCE(r.is_featured, false),
        'redeemed_qty', COALESCE(ls.redeemed_qty, 0),
        'used_qty', COALESCE(ls.used_qty, 0),
        'not_used_qty', GREATEST(COALESCE(ls.redeemed_qty, 0) - COALESCE(ls.used_qty, 0), 0)
      )
      ORDER BY COALESCE(r.is_featured, false) DESC, r.created_at DESC
    ),
    '[]'::jsonb
  )
  INTO v_result
  FROM reward_master r
  LEFT JOIN (
    SELECT
      rrl.reward_id,
      SUM(COALESCE(rrl.qty, 1))::bigint AS redeemed_qty,
      SUM(
        CASE WHEN COALESCE(rrl.used_status, false)
          THEN COALESCE(rrl.qty, 1)
          ELSE 0
        END
      )::bigint AS used_qty
    FROM reward_redemptions_ledger rrl
    WHERE rrl.merchant_id = v_merchant_id
      AND fn_reward_admin_ledger_reportable(
        rrl.success,
        rrl.cancelled,
        rrl.redeemed_status,
        rrl.package_assignment_id,
        rrl.source_type
      )
    GROUP BY rrl.reward_id
  ) ls ON ls.reward_id = r.id
  WHERE r.merchant_id = v_merchant_id
    AND (COALESCE(p_include_inactive, false) OR r.active_status = true);

  RETURN jsonb_build_object('success', true, 'data', v_result);
END;
$function$;

CREATE OR REPLACE FUNCTION public.bff_admin_list_reward_redemptions(
  p_reward_id uuid,
  p_from timestamptz DEFAULT NULL,
  p_to timestamptz DEFAULT NULL,
  p_tab text DEFAULT 'all',
  p_page integer DEFAULT 1,
  p_page_size integer DEFAULT 25
)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_merchant_id uuid;
  v_page integer;
  v_page_size integer;
  v_offset integer;
  v_tab text;
  v_items jsonb;
  v_total bigint;
  v_redeemed_qty bigint;
  v_used_qty bigint;
  v_all_rows bigint;
  v_redeemed_rows bigint;
  v_used_rows bigint;
BEGIN
  v_merchant_id := get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN fn_response_error('No merchant context', NULL, 'NO_MERCHANT', NULL);
  END IF;

  IF NOT check_admin_permission('reward', 'read') THEN
    RETURN fn_response_error('Permission denied', 'reward.read required', 'FORBIDDEN', NULL);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM reward_master rm
    WHERE rm.id = p_reward_id AND rm.merchant_id = v_merchant_id
  ) THEN
    RETURN fn_response_error('Reward not found', NULL, 'NOT_FOUND', NULL);
  END IF;

  v_page := GREATEST(COALESCE(p_page, 1), 1);
  v_page_size := LEAST(GREATEST(COALESCE(p_page_size, 25), 1), 100);
  v_offset := (v_page - 1) * v_page_size;
  v_tab := lower(COALESCE(p_tab, 'all'));

  WITH base AS (
    SELECT
      rrl.*,
      COALESCE(rrl.redeemed_at, rrl.created_at) AS redeemed_sort_at
    FROM reward_redemptions_ledger rrl
    WHERE rrl.merchant_id = v_merchant_id
      AND rrl.reward_id = p_reward_id
      AND fn_reward_admin_ledger_reportable(
        rrl.success,
        rrl.cancelled,
        rrl.redeemed_status,
        rrl.package_assignment_id,
        rrl.source_type
      )
      AND (p_from IS NULL OR COALESCE(rrl.redeemed_at, rrl.created_at) >= p_from)
      AND (p_to IS NULL OR COALESCE(rrl.redeemed_at, rrl.created_at) <= p_to)
  ),
  totals AS (
    SELECT
      COALESCE(SUM(COALESCE(qty, 1)), 0)::bigint AS redeemed_qty,
      COALESCE(SUM(
        CASE WHEN COALESCE(used_status, false) THEN COALESCE(qty, 1) ELSE 0 END
      ), 0)::bigint AS used_qty,
      COUNT(*)::bigint AS all_rows,
      COUNT(*) FILTER (WHERE COALESCE(used_status, false) = false)::bigint AS redeemed_rows,
      COUNT(*) FILTER (WHERE COALESCE(used_status, false) = true)::bigint AS used_rows
    FROM base
  ),
  filtered AS (
    SELECT * FROM base b
    WHERE
      v_tab = 'all'
      OR (v_tab = 'used' AND COALESCE(b.used_status, false) = true)
      OR (v_tab = 'redeemed' AND COALESCE(b.used_status, false) = false)
  )
  SELECT
    t.redeemed_qty,
    t.used_qty,
    t.all_rows,
    t.redeemed_rows,
    t.used_rows,
    (SELECT COUNT(*) FROM filtered),
    COALESCE(
      (
        SELECT jsonb_agg(row_data ORDER BY redeemed_sort_at DESC, id DESC)
        FROM (
          SELECT
            jsonb_build_object(
              'id', f.id,
              'user_id', f.user_id,
              'member_name', COALESCE(
                NULLIF(trim(ua.fullname), ''),
                trim(concat_ws(' ', ua.firstname, ua.lastname))
              ),
              'phone', ua.tel,
              'qty', COALESCE(f.qty, 1),
              'redemption_code', f.code,
              'points_deducted', f.points_deducted,
              'redeemed_store_id', f.redeemed_store_id,
              'redeemed_store_name', rs.name,
              'used_store_id', f.used_store_id,
              'used_store_name', us.name,
              'redeemed_at', f.redeemed_at,
              'used_at', f.used_at,
              'status', CASE
                WHEN COALESCE(f.used_status, false) THEN 'used'
                ELSE 'redeemed'
              END
            ) AS row_data,
            f.redeemed_sort_at,
            f.id
          FROM filtered f
          LEFT JOIN user_accounts ua ON ua.id = f.user_id AND ua.merchant_id = v_merchant_id
          LEFT JOIN store_master rs ON rs.id = f.redeemed_store_id
          LEFT JOIN store_master us ON us.id = f.used_store_id
          ORDER BY f.redeemed_sort_at DESC, f.id DESC
          LIMIT v_page_size OFFSET v_offset
        ) q
      ),
      '[]'::jsonb
    )
  INTO
    v_redeemed_qty,
    v_used_qty,
    v_all_rows,
    v_redeemed_rows,
    v_used_rows,
    v_total,
    v_items
  FROM totals t;

  RETURN fn_response_success(
    'Reward redemptions',
    NULL,
    jsonb_build_object(
      'items', v_items,
      'page', v_page,
      'page_size', v_page_size,
      'total_rows', v_total,
      'totals', jsonb_build_object(
        'redeemed_qty', v_redeemed_qty,
        'used_qty', v_used_qty,
        'not_used_qty', GREATEST(v_redeemed_qty - v_used_qty, 0),
        'tab_counts', jsonb_build_object(
          'all', v_all_rows,
          'redeemed', v_redeemed_rows,
          'used', v_used_rows
        )
      )
    )
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_reward_redemption_export_field_labels()
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
AS $$
  SELECT jsonb_build_object(
    'member_name', 'Member name',
    'phone', 'Phone',
    'redemption_code', 'Redemption code',
    'quantity', 'Quantity',
    'points_deducted', 'Points deducted',
    'redeemed_store', 'Redeemed store',
    'used_store', 'Used store',
    'redeemed_at', 'Redeemed at',
    'used_at', 'Used at',
    'status', 'Status'
  );
$$;

CREATE OR REPLACE FUNCTION public.fn_reward_redemption_export_count(p_batch_id uuid)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_batch record;
  v_reward_id uuid;
  v_from timestamptz;
  v_to timestamptz;
  v_tab text;
  v_count bigint;
BEGIN
  SELECT * INTO v_batch
  FROM bulk_import_batches
  WHERE id = p_batch_id AND import_type = 'reward_redemptions_export';

  IF NOT FOUND THEN
    RETURN 0;
  END IF;

  v_reward_id := (v_batch.metadata->'filters'->>'reward_id')::uuid;
  v_from := NULLIF(v_batch.metadata->'filters'->>'from', '')::timestamptz;
  v_to := NULLIF(v_batch.metadata->'filters'->>'to', '')::timestamptz;
  v_tab := lower(COALESCE(v_batch.metadata->'filters'->>'tab', 'all'));

  WITH base AS (
    SELECT rrl.*
    FROM reward_redemptions_ledger rrl
    WHERE rrl.merchant_id = v_batch.merchant_id
      AND rrl.reward_id = v_reward_id
      AND fn_reward_admin_ledger_reportable(
        rrl.success,
        rrl.cancelled,
        rrl.redeemed_status,
        rrl.package_assignment_id,
        rrl.source_type
      )
      AND (v_from IS NULL OR COALESCE(rrl.redeemed_at, rrl.created_at) >= v_from)
      AND (v_to IS NULL OR COALESCE(rrl.redeemed_at, rrl.created_at) <= v_to)
  )
  SELECT COUNT(*)::bigint INTO v_count
  FROM base b
  WHERE
    v_tab = 'all'
    OR (v_tab = 'used' AND COALESCE(b.used_status, false) = true)
    OR (v_tab = 'redeemed' AND COALESCE(b.used_status, false) = false);

  RETURN v_count;
END;
$function$;

CREATE OR REPLACE FUNCTION public.process_reward_redemption_export_chunk(
  p_batch_id uuid,
  p_offset integer,
  p_limit integer
)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_batch record;
  v_reward_id uuid;
  v_from timestamptz;
  v_to timestamptz;
  v_tab text;
  v_rows jsonb;
BEGIN
  SELECT * INTO v_batch
  FROM bulk_import_batches
  WHERE id = p_batch_id AND import_type = 'reward_redemptions_export';

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Batch not found');
  END IF;

  v_reward_id := (v_batch.metadata->'filters'->>'reward_id')::uuid;
  v_from := NULLIF(v_batch.metadata->'filters'->>'from', '')::timestamptz;
  v_to := NULLIF(v_batch.metadata->'filters'->>'to', '')::timestamptz;
  v_tab := lower(COALESCE(v_batch.metadata->'filters'->>'tab', 'all'));

  WITH base AS (
    SELECT
      rrl.*,
      COALESCE(rrl.redeemed_at, rrl.created_at) AS redeemed_sort_at
    FROM reward_redemptions_ledger rrl
    WHERE rrl.merchant_id = v_batch.merchant_id
      AND rrl.reward_id = v_reward_id
      AND fn_reward_admin_ledger_reportable(
        rrl.success,
        rrl.cancelled,
        rrl.redeemed_status,
        rrl.package_assignment_id,
        rrl.source_type
      )
      AND (v_from IS NULL OR COALESCE(rrl.redeemed_at, rrl.created_at) >= v_from)
      AND (v_to IS NULL OR COALESCE(rrl.redeemed_at, rrl.created_at) <= v_to)
  ),
  filtered AS (
    SELECT * FROM base b
    WHERE
      v_tab = 'all'
      OR (v_tab = 'used' AND COALESCE(b.used_status, false) = true)
      OR (v_tab = 'redeemed' AND COALESCE(b.used_status, false) = false)
  )
  SELECT COALESCE(jsonb_agg(row_data ORDER BY redeemed_sort_at DESC, id DESC), '[]'::jsonb)
  INTO v_rows
  FROM (
    SELECT
      jsonb_build_object(
        'member_name', COALESCE(
          NULLIF(trim(ua.fullname), ''),
          trim(concat_ws(' ', ua.firstname, ua.lastname))
        ),
        'phone', ua.tel,
        'redemption_code', COALESCE(f.code, ''),
        'quantity', COALESCE(f.qty, 1)::text,
        'points_deducted', COALESCE(f.points_deducted, 0)::text,
        'redeemed_store', COALESCE(rs.name, ''),
        'used_store', COALESCE(us.name, ''),
        'redeemed_at', COALESCE(f.redeemed_at::text, ''),
        'used_at', COALESCE(f.used_at::text, ''),
        'status', CASE WHEN COALESCE(f.used_status, false) THEN 'used' ELSE 'redeemed' END
      ) AS row_data,
      f.redeemed_sort_at,
      f.id
    FROM filtered f
    LEFT JOIN user_accounts ua ON ua.id = f.user_id AND ua.merchant_id = v_batch.merchant_id
    LEFT JOIN store_master rs ON rs.id = f.redeemed_store_id
    LEFT JOIN store_master us ON us.id = f.used_store_id
    ORDER BY f.redeemed_sort_at DESC, f.id DESC
    LIMIT GREATEST(p_limit, 0)
    OFFSET GREATEST(p_offset, 0)
  ) q;

  RETURN jsonb_build_object(
    'success', true,
    'rows', v_rows,
    'row_count', jsonb_array_length(v_rows)
  );
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$function$;

CREATE OR REPLACE FUNCTION public.bff_admin_start_reward_redemption_export(
  p_reward_id uuid,
  p_batch_name text,
  p_filters jsonb DEFAULT '{}'::jsonb
)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_merchant uuid := get_current_merchant_id();
  v_id uuid;
  v_file_name text;
  v_request_id bigint;
  v_field_keys text[] := ARRAY[
    'member_name', 'phone', 'redemption_code', 'quantity', 'points_deducted',
    'redeemed_store', 'used_store', 'redeemed_at', 'used_at', 'status'
  ];
  v_metadata jsonb;
BEGIN
  IF NOT check_admin_permission('reward', 'read') THEN
    RETURN fn_response_error('Permission denied', 'reward.read required', 'FORBIDDEN', NULL);
  END IF;
  IF v_merchant IS NULL THEN
    RETURN fn_response_error('No merchant context', NULL, 'NO_MERCHANT', NULL);
  END IF;
  IF p_reward_id IS NULL THEN
    RETURN fn_response_error('Reward required', NULL, 'INVALID', NULL);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM reward_master rm WHERE rm.id = p_reward_id AND rm.merchant_id = v_merchant
  ) THEN
    RETURN fn_response_error('Reward not found', NULL, 'NOT_FOUND', NULL);
  END IF;

  v_file_name := format(
    'reward_redemptions_%s_%s.csv',
    left(replace(p_reward_id::text, '-', ''), 8),
    to_char(clock_timestamp(), 'YYYYMMDD_HH24MISS')
  );

  v_metadata := jsonb_build_object(
    'filters',
    COALESCE(p_filters, '{}'::jsonb) || jsonb_build_object('reward_id', p_reward_id)
  );

  INSERT INTO bulk_import_batches (
    merchant_id, batch_name, file_name, status, import_type, field_selection, metadata, total_rows
  ) VALUES (
    v_merchant,
    COALESCE(NULLIF(trim(p_batch_name), ''), 'Reward redemptions export'),
    v_file_name,
    'pending',
    'reward_redemptions_export',
    jsonb_build_object('field_keys', to_jsonb(v_field_keys)),
    v_metadata,
    0
  ) RETURNING id INTO v_id;

  v_request_id := fn_emit_inngest_event(
    'export/users-csv',
    jsonb_build_object('batch_id', v_id, 'merchant_id', v_merchant)
  );

  RETURN fn_response_success(
    'Export queued',
    NULL,
    jsonb_build_object(
      'batch_id', v_id,
      'file_name', v_file_name,
      'inngest_request_id', v_request_id
    )
  );
EXCEPTION WHEN OTHERS THEN
  RETURN fn_response_error('Failed to start export', SQLERRM, 'INTERNAL', NULL);
END;
$function$;

REVOKE ALL ON FUNCTION public.bff_admin_list_reward_redemptions(uuid, timestamptz, timestamptz, text, integer, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.bff_admin_start_reward_redemption_export(uuid, text, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.bff_admin_list_reward_redemptions(uuid, timestamptz, timestamptz, text, integer, integer) TO postgres, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.bff_admin_start_reward_redemption_export(uuid, text, jsonb) TO postgres, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_reward_redemption_export_count(uuid) TO postgres, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.process_reward_redemption_export_chunk(uuid, integer, integer) TO postgres, authenticated, service_role;
