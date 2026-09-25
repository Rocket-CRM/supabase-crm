-- amp_condition_metadata_v3_collections_1_6
-- Adds curated metadata for: user_wallet, mission_log_completion,
-- reward_redemptions_ledger, user_tags, tier_change_ledger, checkin_ledger

CREATE OR REPLACE FUNCTION public.bff_get_workflow_collections()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
  RETURN $json$[
  {
    "name": "user_accounts",
    "label": "Member Profile",
    "description": "The member's current profile. One row per member; no aggregates.",
    "supports_simple": true,
    "supports_aggregate": false,
    "fields": [
      {"name": "email", "label": "Email", "type": "string", "input": "text", "operators": ["equals", "not_equals", "contains", "not_contains", "starts_with", "ends_with", "is_empty", "is_not_empty"]},
      {"name": "tel", "label": "Phone", "type": "string", "input": "text", "operators": ["equals", "not_equals", "contains", "not_contains", "starts_with", "ends_with", "is_empty", "is_not_empty"]},
      {"name": "fullname", "label": "Full Name", "type": "string", "input": "text", "operators": ["equals", "not_equals", "contains", "not_contains", "starts_with", "ends_with", "is_empty", "is_not_empty"]},
      {"name": "gender", "label": "Gender", "type": "string", "input": "select", "options": [{"value": "MALE", "label": "Male"}, {"value": "FEMALE", "label": "Female"}, {"value": "NOT_SPECIFIED", "label": "Not specified"}], "operators": ["equals", "not_equals", "in", "not_in"]},
      {"name": "birth_date", "label": "Birth Date", "type": "date", "input": "date", "operators": ["birthday_today", "greater_or_equal", "less_or_equal", "greater_than", "less_than"]},
      {"name": "created_at", "label": "Member Since", "type": "timestamp", "input": "date", "operators": ["anniversary_today", "greater_or_equal", "less_or_equal", "greater_than", "less_than"]},
      {"name": "tier_id", "label": "Tier", "type": "uuid", "input": "entity_picker", "ref": "tier", "operators": ["equals", "not_equals", "in", "not_in"]},
      {"name": "persona_id", "label": "Persona", "type": "uuid", "input": "entity_picker", "ref": "persona", "operators": ["equals", "not_equals", "in", "not_in"]},
      {"name": "store_id", "label": "Registered Store", "type": "uuid", "input": "entity_picker", "ref": "store", "operators": ["equals", "not_equals", "in", "not_in"]},
      {"name": "user_stage", "label": "Member Stage", "type": "string", "input": "select", "options": [{"value": "lead", "label": "Lead"}, {"value": "member", "label": "Member"}], "operators": ["equals", "not_equals", "in", "not_in"]},
      {"name": "acquisition_source", "label": "Acquisition Source", "type": "string", "input": "text", "operators": ["equals", "not_equals", "contains", "not_contains", "starts_with", "is_empty", "is_not_empty"]},
      {"name": "line_id", "label": "LINE Connected", "type": "string", "input": "none", "operators": ["is_not_empty", "is_empty"]},
      {"name": "channel_email", "label": "Email Opt-in", "type": "boolean", "input": "boolean", "operators": ["is_true", "is_false"]},
      {"name": "channel_sms", "label": "SMS Opt-in", "type": "boolean", "input": "boolean", "operators": ["is_true", "is_false"]},
      {"name": "channel_line", "label": "LINE Opt-in", "type": "boolean", "input": "boolean", "operators": ["is_true", "is_false"]},
      {"name": "channel_push", "label": "Push Opt-in", "type": "boolean", "input": "boolean", "operators": ["is_true", "is_false"]},
      {"name": "is_signup_form_complete", "label": "Signup Form Completed", "type": "boolean", "input": "boolean", "operators": ["is_true", "is_false"]}
    ]
  },
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
    "name": "wallet_ledger",
    "label": "Points & Wallet Activity",
    "description": "One row per points/ticket transaction (earn or burn).",
    "supports_simple": true,
    "supports_aggregate": true,
    "time_field": "created_at",
    "aggregates": [
      {"aggregate": "count", "field": "id", "label": "Number of transactions"},
      {"aggregate": "sum", "field": "amount", "label": "Total amount (use filters to scope to earn/burn)"},
      {"aggregate": "sum", "field": "signed_amount", "label": "Net change (earn minus burn)"}
    ],
    "aggregate_fields": [
      {"name": "amount", "type": "number", "label": "Amount", "aggregates": ["sum", "count"]},
      {"name": "signed_amount", "type": "number", "label": "Net Change", "aggregates": ["sum"]}
    ],
    "fields": [
      {"name": "currency", "label": "Currency", "type": "string", "input": "select", "options": [{"value": "points", "label": "Points"}, {"value": "ticket", "label": "Tickets"}], "operators": ["equals", "not_equals"]},
      {"name": "transaction_type", "label": "Direction", "type": "string", "input": "select", "options": [{"value": "earn", "label": "Earn"}, {"value": "burn", "label": "Burn"}], "operators": ["equals", "not_equals"]},
      {"name": "source_type", "label": "Source", "type": "string", "input": "select", "options": [
        {"value": "purchase", "label": "Purchase"}, {"value": "purchase_item", "label": "Purchase Item"}, {"value": "mission", "label": "Mission"}, {"value": "campaign", "label": "Campaign"}, {"value": "reward_redemption", "label": "Reward Redemption"}, {"value": "redemption_cancellation", "label": "Redemption Cancellation"}, {"value": "referral", "label": "Referral"}, {"value": "checkin", "label": "Check-in"}, {"value": "spin_wheel", "label": "Spin Wheel"}, {"value": "code", "label": "Code Redemption"}, {"value": "activity", "label": "Activity"}, {"value": "manual", "label": "Manual Adjustment"}, {"value": "amp", "label": "Marketing Automation"}, {"value": "package_assignment", "label": "Package Assignment"}, {"value": "persona_entitlement", "label": "Persona Entitlement"}, {"value": "expiry", "label": "Expiry"}
      ], "operators": ["equals", "not_equals", "in", "not_in"]},
      {"name": "amount", "label": "Amount", "type": "number", "input": "number", "operators": ["equals", "not_equals", "greater_than", "greater_or_equal", "less_than", "less_or_equal"]},
      {"name": "expiry_date", "label": "Points Expiry Date", "type": "date", "input": "date", "operators": ["greater_or_equal", "less_or_equal", "greater_than", "less_than"]},
      {"name": "created_at", "label": "Transaction Date", "type": "timestamp", "input": "date", "operators": ["greater_or_equal", "less_or_equal", "greater_than", "less_than"]}
    ]
  },
  {
    "name": "purchase_ledger",
    "label": "Purchases",
    "description": "One row per purchase transaction.",
    "supports_simple": true,
    "supports_aggregate": true,
    "time_field": "created_at",
    "aggregates": [
      {"aggregate": "count", "field": "id", "label": "Number of purchases"},
      {"aggregate": "sum", "field": "final_amount", "label": "Total spend (amount paid)"},
      {"aggregate": "avg", "field": "final_amount", "label": "Average spend per purchase"},
      {"aggregate": "max", "field": "final_amount", "label": "Largest single purchase"},
      {"aggregate": "sum", "field": "total_amount", "label": "Total order value (before discount)"}
    ],
    "aggregate_fields": [
      {"name": "final_amount", "type": "number", "label": "Amount Paid", "aggregates": ["sum", "avg", "max", "count"]},
      {"name": "total_amount", "type": "number", "label": "Order Value", "aggregates": ["sum"]}
    ],
    "fields": [
      {"name": "transaction_date", "label": "Purchase Date", "type": "timestamp", "input": "date", "operators": ["greater_or_equal", "less_or_equal", "greater_than", "less_than"]},
      {"name": "total_amount", "label": "Order Value (before discount)", "type": "number", "input": "number", "operators": ["equals", "not_equals", "greater_than", "greater_or_equal", "less_than", "less_or_equal"]},
      {"name": "final_amount", "label": "Amount Paid (after discount)", "type": "number", "input": "number", "operators": ["equals", "not_equals", "greater_than", "greater_or_equal", "less_than", "less_or_equal"]},
      {"name": "discount_amount", "label": "Discount Amount", "type": "number", "input": "number", "operators": ["equals", "not_equals", "greater_than", "greater_or_equal", "less_than", "less_or_equal"]},
      {"name": "status", "label": "Status", "type": "string", "input": "select", "options": [{"value": "pending", "label": "Pending"}, {"value": "processing", "label": "Processing"}, {"value": "completed", "label": "Completed"}, {"value": "cancelled", "label": "Cancelled"}, {"value": "refunded", "label": "Refunded"}], "operators": ["equals", "not_equals", "in", "not_in"]},
      {"name": "payment_status", "label": "Payment Status", "type": "string", "input": "select", "options": [{"value": "paid", "label": "Paid"}, {"value": "pending", "label": "Pending"}, {"value": "refunded", "label": "Refunded"}], "operators": ["equals", "not_equals", "in", "not_in"]},
      {"name": "transaction_type", "label": "Purchase Type", "type": "string", "input": "select", "options": [{"value": "receipt_upload", "label": "Receipt Upload"}, {"value": "pos", "label": "POS"}, {"value": "marketplace", "label": "Marketplace"}, {"value": "online", "label": "Online"}], "operators": ["equals", "not_equals", "in", "not_in"]},
      {"name": "transaction_source", "label": "Sales Channel", "type": "string", "input": "select", "options": [{"value": "shopee", "label": "Shopee"}, {"value": "lazada", "label": "Lazada"}, {"value": "tiktok", "label": "TikTok"}, {"value": "marketplace_shopify", "label": "Shopify"}, {"value": "receipt_upload", "label": "Receipt Upload"}, {"value": "event_order", "label": "Event Order"}, {"value": "admin", "label": "Admin"}], "operators": ["equals", "not_equals", "in", "not_in"]},
      {"name": "store", "label": "Store", "type": "uuid", "input": "entity_picker", "ref": "store", "operators": ["equals", "not_equals", "in", "not_in"], "logical": true, "resolves": ["store_id", "store_code"]}
    ]
  },
  {
    "name": "purchase_items_ledger",
    "label": "Purchase Items",
    "description": "One row per purchased line item. Aggregate-only: use aggregates with filters, joined to Purchases for the member/time scope.",
    "supports_simple": false,
    "supports_aggregate": true,
    "time_field": "created_at",
    "joinable_to": {"table": "purchase_ledger", "on": {"local": "transaction_id", "foreign": "id"}, "time_field": "created_at"},
    "aggregates": [
      {"aggregate": "count", "field": "id", "label": "Number of items purchased"},
      {"aggregate": "sum", "field": "line_total", "label": "Total spend on matching items"},
      {"aggregate": "sum", "field": "quantity", "label": "Total quantity purchased"}
    ],
    "aggregate_fields": [
      {"name": "line_total", "type": "number", "label": "Line Total", "aggregates": ["sum", "count"]},
      {"name": "quantity", "type": "number", "label": "Quantity", "aggregates": ["sum"]}
    ],
    "fields": [
      {"name": "sku", "label": "Product (SKU)", "type": "uuid", "input": "entity_picker", "ref": "product_sku", "operators": ["equals", "not_equals", "in", "not_in"], "logical": true, "resolves": ["sku_id", "sku_code"]},
      {"name": "product_name", "label": "Product Name", "type": "string", "input": "text", "operators": ["equals", "not_equals", "contains", "not_contains", "starts_with"]},
      {"name": "quantity", "label": "Quantity", "type": "number", "input": "number", "operators": ["equals", "not_equals", "greater_than", "greater_or_equal", "less_than", "less_or_equal"]},
      {"name": "unit_price", "label": "Unit Price", "type": "number", "input": "number", "operators": ["equals", "not_equals", "greater_than", "greater_or_equal", "less_than", "less_or_equal"]},
      {"name": "line_total", "label": "Line Total", "type": "number", "input": "number", "operators": ["equals", "not_equals", "greater_than", "greater_or_equal", "less_than", "less_or_equal"]},
      {"name": "status", "label": "Status", "type": "string", "input": "select", "options": [{"value": "pending", "label": "Pending"}, {"value": "processing", "label": "Processing"}, {"value": "completed", "label": "Completed"}, {"value": "cancelled", "label": "Cancelled"}, {"value": "refunded", "label": "Refunded"}], "operators": ["equals", "not_equals", "in", "not_in"]}
    ]
  },
  {
    "name": "package_assignment",
    "label": "Package Assignments",
    "description": "Packages assigned to the member.",
    "supports_simple": true,
    "supports_aggregate": true,
    "time_field": "created_at",
    "aggregates": [{"aggregate": "count", "field": "id", "label": "Number of package assignments"}],
    "aggregate_fields": [{"name": "id", "type": "uuid", "label": "Assignment Count", "aggregates": ["count"]}],
    "fields": [
      {"name": "package_id", "label": "Package", "type": "uuid", "input": "entity_picker", "ref": "package", "operators": ["equals", "not_equals", "in", "not_in"]},
      {"name": "status", "label": "Status", "type": "string", "input": "select", "options": [{"value": "active", "label": "Active"}], "operators": ["equals", "not_equals"]},
      {"name": "effective_from", "label": "Effective From", "type": "date", "input": "date", "operators": ["greater_or_equal", "less_or_equal", "greater_than", "less_than"]},
      {"name": "effective_to", "label": "Effective To", "type": "date", "input": "date", "operators": ["greater_or_equal", "less_or_equal", "greater_than", "less_than"]}
    ]
  },
  {
    "name": "user_benefit",
    "label": "User Benefits",
    "description": "Benefits granted to the member (e.g. discounts, priority access).",
    "supports_simple": true,
    "supports_aggregate": true,
    "time_field": "created_at",
    "aggregates": [
      {"aggregate": "count", "field": "id", "label": "Number of benefits"},
      {"aggregate": "sum", "field": "value", "label": "Total benefit value"}
    ],
    "aggregate_fields": [
      {"name": "value", "type": "number", "label": "Benefit Value", "aggregates": ["sum", "count"]},
      {"name": "id", "type": "uuid", "label": "Benefit Count", "aggregates": ["count"]}
    ],
    "fields": [
      {"name": "category", "label": "Category", "type": "string", "input": "text", "operators": ["equals", "not_equals", "contains"]},
      {"name": "benefit_type", "label": "Benefit Type", "type": "string", "input": "text", "operators": ["equals", "not_equals", "contains"]},
      {"name": "value", "label": "Value", "type": "number", "input": "number", "operators": ["equals", "not_equals", "greater_than", "greater_or_equal", "less_than", "less_or_equal"]},
      {"name": "status", "label": "Status", "type": "string", "input": "select", "options": [{"value": "active", "label": "Active"}], "operators": ["equals", "not_equals"]},
      {"name": "valid_from", "label": "Valid From", "type": "date", "input": "date", "operators": ["greater_or_equal", "less_or_equal", "greater_than", "less_than"]},
      {"name": "valid_to", "label": "Valid To", "type": "date", "input": "date", "operators": ["greater_or_equal", "less_or_equal", "greater_than", "less_than"]}
    ]
  },
  {
    "name": "form_submissions",
    "label": "Forms & Surveys",
    "description": "Form/survey submissions by the member. Use condition_kinds for has-submitted and answer-matching; use aggregates for submission counts.",
    "supports_simple": true,
    "supports_aggregate": true,
    "time_field": "submitted_at",
    "aggregates": [{"aggregate": "count", "field": "id", "label": "Number of submissions"}],
    "aggregate_fields": [{"name": "id", "type": "uuid", "label": "Submission Count", "aggregates": ["count"]}],
    "fields": [
      {"name": "form_id", "label": "Form", "type": "uuid", "input": "entity_picker", "ref": "form_template", "operators": ["equals", "not_equals", "in", "not_in"]},
      {"name": "status", "label": "Status", "type": "string", "input": "select", "options": [{"value": "completed", "label": "Completed"}, {"value": "draft", "label": "Draft"}], "operators": ["equals", "not_equals"]},
      {"name": "submitted_at", "label": "Submitted At", "type": "timestamp", "input": "date", "operators": ["greater_or_equal", "less_or_equal", "greater_than", "less_than"]}
    ],
    "condition_kinds": [
      {"type": "form_submission", "label": "Has submitted form", "form_ref": "form_template", "operators": ["submitted", "not_submitted"], "supports_time_range": true},
      {"type": "form_answer", "label": "Answered form question", "form_ref": "form_template", "question_source": {"function": "bff_get_amp_form_fields", "param": "p_form_id", "options_key": "options"}, "operators": ["equals", "not_equals", "contains", "not_contains", "in", "greater_than", "greater_or_equal", "less_than", "less_or_equal", "is_empty", "is_not_empty"], "supports_time_range": true}
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
