/**
 * POST /crm-contacts
 *
 * Replaces the n8n "CRM create / update user" workflow.
 *
 * Flow:
 *  1. Receive webhook body (CRM user event)
 *  2. Fetch full user record from CRM API using body._id
 *  3. Search HubSpot contact by jorakay_event_code = user_id
 *  4a. Contact exists  → go to company-association step
 *  4b. Contact missing → create/upsert contact in HubSpot
 *                      → write back hs_object_id to CRM as reference_id
 *                      → go to company-association step
 *  5. If user has company_name:
 *     → Search HubSpot company by name
 *     → If found  → associate contact × company
 *     → If missing → create company → associate contact × company
 */

import { Router, Request, Response } from 'express';
import { getCrmUser, updateCrmReferenceId } from '../services/crmApi';
import {
  searchContactByUserId,
  upsertContact,
  searchCompanyByName,
  createCompany,
  associateContactWithCompany,
} from '../services/hubspot';

export const contactsRouter = Router();

contactsRouter.post('/', async (req: Request, res: Response) => {
  try {
    const userId: string = req.body?._id ?? req.body?.body?._id;
    if (!userId) {
      res.status(400).json({ error: 'Missing _id in request body' });
      return;
    }

    // Step 2 — fetch CRM user
    const crmUser = await getCrmUser(userId);
    console.log(`[contacts] CRM user fetched: ${crmUser.user_id}`);

    // Step 3 — search HubSpot contact
    let contact = await searchContactByUserId(crmUser.user_id);
    let contactId: string;

    if (contact) {
      // Step 4a — contact already exists, just grab its id
      console.log(`[contacts] Contact exists in HubSpot: ${contact.id}`);
      contactId = contact.id;
    } else {
      // Step 4b — create contact
      console.log(`[contacts] Contact not found, creating…`);
      contactId = await upsertContact({
        userId: crmUser.user_id,
        firstName: crmUser.first_name,
        lastName: crmUser.last_name,
        phone: crmUser.phone,
        lineUserId: crmUser.line_user_id,
        province: crmUser.state,
        district: crmUser.city,
        subDistrict: crmUser.sub_district,
        postalCode: crmUser.postal_code,
        streetAddress: [crmUser.address_line_1, crmUser.address_line_2].filter(Boolean).join(''),
      });
      console.log(`[contacts] Contact created: ${contactId}`);

      // Write HubSpot id back to CRM
      await updateCrmReferenceId(crmUser.user_id, contactId);
      console.log(`[contacts] CRM reference_id updated`);
    }

    // Step 5 — company association (runs for both new and existing contacts)
    if (crmUser.company_name) {
      await handleCompanyAssociation(contactId, crmUser.company_name);
    }

    res.json({ ok: true, contactId });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err);
    console.error('[contacts] Error:', message);
    res.status(500).json({ error: message });
  }
});

async function handleCompanyAssociation(contactId: string, companyName: string): Promise<void> {
  console.log(`[contacts] Checking company: "${companyName}"`);
  const existing = await searchCompanyByName(companyName);

  let companyId: string;
  if (existing) {
    console.log(`[contacts] Company found: ${existing.id}`);
    companyId = existing.id;
  } else {
    console.log(`[contacts] Company not found, creating…`);
    companyId = await createCompany(companyName);
    console.log(`[contacts] Company created: ${companyId}`);
  }

  await associateContactWithCompany(contactId, companyId);
  console.log(`[contacts] Associated contact ${contactId} ↔ company ${companyId}`);
}
