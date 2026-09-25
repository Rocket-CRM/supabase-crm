/**
 * amp-analysis-recommendation-apply
 *
 * Type-router: loads the recommendation, merges overrides,
 * calls the appropriate BFF function based on rec.type,
 * then updates the recommendation status.
 */
import { inngest } from '../inngest-client';
import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = process.env.SUPABASE_URL!;
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY!;

function getDb() {
  return createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
}

export const ampAnalysisRecommendationApply = inngest.createFunction(
  { id: 'amp-analysis-recommendation-apply', name: 'AMP Analysis Recommendation Apply' },
  { event: 'amp/analysis.apply' },
  async ({ event, step }) => {
    const { recommendation_id, merchant_id, admin_id, overrides } = event.data as {
      recommendation_id: string;
      merchant_id: string;
      admin_id: string;
      overrides: Record<string, unknown>;
    };

    const db = getDb();

    // Load recommendation
    const rec = await step.run('load-recommendation', async () => {
      const { data, error } = await db
        .from('amp_analysis_recommendations')
        .select('id, type, config, target_segment, title, merchant_id')
        .eq('id', recommendation_id)
        .eq('merchant_id', merchant_id)
        .single();
      if (error) throw new Error(`Failed to load recommendation: ${error.message}`);
      return data;
    });

    if (!rec) throw new Error('recommendation_not_found');

    // Merge inline overrides from the UI (name, dates, target_value, amount edits)
    const mergedConfig = { ...(rec.config as Record<string, unknown>), ...overrides };

    // Hard-enforce is_active: false regardless of overrides
    if (rec.type === 'mission') {
      mergedConfig.is_active = false;
    }

    // Set merchant session context (service-role pattern)
    await step.run('set-merchant-session', async () => {
      await db.rpc('set_config', {
        setting: 'app.current_merchant_id',
        value: merchant_id,
        is_local: false,
      });
    });

    // TYPE ROUTER — apply the recommendation
    let appliedResourceId: string | null = null;

    switch (rec.type) {
      case 'mission': {
        const result = await step.run('apply-mission', async () => {
          const { data, error } = await db.rpc('bff_upsert_mission', mergedConfig);
          if (error) throw new Error(`bff_upsert_mission failed: ${error.message}`);
          if (!data?.success) throw new Error(data?.description ?? 'Mission upsert failed');
          return data;
        });
        appliedResourceId = result?.data?.mission_id ?? null;
        break;
      }
      // Future types:
      // case 'campaign': { ... }
      default:
        throw new Error(`Unknown recommendation type: ${rec.type}`);
    }

    // Update recommendation status
    await step.run('update-status', async () => {
      await db
        .from('amp_analysis_recommendations')
        .update({
          status: 'applied',
          applied_resource_id: appliedResourceId,
          applied_by: admin_id,
          applied_at: new Date().toISOString(),
        })
        .eq('id', recommendation_id);
    });

    return {
      ok: true,
      recommendation_id,
      type: rec.type,
      applied_resource_id: appliedResourceId,
    };
  },
);
