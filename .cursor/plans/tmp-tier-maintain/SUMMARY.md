# Tier maintain — function dump findings

Source: live `pg_get_functiondef` on `wkevmsedchftztoolkmi` (read-only). Line numbers refer to the `.sql` files in this folder.

---

## 1. `calculate_maintain_deadline` — EXISTS / `v_has_maintain`

`maintain_enabled` is **derived**, not a column. Early return if no active maintain amount exists on the ladder:

```21:34:calculate_maintain_deadline.sql
  -- maintain_enabled is derived: the ladder must carry at least one active maintain amount.
  SELECT EXISTS (
    SELECT 1
    FROM public.tier_conditions tc
    JOIN public.tier_master tm ON tm.id = tc.tier_id
    WHERE tm.merchant_id = p_merchant_id
      AND tm.user_type = p_user_type
      AND tc.condition_type = 'maintain'
      AND tc.active_status IS TRUE
  ) INTO v_has_maintain;

  IF NOT v_has_maintain THEN
    RETURN;
  END IF;
```

After that: `calendar_year` → period end as deadline / `fixed_period`; else `achieved_date + rolling_months` / `rolling`.

---

## 2. `evaluate_user_tier_status` — maintain lookup, `v_maintain_qualified`, deadline, downgrade

**Deadline lookup** (lines 89–91): reads `tier_evaluation_tracking.maintain_deadline` for the user/merchant.

**Qualification** (lines 93–105): only when deadline is set **and** `deadline <= evaluation_date`, load the current tier’s highest active maintain `amount`; if metric is below that amount → `v_maintain_qualified := false`. Defaults to `true` (line 19). No deadline / deadline in future → stay qualified without checking amount.

**Downgrade target** (lines 107–129):
- Compute `v_upgrade_tier_id` (higher ladder rungs still met) and `v_downgrade_tier_id` (highest **lower** rung still met by upgrade amount).
- If upgrade possible → `upgrade`.
- `ELSIF NOT v_maintain_qualified` → `downgrade`, `recommended_tier_id := COALESCE(v_downgrade_tier_id, v_entry_tier_id)` (D1 comment).
- Else → `maintain`, keep current tier.

Key block:

```89:133:evaluate_user_tier_status.sql
  SELECT tet.maintain_deadline INTO v_maintain_deadline
  FROM public.tier_evaluation_tracking tet
  WHERE tet.user_id = p_user_id AND tet.merchant_id = p_merchant_id;

  IF v_maintain_deadline IS NOT NULL AND v_maintain_deadline <= p_evaluation_date THEN
    SELECT tc.amount INTO v_maintain_amount
    ...
    IF v_maintain_amount IS NOT NULL AND v_metric_value < v_maintain_amount THEN
      v_maintain_qualified := false;
    END IF;
  END IF;
  ...
  ELSIF NOT v_maintain_qualified THEN
    -- D1: land on the highest lower rung the member still qualifies for, else the entry rung.
    v_action := 'downgrade';
    v_recommended_tier_id := COALESCE(v_downgrade_tier_id, v_entry_tier_id);
```

---

## 3. `ensure_tier_progress` — how `v_maintain_threshold` is set

From active `tier_conditions` on **effective** tier (`COALESCE(recommended, current)`), `condition_type = 'maintain'`, highest amount:

```80:92:ensure_tier_progress.sql
  IF v_effective_tier_id IS NOT NULL THEN
    SELECT tc.amount INTO v_maintain_threshold
    FROM public.tier_conditions tc
    WHERE tc.tier_id = v_effective_tier_id
      AND tc.condition_type = 'maintain'
      AND tc.active_status IS TRUE
    ORDER BY tc.amount DESC NULLS LAST
    LIMIT 1;

    IF v_maintain_threshold IS NOT NULL THEN
      v_maintain_metric := v_cfg.metric;
      v_maintain_progress := v_metric_value * 100.0 / NULLIF(v_maintain_threshold, 0);
    END IF;
  END IF;
```

(Deadline refresh via `calculate_maintain_deadline` only runs on upgrade/downgrade chokepoint path, lines 122–152.)

---

## 4. `bff_get_tier_program_config` — `maintain_enabled` EXISTS

Per-row field on program config, same EXISTS pattern as calculate:

```27:34:bff_get_tier_program_config.sql
           'maintain_enabled', EXISTS (
             SELECT 1 FROM public.tier_conditions tc
             JOIN public.tier_master tm ON tm.id = tc.tier_id
             WHERE tm.merchant_id = c.merchant_id
               AND tm.user_type = c.user_type
               AND tc.condition_type = 'maintain'
               AND tc.active_status IS TRUE
           )
```

---

## 5. `bff_upsert_tier_program_config` — validation structure; where to add `maintain_mode` + side-effects

**Structure today:**
1. Merchant context (lines 17–21)
2. Parse fields from `p_config` (lines 23–31): `user_type`, `metric`, `period_type`, `period_start_month`, `rolling_months`, `upgrade_timing`, `program_start_date` — **no maintain_mode**
3. Validation gates (lines 33–60): `INVALID_METRIC` → `INVALID_PERIOD_TYPE` → calendar vs rolling month checks → `INVALID_UPGRADE_TIMING`
4. UPSERT into `tier_program_config` columns listed above (lines 62–77)
5. Success / EXCEPTION (lines 79–84)

**Where to add:**
- **Parse + validate `maintain_mode`:** after `v_upgrade_timing` parse (~line 30) and after the `INVALID_UPGRADE_TIMING` block (~line 60), before INSERT — mirror the enum check pattern.
- **Persist:** add column to INSERT / ON CONFLICT UPDATE lists (lines 62–75).
- **Transition side-effects:** after successful UPSERT / `RETURNING id` (~line 77), before the success RETURN — compare old vs new mode (need a pre-read of existing row) and run any clear/recompute of tracking/progress. Currently there are **zero** post-upsert side-effects.

---

## 6. `bff_upsert_tier_with_conditions` — maintain arrays + rejected-fields loop

**Rejected-fields loop (lines 36–70):**
1. Top-level: reject `ranking`, `entry_tier` if present on `tier_data`.
2. Concatenate `upgrade` + `maintain` arrays; for each condition object, reject retired keys: `metric`, `window_type`, `window_months`, `window_start`, `frequency`, `window_start_field`, `upgrade_evaluation_timing`, `upgrade_evaluation_value`.
3. If any rejected → `UNSUPPORTED_FIELDS` with `data.rejected_fields`.

**Maintain write (lines 212–241):** if `tier_data->'maintain'` is an array, upsert-by-id each element (`amount`, `active_status` only) with `condition_type = 'maintain'`, collect `v_maintain_ids`, then DELETE maintain rows for the tier not in that list. Mirrors the upgrade block.

---

## 7. `get_tier_conditions_by_type` — maintain key in return

- Mode `new` (line 25): `'maintain', '[]'::jsonb`
- Mode `edit`: aggregates maintain rows into `v_maintain_conditions` (lines 66–74), returns `'maintain', v_maintain_conditions` (line 87) alongside `'upgrade'`.
