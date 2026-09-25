import axios from 'axios';
import https from 'https';

const BASE_URL = process.env.CRM_BASE_URL ?? 'https://crm-api.rocket-tech.app';
const API_KEY = process.env.CRM_API_KEY ?? '';

// n8n had allowUnauthorizedCerts: true on PATCH calls — replicate here
const httpsAgent = new https.Agent({ rejectUnauthorized: false });

const client = axios.create({
  baseURL: BASE_URL,
  headers: { 'x-api-key': API_KEY },
  httpsAgent,
});

export interface CrmUser {
  user_id: string;
  first_name: string;
  last_name: string;
  phone: string;
  line_user_id?: string;
  state?: string;       // province
  city?: string;        // district
  sub_district?: string;
  postal_code?: string;
  address_line_1?: string;
  address_line_2?: string;
  company_name?: string;
  reference_id?: string;
}

/** GET /openapi/api/v1/users/:userId */
export async function getCrmUser(userId: string): Promise<CrmUser> {
  const res = await client.get<{ data: CrmUser }>(`/openapi/api/v1/users/${userId}`);
  return res.data.data;
}

/** PATCH /openapi/api/v1/users/:userId — write back the HubSpot contact id */
export async function updateCrmReferenceId(userId: string, hsObjectId: string): Promise<void> {
  await client.patch(`/openapi/api/v1/users/${userId}`, { reference_id: hsObjectId });
}
