import 'dotenv/config';
import express from 'express';
import { contactsRouter } from './routes/contacts';
import { receiptsRouter } from './routes/receipts';

const app = express();
app.use(express.json({ limit: '10mb' }));

// Health check
app.get('/health', (_req, res) => res.json({ ok: true }));

// Webhook routes — paths match the original n8n webhook paths
app.use('/webhook/crm-contacts', contactsRouter);
app.use('/webhook/crm-receipts', receiptsRouter);

const PORT = Number(process.env.PORT ?? 3000);
app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
  console.log(`  POST http://localhost:${PORT}/webhook/crm-contacts`);
  console.log(`  POST http://localhost:${PORT}/webhook/crm-receipts`);
});
