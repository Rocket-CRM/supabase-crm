// link-redirect: public click-tracking redirect for AMP message links.
// GET /functions/v1/link-redirect/<token>
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.46.0";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

Deno.serve(async (req: Request) => {
  if (req.method !== "GET" && req.method !== "HEAD") {
    return new Response("Method not allowed", { status: 405 });
  }

  const url = new URL(req.url);
  const segments = url.pathname.split("/").filter(Boolean);
  const token = segments[segments.length - 1];

  if (!token || token === "link-redirect" || !/^[0-9a-f]{8,32}$/.test(token)) {
    return new Response("Not found", { status: 404 });
  }

  const { data: link } = await supabase
    .from("amp_tracked_link")
    .select("token, merchant_id, workflow_id, node_id, resource_id, user_id, destination_url")
    .eq("token", token)
    .maybeSingle();

  if (!link) {
    return new Response("Not found", { status: 404 });
  }

  try {
    await supabase.from("amp_engagement_event").insert({
      token: link.token,
      event_type: "click",
      merchant_id: link.merchant_id,
      workflow_id: link.workflow_id,
      node_id: link.node_id,
      resource_id: link.resource_id,
      user_id: link.user_id,
      user_agent: req.headers.get("user-agent")?.slice(0, 500) ?? null,
    });
  } catch (_e) {
    /* redirect anyway */
  }

  let dest: URL;
  try {
    dest = new URL(link.destination_url);
  } catch (_e) {
    return new Response("Invalid destination", { status: 500 });
  }
  if (!dest.searchParams.has("rct")) dest.searchParams.set("rct", link.token);

  return new Response(null, {
    status: 302,
    headers: {
      Location: dest.toString(),
      "Cache-Control": "no-store, max-age=0",
      "Referrer-Policy": "no-referrer",
    },
  });
});
