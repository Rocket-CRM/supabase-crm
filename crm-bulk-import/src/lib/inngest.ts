import { Inngest } from 'inngest';

export const inngest = new Inngest({
  id: 'crm-bulk-import-api',
  eventKey: process.env.INNGEST_EVENT_KEY!,
});
