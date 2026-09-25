import { createMarketplaceWebhookHandler } from "../lib/marketplace-ingest.ts";

Deno.serve(createMarketplaceWebhookHandler("lazada", "webhook-marketplace-lazada"));
