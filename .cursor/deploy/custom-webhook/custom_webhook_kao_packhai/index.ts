import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createWebhookHandler } from "./lib/handler.ts";

Deno.serve(createWebhookHandler({
  functionSlug: "custom_webhook_kao_packhai",
  destinationUrl: "https://eoe8uj4rv4hwft0.m.pipedream.net",
  filter: {
    ChannelName: "LINE",
  },
}));
