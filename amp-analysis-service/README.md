# AMP Analysis Service — Inngest Functions

These TypeScript files belong in `amp-ai-service` on Render alongside the existing AMP marketing agent functions.

## Files

| File | Inngest function(s) | Trigger |
|---|---|---|
| `amp-analysis-agent.ts` | `amp-analysis-agent` | `amp/analysis.thread.started` event |
| `amp-analysis-distil.ts` | `amp-analysis-distil` | `amp/analysis.distil` event (invoked by agent on session end) |
| `amp-analysis-recommendation-apply.ts` | `amp-analysis-recommendation-apply` | `amp/analysis.apply` event |
| `amp-analysis-refresh-crons.ts` | `amp-analysis-refresh-quartiles`, `amp-analysis-refresh-member-attrs`, `amp-analysis-refresh-mvs` | Cron schedules |

## Registration

In your existing `inngest-serve` handler (wherever `serve()` is called), add:

```typescript
import { ampAnalysisAgent } from './functions/amp-analysis-agent';
import { ampAnalysisDistil } from './functions/amp-analysis-distil';
import { ampAnalysisRecommendationApply } from './functions/amp-analysis-recommendation-apply';
import {
  ampAnalysisRefreshQuartiles,
  ampAnalysisRefreshMemberAttrs,
  ampAnalysisRefreshMvs,
} from './functions/amp-analysis-refresh-crons';

// Add to your serve() functions array:
serve({
  client: inngest,
  functions: [
    // ... existing functions ...
    ampAnalysisAgent,
    ampAnalysisDistil,
    ampAnalysisRecommendationApply,
    ampAnalysisRefreshQuartiles,
    ampAnalysisRefreshMemberAttrs,
    ampAnalysisRefreshMvs,
  ],
});
```

## Required Environment Variables (add to Render)

| Variable | Description |
|---|---|
| `SUPABASE_URL` | Already set |
| `SUPABASE_SERVICE_ROLE_KEY` | Already set |
| `ANTHROPIC_API_KEY` | Already set |
| `AMP_ANALYSIS_TOOLS_URL` | Supabase project URL (same as SUPABASE_URL, used to call Edge Functions) |
| `INNGEST_EVENT_KEY` | Already set |
| `INNGEST_API_URL` | `https://inn.gs/e` (default) or your Inngest dev server URL |

## Supabase Edge Functions deployed

| Function | Path | Auth |
|---|---|---|
| `amp-analysis-tools` | `/functions/v1/amp-analysis-tools/{tool_name}` | No JWT (internal, called by Inngest) |
| `amp-analysis-message` | `/functions/v1/amp-analysis-message` | JWT required (admin panel) |
| `amp-analysis-apply` | `/functions/v1/amp-analysis-apply` | JWT required (admin panel) |

## Database tables created

- `ai_knowledge_registry` — shared AI reference content registry
- `amp_analysis_params` — per-merchant analysis parameters
- `amp_analysis_spend_quartiles` — daily spend quartile thresholds
- `amp_analysis_member_attrs` — hourly per-user computed attributes
- `amp_analysis_threads` — analysis chat threads
- `amp_analysis_messages` — messages within threads
- `amp_analysis_recommendations` — typed recommendation cards
- `mv_amp_analysis_acquisition` — monthly signup + activation trends
- `mv_amp_analysis_earn_activity` — earn events by source × period
- `mv_amp_analysis_burn_activity` — redemption stats × period
- `mv_amp_analysis_purchase_trends` — revenue/AOV × period
- `mv_amp_analysis_member_segments` — (true PG MV) cohort breakdown
- `mv_amp_analysis_mission_performance` — (true PG MV) per-mission stats
