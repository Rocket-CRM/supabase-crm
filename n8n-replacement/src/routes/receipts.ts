/**
 * POST /crm-receipts
 *
 * Replaces the n8n "Receipts" workflow.
 *
 * Flow:
 *  1. Receive approved-receipt webhook body
 *  2. Fetch full CRM user by body.profile_id
 *  3. Search HubSpot contact by jorakay_event_code = user_id
 *  4a. Contact exists  → go to company + deal step
 *  4b. Contact missing → create/upsert contact
 *                      → write back hs_object_id as reference_id to CRM
 *                      → go to company + deal step
 *  5. Company association:
 *     - If company_name present  → search → associate existing / create then associate
 *     - No company_name          → skip straight to deal
 *  6. Create HubSpot Deal (stage=183511953, pipeline=3678552)
 *  7. Associate contact × deal
 *  8. Loop basket_items → create one line item per item, linked to deal
 */

import { Router, Request, Response } from 'express';
import { getCrmUser, updateCrmReferenceId } from '../services/crmApi';
import {
  searchContactByUserId,
  upsertContact,
  searchCompanyByName,
  createCompany,
  associateContactWithCompany,
  associateContactWithDeal,
  createDeal,
  createLineItem,
  BasketItem,
} from '../services/hubspot';

export const receiptsRouter = Router();

receiptsRouter.post('/', async (req: Request, res: Response) => {
  try {
    // n8n pinned data shows body is nested under req.body.body when proxied,
    // but direct calls will have it flat — handle both.
    const payload = req.body?.body ?? req.body;

    const profileId: string = payload?.profile_id;
    if (!profileId) {
      res.status(400).json({ error: 'Missing profile_id in request body' });
      return;
    }

    // Step 2 — fetch CRM user
    const crmUser = await getCrmUser(profileId);
    console.log(`[receipts] CRM user fetched: ${crmUser.user_id}`);

    // Step 3 — search HubSpot contact
    const contact = await searchContactByUserId(crmUser.user_id);
    let contactId: string;

    if (contact) {
      // Step 4a — contact already exists
      console.log(`[receipts] Contact exists: ${contact.id}`);
      contactId = contact.id;
    } else {
      // Step 4b — create contact, write reference back
      console.log(`[receipts] Contact not found, creating…`);
      contactId = await upsertContact({
        userId: crmUser.user_id,
        firstName: crmUser.first_name,
        lastName: crmUser.last_name,
        phone: crmUser.phone,
      });
      console.log(`[receipts] Contact created: ${contactId}`);

      await updateCrmReferenceId(crmUser.user_id, contactId);
      console.log(`[receipts] CRM reference_id updated`);
    }

    // Step 5 — company association (optional)
    if (crmUser.company_name) {
      const companyId = await resolveCompanyId(contactId, crmUser.company_name);
      console.log(`[receipts] Company resolved: ${companyId}`);
    }

    // Step 6 — create deal
    const dealId = await createDeal({
      amount: payload.net,
      orderCode: payload.order_code,
    });
    console.log(`[receipts] Deal created: ${dealId}`);

    // Step 7 — associate contact × deal
    await associateContactWithDeal(contactId, dealId);
    console.log(`[receipts] Contact associated with deal`);

    // Step 8 — create line items for each basket item
    const basketItems: BasketItem[] = payload.basket_items ?? [];
    await Promise.all(basketItems.map((item) => createLineItem(item, dealId)));
    console.log(`[receipts] ${basketItems.length} line item(s) created`);

    res.json({ ok: true, contactId, dealId, lineItemCount: basketItems.length });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err);
    console.error('[receipts] Error:', message);
    res.status(500).json({ error: message });
  }
});

/**
 * Resolve a HubSpot company by name, creating it if needed.
 * Then associates the contact with the company.
 * Returns the companyId.
 */
async function resolveCompanyId(contactId: string, companyName: string): Promise<string> {
  console.log(`[receipts] Checking company: "${companyName}"`);
  const existing = await searchCompanyByName(companyName);

  let companyId: string;
  if (existing) {
    console.log(`[receipts] Company found: ${existing.id}`);
    companyId = existing.id;
  } else {
    console.log(`[receipts] Company not found, creating…`);
    companyId = await createCompany(companyName);
    console.log(`[receipts] Company created: ${companyId}`);
  }

  await associateContactWithCompany(contactId, companyId);
  console.log(`[receipts] Contact ${contactId} associated with company ${companyId}`);
  return companyId;
}
