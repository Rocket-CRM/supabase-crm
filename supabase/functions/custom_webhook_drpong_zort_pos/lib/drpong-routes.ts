export const POS_CHANNEL = "Dataslot - POS";
export const BIGCOMMERCE_CHANNEL = "Web_Rocket bigcommerce";
export const PIPEDREAM_BIGCOMMERCE_URL =
  "https://eot6isanrrx84y3.m.pipedream.net";
export const CRM_RECEIPTS_URL =
  "https://crm-api.rocket-tech.app/openapi/api/v1/receipts";

const POS_METHODS = new Set(["ADDORDER", "UPDATEORDER", "UPDATEORDERPAYMENT"]);

export type DrpongRoute =
  | { action: "filter"; reason: string }
  | { action: "pipedream_bigcommerce"; destinationUrl: string }
  | { action: "crm_pos"; destinationUrl: string };

export function parseZortMethod(req: Request): string {
  return new URL(req.url).searchParams.get("method")?.toUpperCase() ?? "";
}

export function resolveDrpongRoute(
  body: Record<string, unknown>,
  method: string,
): DrpongRoute {
  if (method === "UPDATEORDERTRACKING") {
    return { action: "filter", reason: "filtered_method_tracking" };
  }

  const channel = typeof body.saleschannel === "string" ? body.saleschannel : "";
  const status = typeof body.status === "string" ? body.status : "";
  const payment = typeof body.paymentstatus === "string" ? body.paymentstatus : "";

  if (channel === POS_CHANNEL) {
    if (!POS_METHODS.has(method)) {
      return { action: "filter", reason: "filtered_method" };
    }
    if (status !== "Success" || payment !== "Paid") {
      return { action: "filter", reason: "filtered_status" };
    }
    return { action: "crm_pos", destinationUrl: CRM_RECEIPTS_URL };
  }

  if (channel === BIGCOMMERCE_CHANNEL) {
    if (method !== "UPDATEORDER") {
      return { action: "filter", reason: "filtered_method" };
    }
    if (payment !== "Paid") {
      return { action: "filter", reason: "filtered_status" };
    }
    if (status !== "Waiting" && status !== "Success") {
      return { action: "filter", reason: "filtered_status" };
    }
    return {
      action: "pipedream_bigcommerce",
      destinationUrl: PIPEDREAM_BIGCOMMERCE_URL,
    };
  }

  if (!channel) {
    return { action: "filter", reason: "filtered_missing_channel" };
  }

  return { action: "filter", reason: "unsupported_channel" };
}
