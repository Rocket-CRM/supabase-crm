-- Rename existing metadata holder, append 6 new curated collections.

ALTER FUNCTION public.bff_get_workflow_collections() RENAME TO bff_get_workflow_collections_v2;

CREATE OR REPLACE FUNCTION public.bff_get_workflow_collections_v3_extensions()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
  RETURN $json$[
  {
    "name": "user_wallet",
    "label": "Current Balance",
    "description": "The member's current points and ticket balances (one row per member). Use for snapshot thresholds like \"has at least 500 points\".",
    "supports_simple": true,
    "supports_aggregate": false,
    "fields": [
      {"name": "points_balance", "label": "Points Balance", "type": "number", "input": "number", "operators": ["equals", "not_equals", "greater_than", "greater_or_equal", "less_than", "less_or_equal"]},
      {"name": "ticket_balance", "label": "Ticket Balance", "type": "number", "input": "number", "operators": ["equals", "not_equals", "greater_than", "greater_or_equal", "less_than", "less_or_equal"]}
    ]
  },
  {
    "name": "mission_log_completion",
    "label": "Mission Completions",
    "description": "Each row is one time the member completed a mission.",
    "supports_simple": true,
    "supports_aggregate": true,
    "time_field": "completed_at",
    "aggregates": [
      {"aggregate": "count", "field": "id", "label": "Number of completions"},
      {"aggregate": "sum", "field": "loops_completed", "label": "Total loops completed"}
    ],
    "aggregate_fields": [
      {"name": "id", "type": "uuid", "label": "Completion Count", "aggregates": ["count"]},
      {"name": "loops_completed", "type": "number", "label": "Loops Completed", "aggregates": ["sum"]}
    ],
    "fields": [
      {"name": "mission_id", "label": "Mission", "type": "uuid", "input": "entity_picker", "ref": "mission", "operators": ["equals", "not_equals", "in", "not_in"]},
      {"name": "is_claimed", "label": "Reward Claimed", "type": "boolean", "input": "boolean", "operators": ["is_true", "is_false"]},
      {"name": "milestone_level", "label": "Milestone Level", "type": "number", "input": "number", "operators": ["equals", "not_equals", "greater_than", "greater_or_equal", "less_than", "less_or_equal"]},
      {"name": "completed_at", "label": "Completed At", "type": "timestamp", "input": "date", "operators": ["greater_or_equal", "less_or_equal", "greater_than", "less_than"]}
    ]
  },
  {
    "name": "reward_redemptions_ledger",
    "label": "Reward Redemptions",
    "description": "Each row is one reward redemption by the member.",
    "supports_simple": true,
    "supports_aggregate": true,
    "time_field": "redeemed_at",
    "aggregates": [
      {"aggregate": "count", "field": "id", "label": "Number of redemptions"},
      {"aggregate": "sum", "field": "qty", "label": "Total quantity redeemed"}
    ],
    "aggregate_fields": [
      {"name": "id", "type": "uuid", "label": "Redemption Count", "aggregates": ["count"]},
      {"name": "qty", "type": "number", "label": "Quantity", "aggregates": ["sum"]}
    ],
    "fields": [
      {"name": "reward_id", "label": "Reward", "type": "uuid", "input": "entity_picker", "ref": "reward", "operators": ["equals", "not_equals", "in", "not_in"]},
      {"name": "redeemed_status", "label": "Redeemed", "type": "boolean", "input": "boolean", "operators": ["is_true", "is_false"]},
      {"name": "used_status", "label": "Used", "type": "boolean", "input": "boolean", "operators": ["is_true", "is_false"]},
      {"name": "cancelled", "label": "Cancelled", "type": "boolean", "input": "boolean", "operators": ["is_true", "is_false"]},
      {"name": "fulfillment_status", "label": "Fulfillment Status", "type": "string", "input": "select", "options": [{"value": "pending", "label": "Pending"}, {"value": "shipped", "label": "Shipped"}, {"value": "delivered", "label": "Delivered"}, {"value": "completed", "label": "Completed"}, {"value": "cancelled", "label": "Cancelled"}, {"value": "reject", "label": "Rejected"}], "operators": ["equals", "not_equals", "in", "not_in"]},
      {"name": "qty", "label": "Quantity", "type": "number", "input": "number", "operators": ["equals", "not_equals", "greater_than", "greater_or_equal", "less_than", "less_or_equal"]},
      {"name": "redeemed_at", "label": "Redeemed At", "type": "timestamp", "input": "date", "operators": ["greater_or_equal", "less_or_equal", "greater_than", "less_than"]},
      {"name": "used_at", "label": "Used At", "type": "timestamp", "input": "date", "operators": ["greater_or_equal", "less_or_equal", "greater_than", "less_than"]}
    ]
  },
  {
    "name": "user_tags",
    "label": "Member Tags",
    "description": "Tags assigned to the member.",
    "supports_simple": true,
    "supports_aggregate": true,
    "time_field": "created_at",
    "aggregates": [{"aggregate": "count", "field": "id", "label": "Number of tags"}],
    "aggregate_fields": [{"name": "id", "type": "uuid", "label": "Tag Count", "aggregates": ["count"]}],
    "fields": [
      {"name": "tag_id", "label": "Tag", "type": "uuid", "input": "entity_picker", "ref": "tag", "operators": ["equals", "not_equals", "in", "not_in"]},
      {"name": "created_at", "label": "Tagged At", "type": "timestamp", "input": "date", "operators": ["greater_or_equal", "less_or_equal", "greater_than", "less_than"]}
    ]
  },
  {
    "name": "tier_change_ledger",
    "label": "Tier Changes",
    "description": "History of tier upgrades, downgrades, and initial assignments.",
    "supports_simple": true,
    "supports_aggregate": true,
    "time_field": "created_at",
    "aggregates": [{"aggregate": "count", "field": "id", "label": "Number of tier changes"}],
    "aggregate_fields": [{"name": "id", "type": "uuid", "label": "Change Count", "aggregates": ["count"]}],
    "fields": [
      {"name": "change_type", "label": "Change Type", "type": "string", "input": "select", "options": [{"value": "initial", "label": "Initial assignment"}, {"value": "upgrade", "label": "Upgrade"}, {"value": "downgrade", "label": "Downgrade"}, {"value": "manual", "label": "Manual change"}, {"value": "scheduled", "label": "Scheduled change"}], "operators": ["equals", "not_equals", "in", "not_in"]},
      {"name": "from_tier_id", "label": "From Tier", "type": "uuid", "input": "entity_picker", "ref": "tier", "operators": ["equals", "not_equals", "in", "not_in"]},
      {"name": "to_tier_id", "label": "To Tier", "type": "uuid", "input": "entity_picker", "ref": "tier", "operators": ["equals", "not_equals", "in", "not_in"]},
      {"name": "created_at", "label": "Changed At", "type": "timestamp", "input": "date", "operators": ["greater_or_equal", "less_or_equal", "greater_than", "less_than"]}
    ]
  },
  {
    "name": "checkin_ledger",
    "label": "Check-ins",
    "description": "Each row is one check-in event by the member.",
    "supports_simple": true,
    "supports_aggregate": true,
    "time_field": "checkin_timestamp",
    "aggregates": [
      {"aggregate": "count", "field": "id", "label": "Number of check-ins"},
      {"aggregate": "max", "field": "streak_day", "label": "Highest streak day reached"}
    ],
    "aggregate_fields": [
      {"name": "id", "type": "uuid", "label": "Check-in Count", "aggregates": ["count"]},
      {"name": "streak_day", "type": "number", "label": "Streak Day", "aggregates": ["max"]}
    ],
    "fields": [
      {"name": "checkin_id", "label": "Check-in Campaign", "type": "uuid", "input": "entity_picker", "ref": "checkin", "operators": ["equals", "not_equals", "in", "not_in"]},
      {"name": "streak_day", "label": "Streak Day", "type": "number", "input": "number", "operators": ["equals", "not_equals", "greater_than", "greater_or_equal", "less_than", "less_or_equal"]},
      {"name": "checkin_date", "label": "Check-in Date", "type": "date", "input": "date", "operators": ["greater_or_equal", "less_or_equal", "greater_than", "less_than"]},
      {"name": "checkin_timestamp", "label": "Check-in Time", "type": "timestamp", "input": "date", "operators": ["greater_or_equal", "less_or_equal", "greater_than", "less_than"]}
    ]
  }
]$json$::jsonb;
END;
$function$;

CREATE OR REPLACE FUNCTION public.bff_get_workflow_collections()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_base jsonb := bff_get_workflow_collections_v2();
  v_ext jsonb := bff_get_workflow_collections_v3_extensions();
  v_wallet jsonb;
  v_ext_rest jsonb;
BEGIN
  SELECT COALESCE(jsonb_agg(elem), '[]'::jsonb) INTO v_wallet
  FROM jsonb_array_elements(v_ext) elem
  WHERE elem->>'name' = 'user_wallet';

  SELECT COALESCE(jsonb_agg(elem), '[]'::jsonb) INTO v_ext_rest
  FROM jsonb_array_elements(v_ext) elem
  WHERE elem->>'name' <> 'user_wallet';

  IF jsonb_array_length(v_wallet) = 0 THEN
    RETURN v_base || v_ext_rest;
  END IF;

  -- Insert Current Balance immediately after Member Profile
  RETURN jsonb_build_array(v_base->0) || v_wallet || COALESCE(
    (SELECT jsonb_agg(elem ORDER BY idx)
     FROM jsonb_array_elements(v_base) WITH ORDINALITY t(elem, idx)
     WHERE idx > 1),
    '[]'::jsonb
  ) || v_ext_rest;
END;
$function$;
