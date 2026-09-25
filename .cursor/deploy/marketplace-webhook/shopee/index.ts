import { createMarketplaceWebhookHandler } from "../lib/marketplace-ingest.ts";

Deno.serve(createMarketplaceWebhookHandler("shopee", "webhook-marketplace-shopee"));
