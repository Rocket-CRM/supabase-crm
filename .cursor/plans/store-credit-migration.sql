-- store_credit internal top-up v1

CREATE TABLE IF NOT EXISTS public.store_credit_promo (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id uuid NOT NULL REFERENCES public.merchant_master(id) ON DELETE CASCADE,
  name text NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  window_start timestamptz,
  window_end timestamptz,
  event_id uuid REFERENCES public.syngenta_events_master(id) ON DELETE CASCADE,
  min_topup_amount integer NOT NULL CHECK (min_topup_amount > 0),
  bonus_type text NOT NULL CHECK (bonus_type IN ('fixed', 'percent')),
  bonus_amount integer CHECK (bonus_amount IS NULL OR bonus_amount >= 0),
  bonus_percent numeric(5,2) CHECK (bonus_percent IS NULL OR bonus_percent >= 0),
  max_bonus_amount integer CHECK (max_bonus_amount IS NULL OR max_bonus_amount >= 0),
  max_bonus_per_topup integer CHECK (max_bonus_per_topup IS NULL OR max_bonus_per_topup >= 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT store_credit_promo_bonus_shape CHECK (
    (bonus_type = 'fixed' AND bonus_amount IS NOT NULL AND bonus_percent IS NULL)
    OR (bonus_type = 'percent' AND bonus_percent IS NOT NULL AND bonus_amount IS NULL)
  )
);

CREATE INDEX IF NOT EXISTS idx_store_credit_promo_merchant_active
  ON public.store_credit_promo (merchant_id, is_active, min_topup_amount DESC);

CREATE INDEX IF NOT EXISTS idx_store_credit_promo_event
  ON public.store_credit_promo (merchant_id, event_id)
  WHERE event_id IS NOT NULL;

ALTER TABLE public.store_credit_promo ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS merchant_isolation ON public.store_credit_promo;
CREATE POLICY merchant_isolation ON public.store_credit_promo
  FOR ALL USING (merchant_id = get_current_merchant_id());

DROP TRIGGER IF EXISTS set_updated_at ON public.store_credit_promo;
CREATE TRIGGER set_updated_at
  BEFORE UPDATE ON public.store_credit_promo
  FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

COMMENT ON TABLE public.store_credit_promo IS 'Store credit top-up bonus conditions. Each row is one tier; runtime picks highest qualifying min_topup_amount.';
