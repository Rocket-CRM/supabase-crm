import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createWebhookHandler } from "./lib/handler.ts";

Deno.serve(createWebhookHandler({
  functionSlug: "custom_webhook_yuedpao_zort_pos",
  destinationUrl: "https://api-store-admin.rocket-tech.app/1.0.0/flow_rw/createReceiptWorkflow",
  auth: {
    headerName: "key1",
    expectedValue: "f32b9f8e-7ae1-4c6c-9a92-0c83b4f7d4fe",
  },
  filter: {
    $and: [
      { customerphone: { $exist: true } },
      { customerphone: { $neq: "" } },
      { customerphone: { $nin: "*" } },
      { status: "Success" },
      {
        saleschannel: {
          $or: [
            "Shopscape",
            "POS",
            "ig",
            "line",
            "LINE MyShop",
            "Facebookov",
            "Facebookoff",
            "Facebookm",
            "Facebookkid",
          ],
        },
      },
      { paymentstatus: "Paid" },
    ],
  },
  transform: (body) => ({
    body: {
      ...body,
      organization_id: "691c24615b53cf826f28e87f",
    },
    headers: {
      "rocket-api-key":
        "X2tNP78nFI66oWVjf6iECJ5DS3hrIVRCx9crvVvG3Kf67yJ4sHuh1saaEueAYFmlz8mEGUoQ4JOK8JZ8hqjBGJV9TE4NWKveOCRz4h23wmPRf6aIlVIL1LC6o2MnfSfZWp7ziLXaVwcQJfTa2Wke3J",
    },
  }),
}));
