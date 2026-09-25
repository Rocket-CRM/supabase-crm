-- AMP birth-date month operators (month_in, month_not_in, month_current)

DO $migrate$
DECLARE
  v_def text;
  v_old text := '{"name": "birth_date", "label": "Birth Date", "type": "date", "input": "date", "operators": ["birthday_today", "greater_or_equal", "less_or_equal", "greater_than", "less_than"]}';
  v_new text := '{"name": "birth_date", "label": "Birth Date", "type": "date", "input": "date", "operators": ["birthday_today", "month_current", "month_in", "month_not_in", "greater_or_equal", "less_or_equal", "greater_than", "less_than"]}';
BEGIN
  v_def := pg_get_functiondef('public.bff_get_workflow_collections_v2()'::regprocedure);
  IF position(v_old in v_def) = 0 THEN
    RAISE EXCEPTION 'birth_date metadata snippet not found in bff_get_workflow_collections_v2';
  END IF;
  v_def := replace(v_def, v_old, v_new);
  EXECUTE v_def;
END;
$migrate$;

CREATE OR REPLACE FUNCTION public.fn_amp_build_condition_clause(p_collection text, p_cond jsonb, p_alias text DEFAULT ''::text, p_default_timezone text DEFAULT 'UTC'::text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_field TEXT := p_cond->>'field';
  v_operator TEXT := COALESCE(p_cond->>'operator', 'equals');
  v_value TEXT := p_cond->>'value';
  v_timezone TEXT := COALESCE(p_cond->>'timezone', p_default_timezone);
  v_days_offset INT := COALESCE((p_cond->>'days_offset')::int, (p_cond->>'days_before')::int, 0);
  v_values TEXT[];
  v_codes TEXT[];
  v_list TEXT;
  v_code TEXT;
  v_id_col TEXT;
  v_code_col TEXT;
  v_eq TEXT;
  v_json_kind TEXT;
  v_json_type TEXT;
  v_json_key TEXT;
  v_uuid_re CONSTANT TEXT := '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
BEGIN
  IF v_field ~ '^(prop|attr)__' THEN
    v_json_kind := split_part(v_field, '__', 2 - 1);
    v_json_type := split_part(v_field, '__', 2);
    v_json_key := substring(v_field FROM length(v_json_kind) + length(v_json_type) + 5);
    IF v_json_type NOT IN ('string','number','boolean','date','timestamp','enum','entity_ref') OR v_json_key = '' THEN
      RAISE EXCEPTION 'Malformed AMP typed json field: %', v_field;
    END IF;
    RETURN fn_amp_build_json_field_clause(
      format('%s%I->>%L', p_alias,
        CASE WHEN v_json_kind = 'prop' THEN 'properties' ELSE 'attribution' END,
        v_json_key),
      v_json_type, p_cond);
  END IF;

  IF v_operator IN ('in', 'not_in', 'month_in', 'month_not_in') THEN
    IF jsonb_typeof(p_cond->'value') = 'array' THEN
      SELECT COALESCE(array_agg(x), ARRAY[]::text[]) INTO v_values
      FROM jsonb_array_elements_text(p_cond->'value') x;
    ELSIF v_value IS NOT NULL THEN
      v_values := ARRAY[v_value];
    ELSE
      v_values := ARRAY[]::text[];
    END IF;
  END IF;

  IF (p_collection = 'purchase_ledger' AND v_field = 'store')
     OR (p_collection = 'purchase_items_ledger' AND v_field = 'sku') THEN
    IF p_collection = 'purchase_ledger' THEN
      v_id_col := 'store_id'; v_code_col := 'store_code';
    ELSE
      v_id_col := 'sku_id'; v_code_col := 'sku_code';
    END IF;

    IF v_operator IN ('equals', 'not_equals') THEN
      IF v_value IS NULL OR v_value !~ v_uuid_re THEN
        RETURN CASE WHEN v_operator = 'equals' THEN 'FALSE' ELSE 'TRUE' END;
      END IF;
      IF p_collection = 'purchase_ledger' THEN
        SELECT store_code INTO v_code FROM store_master WHERE id = v_value::uuid;
      ELSE
        SELECT sku_code INTO v_code FROM product_sku_master WHERE id = v_value::uuid;
      END IF;
      IF v_code IS NULL THEN
        v_eq := format('%s%I = %L', p_alias, v_id_col, v_value);
      ELSE
        v_eq := format('(%s%I = %L OR %s%I = %L)', p_alias, v_id_col, v_value, p_alias, v_code_col, v_code);
      END IF;
      RETURN CASE WHEN v_operator = 'equals' THEN v_eq
                  ELSE format('NOT COALESCE(%s, FALSE)', v_eq) END;
    ELSIF v_operator IN ('in', 'not_in') THEN
      SELECT COALESCE(array_agg(x), ARRAY[]::text[]) INTO v_values
      FROM unnest(v_values) x WHERE x ~ v_uuid_re;
      IF COALESCE(array_length(v_values, 1), 0) = 0 THEN
        RETURN CASE WHEN v_operator = 'in' THEN 'FALSE' ELSE 'TRUE' END;
      END IF;
      IF p_collection = 'purchase_ledger' THEN
        SELECT COALESCE(array_agg(store_code), ARRAY[]::text[]) INTO v_codes
        FROM store_master WHERE id = ANY (v_values::uuid[]) AND store_code IS NOT NULL;
      ELSE
        SELECT COALESCE(array_agg(sku_code), ARRAY[]::text[]) INTO v_codes
        FROM product_sku_master WHERE id = ANY (v_values::uuid[]) AND sku_code IS NOT NULL;
      END IF;
      SELECT string_agg(format('%L', x), ',') INTO v_list FROM unnest(v_values) x;
      v_eq := format('%s%I IN (%s)', p_alias, v_id_col, v_list);
      IF COALESCE(array_length(v_codes, 1), 0) > 0 THEN
        SELECT string_agg(format('%L', x), ',') INTO v_list FROM unnest(v_codes) x;
        v_eq := format('(%s OR %s%I IN (%s))', v_eq, p_alias, v_code_col, v_list);
      END IF;
      RETURN CASE WHEN v_operator = 'in' THEN v_eq
                  ELSE format('NOT COALESCE(%s, FALSE)', v_eq) END;
    ELSE
      RETURN format('%s%I = %L', p_alias, v_id_col, v_value);
    END IF;
  END IF;

  CASE v_operator
    WHEN 'equals', 'eq' THEN
      IF v_field = 'tel' THEN
        RETURN format('fn_normalize_thai_phone(%s%I) = fn_normalize_thai_phone(%L)', p_alias, v_field, v_value);
      END IF;
      RETURN format('%s%I = %L', p_alias, v_field, v_value);
    WHEN 'not_equals' THEN
      IF v_field = 'tel' THEN
        RETURN format('fn_normalize_thai_phone(%s%I) IS DISTINCT FROM fn_normalize_thai_phone(%L)', p_alias, v_field, v_value);
      END IF;
      RETURN format('%s%I != %L', p_alias, v_field, v_value);
    WHEN 'greater_than', 'gt' THEN
      RETURN format('%s%I > %L', p_alias, v_field, v_value);
    WHEN 'greater_or_equal', 'greater_than_or_equals', 'gte' THEN
      RETURN format('%s%I >= %L', p_alias, v_field, v_value);
    WHEN 'less_than', 'lt' THEN
      RETURN format('%s%I < %L', p_alias, v_field, v_value);
    WHEN 'less_or_equal', 'less_than_or_equals', 'lte' THEN
      RETURN format('%s%I <= %L', p_alias, v_field, v_value);
    WHEN 'contains' THEN
      RETURN format('%s%I ILIKE %L', p_alias, v_field, '%' || v_value || '%');
    WHEN 'not_contains' THEN
      RETURN format('(%s%I IS NULL OR %s%I NOT ILIKE %L)', p_alias, v_field, p_alias, v_field, '%' || v_value || '%');
    WHEN 'starts_with' THEN
      RETURN format('%s%I ILIKE %L', p_alias, v_field, v_value || '%');
    WHEN 'ends_with' THEN
      RETURN format('%s%I ILIKE %L', p_alias, v_field, '%' || v_value);
    WHEN 'is_empty' THEN
      RETURN format('(%s%I IS NULL OR %s%I::text = %L)', p_alias, v_field, p_alias, v_field, '');
    WHEN 'is_not_empty' THEN
      RETURN format('(%s%I IS NOT NULL AND %s%I::text <> %L)', p_alias, v_field, p_alias, v_field, '');
    WHEN 'is_null' THEN
      RETURN format('%s%I IS NULL', p_alias, v_field);
    WHEN 'is_not_null' THEN
      RETURN format('%s%I IS NOT NULL', p_alias, v_field);
    WHEN 'is_true' THEN
      RETURN format('%s%I IS TRUE', p_alias, v_field);
    WHEN 'is_false' THEN
      RETURN format('%s%I IS FALSE', p_alias, v_field);
    WHEN 'in' THEN
      IF COALESCE(array_length(v_values, 1), 0) = 0 THEN RETURN 'FALSE'; END IF;
      SELECT string_agg(format('%L', x), ',') INTO v_list FROM unnest(v_values) x;
      RETURN format('%s%I IN (%s)', p_alias, v_field, v_list);
    WHEN 'not_in' THEN
      IF COALESCE(array_length(v_values, 1), 0) = 0 THEN RETURN 'TRUE'; END IF;
      SELECT string_agg(format('%L', x), ',') INTO v_list FROM unnest(v_values) x;
      RETURN format('(%s%I IS NULL OR %s%I NOT IN (%s))', p_alias, v_field, p_alias, v_field, v_list);
    WHEN 'birthday_today', 'anniversary_today', 'date_anniversary_today' THEN
      RETURN format(
        'fn_amp_lifecycle_date_matches(%s%I::date, %L, now(), %L, %s)',
        p_alias, v_field, v_operator, v_timezone, v_days_offset
      );
    WHEN 'month_in', 'month_not_in' THEN
      SELECT string_agg(DISTINCT x::int::text, ',') INTO v_list
      FROM unnest(v_values) x
      WHERE CASE WHEN x ~ '^[0-9]{1,2}$' THEN x::int BETWEEN 1 AND 12 ELSE false END;
      IF v_list IS NULL THEN
        RETURN 'FALSE';
      END IF;
      RETURN format(
        'COALESCE(EXTRACT(MONTH FROM %s%I::date)::int %s (%s), false)',
        p_alias, v_field,
        CASE WHEN v_operator = 'month_in' THEN 'IN' ELSE 'NOT IN' END,
        v_list
      );
    WHEN 'month_current' THEN
      RETURN format(
        'COALESCE(EXTRACT(MONTH FROM %s%I::date)::int = EXTRACT(MONTH FROM timezone(%L, now()))::int, false)',
        p_alias, v_field, COALESCE(NULLIF(v_timezone, ''), 'UTC')
      );
    ELSE
      RAISE EXCEPTION 'Unknown AMP condition operator: %', v_operator;
  END CASE;
END;
$function$;
