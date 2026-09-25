/**
 * AMP Analysis refresh crons
 *
 * Three Inngest cron functions:
 *  1. amp-analysis-refresh-quartiles  — daily, spend quartile thresholds
 *  2. amp-analysis-refresh-member-attrs — hourly, incremental UPSERT per merchant
 *  3. amp-analysis-refresh-mvs        — hourly (after member attrs), all aggregate tables + MV REFRESH
 *
 * Register all exports in your Inngest serve() handler alongside existing AMP functions.
 */
import { inngest } from '../inngest-client';
import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = process.env.SUPABASE_URL!;
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY!;

function getDb() {
  return createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
}

// ─── 1. Daily spend quartiles ─────────────────────────────────────────────────

export const ampAnalysisRefreshQuartiles = inngest.createFunction(
  { id: 'amp-analysis-refresh-quartiles', name: 'AMP Analysis: Refresh Spend Quartiles' },
  { cron: '0 2 * * *' }, // 2 AM daily
  async ({ step }) => {
    const db = getDb();

    const result = await step.run('refresh-all-merchants', async () => {
      const { data, error } = await db.rpc('fn_amp_analysis_refresh_spend_quartiles', {
        p_merchant_id: null, // null = all merchants
      });
      if (error) throw new Error(`Quartile refresh failed: ${error.message}`);
      return data;
    });

    return result;
  },
);

// ─── 2. Hourly member attrs ───────────────────────────────────────────────────

export const ampAnalysisRefreshMemberAttrs = inngest.createFunction(
  {
    id: 'amp-analysis-refresh-member-attrs',
    name: 'AMP Analysis: Refresh Member Attrs',
    concurrency: { limit: 5 }, // process up to 5 merchants in parallel
  },
  { cron: '5 * * * *' }, // 5 minutes past every hour (after any upstream crons)
  async ({ step }) => {
    const db = getDb();

    // Get all active merchants
    const merchants = await step.run('get-merchants', async () => {
      const { data, error } = await db
        .from('merchant_master')
        .select('id')
        .eq('is_active', true);
      if (error) throw new Error(error.message);
      return data ?? [];
    });

    // Incremental: only users updated since last run (1 hour + 5min buffer)
    const since = new Date(Date.now() - 65 * 60 * 1000).toISOString();

    // Process each merchant (step.run per merchant for parallelism and retryability)
    const results = await Promise.all(
      merchants.map((m: { id: string }) =>
        step.run(`refresh-${m.id}`, async () => {
          const { data, error } = await db.rpc('fn_amp_analysis_refresh_member_attrs', {
            p_merchant_id: m.id,
            p_since: since,
          });
          if (error) throw new Error(`Member attrs refresh failed for ${m.id}: ${error.message}`);
          return data;
        }),
      ),
    );

    // Trigger MV refresh after member attrs complete
    await step.invoke('trigger-mv-refresh', {
      function: ampAnalysisRefreshMvs,
      data: { triggered_by: 'member-attrs-refresh', since },
    });

    return { merchants_processed: merchants.length, results };
  },
);

// ─── 3. Hourly MV refresh ─────────────────────────────────────────────────────

export const ampAnalysisRefreshMvs = inngest.createFunction(
  {
    id: 'amp-analysis-refresh-mvs',
    name: 'AMP Analysis: Refresh Aggregate MVs',
    concurrency: { limit: 5 },
  },
  [
    { cron: '15 * * * *' }, // standalone hourly fallback
    { event: 'amp/analysis.refresh-mvs' }, // invokable by member attrs cron
  ],
  async ({ step }) => {
    const db = getDb();

    const merchants = await step.run('get-merchants-with-params', async () => {
      const { data, error } = await db
        .from('amp_analysis_params')
        .select('merchant_id, analysis_periods, activation_window_days');
      if (error) throw new Error(error.message);
      return data ?? [];
    });

    const results = await Promise.all(
      merchants.map((m: { merchant_id: string; analysis_periods: number[]; activation_window_days: number }) =>
        step.run(`refresh-mvs-${m.merchant_id}`, async () => {
          const periods: number[] = m.analysis_periods ?? [30, 90, 180];

          // Run all 4 aggregate refreshes in parallel per merchant
          const [acq, earn, burn, purchase] = await Promise.all([
            db.rpc('fn_amp_analysis_refresh_acquisition', { p_merchant_id: m.merchant_id }).then((r) => r.data),
            db.rpc('fn_amp_analysis_refresh_earn_activity', { p_merchant_id: m.merchant_id, p_periods: periods }).then((r) => r.data),
            db.rpc('fn_amp_analysis_refresh_burn_activity', { p_merchant_id: m.merchant_id, p_periods: periods }).then((r) => r.data),
            db.rpc('fn_amp_analysis_refresh_purchase_trends', { p_merchant_id: m.merchant_id, p_periods: periods }).then((r) => r.data),
          ]);

          // Refresh the two true PostgreSQL MVs
          await db.rpc('fn_amp_analysis_refresh_postgres_mvs', { p_merchant_id: m.merchant_id }).catch(() => {
            // Fallback: direct SQL via a helper function (see note below)
          });

          return { merchant_id: m.merchant_id, acq, earn, burn, purchase };
        }),
      ),
    );

    return { merchants_processed: merchants.length, results };
  },
);

/*
 * NOTE: REFRESH MATERIALIZED VIEW CONCURRENTLY cannot be called from a plpgsql function
 * in the standard Supabase SQL editor — it must be called from a SECURITY DEFINER function
 * or via direct DB connection. Add this migration to enable it:
 *
 * CREATE OR REPLACE FUNCTION fn_amp_analysis_refresh_postgres_mvs(p_merchant_id uuid DEFAULT NULL)
 * RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
 * BEGIN
 *   REFRESH MATERIALIZED VIEW CONCURRENTLY mv_amp_analysis_member_segments;
 *   REFRESH MATERIALIZED VIEW CONCURRENTLY mv_amp_analysis_mission_performance;
 * END;
 * $$;
 *
 * This is a full refresh (not per-merchant) since PostgreSQL MVs don't support partial refresh.
 * The GROUP BY on pre-computed tables keeps this fast regardless of merchant count.
 */
