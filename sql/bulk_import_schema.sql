-- =====================================================
-- Bulk Import System - Database Schema
-- =====================================================
-- This file creates the necessary database objects for
-- the bulk purchase import system.
-- =====================================================

-- 1. Create bulk_import_batches table
-- Tracks import job status and metadata
CREATE TABLE IF NOT EXISTS bulk_import_batches (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id UUID NOT NULL REFERENCES merchant_master(id),
  batch_name TEXT NOT NULL,
  uploaded_by UUID REFERENCES user_accounts(id),
  file_name TEXT NOT NULL,
  total_rows INTEGER,
  imported_purchases INTEGER DEFAULT 0,
  imported_items INTEGER DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'pending',
  error_message TEXT,
  metadata JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  started_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ
);

-- Create indexes for efficient queries
CREATE INDEX IF NOT EXISTS idx_bulk_import_merchant_status 
  ON bulk_import_batches(merchant_id, status);

CREATE INDEX IF NOT EXISTS idx_bulk_import_created 
  ON bulk_import_batches(created_at DESC);

-- Add comment
COMMENT ON TABLE bulk_import_batches IS 'Tracks bulk import jobs for purchase transactions';

-- =====================================================
-- 2. Create atomic insert function
-- Inserts purchases and items in a single transaction
-- All-or-nothing: 50k rows succeed or fail together
-- =====================================================

CREATE OR REPLACE FUNCTION bulk_insert_purchases_with_items(
  p_purchases JSONB,  -- Array of purchase objects with nested items
  p_merchant_id UUID
) RETURNS TABLE (
  success BOOLEAN,
  imported_purchases INTEGER,
  imported_items INTEGER,
  error_message TEXT
) AS $$
DECLARE
  v_purchase JSONB;
  v_item JSONB;
  v_transaction_id UUID;
  v_purchase_count INTEGER := 0;
  v_item_count INTEGER := 0;
  v_user_id UUID;
  v_store_id TEXT;
BEGIN
  BEGIN -- Atomic transaction block
    -- Loop through each purchase
    FOR v_purchase IN SELECT * FROM jsonb_array_elements(p_purchases)
    LOOP
      -- Resolve user_id
      v_user_id := (v_purchase->>'user_id')::UUID;
      v_store_id := v_purchase->>'store_id';
      
      -- Insert purchase header
      INSERT INTO purchase_ledger (
        merchant_id,
        transaction_number,
        transaction_date,
        user_id,
        store_id,
        total_amount,
        discount_amount,
        tax_amount,
        final_amount,
        status,
        payment_status,
        record_type,
        processing_method,
        earn_currency,
        transaction_source,
        api_source,
        external_ref,
        notes
      ) VALUES (
        p_merchant_id,
        v_purchase->>'transaction_number',
        (v_purchase->>'transaction_date')::TIMESTAMPTZ,
        v_user_id,
        v_store_id,
        (v_purchase->>'total_amount')::NUMERIC,
        COALESCE((v_purchase->>'discount_amount')::NUMERIC, 0),
        COALESCE((v_purchase->>'tax_amount')::NUMERIC, 0),
        (v_purchase->>'final_amount')::NUMERIC,
        COALESCE(v_purchase->>'status', 'completed'),
        COALESCE(v_purchase->>'payment_status', 'paid'),
        COALESCE(v_purchase->>'record_type', 'credit'),
        COALESCE(v_purchase->>'processing_method', 'queue'),
        COALESCE((v_purchase->>'earn_currency')::BOOLEAN, true),
        COALESCE(v_purchase->>'transaction_source', 'admin'),
        'bulk_import',
        v_purchase->>'external_ref',
        v_purchase->>'notes'
      ) RETURNING id INTO v_transaction_id;
      
      v_purchase_count := v_purchase_count + 1;
      
      -- Insert line items
      FOR v_item IN SELECT * FROM jsonb_array_elements(v_purchase->'items')
      LOOP
        INSERT INTO purchase_items_ledger (
          transaction_id,
          merchant_id,
          sku_id,
          quantity,
          unit_price,
          discount_amount,
          tax_amount,
          line_total
        ) VALUES (
          v_transaction_id,
          p_merchant_id,
          (v_item->>'sku_id')::UUID,
          (v_item->>'quantity')::NUMERIC,
          (v_item->>'unit_price')::NUMERIC,
          COALESCE((v_item->>'discount_amount')::NUMERIC, 0),
          COALESCE((v_item->>'tax_amount')::NUMERIC, 0),
          (v_item->>'line_total')::NUMERIC
        );
        
        v_item_count := v_item_count + 1;
      END LOOP;
    END LOOP;
    
    -- Success - commit will happen automatically
    RETURN QUERY SELECT true, v_purchase_count, v_item_count, NULL::TEXT;
    
  EXCEPTION WHEN OTHERS THEN
    -- Any error rolls back entire batch
    RETURN QUERY SELECT false, 0, 0, SQLERRM;
  END;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Add comment
COMMENT ON FUNCTION bulk_insert_purchases_with_items IS 
  'Atomically inserts bulk purchases with line items. All-or-nothing transaction.';

-- =====================================================
-- Schema creation complete
-- =====================================================
-- Usage:
-- 1. Run this SQL in Supabase SQL Editor
-- 2. Verify table created: SELECT * FROM bulk_import_batches LIMIT 1;
-- 3. Test function with sample data
-- =====================================================
