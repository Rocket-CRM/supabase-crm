import express from 'express';
import multer from 'multer';
import Papa from 'papaparse';
import fs from 'fs';
import { supabase } from '../lib/supabase.js';
import { inngest } from '../lib/inngest.js';

const router = express.Router();

// Configure multer for file uploads
const upload = multer({
  dest: '/tmp/uploads',
  limits: { fileSize: 100 * 1024 * 1024 }, // 100MB max
  fileFilter: (req, file, cb) => {
    if (file.mimetype !== 'text/csv' && !file.originalname.endsWith('.csv')) {
      cb(new Error('Only CSV files are allowed'));
      return;
    }
    cb(null, true);
  },
});

// Normalize CSV row keys: support table-prefixed (user_accounts_tel) and short names (tel)
function normalizeCustomerRow(raw: Record<string, string>): Record<string, string> {
  const row: Record<string, string> = {};
  for (const [k, v] of Object.entries(raw)) {
    if (v === undefined || v === null) continue;
    const key = k.trim().toLowerCase();
    row[key] = typeof v === 'string' ? v.trim() : String(v);
  }
  return row;
}

// Upload CSV and trigger customer import
router.post('/customers', upload.single('file'), async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ error: 'No file uploaded' });
    }

    const { merchant_id, batch_name, create_wallet_ledger_entry } = req.body;

    if (!merchant_id) {
      fs.unlinkSync(req.file.path);
      return res.status(400).json({ error: 'merchant_id is required' });
    }

    const createLedger = create_wallet_ledger_entry === 'true' || create_wallet_ledger_entry === true;

    const fileContent = fs.readFileSync(req.file.path, 'utf-8');
    const parsed = Papa.parse(fileContent, {
      header: true,
      skipEmptyLines: true,
      transformHeader: (header: string) => header.trim().toLowerCase(),
    });

    if (parsed.errors.length > 0) {
      fs.unlinkSync(req.file.path);
      return res.status(400).json({
        error: 'CSV parsing failed',
        details: parsed.errors,
      });
    }

    const rows = (parsed.data as Record<string, string>[]).map(normalizeCustomerRow);

    const { data: batch, error: batchError } = await supabase
      .from('bulk_import_batches')
      .insert({
        merchant_id,
        batch_name: batch_name || req.file.originalname,
        file_name: req.file.originalname,
        total_rows: rows.length,
        status: 'pending',
        import_type: 'customers',
      })
      .select()
      .single();

    if (batchError || !batch) {
      fs.unlinkSync(req.file.path);
      throw new Error(`Failed to create batch: ${batchError?.message}`);
    }

    await inngest.send({
      name: 'import/bulk-customers',
      data: {
        batch_id: batch.id,
        merchant_id,
        create_wallet_ledger_entry: createLedger,
        csv_data: rows,
      },
    });

    fs.unlinkSync(req.file.path);

    res.json({
      success: true,
      batch_id: batch.id,
      total_rows: rows.length,
      message: 'Customer import started. Check status endpoint for progress.',
    });
  } catch (error) {
    console.error('Customer upload error:', error);
    res.status(500).json({
      error: error instanceof Error ? error.message : 'Upload failed',
    });
  }
});

// Upload CSV and trigger import
router.post('/purchases', upload.single('file'), async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ error: 'No file uploaded' });
    }
    
    const { merchant_id, batch_name } = req.body;
    
    if (!merchant_id) {
      return res.status(400).json({ error: 'merchant_id is required' });
    }
    
    // Parse CSV immediately on Render
    const fileContent = fs.readFileSync(req.file.path, 'utf-8');
    const parsed = Papa.parse(fileContent, {
      header: true,
      skipEmptyLines: true,
      transformHeader: (header: string) => header.trim().toLowerCase(),
    });
    
    if (parsed.errors.length > 0) {
      fs.unlinkSync(req.file.path); // Clean up file
      return res.status(400).json({ 
        error: 'CSV parsing failed', 
        details: parsed.errors 
      });
    }
    
    // Create batch record
    const { data: batch, error: batchError } = await supabase
      .from('bulk_import_batches')
      .insert({
        merchant_id,
        batch_name: batch_name || req.file.originalname,
        file_name: req.file.originalname,
        total_rows: parsed.data.length,
        status: 'pending',
        import_type: 'purchases',
      })
      .select()
      .single();
    
    if (batchError || !batch) {
      fs.unlinkSync(req.file.path); // Clean up file
      throw new Error(`Failed to create batch: ${batchError?.message}`);
    }
    
    // Trigger Inngest workflow with parsed CSV data
    await inngest.send({
      name: 'import/bulk-purchases',
      data: {
        batch_id: batch.id,
        csv_data: parsed.data, // Send parsed data instead of file path
        merchant_id,
      },
    });
    
    // Clean up file immediately after parsing
    fs.unlinkSync(req.file.path);
    
    res.json({
      success: true,
      batch_id: batch.id,
      total_rows: parsed.data.length,
      message: 'Import started. Check status endpoint for progress.',
    });
  } catch (error) {
    console.error('Upload error:', error);
    res.status(500).json({
      error: error instanceof Error ? error.message : 'Upload failed',
    });
  }
});

// Check import status
router.get('/status/:batch_id', async (req, res) => {
  try {
    const { data: batch } = await supabase
      .from('bulk_import_batches')
      .select('*')
      .eq('id', req.params.batch_id)
      .single();
    
    if (!batch) {
      return res.status(404).json({ error: 'Batch not found' });
    }
    
    res.json(batch);
  } catch (error) {
    res.status(500).json({ error: 'Failed to fetch status' });
  }
});

// List imports for merchant
router.get('/list/:merchant_id', async (req, res) => {
  try {
    const { data: batches } = await supabase
      .from('bulk_import_batches')
      .select('*')
      .eq('merchant_id', req.params.merchant_id)
      .order('created_at', { ascending: false })
      .limit(50);
    
    res.json(batches || []);
  } catch (error) {
    res.status(500).json({ error: 'Failed to fetch batches' });
  }
});

export { router as importRoutes };
