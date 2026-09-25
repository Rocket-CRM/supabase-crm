-- chokepoint_post_user_event: auto-assign 8-digit member_code on create when omitted

CREATE OR REPLACE FUNCTION public.chokepoint_post_user_event(
  p_event_type text,
  p_merchant_id uuid DEFAULT NULL::uuid,
  p_user_id uuid DEFAULT NULL::uuid,
  p_changes jsonb DEFAULT '{}'::jsonb,
  p_skip_side_effects boolean DEFAULT false,
  p_skip_cdc boolean DEFAULT false,
  p_actor jsonb DEFAULT '{}'::jsonb,
  p_dedup_key text DEFAULT NULL::text,
  p_metadata jsonb DEFAULT '{}'::jsonb
)
 RETURNS user_accounts
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_old                public.user_accounts;
  v_row                public.user_accounts;
  v_changes            jsonb := COALESCE(p_changes, '{}'::jsonb);
  v_persona_id         uuid;
  v_user_type          public.user_type;
  v_group_user_type    public.user_type;
  v_entry_tier_id      uuid;
  v_persona_changed    boolean := false;
  v_tier_changed       boolean := false;
  v_old_rank           smallint;
  v_new_rank           smallint;
  v_tier_change_type   public.tier_change_type;
  v_tier_change_reason text;
  v_tier_metadata      jsonb;
  v_skip_emit          boolean := COALESCE(p_metadata->>'_skip_emit','false') = 'true';
  v_user_id            uuid;
  v_member_code        text;
  v_supplied_member_code text;
  v_attempt            integer;
  v_auto_assigned      boolean := false;
  v_constraint_name    text;
BEGIN
  IF p_event_type IS NULL OR p_event_type NOT IN ('create','update','soft_delete','hard_delete') THEN
    RAISE EXCEPTION 'chokepoint_post_user_event: p_event_type must be one of (create, update, soft_delete, hard_delete), got %', p_event_type;
  END IF;

  IF p_event_type = 'create' THEN
    IF p_merchant_id IS NULL THEN
      RAISE EXCEPTION 'chokepoint_post_user_event: p_merchant_id is required for event_type=create';
    END IF;

    v_persona_id := NULLIF(v_changes->>'persona_id','')::uuid;
    IF v_persona_id IS NOT NULL AND NOT (v_changes ? 'user_type') THEN
      SELECT pgm.user_type INTO v_group_user_type
      FROM public.persona_master pm
      JOIN public.persona_group_master pgm ON pm.group_id = pgm.id
      WHERE pm.id = v_persona_id;
      IF v_group_user_type IS NOT NULL THEN
        v_changes := v_changes || jsonb_build_object('user_type', v_group_user_type::text);
      END IF;
    END IF;

    IF NULLIF(v_changes->>'tier_id','') IS NULL THEN
      v_user_type := COALESCE(NULLIF(v_changes->>'user_type','')::public.user_type, 'buyer'::public.user_type);
      SELECT tm.id INTO v_entry_tier_id
      FROM public.tier_master tm
      WHERE tm.merchant_id = p_merchant_id
        AND (tm.user_type = v_user_type OR tm.user_type IS NULL)
        AND public.fn_tier_matches_persona(tm.id, v_persona_id)
        AND tm.entry_tier = true
      ORDER BY
        CASE WHEN EXISTS (SELECT 1 FROM public.tier_persona_assignments tpa WHERE tpa.tier_id = tm.id) THEN 0 ELSE 1 END,
        tm.ranking ASC
      LIMIT 1;
      IF v_entry_tier_id IS NOT NULL THEN
        v_changes := v_changes || jsonb_build_object('tier_id', v_entry_tier_id);
      END IF;
    END IF;

    v_user_id := COALESCE(NULLIF(v_changes->>'id','')::uuid, gen_random_uuid());
    v_supplied_member_code := NULLIF(TRIM(v_changes->>'member_code'), '');

    IF v_supplied_member_code IS NOT NULL THEN
      INSERT INTO public.user_accounts (
        id, auth_user_id, merchant_id, type_id, tier_id,
        birth_date, line_id, user_type,
        tier_lock_downgrade, tier_locked_downgrade_until, persona_id,
        channel_email, channel_sms, channel_line, channel_push,
        email, tel, role, external_user_id, id_card,
        firstname, lastname, fullname, user_stage,
        is_signup_form_complete, gender, image, marketplace_external_ids,
        mongo_id, member_code, acquisition_source, is_active, deleted_at, created_at, skip_cdc
      ) VALUES (
        v_user_id,
        NULLIF(v_changes->>'auth_user_id','')::uuid,
        p_merchant_id,
        NULLIF(v_changes->>'type_id','')::uuid,
        NULLIF(v_changes->>'tier_id','')::uuid,
        NULLIF(v_changes->>'birth_date','')::date,
        NULLIF(v_changes->>'line_id',''),
        COALESCE(NULLIF(v_changes->>'user_type','')::public.user_type, 'buyer'::public.user_type),
        COALESCE((v_changes->>'tier_lock_downgrade')::boolean, false),
        NULLIF(v_changes->>'tier_locked_downgrade_until','')::timestamptz,
        NULLIF(v_changes->>'persona_id','')::uuid,
        COALESCE((v_changes->>'channel_email')::boolean, true),
        COALESCE((v_changes->>'channel_sms')::boolean,   false),
        COALESCE((v_changes->>'channel_line')::boolean,  true),
        COALESCE((v_changes->>'channel_push')::boolean,  true),
        NULLIF(v_changes->>'email',''),
        NULLIF(v_changes->>'tel',''),
        COALESCE(NULLIF(v_changes->>'role','')::public.role, 'user'::public.role),
        NULLIF(v_changes->>'external_user_id',''),
        NULLIF(v_changes->>'id_card',''),
        NULLIF(v_changes->>'firstname',''),
        NULLIF(v_changes->>'lastname',''),
        NULLIF(v_changes->>'fullname',''),
        COALESCE(NULLIF(v_changes->>'user_stage',''), 'lead'),
        COALESCE((v_changes->>'is_signup_form_complete')::boolean, false),
        NULLIF(v_changes->>'gender',''),
        NULLIF(v_changes->>'image',''),
        COALESCE(v_changes->'marketplace_external_ids', '{}'::jsonb),
        NULLIF(v_changes->>'mongo_id',''),
        v_supplied_member_code,
        public.fn_resolve_acquisition_source_code(p_merchant_id, v_changes->>'acquisition_source'),
        COALESCE((v_changes->>'is_active')::boolean, true),
        NULLIF(v_changes->>'deleted_at','')::timestamptz,
        COALESCE(NULLIF(v_changes->>'created_at','')::timestamptz, now()),
        COALESCE(p_skip_cdc, false)
      )
      RETURNING * INTO v_row;

    ELSIF v_changes ? 'member_code' THEN
      INSERT INTO public.user_accounts (
        id, auth_user_id, merchant_id, type_id, tier_id,
        birth_date, line_id, user_type,
        tier_lock_downgrade, tier_locked_downgrade_until, persona_id,
        channel_email, channel_sms, channel_line, channel_push,
        email, tel, role, external_user_id, id_card,
        firstname, lastname, fullname, user_stage,
        is_signup_form_complete, gender, image, marketplace_external_ids,
        mongo_id, member_code, acquisition_source, is_active, deleted_at, created_at, skip_cdc
      ) VALUES (
        v_user_id,
        NULLIF(v_changes->>'auth_user_id','')::uuid,
        p_merchant_id,
        NULLIF(v_changes->>'type_id','')::uuid,
        NULLIF(v_changes->>'tier_id','')::uuid,
        NULLIF(v_changes->>'birth_date','')::date,
        NULLIF(v_changes->>'line_id',''),
        COALESCE(NULLIF(v_changes->>'user_type','')::public.user_type, 'buyer'::public.user_type),
        COALESCE((v_changes->>'tier_lock_downgrade')::boolean, false),
        NULLIF(v_changes->>'tier_locked_downgrade_until','')::timestamptz,
        NULLIF(v_changes->>'persona_id','')::uuid,
        COALESCE((v_changes->>'channel_email')::boolean, true),
        COALESCE((v_changes->>'channel_sms')::boolean,   false),
        COALESCE((v_changes->>'channel_line')::boolean,  true),
        COALESCE((v_changes->>'channel_push')::boolean,  true),
        NULLIF(v_changes->>'email',''),
        NULLIF(v_changes->>'tel',''),
        COALESCE(NULLIF(v_changes->>'role','')::public.role, 'user'::public.role),
        NULLIF(v_changes->>'external_user_id',''),
        NULLIF(v_changes->>'id_card',''),
        NULLIF(v_changes->>'firstname',''),
        NULLIF(v_changes->>'lastname',''),
        NULLIF(v_changes->>'fullname',''),
        COALESCE(NULLIF(v_changes->>'user_stage',''), 'lead'),
        COALESCE((v_changes->>'is_signup_form_complete')::boolean, false),
        NULLIF(v_changes->>'gender',''),
        NULLIF(v_changes->>'image',''),
        COALESCE(v_changes->'marketplace_external_ids', '{}'::jsonb),
        NULLIF(v_changes->>'mongo_id',''),
        NULL,
        public.fn_resolve_acquisition_source_code(p_merchant_id, v_changes->>'acquisition_source'),
        COALESCE((v_changes->>'is_active')::boolean, true),
        NULLIF(v_changes->>'deleted_at','')::timestamptz,
        COALESCE(NULLIF(v_changes->>'created_at','')::timestamptz, now()),
        COALESCE(p_skip_cdc, false)
      )
      RETURNING * INTO v_row;

    ELSE
      FOR v_attempt IN 0..5 LOOP
        v_member_code := public.fn_derive_member_code(v_user_id, p_merchant_id, v_attempt);
        BEGIN
          INSERT INTO public.user_accounts (
            id, auth_user_id, merchant_id, type_id, tier_id,
            birth_date, line_id, user_type,
            tier_lock_downgrade, tier_locked_downgrade_until, persona_id,
            channel_email, channel_sms, channel_line, channel_push,
            email, tel, role, external_user_id, id_card,
            firstname, lastname, fullname, user_stage,
            is_signup_form_complete, gender, image, marketplace_external_ids,
            mongo_id, member_code, acquisition_source, is_active, deleted_at, created_at, skip_cdc
          ) VALUES (
            v_user_id,
            NULLIF(v_changes->>'auth_user_id','')::uuid,
            p_merchant_id,
            NULLIF(v_changes->>'type_id','')::uuid,
            NULLIF(v_changes->>'tier_id','')::uuid,
            NULLIF(v_changes->>'birth_date','')::date,
            NULLIF(v_changes->>'line_id',''),
            COALESCE(NULLIF(v_changes->>'user_type','')::public.user_type, 'buyer'::public.user_type),
            COALESCE((v_changes->>'tier_lock_downgrade')::boolean, false),
            NULLIF(v_changes->>'tier_locked_downgrade_until','')::timestamptz,
            NULLIF(v_changes->>'persona_id','')::uuid,
            COALESCE((v_changes->>'channel_email')::boolean, true),
            COALESCE((v_changes->>'channel_sms')::boolean,   false),
            COALESCE((v_changes->>'channel_line')::boolean,  true),
            COALESCE((v_changes->>'channel_push')::boolean,  true),
            NULLIF(v_changes->>'email',''),
            NULLIF(v_changes->>'tel',''),
            COALESCE(NULLIF(v_changes->>'role','')::public.role, 'user'::public.role),
            NULLIF(v_changes->>'external_user_id',''),
            NULLIF(v_changes->>'id_card',''),
            NULLIF(v_changes->>'firstname',''),
            NULLIF(v_changes->>'lastname',''),
            NULLIF(v_changes->>'fullname',''),
            COALESCE(NULLIF(v_changes->>'user_stage',''), 'lead'),
            COALESCE((v_changes->>'is_signup_form_complete')::boolean, false),
            NULLIF(v_changes->>'gender',''),
            NULLIF(v_changes->>'image',''),
            COALESCE(v_changes->'marketplace_external_ids', '{}'::jsonb),
            NULLIF(v_changes->>'mongo_id',''),
            v_member_code,
            public.fn_resolve_acquisition_source_code(p_merchant_id, v_changes->>'acquisition_source'),
            COALESCE((v_changes->>'is_active')::boolean, true),
            NULLIF(v_changes->>'deleted_at','')::timestamptz,
            COALESCE(NULLIF(v_changes->>'created_at','')::timestamptz, now()),
            COALESCE(p_skip_cdc, false)
          )
          RETURNING * INTO v_row;
          v_auto_assigned := true;
          EXIT;
        EXCEPTION
          WHEN unique_violation THEN
            GET STACKED DIAGNOSTICS v_constraint_name = CONSTRAINT_NAME;
            IF NOT public.fn_is_member_code_unique_violation(v_constraint_name) THEN
              RAISE;
            END IF;
        END;
      END LOOP;

      IF NOT v_auto_assigned THEN
        RAISE EXCEPTION 'chokepoint_post_user_event: member_code_assignment_exhausted for user_id % merchant %', v_user_id, p_merchant_id;
      END IF;
    END IF;

    IF NOT p_skip_side_effects AND v_row.tier_id IS NOT NULL THEN
      INSERT INTO public.tier_progress (user_id, merchant_id, current_tier_id)
      VALUES (v_row.id, v_row.merchant_id, v_row.tier_id)
      ON CONFLICT (user_id, merchant_id) DO NOTHING;

      PERFORM public.chokepoint_post_tier_change(
        v_row.id,
        v_row.merchant_id,
        NULL,
        v_row.tier_id,
        'initial'::public.tier_change_type,
        COALESCE(p_metadata->>'tier_change_reason', 'New user signup'),
        NULL::jsonb,
        NULLIF(p_actor->>'actor_id','')::uuid,
        NULL
      );
    END IF;

    IF NOT v_skip_emit THEN
      PERFORM public.fn_chokepoint_emit_event(
        'crm.events.user',
        v_row.id::text,
        jsonb_build_object(
          'event',           'create',
          'user_event_type', 'create',
          'merchant_id',     p_merchant_id,
          'user_id',         v_row.id,
          'changes',         p_changes,
          'actor',           p_actor,
          'skip_cdc',        COALESCE(p_skip_cdc, false),
          'user_after',      to_jsonb(v_row),
          'occurred_at',     to_jsonb(now()),
          'source',          'chokepoint_post_user_event'
        )
      );
    END IF;

    RETURN v_row;
  END IF;

  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'chokepoint_post_user_event: p_user_id is required for event_type=%', p_event_type;
  END IF;

  SELECT * INTO v_old FROM public.user_accounts WHERE id = p_user_id;
  IF v_old.id IS NULL THEN
    RAISE EXCEPTION 'chokepoint_post_user_event: user_id % not found', p_user_id;
  END IF;

  IF p_event_type = 'hard_delete' THEN
    DELETE FROM public.user_accounts WHERE id = p_user_id;

    IF NOT v_skip_emit THEN
      PERFORM public.fn_chokepoint_emit_event(
        'crm.events.user',
        v_old.id::text,
        jsonb_build_object(
          'event',           'hard_delete',
          'user_event_type', 'hard_delete',
          'merchant_id',     COALESCE(p_merchant_id, v_old.merchant_id),
          'user_id',         v_old.id,
          'changes',         p_changes,
          'actor',           p_actor,
          'skip_cdc',        COALESCE(p_skip_cdc, false),
          'user_after',      NULL,
          'occurred_at',     to_jsonb(now()),
          'source',          'chokepoint_post_user_event'
        )
      );
    END IF;

    RETURN v_old;
  END IF;

  IF p_event_type = 'soft_delete' THEN
    v_changes := COALESCE(p_changes,'{}'::jsonb) || jsonb_build_object(
      'firstname',                NULL,
      'lastname',                 NULL,
      'fullname',                 NULL,
      'email',                    NULL,
      'tel',                      NULL,
      'line_id',                  NULL,
      'birth_date',               NULL,
      'id_card',                  NULL,
      'gender',                   NULL,
      'image',                    NULL,
      'external_user_id',         NULL,
      'marketplace_external_ids', '{}'::jsonb,
      'deleted_at',               to_jsonb(now())
    );
  END IF;

  IF v_changes ? 'persona_id' THEN
    v_persona_id := NULLIF(v_changes->>'persona_id','')::uuid;
    v_persona_changed := (v_persona_id IS DISTINCT FROM v_old.persona_id);
    IF v_persona_changed AND v_persona_id IS NOT NULL AND NOT (v_changes ? 'user_type') THEN
      SELECT pgm.user_type INTO v_group_user_type
      FROM public.persona_master pm
      JOIN public.persona_group_master pgm ON pm.group_id = pgm.id
      WHERE pm.id = v_persona_id;
      IF v_group_user_type IS NOT NULL THEN
        v_changes := v_changes || jsonb_build_object('user_type', v_group_user_type::text);
      END IF;
    END IF;
  END IF;

  IF v_changes ? 'tier_id' THEN
    v_tier_changed := (NULLIF(v_changes->>'tier_id','')::uuid IS DISTINCT FROM v_old.tier_id);
  END IF;

  UPDATE public.user_accounts SET
    auth_user_id                 = CASE WHEN v_changes ? 'auth_user_id'                 THEN NULLIF(v_changes->>'auth_user_id','')::uuid                    ELSE auth_user_id END,
    type_id                      = CASE WHEN v_changes ? 'type_id'                      THEN NULLIF(v_changes->>'type_id','')::uuid                         ELSE type_id END,
    tier_id                      = CASE WHEN v_changes ? 'tier_id'                      THEN NULLIF(v_changes->>'tier_id','')::uuid                         ELSE tier_id END,
    birth_date                   = CASE WHEN v_changes ? 'birth_date'                   THEN NULLIF(v_changes->>'birth_date','')::date                      ELSE birth_date END,
    line_id                      = CASE WHEN v_changes ? 'line_id'                      THEN NULLIF(v_changes->>'line_id','')                               ELSE line_id END,
    user_type                    = CASE WHEN v_changes ? 'user_type'                    THEN COALESCE(NULLIF(v_changes->>'user_type','')::public.user_type, user_type) ELSE user_type END,
    tier_lock_downgrade          = CASE WHEN v_changes ? 'tier_lock_downgrade'          THEN (v_changes->>'tier_lock_downgrade')::boolean                   ELSE tier_lock_downgrade END,
    tier_locked_downgrade_until  = CASE WHEN v_changes ? 'tier_locked_downgrade_until'  THEN NULLIF(v_changes->>'tier_locked_downgrade_until','')::timestamptz ELSE tier_locked_downgrade_until END,
    persona_id                   = CASE WHEN v_changes ? 'persona_id'                   THEN NULLIF(v_changes->>'persona_id','')::uuid                      ELSE persona_id END,
    channel_email                = CASE WHEN v_changes ? 'channel_email'                THEN (v_changes->>'channel_email')::boolean                         ELSE channel_email END,
    channel_sms                  = CASE WHEN v_changes ? 'channel_sms'                  THEN (v_changes->>'channel_sms')::boolean                           ELSE channel_sms END,
    channel_line                 = CASE WHEN v_changes ? 'channel_line'                 THEN (v_changes->>'channel_line')::boolean                          ELSE channel_line END,
    channel_push                 = CASE WHEN v_changes ? 'channel_push'                 THEN (v_changes->>'channel_push')::boolean                          ELSE channel_push END,
    email                        = CASE WHEN v_changes ? 'email'                        THEN NULLIF(v_changes->>'email','')                                 ELSE email END,
    tel                          = CASE WHEN v_changes ? 'tel'                          THEN NULLIF(v_changes->>'tel','')                                   ELSE tel END,
    role                         = CASE WHEN v_changes ? 'role'                         THEN COALESCE(NULLIF(v_changes->>'role','')::public.role, role)     ELSE role END,
    external_user_id             = CASE WHEN v_changes ? 'external_user_id'             THEN NULLIF(v_changes->>'external_user_id','')                      ELSE external_user_id END,
    id_card                      = CASE WHEN v_changes ? 'id_card'                      THEN NULLIF(v_changes->>'id_card','')                               ELSE id_card END,
    firstname                    = CASE WHEN v_changes ? 'firstname'                    THEN NULLIF(v_changes->>'firstname','')                             ELSE firstname END,
    lastname                     = CASE WHEN v_changes ? 'lastname'                     THEN NULLIF(v_changes->>'lastname','')                              ELSE lastname END,
    fullname                     = CASE WHEN v_changes ? 'fullname'                     THEN NULLIF(v_changes->>'fullname','')                              ELSE fullname END,
    user_stage                   = CASE WHEN v_changes ? 'user_stage'                   THEN NULLIF(v_changes->>'user_stage','')                            ELSE user_stage END,
    is_signup_form_complete      = CASE WHEN v_changes ? 'is_signup_form_complete'      THEN (v_changes->>'is_signup_form_complete')::boolean               ELSE is_signup_form_complete END,
    gender                       = CASE WHEN v_changes ? 'gender'                       THEN NULLIF(v_changes->>'gender','')                                ELSE gender END,
    image                        = CASE WHEN v_changes ? 'image'                        THEN NULLIF(v_changes->>'image','')                                 ELSE image END,
    marketplace_external_ids     = CASE WHEN v_changes ? 'marketplace_external_ids'     THEN COALESCE(v_changes->'marketplace_external_ids','{}'::jsonb)   ELSE marketplace_external_ids END,
    mongo_id                     = CASE WHEN v_changes ? 'mongo_id'                     THEN NULLIF(v_changes->>'mongo_id','')                              ELSE mongo_id END,
    member_code                  = CASE WHEN v_changes ? 'member_code'                  THEN NULLIF(v_changes->>'member_code','')                           ELSE member_code END,
    acquisition_source           = CASE WHEN v_changes ? 'acquisition_source' AND acquisition_source IS NULL THEN public.fn_resolve_acquisition_source_code(COALESCE(p_merchant_id, v_old.merchant_id), v_changes->>'acquisition_source') ELSE acquisition_source END,
    is_active                    = CASE WHEN v_changes ? 'is_active'                    THEN (v_changes->>'is_active')::boolean                             ELSE is_active END,
    deleted_at                   = CASE WHEN v_changes ? 'deleted_at'                   THEN NULLIF(v_changes->>'deleted_at','')::timestamptz               ELSE deleted_at END,
    skip_cdc                     = CASE WHEN p_skip_cdc THEN true                                                                                          ELSE skip_cdc END,
    updated_at                   = now()
  WHERE id = p_user_id
  RETURNING * INTO v_row;

  IF NOT p_skip_side_effects THEN
    IF v_persona_changed THEN
      IF v_old.persona_id IS NOT NULL THEN
        UPDATE public.user_benefit
           SET status = 'cancelled'
         WHERE user_id     = v_row.id
           AND source_type = 'persona'
           AND source_id   = v_old.persona_id
           AND status      = 'active';
      END IF;

      IF v_row.persona_id IS NOT NULL THEN
        PERFORM public.fn_auto_assign_on_persona(v_row.id, v_row.persona_id);
      END IF;

      PERFORM public.process_tier_event(v_row.id, v_row.merchant_id);
    END IF;

    IF v_tier_changed THEN
      v_tier_change_type := NULLIF(p_metadata->>'tier_change_type','')::public.tier_change_type;
      IF v_tier_change_type IS NULL THEN
        IF v_old.tier_id IS NULL THEN
          v_tier_change_type := 'initial'::public.tier_change_type;
        ELSIF v_row.tier_id IS NULL THEN
          v_tier_change_type := 'manual'::public.tier_change_type;
        ELSE
          SELECT ranking INTO v_old_rank FROM public.tier_master WHERE id = v_old.tier_id;
          SELECT ranking INTO v_new_rank FROM public.tier_master WHERE id = v_row.tier_id;
          v_tier_change_type := CASE
            WHEN v_new_rank IS NULL OR v_old_rank IS NULL THEN 'manual'::public.tier_change_type
            WHEN v_new_rank > v_old_rank                  THEN 'upgrade'::public.tier_change_type
            WHEN v_new_rank < v_old_rank                  THEN 'downgrade'::public.tier_change_type
            ELSE 'manual'::public.tier_change_type
          END;
        END IF;
      END IF;
      v_tier_change_reason := COALESCE(p_metadata->>'tier_change_reason', 'Tier change via chokepoint_post_user_event');
      v_tier_metadata      := CASE WHEN p_metadata ? 'tier_evaluation' THEN p_metadata->'tier_evaluation' ELSE NULL END;

      PERFORM public.chokepoint_post_tier_change(
        v_row.id,
        v_row.merchant_id,
        v_old.tier_id,
        v_row.tier_id,
        v_tier_change_type,
        v_tier_change_reason,
        v_tier_metadata,
        NULLIF(p_actor->>'actor_id','')::uuid,
        NULL
      );
    END IF;
  END IF;

  IF NOT v_skip_emit THEN
    PERFORM public.fn_chokepoint_emit_event(
      'crm.events.user',
      v_row.id::text,
      jsonb_build_object(
        'event',           p_event_type,
        'user_event_type', p_event_type,
        'merchant_id',     COALESCE(p_merchant_id, v_row.merchant_id),
        'user_id',         v_row.id,
        'changes',         p_changes,
        'actor',           p_actor,
        'skip_cdc',        COALESCE(p_skip_cdc, false),
        'user_after',      to_jsonb(v_row),
        'occurred_at',     to_jsonb(now()),
        'source',          'chokepoint_post_user_event'
      )
    );
  END IF;

  RETURN v_row;
END;
$function$;
