import express from 'express';
import cors from 'cors';
import { importRoutes } from './routes/import.js';

const app = express();
const PORT = process.env.PORT || 3000;

app.use(cors());
app.use(express.json());

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', service: 'crm-bulk-import' });
});

// Mount import routes
app.use('/api/import', importRoutes);

app.listen(PORT, () => {
  console.log(`Bulk import service listening on port ${PORT}`);
});
