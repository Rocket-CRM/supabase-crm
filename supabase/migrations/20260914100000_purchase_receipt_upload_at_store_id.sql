-- Front Line counter (reward-stock store) vs store on the receipt (store_id).
-- Nullable: existing writers omit the column; reports treat NULL as unknown counter.

ALTER TABLE public.purchase_receipt_upload
  ADD COLUMN IF NOT EXISTS upload_at_store_id uuid;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'purchase_receipt_upload_upload_at_store_id_fkey'
  ) THEN
    ALTER TABLE public.purchase_receipt_upload
      ADD CONSTRAINT purchase_receipt_upload_upload_at_store_id_fkey
      FOREIGN KEY (upload_at_store_id)
      REFERENCES public.store_master (id)
      ON DELETE SET NULL;
  END IF;
END $$;

COMMENT ON COLUMN public.purchase_receipt_upload.upload_at_store_id IS
  'Reward-stock counter where staff processed the upload (Front Line). Distinct from store_id (store on receipt).';
