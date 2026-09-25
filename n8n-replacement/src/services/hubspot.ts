import axios, { AxiosInstance } from 'axios';

function getClient(): AxiosInstance {
  const token = process.env.HUBSPOT_ACCESS_TOKEN;
  if (!token) throw new Error('HUBSPOT_ACCESS_TOKEN is not set');
  return axios.create({
    baseURL: 'https://api.hubapi.com',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
  });
}

// ---------------------------------------------------------------------------
// Contacts
// ---------------------------------------------------------------------------

export interface HsContact {
  id: string;
  properties: Record<string, { value?: string } | string>;
}

/**
 * Search for a HubSpot contact by the custom property `jorakay_event_code`.
 * Mirrors the n8n HubSpot "search contact" node used in both workflows.
 */
export async function searchContactByUserId(userId: string): Promise<HsContact | null> {
  const hs = getClient();
  // The legacy HubSpot search used by the n8n node returns results under `results`
  const res = await hs.post<{ results: HsContact[] }>('/crm/v3/objects/contacts/search', {
    filterGroups: [
      {
        filters: [
          { propertyName: 'jorakay_event_code', operator: 'EQ', value: userId },
        ],
      },
    ],
    properties: ['hs_object_id', 'jorakay_event_code', 'firstname', 'lastname', 'phone', 'email'],
    limit: 1,
  });
  return res.data.results[0] ?? null;
}

export interface CreateContactParams {
  userId: string;
  firstName: string;
  lastName: string;
  phone: string;
  lineUserId?: string;
  province?: string;
  district?: string;
  subDistrict?: string;
  postalCode?: string;
  streetAddress?: string;
}

/**
 * Create-or-update a HubSpot contact.
 * Uses email = `{userId}@mail.com` as the unique key (same as n8n).
 * Returns the hs_object_id.
 */
export async function upsertContact(params: CreateContactParams): Promise<string> {
  const hs = getClient();
  const email = `${params.userId}@mail.com`;

  const properties: Record<string, string | undefined> = {
    email,
    firstname: params.firstName,
    lastname: params.lastName,
    mobilephone: params.phone,
    jorakay_event_code: params.userId,
    jorakay_family_status: 'ACTIVE',
    province: params.province,
    district: params.district,
    sub_district: params.subDistrict,
    zip: params.postalCode,
    address: params.streetAddress,
    line_id: params.lineUserId,
  };

  // Remove undefined values
  const cleanProps = Object.fromEntries(
    Object.entries(properties).filter(([, v]) => v !== undefined && v !== ''),
  ) as Record<string, string>;

  // HubSpot upsert via create-or-update (patch by email)
  const res = await hs.post<{ id: string; properties: Record<string, string> }>(
    '/crm/v3/objects/contacts',
    { properties: cleanProps },
  );
  return res.data.id;
}

// ---------------------------------------------------------------------------
// Companies
// ---------------------------------------------------------------------------

export interface HsCompany {
  id: string;
  properties: Record<string, string>;
}

/** Search HubSpot companies by exact name. Returns the first match or null. */
export async function searchCompanyByName(name: string): Promise<HsCompany | null> {
  const hs = getClient();
  const res = await hs.post<{ total: number; results: HsCompany[] }>(
    '/crm/v3/objects/companies/search',
    {
      filterGroups: [
        {
          filters: [{ propertyName: 'name', operator: 'EQ', value: name }],
        },
      ],
      properties: ['name', 'domain', 'city', 'industry', 'phone'],
      limit: 10,
    },
  );
  return res.data.results[0] ?? null;
}

/** Create a HubSpot company. Returns the new company id. */
export async function createCompany(name: string): Promise<string> {
  const hs = getClient();
  const res = await hs.post<{ id: string }>('/crm/v3/objects/companies', {
    properties: { name },
  });
  return res.data.id;
}

// ---------------------------------------------------------------------------
// Associations
// ---------------------------------------------------------------------------

/** Associate a contact with a company (default association). */
export async function associateContactWithCompany(contactId: string, companyId: string): Promise<void> {
  const hs = getClient();
  await hs.put(
    `/crm/v4/objects/contacts/${contactId}/associations/default/companies/${companyId}`,
  );
}

/** Associate a contact with a deal (default association). */
export async function associateContactWithDeal(contactId: string, dealId: string): Promise<void> {
  const hs = getClient();
  await hs.put(
    `/crm/v4/objects/contact/${contactId}/associations/default/deal/${dealId}`,
  );
}

// ---------------------------------------------------------------------------
// Deals
// ---------------------------------------------------------------------------

export interface CreateDealParams {
  amount: number;
  orderCode: string;
}

/**
 * Create a HubSpot Deal for a receipt.
 * Stage and pipeline come from env vars matching the n8n hardcoded values.
 */
export async function createDeal(params: CreateDealParams): Promise<string> {
  const hs = getClient();
  const stageId = process.env.HUBSPOT_DEAL_STAGE_ID ?? '183511953';
  const pipelineId = process.env.HUBSPOT_PIPELINE_ID ?? '3678552';

  const res = await hs.post<{ id: string; dealId?: string }>('/crm/v3/objects/deals', {
    properties: {
      dealname: 'Reward points',
      dealstage: stageId,
      pipeline: pipelineId,
      amount: String(params.amount),
      receipt_number: params.orderCode,
    },
  });
  return res.data.id;
}

// ---------------------------------------------------------------------------
// Line items
// ---------------------------------------------------------------------------

export interface BasketItem {
  _id: string;
  product_name?: string;
  product_id?: string;
  product_category_name?: string;
  brand_name?: string;
  qty: number;
  price_unit: number;
  discount?: number;
  vat?: number;
}

/**
 * Create a single HubSpot line item associated with a deal.
 * Replicates the "Edit Fields" + "Create line item" nodes in the Receipts workflow.
 */
export async function createLineItem(item: BasketItem, dealId: string): Promise<void> {
  const hs = getClient();

  const body = {
    properties: {
      name: item.product_name ?? item.product_id ?? 'Product',
      quantity: String(item.qty),
      price: String(item.price_unit),
      hs_sku: item._id,
      discount: String(item.discount ?? 0),
      tax: String(item.vat ?? 0),
      product_name_group: item.product_category_name ?? '',
      product_sub: item.brand_name ?? '',
    },
    associations: [
      {
        to: { id: dealId },
        types: [{ associationCategory: 'HUBSPOT_DEFINED', associationTypeId: 20 }],
      },
    ],
  };

  await hs.post('/crm/v3/objects/line_items', body);
}
