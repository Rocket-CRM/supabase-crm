import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const INNGEST_EVENT_KEY = Deno.env.get("INNGEST_EVENT_KEY") || '';
const INNGEST_EVENT_URL = `https://inn.gs/e/${INNGEST_EVENT_KEY}`;

interface LineSubject {
  line_user_id: string;
  user_id?: string | null;
}

interface BatchRequest {
  workflow_id: string;
  merchant_id: string;
  user_ids?: string[];
  entry_type?: string;
  run_scope?: string;
  trigger_data?: Record<string, unknown>;
  line_subjects?: LineSubject[];
}

async function postInngestEvents(events: Array<{ name: string; data: Record<string, unknown> }>) {
  const resp = await fetch(INNGEST_EVENT_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(events),
  });
  if (!resp.ok) {
    const errText = await resp.text();
    throw new Error(`Inngest post failed: ${errText}`);
  }
  return resp;
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Methods': 'POST, OPTIONS', 'Access-Control-Allow-Headers': 'Content-Type, Authorization' } });
  }

  try {
    const body: BatchRequest = await req.json();
    const { workflow_id, merchant_id } = body;
    const entry_type = body.entry_type || (body.trigger_data?.entry_type as string | undefined);
    const run_scope = body.run_scope;
    const trigger_data = { source: 'batch_run', ...(body.trigger_data || {}) };
    const user_ids = body.user_ids || [];
    const line_subjects = body.line_subjects || [];

    if (!workflow_id || !merchant_id) {
      return new Response(JSON.stringify({ error: 'workflow_id and merchant_id are required' }), { status: 400, headers: { 'Content-Type': 'application/json' } });
    }

    const isBroadcast = entry_type === 'all_line_friends' || run_scope === 'broadcast';
    const isLineSubjects = line_subjects.length > 0;
    const isFollowerScan = entry_type === 'all_line_friends_exclude_members';

    if (!isBroadcast && !isLineSubjects && !isFollowerScan && user_ids.length === 0) {
      return new Response(JSON.stringify({ error: 'user_ids, line_subjects, or broadcast entry_type is required' }), { status: 400, headers: { 'Content-Type': 'application/json' } });
    }

    if (!INNGEST_EVENT_KEY) {
      return new Response(JSON.stringify({ error: 'INNGEST_EVENT_KEY not configured' }), { status: 500, headers: { 'Content-Type': 'application/json' } });
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

    const { data: wf } = await supabase.from('workflow_master').select('id, name, is_active').eq('id', workflow_id).eq('merchant_id', merchant_id).single();
    if (!wf || !wf.is_active) {
      return new Response(JSON.stringify({ error: 'Workflow not found or not active' }), { status: 400, headers: { 'Content-Type': 'application/json' } });
    }

    let dispatched = 0;
    let failed = 0;

    if (isFollowerScan) {
      try {
        await postInngestEvents([{
          name: 'amp/workflow.trigger',
          data: {
            workflow_id,
            merchant_id,
            run_scope: 'line',
            trigger_data: {
              ...trigger_data,
              entry_type: 'all_line_friends_exclude_members',
              source: trigger_data.source || 'batch_run',
            },
          },
        }]);
        dispatched = 1;
        console.log(`[amp-dispatch-workflow-batch] Dispatched follower-scan seed run for ${workflow_id}`);
      } catch (e: any) {
        failed = 1;
        console.error(`[amp-dispatch-workflow-batch] Follower-scan seed error: ${e.message}`);
      }

      await supabase.from('workflow_log').insert({
        merchant_id,
        workflow_id,
        user_id: null,
        run_scope: 'line',
        inngest_run_id: `batch_run_follower_scan_${Date.now()}`,
        event_type: 'batch_run_completed',
        event_data: { entry_type: 'all_line_friends_exclude_members', run_scope: 'line', seed_dispatched: dispatched, failed },
      });

      return new Response(JSON.stringify({
        success: failed === 0,
        workflow_id,
        entry_type: 'all_line_friends_exclude_members',
        run_scope: 'line',
        dispatched,
        failed,
      }), { headers: { 'Content-Type': 'application/json' } });
    }

    if (isBroadcast) {
      try {
        await postInngestEvents([{
          name: 'amp/workflow.trigger',
          data: {
            workflow_id,
            merchant_id,
            run_scope: 'broadcast',
            trigger_data: { ...trigger_data, entry_type: 'all_line_friends', source: trigger_data.source || 'batch_run' },
          },
        }]);
        dispatched = 1;
        console.log(`[amp-dispatch-workflow-batch] Dispatched 1 broadcast run for ${workflow_id}`);
      } catch (e: any) {
        failed = 1;
        console.error(`[amp-dispatch-workflow-batch] Broadcast error: ${e.message}`);
      }

      const batchRunId = `batch_run_broadcast_${Date.now()}`;
      await supabase.from('workflow_log').insert({
        merchant_id,
        workflow_id,
        user_id: null,
        run_scope: 'broadcast',
        inngest_run_id: batchRunId,
        event_type: 'batch_run_completed',
        event_data: { entry_type: 'all_line_friends', run_scope: 'broadcast', total_users: 0, dispatched, failed },
      });

      return new Response(JSON.stringify({
        success: failed === 0,
        workflow_id,
        entry_type: 'all_line_friends',
        run_scope: 'broadcast',
        total_users: 0,
        dispatched,
        failed,
      }), { headers: { 'Content-Type': 'application/json' } });
    }

    if (isLineSubjects) {
      const batchSize = 500;
      for (let i = 0; i < line_subjects.length; i += batchSize) {
        const batch = line_subjects.slice(i, i + batchSize);
        const events = batch.map((s) => ({
          name: 'amp/workflow.trigger',
          data: {
            workflow_id,
            merchant_id,
            run_scope: 'line',
            line_user_id: s.line_user_id,
            user_id: s.user_id || null,
            trigger_data: {
              ...trigger_data,
              entry_type: entry_type || 'past_line_interaction',
              fanout: true,
              source: trigger_data.source || 'batch_run',
            },
          },
        }));
        try {
          await postInngestEvents(events);
          dispatched += batch.length;
          console.log(`[amp-dispatch-workflow-batch] LINE subjects batch ${Math.floor(i / batchSize) + 1}: dispatched ${batch.length}`);
        } catch (e: any) {
          failed += batch.length;
          console.error(`[amp-dispatch-workflow-batch] LINE subjects batch error: ${e.message}`);
        }
      }

      const batchRunId = `batch_run_line_${Date.now()}`;
      await supabase.from('workflow_log').insert({
        merchant_id,
        workflow_id,
        user_id: null,
        run_scope: 'line',
        inngest_run_id: batchRunId,
        event_type: 'batch_run_completed',
        event_data: { entry_type: entry_type || 'past_line_interaction', total_users: line_subjects.length, dispatched, failed },
      });

      return new Response(JSON.stringify({
        success: failed === 0,
        workflow_id,
        entry_type: entry_type || 'past_line_interaction',
        run_scope: 'line',
        total_users: line_subjects.length,
        dispatched,
        failed,
      }), { headers: { 'Content-Type': 'application/json' } });
    }

    const batchSize = 500;

    for (let i = 0; i < user_ids.length; i += batchSize) {
      const batch = user_ids.slice(i, i + batchSize);

      const events = batch.map(uid => ({
        name: 'amp/workflow.trigger',
        data: {
          workflow_id,
          user_id: uid,
          merchant_id,
          trigger_data: { source: 'batch_run' },
        },
      }));

      try {
        await postInngestEvents(events);
        dispatched += batch.length;
        console.log(`[amp-dispatch-workflow-batch] Batch ${Math.floor(i / batchSize) + 1}: dispatched ${batch.length} users`);
      } catch (e: any) {
        failed += batch.length;
        console.error(`[amp-dispatch-workflow-batch] Batch error: ${e.message}`);
      }
    }

    const batchRunId = `batch_run_${Date.now()}`;
    await supabase.from('workflow_log').insert({
      merchant_id,
      workflow_id,
      user_id: '00000000-0000-0000-0000-000000000000',
      inngest_run_id: batchRunId,
      event_type: 'batch_run_completed',
      event_data: { total_users: user_ids.length, dispatched, failed },
    });

    return new Response(JSON.stringify({
      success: true,
      workflow_id,
      total_users: user_ids.length,
      dispatched,
      failed,
    }), { headers: { 'Content-Type': 'application/json' } });

  } catch (error: any) {
    console.error('[amp-dispatch-workflow-batch] Error:', error);
    return new Response(JSON.stringify({ error: error.message }), { status: 500, headers: { 'Content-Type': 'application/json' } });
  }
});
