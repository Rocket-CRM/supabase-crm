import { CRM_RECEIPTS_URL } from "./drpong-routes.ts";

interface ZortLineItem {
  id?: number;
  sku?: string;
  name?: string;
  number?: number;
  pricepernumber?: number;
  discount?: string | number;
  totalprice?: number;
  totalprice_vat?: number;
}

interface CrmReceiptPayload {
  receipt_no: string;
  product_order_id: string | null;
  currency: string;
  customer: {
    customer_id: null;
    phone: string;
    first_name: string;
    middle_name: string;
    last_name: string;
    email: string;
    address: Record<string, string>;
  };
  reference_id: string;
  store: Record<string, unknown>;
  items: Record<string, unknown>[];
  subtotal: string;
  discount: { amount: string; description: string };
  tax: { is_tax_included: boolean; rate: string; amount: string };
  total_amount: string;
  status: "COMPLETE" | "PENDING";
  is_create_product: boolean;
  is_reward_point_enabled: boolean;
  is_paid: boolean;
  note: string;
  point_target: string;
}

interface CrmApiResponse {
  code?: number;
  HttpStatus?: number;
  message?: string;
  data?: { receipt_id?: string };
}

function str(value: unknown): string {
  if (value === null || value === undefined) return "";
  return String(value);
}

function buildPhone(rawPhone: unknown): string {
  const phone = str(rawPhone);
  if (!phone) return "";
  if (phone.startsWith("+")) return phone;
  if (phone.startsWith("0") && phone.length > 1) return "+66" + phone.substring(1);
  return phone;
}

export function buildCrmReceiptPayload(
  body: Record<string, unknown>,
): CrmReceiptPayload {
  const status = str(body.status);
  const paymentstatus = str(body.paymentstatus);
  const list = Array.isArray(body.list) ? body.list as ZortLineItem[] : [];

  const basketItems = list.map((item) => ({
    product_category: "",
    product_code: str(item.sku),
    product_name: str(item.name),
    product_variant_code: str(item.id),
    product_variant_dimensions: [
      { dimension: "General", value: "General" },
    ],
    quantity: str(item.number),
    unit_price: str(item.pricepernumber),
    discounted_price: str(item.discount),
    subtotal: str(item.totalprice),
    total_price: str(item.totalprice),
    tax_amount: str(item.totalprice_vat),
  }));

  return {
    receipt_no: str(body.number),
    product_order_id: null,
    currency: str(body.currency) || "THB",
    customer: {
      customer_id: null,
      phone: buildPhone(body.customerphone),
      first_name: str(body.customername),
      middle_name: "",
      last_name: "",
      email: "",
      address: {
        address_line_1: "",
        address_line_2: "",
        city: "",
        state: "",
        postal_code: "",
        country: "",
        sub_district: "",
      },
    },
    reference_id: "",
    store: {
      store_code: str(body.warehousecode),
      store_name: "",
      store_collection: "",
      store_category: "",
      store_subcategory: "",
      store_location: {
        address_line_1: "",
        address_line_2: "",
        city: "",
        state: "TH",
        postal_code: "",
        country: "TH",
      },
    },
    items: basketItems,
    subtotal: str(body.paymentamount),
    discount: {
      amount: str(body.discountamount),
      description: "",
    },
    tax: {
      is_tax_included: false,
      rate: str(body.vatpercent),
      amount: str(body.vatamount),
    },
    total_amount: str(body.paymentamount),
    status: status === "Success" ? "COMPLETE" : "PENDING",
    is_create_product: false,
    is_reward_point_enabled: status === "Success",
    is_paid: paymentstatus === "Paid",
    note: "",
    point_target: "CRM",
  };
}

export async function postCrmReceipt(
  body: Record<string, unknown>,
): Promise<{ status: number; body: CrmApiResponse; action: string }> {
  const apiKey = Deno.env.get("DRPONG_CRM_API_KEY");
  if (!apiKey) {
    throw new Error("DRPONG_CRM_API_KEY is not configured");
  }

  const headers = {
    "accept-language": "EN",
    access: "*/*",
    "Content-Type": "application/json",
    "X-API-Key": apiKey,
  };

  const payload = buildCrmReceiptPayload(body);

  const createResponse = await fetch(CRM_RECEIPTS_URL, {
    method: "POST",
    headers,
    body: JSON.stringify(payload),
  });

  const createText = await createResponse.text();
  let createBody: CrmApiResponse;
  try {
    createBody = JSON.parse(createText);
  } catch {
    throw new Error(`CRM POST returned non-JSON: ${createText.slice(0, 200)}`);
  }

  if (createBody.code !== -1011) {
    return {
      status: createResponse.status,
      body: createBody,
      action: "created",
    };
  }

  if (createBody.HttpStatus === 409) {
    return {
      status: createResponse.status,
      body: createBody,
      action: "duplicate_conflict",
    };
  }

  const receiptId = createBody.data?.receipt_id;
  if (!receiptId) {
    throw new Error("CRM duplicate response missing receipt_id");
  }

  payload.product_order_id = receiptId;

  const updateResponse = await fetch(CRM_RECEIPTS_URL, {
    method: "PATCH",
    headers,
    body: JSON.stringify(payload),
  });

  const updateText = await updateResponse.text();
  let updateBody: CrmApiResponse;
  try {
    updateBody = JSON.parse(updateText);
  } catch {
    throw new Error(`CRM PATCH returned non-JSON: ${updateText.slice(0, 200)}`);
  }

  if (updateBody.code === -1001) {
    return {
      status: updateResponse.status,
      body: updateBody,
      action: "update_failed",
    };
  }

  return {
    status: updateResponse.status,
    body: updateBody,
    action: "updated",
  };
}
