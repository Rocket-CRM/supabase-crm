-- Ausiris AMP workflows + historical execution/engagement for analytics time series.
-- Triggers stay inactive so cron/CDC cannot send live LINE.

CREATE OR REPLACE FUNCTION public.custom_ausiris_demo_seed_workflows()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_mid uuid := custom_ausiris_demo_merchant_id();
  v_c0 uuid;
  v_aud_win uuid;
  v_aud_wel uuid;
  v_tag_new uuid;
  v_tag_risk uuid;
  v_wf_wel uuid := md5('aus-wf-welcome')::uuid;
  v_wf_con uuid := md5('aus-wf-congrats')::uuid;
  v_wf_win uuid := md5('aus-wf-winback')::uuid;
  v_n_wel_entry uuid := md5('aus-wf-welcome:entry')::uuid;
  v_n_wel_line uuid := md5('aus-wf-welcome:line')::uuid;
  v_n_wel_pts uuid := md5('aus-wf-welcome:points')::uuid;
  v_n_con_entry uuid := md5('aus-wf-congrats:entry')::uuid;
  v_n_con_line uuid := md5('aus-wf-congrats:line')::uuid;
  v_n_con_pts uuid := md5('aus-wf-congrats:points')::uuid;
  v_n_win_entry uuid := md5('aus-wf-winback:entry')::uuid;
  v_n_win_line uuid := md5('aus-wf-winback:line')::uuid;
  v_n_win_pts uuid := md5('aus-wf-winback:points')::uuid;
  v_n_win_wait uuid := md5('aus-wf-winback:wait')::uuid;
  v_n_win_chk uuid := md5('aus-wf-winback:check')::uuid;
  v_n_win_final uuid := md5('aus-wf-winback:final')::uuid;
  v_url_rewards text := 'https://ausiris.rocket-loyalty.app/?page=rewards';
  v_url_missions text := 'https://ausiris.rocket-loyalty.app/?page=missions';
  v_runs int;
  v_logs int;
  v_links int;
  v_clicks int;
BEGIN
  PERFORM custom_ausiris_demo_set_ctx();

  SELECT id INTO v_c0
  FROM user_accounts
  WHERE merchant_id = v_mid AND tel = '0812345678'
  LIMIT 1;

  SELECT id INTO v_aud_win FROM amp_audience_master
  WHERE merchant_id = v_mid AND funnel_id IS NULL AND name = 'Ausiris Win-back' LIMIT 1;
  SELECT id INTO v_aud_wel FROM amp_audience_master
  WHERE merchant_id = v_mid AND funnel_id IS NULL AND name = 'Ausiris Welcome' LIMIT 1;

  v_tag_new := (custom_ausiris_demo_cfg('tag','New Member')->>'id')::uuid;
  v_tag_risk := (custom_ausiris_demo_cfg('tag','At Risk')->>'id')::uuid;

  DELETE FROM amp_engagement_event e
  USING workflow_master w
  WHERE e.workflow_id = w.id AND w.merchant_id = v_mid AND w.workflow_code LIKE 'aus-wf-%';

  DELETE FROM amp_tracked_link t
  USING workflow_master w
  WHERE t.workflow_id = w.id AND w.merchant_id = v_mid AND w.workflow_code LIKE 'aus-wf-%';

  DELETE FROM workflow_log l
  USING workflow_master w
  WHERE l.workflow_id = w.id AND w.merchant_id = v_mid AND w.workflow_code LIKE 'aus-wf-%';

  DELETE FROM workflow_master
  WHERE merchant_id = v_mid AND workflow_code LIKE 'aus-wf-%';

  INSERT INTO workflow_master (
    id, merchant_id, workflow_code, name, description, is_active,
    run_mode, scope, domain, created_at, updated_at, config
  ) VALUES
    (v_wf_wel, v_mid, 'aus-wf-welcome', 'Ausiris Welcome',
     'Welcome new members with a LINE message and 50 points.',
     true, 'on_event', 'user', 'loyalty',
     timestamptz '2026-02-20 04:00:00+07', now(), '{}'::jsonb),
    (v_wf_con, v_mid, 'aus-wf-congrats', 'Ausiris Congratulations',
     'Congratulate the first completed purchase and award 100 points.',
     true, 'on_event', 'user', 'loyalty',
     timestamptz '2026-02-20 04:05:00+07', now(), '{}'::jsonb),
    (v_wf_win, v_mid, 'aus-wf-winback', 'Ausiris Win-back',
     'Win back At Risk members with a LINE offer, 150 points, and a 7-day follow-up.',
     true, 'on_event', 'user', 'loyalty',
     timestamptz '2026-02-20 04:10:00+07', now(), '{}'::jsonb);

  INSERT INTO workflow_node (
    id, workflow_id, merchant_id, node_type, node_name, node_config,
    position_x, position_y, created_at, updated_at
  ) VALUES
    (v_n_wel_entry, v_wf_wel, v_mid, 'condition', 'New member?',
     jsonb_build_object('label','New member?','match','all','groups_operator','OR','groups', jsonb_build_array(
       jsonb_build_object('id','g1','type','simple','collection','user_tags','conditions',
         jsonb_build_array(jsonb_build_object('field','tag_id','operator','equals','value', v_tag_new))),
       jsonb_build_object('id','g2','type','simple','collection','amp_audience_member','conditions',
         jsonb_build_array(jsonb_build_object('field','audience_id','operator','is_member_of','value', v_aud_wel::text)))
     )), 500, 0, timestamptz '2026-02-20 04:00:01+07', now()),
    (v_n_wel_line, v_wf_wel, v_mid, 'action', 'LINE: Welcome to Ausiris',
     jsonb_build_object('channel','line','action_type','send_line_message',
       'content', 'ยินดีต้อนรับสู่ Ausiris Rewards ค่ะ 🌟' || E'\n' ||
                  'รับ 50 คะแนนต้อนรับ เริ่มออมทองและสะสมคะแนนได้เลย' || E'\n' ||
                  'ดูรางวัล: ' || v_url_rewards),
     500, 200, timestamptz '2026-02-20 04:00:02+07', now()),
    (v_n_wel_pts, v_wf_wel, v_mid, 'action', 'Award 50 welcome points',
     jsonb_build_object('action_type','award_currency','currency','points','amount',50,
       'description','Welcome to Ausiris Rewards'),
     500, 400, timestamptz '2026-02-20 04:00:03+07', now()),

    (v_n_con_entry, v_wf_con, v_mid, 'condition', 'First purchase?',
     jsonb_build_object('label','First purchase?','match','all','groups_operator','AND','groups', jsonb_build_array(
       jsonb_build_object('id','g1','type','aggregate','collection','purchase_ledger','aggregate','count',
         'field','id','operator','gte','value',1,'time_field','created_at','time_range','7 days')
     )), 500, 0, timestamptz '2026-02-20 04:05:01+07', now()),
    (v_n_con_line, v_wf_con, v_mid, 'action', 'LINE: Congratulations',
     jsonb_build_object('channel','line','action_type','send_line_message',
       'content', 'ยินดีด้วยค่ะ 🎉 การซื้อครั้งแรกของคุณสำเร็จแล้ว' || E'\n' ||
                  'รับ 100 คะแนนโบนัส แลกรางวัลได้ที่' || E'\n' || v_url_rewards),
     500, 200, timestamptz '2026-02-20 04:05:02+07', now()),
    (v_n_con_pts, v_wf_con, v_mid, 'action', 'Award 100 first-purchase points',
     jsonb_build_object('action_type','award_currency','currency','points','amount',100,
       'description','First purchase congratulations'),
     500, 400, timestamptz '2026-02-20 04:05:03+07', now()),

    (v_n_win_entry, v_wf_win, v_mid, 'condition', 'In Win-back audience?',
     jsonb_build_object('label','In Win-back audience?','match','all','groups_operator','AND','groups', jsonb_build_array(
       jsonb_build_object('id','g1','type','simple','collection','amp_audience_member','conditions',
         jsonb_build_array(jsonb_build_object('field','audience_id','operator','is_member_of','value', v_aud_win::text)))
     )), 500, 0, timestamptz '2026-02-20 04:10:01+07', now()),
    (v_n_win_line, v_wf_win, v_mid, 'action', 'LINE: We miss you',
     jsonb_build_object('channel','line','action_type','send_line_message',
       'content', 'คิดถึงคุณค่ะ เราเตรียมสิทธิ์พิเศษให้สมาชิกที่ห่างหาย' || E'\n' ||
                  'รับ 150 คะแนน + ส่วนลดออมทอง' || E'\n' || v_url_missions),
     500, 200, timestamptz '2026-02-20 04:10:02+07', now()),
    (v_n_win_pts, v_wf_win, v_mid, 'action', 'Award 150 win-back points',
     jsonb_build_object('action_type','award_currency','currency','points','amount',150,
       'description','Win-back incentive'),
     500, 400, timestamptz '2026-02-20 04:10:03+07', now()),
    (v_n_win_wait, v_wf_win, v_mid, 'wait', 'Wait 7 days',
     jsonb_build_object('unit','days','duration',7),
     500, 600, timestamptz '2026-02-20 04:10:04+07', now()),
    (v_n_win_chk, v_wf_win, v_mid, 'condition', 'Purchased in 7 days?',
     jsonb_build_object('label','Purchased in 7 days?','match','all','groups_operator','AND','groups', jsonb_build_array(
       jsonb_build_object('id','g1','type','aggregate','collection','purchase_ledger','aggregate','count',
         'field','id','operator','gte','value',1,'time_field','created_at','time_range','7 days')
     )), 500, 800, timestamptz '2026-02-20 04:10:05+07', now()),
    (v_n_win_final, v_wf_win, v_mid, 'action', 'LINE: Final win-back offer',
     jsonb_build_object('channel','line','action_type','send_line_message',
       'content', 'ข้อเสนอสุดท้ายสำหรับคุณ หมดเขต 7 วัน' || E'\n' ||
                  'กลับมาออมทองกับ Ausiris วันนี้' || E'\n' || v_url_rewards),
     100, 1000, timestamptz '2026-02-20 04:10:06+07', now());

  INSERT INTO workflow_edge (
    id, workflow_id, merchant_id, from_node_id, to_node_id, source_handle
  ) VALUES
    (md5('aus-wf-welcome:e1')::uuid, v_wf_wel, v_mid, v_n_wel_entry, v_n_wel_line, 'output-true'),
    (md5('aus-wf-welcome:e2')::uuid, v_wf_wel, v_mid, v_n_wel_line, v_n_wel_pts, 'default'),
    (md5('aus-wf-congrats:e1')::uuid, v_wf_con, v_mid, v_n_con_entry, v_n_con_line, 'output-true'),
    (md5('aus-wf-congrats:e2')::uuid, v_wf_con, v_mid, v_n_con_line, v_n_con_pts, 'default'),
    (md5('aus-wf-winback:e1')::uuid, v_wf_win, v_mid, v_n_win_entry, v_n_win_line, 'output-true'),
    (md5('aus-wf-winback:e2')::uuid, v_wf_win, v_mid, v_n_win_line, v_n_win_pts, 'default'),
    (md5('aus-wf-winback:e3')::uuid, v_wf_win, v_mid, v_n_win_pts, v_n_win_wait, 'default'),
    (md5('aus-wf-winback:e4')::uuid, v_wf_win, v_mid, v_n_win_wait, v_n_win_chk, 'default'),
    (md5('aus-wf-winback:e5')::uuid, v_wf_win, v_mid, v_n_win_chk, v_n_win_final, 'output-false');

  -- Inactive so live CDC / scheduled cron cannot send LINE.
  INSERT INTO workflow_trigger (
    id, workflow_id, merchant_id, trigger_type, trigger_table, trigger_operation,
    trigger_conditions, is_active, domain
  ) VALUES
    (md5('aus-wf-welcome:trg')::uuid, v_wf_wel, v_mid, 'database', 'user_accounts', 'INSERT', '{}'::jsonb, false, 'loyalty'),
    (md5('aus-wf-congrats:trg')::uuid, v_wf_con, v_mid, 'database', 'purchase_ledger', 'INSERT', '{}'::jsonb, false, 'loyalty'),
    (md5('aus-wf-winback:trg')::uuid, v_wf_win, v_mid, 'database', 'user_tags', 'INSERT',
     jsonb_build_object('tag_id', v_tag_risk), false, 'loyalty');

  CREATE TEMP TABLE _aus_wf_runs (
    workflow_id uuid NOT NULL,
    user_id uuid NOT NULL,
    run_at timestamptz NOT NULL,
    inngest_run_id text NOT NULL,
    kind text NOT NULL,
    include_wait boolean NOT NULL DEFAULT false,
    include_final boolean NOT NULL DEFAULT false,
    failed boolean NOT NULL DEFAULT false,
    completed boolean NOT NULL DEFAULT true
  ) ON COMMIT DROP;

  -- Welcome follows signup dates (~38% of members).
  INSERT INTO _aus_wf_runs (workflow_id, user_id, run_at, inngest_run_id, kind, failed, completed)
  SELECT v_wf_wel, u.id,
    u.created_at + interval '75 minutes'
      + make_interval(secs => (custom_ausiris_demo_rand(u.id::text || ':wel-h') * 21600)::int),
    'ausv2-wel-' || replace(u.id::text, '-', ''),
    'welcome',
    custom_ausiris_demo_rand(u.id::text || ':wel-fail') < 0.03,
    custom_ausiris_demo_rand(u.id::text || ':wel-done') < 0.94
  FROM user_accounts u
  WHERE u.merchant_id = v_mid
    AND u.external_user_id LIKE 'AUSV2-%'
    AND (custom_ausiris_demo_rand(u.id::text || ':wel') < 0.38 OR u.id = v_c0);

  -- Congratulations on first purchase (~42% of buyers).
  INSERT INTO _aus_wf_runs (workflow_id, user_id, run_at, inngest_run_id, kind, failed, completed)
  SELECT v_wf_con, p.user_id,
    p.first_at + interval '40 minutes'
      + make_interval(secs => (custom_ausiris_demo_rand(p.user_id::text || ':con-h') * 10800)::int),
    'ausv2-con-' || replace(p.user_id::text, '-', ''),
    'congrats',
    custom_ausiris_demo_rand(p.user_id::text || ':con-fail') < 0.025,
    custom_ausiris_demo_rand(p.user_id::text || ':con-done') < 0.95
  FROM (
    SELECT DISTINCT ON (pl.user_id) pl.user_id, pl.created_at AS first_at
    FROM purchase_ledger pl
    WHERE pl.merchant_id = v_mid AND pl.external_ref LIKE 'AUSV2%'
    ORDER BY pl.user_id, pl.created_at
  ) p
  JOIN user_accounts u ON u.id = p.user_id
  WHERE custom_ausiris_demo_rand(p.user_id::text || ':con') < 0.42 OR u.id = v_c0;

  -- Win-back: At Risk audience plus stale buyers whose send date still lands in the 6-month window.
  INSERT INTO _aus_wf_runs (
    workflow_id, user_id, run_at, inngest_run_id, kind,
    include_wait, include_final, failed, completed
  )
  SELECT v_wf_win, s.user_id, s.run_at,
    'ausv2-win-' || replace(s.user_id::text, '-', ''),
    'winback',
    custom_ausiris_demo_rand(s.user_id::text || ':wait') < 0.72,
    custom_ausiris_demo_rand(s.user_id::text || ':final') < 0.40,
    custom_ausiris_demo_rand(s.user_id::text || ':win-fail') < 0.04,
    custom_ausiris_demo_rand(s.user_id::text || ':win-done') < 0.91
  FROM (
    SELECT
      lp.user_id,
      lp.last_at
        + interval '28 days'
        + make_interval(days => (custom_ausiris_demo_rand(lp.user_id::text || ':win-d') * 25)::int)
        AS run_at,
      EXISTS (
        SELECT 1 FROM amp_audience_member am
        WHERE am.audience_id = v_aud_win AND am.user_id = lp.user_id AND am.exited_at IS NULL
      ) AS in_aud
    FROM (
      SELECT user_id, max(created_at) AS last_at
      FROM purchase_ledger
      WHERE merchant_id = v_mid AND external_ref LIKE 'AUSV2%'
      GROUP BY user_id
    ) lp
  ) s
  JOIN user_accounts u ON u.id = s.user_id
  WHERE s.run_at <= now()
    AND s.run_at >= timestamptz '2026-02-24 00:00:00+07'
    AND (
      s.in_aud
      OR u.id = v_c0
      OR custom_ausiris_demo_rand(s.user_id::text || ':win') < 0.40
    );

  -- C0 always has a recent run on each workflow so the default 30-day AMP chart and 360 timeline are populated.
  IF v_c0 IS NOT NULL THEN
    INSERT INTO _aus_wf_runs (workflow_id, user_id, run_at, inngest_run_id, kind, failed, completed)
    VALUES
      (v_wf_wel, v_c0, now() - interval '11 days', 'ausv2-wel-c0-recent', 'welcome', false, true),
      (v_wf_con, v_c0, now() - interval '8 days', 'ausv2-con-c0-recent', 'congrats', false, true);
    INSERT INTO _aus_wf_runs (
      workflow_id, user_id, run_at, inngest_run_id, kind,
      include_wait, include_final, failed, completed
    ) VALUES
      (v_wf_win, v_c0, now() - interval '12 days', 'ausv2-win-c0-recent', 'winback',
       true, true, false, true);
  END IF;

  UPDATE _aus_wf_runs SET include_final = false WHERE NOT include_wait;
  UPDATE _aus_wf_runs
    SET include_wait = false, include_final = false
    WHERE include_wait AND run_at + interval '7 days' > now();
  UPDATE _aus_wf_runs SET completed = false WHERE failed;

  INSERT INTO workflow_log (
    id, merchant_id, workflow_id, user_id, inngest_run_id, event_type,
    node_id, node_type, action_type, status, action_channel,
    event_data, created_at, cost, normalized_cost, run_scope
  )
  SELECT
    md5(r.inngest_run_id || ':' || ev.evt)::uuid,
    v_mid, r.workflow_id, r.user_id, r.inngest_run_id, ev.event_type,
    ev.node_id, ev.node_type, ev.action_type, ev.status, ev.action_channel,
    jsonb_build_object('seed','SEED-AUS-V2','source','custom_ausiris_demo_seed_workflows'),
    r.run_at + ev.offset_s, ev.cost, ev.cost, 'member'
  FROM _aus_wf_runs r
  JOIN LATERAL (
    SELECT * FROM (VALUES
      ('start', 'execution_started', NULL::uuid, NULL::text, NULL::text, NULL::text, NULL::text, interval '0 seconds', 0::numeric),
      ('entry', 'node_executed',
        CASE r.kind WHEN 'welcome' THEN v_n_wel_entry WHEN 'congrats' THEN v_n_con_entry ELSE v_n_win_entry END,
        'condition', NULL::text, 'executed', NULL::text, interval '2 seconds', 0::numeric)
    ) s(evt, event_type, node_id, node_type, action_type, status, action_channel, offset_s, cost)
    UNION ALL
    SELECT * FROM (VALUES
      ('line1', 'action_executed',
        CASE r.kind WHEN 'welcome' THEN v_n_wel_line WHEN 'congrats' THEN v_n_con_line ELSE v_n_win_line END,
        'action', 'send_line_message',
        CASE WHEN r.failed THEN 'failed'
             WHEN custom_ausiris_demo_rand(r.inngest_run_id || ':line-st') < 0.18 THEN 'executed'
             ELSE 'sent' END,
        'line', interval '5 seconds', 3.40::numeric)
    ) s
    UNION ALL
    SELECT * FROM (VALUES
      ('pts', 'action_executed',
        CASE r.kind WHEN 'welcome' THEN v_n_wel_pts WHEN 'congrats' THEN v_n_con_pts ELSE v_n_win_pts END,
        'action', 'award_points',
        CASE WHEN r.failed THEN 'failed' ELSE 'executed' END,
        NULL::text, interval '8 seconds',
        CASE r.kind WHEN 'welcome' THEN 2.5 WHEN 'congrats' THEN 5.0 ELSE 7.5 END)
    ) s
    WHERE r.kind <> 'winback' OR custom_ausiris_demo_rand(r.inngest_run_id || ':pts') < 0.82
    UNION ALL
    SELECT * FROM (VALUES
      ('wait', 'node_executed', v_n_win_wait, 'wait', NULL::text, 'executed', NULL::text, interval '9 seconds', 0::numeric)
    ) s
    WHERE r.kind = 'winback' AND r.include_wait
    UNION ALL
    SELECT * FROM (VALUES
      ('chk', 'node_executed', v_n_win_chk, 'condition', NULL::text, 'executed', NULL::text, interval '7 days 2 minutes', 0::numeric)
    ) s
    WHERE r.kind = 'winback' AND r.include_wait
    UNION ALL
    SELECT * FROM (VALUES
      ('line2', 'action_executed', v_n_win_final, 'action', 'send_line_message',
        CASE WHEN r.failed THEN 'failed' ELSE 'sent' END,
        'line', interval '7 days 3 minutes', 3.40::numeric)
    ) s
    WHERE r.kind = 'winback' AND r.include_final
    UNION ALL
    SELECT * FROM (VALUES
      ('endok', CASE WHEN r.failed THEN 'execution_failed' ELSE 'execution_completed' END,
        NULL::uuid, NULL::text, NULL::text, NULL::text, NULL::text,
        CASE WHEN r.kind = 'winback' AND r.include_wait THEN interval '7 days 4 minutes' ELSE interval '12 seconds' END,
        0::numeric)
    ) s
    WHERE r.completed OR r.failed
  ) ev ON true;

  INSERT INTO amp_tracked_link (
    token, merchant_id, workflow_id, node_id, user_id, workflow_log_id,
    destination_url, channel, created_at, link_label
  )
  SELECT
    'aus' || substr(md5(r.inngest_run_id || ':tok:' || ev.which), 1, 29),
    v_mid, r.workflow_id, ev.node_id, r.user_id,
    md5(r.inngest_run_id || ':' || ev.log_evt)::uuid,
    ev.url, 'line',
    r.run_at + ev.offset_s,
    ev.label
  FROM _aus_wf_runs r
  JOIN LATERAL (
    SELECT * FROM (VALUES
      ('l1', CASE r.kind WHEN 'welcome' THEN v_n_wel_line WHEN 'congrats' THEN v_n_con_line ELSE v_n_win_line END,
       'line1',
       CASE r.kind WHEN 'winback' THEN v_url_missions ELSE v_url_rewards END,
       CASE r.kind WHEN 'welcome' THEN 'ดูรางวัล' WHEN 'congrats' THEN 'แลกรางวัล' ELSE 'ภารกิจ' END,
       interval '5 seconds')
    ) s(which, node_id, log_evt, url, label, offset_s)
    UNION ALL
    SELECT * FROM (VALUES
      ('l2', v_n_win_final, 'line2', v_url_rewards, 'กลับมาออมทอง', interval '7 days 3 minutes')
    ) s
    WHERE r.kind = 'winback' AND r.include_final
  ) ev ON true
  WHERE NOT r.failed
    AND custom_ausiris_demo_rand(r.inngest_run_id || ':track:' || ev.which) < 0.78;

  INSERT INTO amp_engagement_event (
    token, event_type, value, session_id, merchant_id, workflow_id, node_id,
    user_id, created_at, workflow_log_id, metadata
  )
  SELECT
    t.token, ev.event_type, ev.value, ev.session_id,
    t.merchant_id, t.workflow_id, t.node_id, t.user_id,
    t.created_at + ev.lag, t.workflow_log_id,
    jsonb_build_object('seed','SEED-AUS-V2')
  FROM amp_tracked_link t
  JOIN workflow_master w ON w.id = t.workflow_id
  JOIN LATERAL (
    SELECT
      'aus-sess-' || substr(md5(t.token), 1, 12) AS session_id,
      custom_ausiris_demo_rand(t.token || ':clk') AS p_click,
      custom_ausiris_demo_rand(t.token || ':pg') AS p_page
  ) rnd ON true
  JOIN LATERAL (
    SELECT * FROM (VALUES
      ('click'::text, NULL::numeric, rnd.session_id, interval '4 minutes')
    ) s(event_type, value, session_id, lag)
    WHERE rnd.p_click < 0.22
    UNION ALL
    SELECT * FROM (VALUES
      ('page_view'::text, NULL::numeric, rnd.session_id, interval '4 minutes 8 seconds')
    ) s
    WHERE rnd.p_click < 0.22 AND rnd.p_page < 0.70
    UNION ALL
    SELECT * FROM (VALUES
      ('page_time'::text,
       (18 + custom_ausiris_demo_rand(t.token || ':sec') * 90)::numeric,
       rnd.session_id, interval '5 minutes')
    ) s
    WHERE rnd.p_click < 0.22 AND rnd.p_page < 0.65
    UNION ALL
    SELECT * FROM (VALUES
      ('scroll_depth'::text,
       (35 + custom_ausiris_demo_rand(t.token || ':sc') * 55)::numeric,
       rnd.session_id, interval '5 minutes 20 seconds')
    ) s
    WHERE rnd.p_click < 0.22 AND rnd.p_page < 0.60
  ) ev ON true
  WHERE w.merchant_id = v_mid AND w.workflow_code LIKE 'aus-wf-%';

  INSERT INTO custom_ausiris_demo_config (kind, code, payload)
  VALUES
    ('id', 'wf_welcome', jsonb_build_object('id', v_wf_wel, 'code', 'aus-wf-welcome')),
    ('id', 'wf_congrats', jsonb_build_object('id', v_wf_con, 'code', 'aus-wf-congrats')),
    ('id', 'wf_winback', jsonb_build_object('id', v_wf_win, 'code', 'aus-wf-winback'))
  ON CONFLICT (kind, code) DO UPDATE
    SET payload = EXCLUDED.payload, updated_at = now();

  SELECT count(*) INTO v_runs FROM _aus_wf_runs;
  SELECT count(*) INTO v_logs FROM workflow_log WHERE merchant_id = v_mid AND event_data->>'seed' = 'SEED-AUS-V2';
  SELECT count(*) INTO v_links FROM amp_tracked_link WHERE merchant_id = v_mid AND token LIKE 'aus%';
  SELECT count(*) INTO v_clicks FROM amp_engagement_event
  WHERE merchant_id = v_mid AND event_type = 'click' AND metadata->>'seed' = 'SEED-AUS-V2';

  RETURN jsonb_build_object(
    'success', true,
    'workflows', 3,
    'runs', v_runs,
    'log_rows', v_logs,
    'tracked_links', v_links,
    'clicks', v_clicks
  );
END;
$fn$;
