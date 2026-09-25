import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createWebhookHandler } from "./lib/handler.ts";

Deno.serve(createWebhookHandler({
  functionSlug: "custom_webhook_4care_zort_create_bill",
  destinationUrl: "https://api-store-admin.rocket-tech.app/1.0.0/flow_rw/createReceiptWorkflow",
  auth: {
    headerName: "key1",
    expectedValue: "XBhYmFzZSIsInJlZiI6IndrZXZtc2VkY2hmdHp0b29sa21pIiwicm9sZSI6Im",
  },
  filter: {
    $not: {
      saleschannel: "1st Party E-Commerce",
    },
  },
  transform: (body) => ({
    body: {
      ...body,
      organization_id: "67ff82ffc451e6dd7713f8a4",
      x_api_key: "Hw6633AcHYfxuZmMHAtvRJJJoi3iBPqF6l5EqTrdaW1",
    },
    headers: {
      "rocket-api-key":
        "jn4m8ypywqDxynsrsa1qqp9p04TKu4rxPjJ8bScCax4o3t7cHVXivksZF7EfiX5zOHQfkwLJfNCKaI3A6Fcgb4CGRhsHdBTouxNc5vpHLMx7aLcYm7uOtw18xezaWWWfF2CSd29fpc46b80cvDohYX",
    },
  }),
}));
