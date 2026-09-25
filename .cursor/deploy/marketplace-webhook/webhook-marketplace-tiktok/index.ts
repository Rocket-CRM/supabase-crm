import { createMarketplaceWebhookHandler } from "./lib/marketplace-ingest.ts";

Deno.serve(createMarketplaceWebhookHandler("tiktok", "webhook-marketplace-tiktok"));
