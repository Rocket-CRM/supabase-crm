## Customer Import API Implementation

Add this to your `Rocket-CRM/crm-batch-upload/src/routes/import.ts`:

### 1. Customer Row Normalization Function

```typescript
function normalizeCustomerRow(row: any): Record<string, unknown> {
  return {
    // Core fields
    user_accounts_tel: row.user_accounts_tel || row.tel || null,
    user_accounts_first_name: row.user_accounts_first_name || row.first_name || null,
    user_accounts_last_name: row.user_accounts_last_name || row.last_name || null,
    user_accounts_email: row.user_accounts_email || row.email || null,
    user_accounts_birthdate: row.user_accounts_birthdate || row.birthdate || null,
    user_accounts_gender: row.user_accounts_gender || row.gender || null,
    
    // New persona/type fields
    user_accounts_persona_id: row.user_accounts_persona_id || row.persona_id || null,
    user_accounts_user_type: row.user_accounts_user_type || row.user_type || null,
    
    // Tier fields
    user_accounts_tier_id: row.user_accounts_tier_id || row.tier_id || null,
    user_accounts_tier_lock_downgrade: row.user_accounts_tier_lock_downgrade === 'true' || row.user_accounts_tier_lock_downgrade === true,
    user_accounts_tier_locked_downgrade_until: row.user_accounts_tier_locked_downgrade_until || row.tier_locked_downgrade_until || null,
    
    // Wallet
    user_wallet_points_balance: row.user_wallet_points_balance || row.points_balance || null,
    
    // Channel preferences
    user_accounts_channel_line_notify: row.user_accounts_channel_line_notify === 'true' || row.user_accounts_channel_line_notify === true,
    user_accounts_channel_email_notify: row.user_accounts_channel_email_notify === 'true' || row.user_accounts_channel_email_notify === true,
    user_accounts_channel_sms_notify: row.user_accounts_channel_sms_notify === 'true' || row.user_accounts_channel_sms_notify === true,
    user_accounts_channel_line_marketing: row.user_accounts_channel_line_marketing === 'true' || row.user_accounts_channel_line_marketing === true,
    user_accounts_channel_email_marketing: row.user_accounts_channel_email_marketing === 'true' || row.user_accounts_channel_email_marketing === true,
    user_accounts_channel_sms_marketing: row.user_accounts_channel_sms_marketing === 'true' || row.user_accounts_channel_sms_marketing === true,
    
    // External IDs
    user_accounts_line_id: row.user_accounts_line_id || row.line_id || null,
    user_accounts_external_id: row.user_accounts_external_id || row.external_id || null,
  };
}
```

### 2. Customer Import Route

```typescript
router.post('/api/import/customers', async (req, res) => {
  try {
    const { csv, merchant_id, create_wallet_ledger_entry } = req.body;

    if (!csv || !merchant_id) {
      return res.status(400).json({ error: 'Missing required fields: csv, merchant_id' });
    }

    // Parse CSV
    const records = await new Promise((resolve, reject) => {
      parse(csv, { columns: true, skip_empty_lines: true }, (err, output) => {
        if (err) reject(err);
        else resolve(output);
      });
    });

    // Normalize all rows
    const normalizedData = records.map(normalizeCustomerRow);

    // Create batch record
    const { data: batch, error: batchError } = await supabase
      .from('bulk_import_batches')
      .insert({
        merchant_id,
        import_type: 'customers',
        status: 'pending',
        total_rows: normalizedData.length,
      })
      .select()
      .single();

    if (batchError || !batch) {
      throw new Error(`Failed to create batch: ${batchError?.message}`);
    }

    // Send to Inngest
    await inngest.send({
      name: 'import/bulk-customers',
      data: {
        batch_id: batch.id,
        merchant_id,
        create_wallet_ledger_entry: create_wallet_ledger_entry === true,
        csv_data: normalizedData,
      },
    });

    res.json({
      success: true,
      batch_id: batch.id,
      total_rows: normalizedData.length,
    });
  } catch (error) {
    console.error('Customer import error:', error);
    res.status(500).json({ error: error.message });
  }
});
```

### 3. Update Purchase Import Route

Make sure the purchase route explicitly sets `import_type: 'purchases'`:

```typescript
router.post('/api/import/purchases', async (req, res) => {
  // ... existing code ...
  
  const { data: batch, error: batchError } = await supabase
    .from('bulk_import_batches')
    .insert({
      merchant_id,
      import_type: 'purchases',  // <-- Make sure this is explicitly set
      status: 'pending',
      total_rows: parsedData.length,
    })
    .select()
    .single();
    
  // ... rest of code ...
});
```

## Next Steps

1. Add the above code to `Rocket-CRM/crm-batch-upload/src/routes/import.ts`
2. Commit and push to GitHub
3. Verify Render auto-deploys
4. Register the customer function in Inngest
