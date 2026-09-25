-- Referral rebuild: one program, two conversions (signup | purchase).
-- Schema only — functions in the following migration.

CREATE TABLE IF NOT EXISTS public.referral_program (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id uuid NOT NULL UNIQUE REFERENCES public.merchant_master(id),
  is_active boolean NOT NULL DEFAULT false,
  signup_enabled boolean NOT NULL DEFAULT false,
  purchase_enabled boolean NOT NULL DEFAULT false,
  platforms text[] NOT NULL DEFAULT '{}'::text[],
  friend_offer jsonb NOT NULL DEFAULT jsonb_build_object(
    'discount_type', 'amount',
    'value', null,
    'min_spend', null,
    'ttl_hours', 24,
    'shop_live_unused_cap', 800,
    'per_referrer_live_unused_cap', 5
  ),
  shopify_wrapper jsonb NOT NULL DEFAULT jsonb_build_object(
    'landing_url', null,
    'share_message', null,
    'popup_title', null,
    'popup_button', null
  ),
  shopify_mother_discount_id text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.referral_program ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS merchant_isolation ON public.referral_program;
CREATE POLICY merchant_isolation ON public.referral_program
  FOR ALL USING (merchant_id = get_current_merchant_id());

DROP TRIGGER IF EXISTS trigger_set_updated_at_referral_program ON public.referral_program;
CREATE TRIGGER trigger_set_updated_at_referral_program
  BEFORE UPDATE ON public.referral_program
  FOR EACH ROW EXECUTE FUNCTION public.trigger_set_updated_at();

ALTER TABLE public.referral_outcomes
  ADD COLUMN IF NOT EXISTS kind text NOT NULL DEFAULT 'signup';

UPDATE public.referral_outcomes SET kind = 'signup' WHERE kind IS NULL OR kind = '';

ALTER TABLE public.referral_outcomes
  DROP CONSTRAINT IF EXISTS referral_outcomes_kind_check;
ALTER TABLE public.referral_outcomes
  ADD CONSTRAINT referral_outcomes_kind_check CHECK (kind IN ('signup', 'purchase'));

CREATE INDEX IF NOT EXISTS idx_referral_outcomes_merchant_kind
  ON public.referral_outcomes (merchant_id, kind);

ALTER TABLE public.referral_ledger
  ADD COLUMN IF NOT EXISTS kind text NOT NULL DEFAULT 'signup',
  ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'settled',
  ADD COLUMN IF NOT EXISTS platform text,
  ADD COLUMN IF NOT EXISTS claim_id uuid,
  ADD COLUMN IF NOT EXISTS code_id uuid,
  ADD COLUMN IF NOT EXISTS order_key text,
  ADD COLUMN IF NOT EXISTS friend_email text,
  ADD COLUMN IF NOT EXISTS friend_phone text,
  ADD COLUMN IF NOT EXISTS settled_at timestamptz,
  ADD COLUMN IF NOT EXISTS clawed_back_at timestamptz,
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

UPDATE public.referral_ledger
SET kind = 'signup', status = 'settled'
WHERE kind IS NULL OR kind = '';

ALTER TABLE public.referral_ledger
  DROP CONSTRAINT IF EXISTS referral_ledger_kind_check;
ALTER TABLE public.referral_ledger
  ADD CONSTRAINT referral_ledger_kind_check CHECK (kind IN ('signup', 'purchase'));

ALTER TABLE public.referral_ledger
  DROP CONSTRAINT IF EXISTS referral_ledger_status_check;
ALTER TABLE public.referral_ledger
  ADD CONSTRAINT referral_ledger_status_check CHECK (
    status IN ('applied', 'attributed', 'settled', 'clawed_back')
  );

DROP TRIGGER IF EXISTS trigger_set_updated_at_referral_ledger ON public.referral_ledger;
CREATE TRIGGER trigger_set_updated_at_referral_ledger
  BEFORE UPDATE ON public.referral_ledger
  FOR EACH ROW EXECUTE FUNCTION public.trigger_set_updated_at();

CREATE UNIQUE INDEX IF NOT EXISTS uq_referral_ledger_purchase_order
  ON public.referral_ledger (merchant_id, platform, order_key)
  WHERE kind = 'purchase' AND order_key IS NOT NULL AND status <> 'clawed_back';

CREATE TABLE IF NOT EXISTS public.referral_claim (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id uuid NOT NULL REFERENCES public.merchant_master(id),
  referrer_user_id uuid NOT NULL REFERENCES public.user_accounts(id),
  platform text NOT NULL,
  friend_email text,
  friend_phone text,
  friend_shopify_customer_id text,
  status text NOT NULL DEFAULT 'open',
  ledger_id uuid REFERENCES public.referral_ledger(id),
  completed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT referral_claim_platform_check CHECK (platform IN ('shopify', 'shopee', 'lazada')),
  CONSTRAINT referral_claim_status_check CHECK (status IN ('open', 'completed', 'expired', 'aborted')),
  CONSTRAINT referral_claim_identity_check CHECK (
    friend_email IS NOT NULL OR friend_phone IS NOT NULL
  )
);

ALTER TABLE public.referral_claim ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS merchant_isolation ON public.referral_claim;
CREATE POLICY merchant_isolation ON public.referral_claim
  FOR ALL USING (merchant_id = get_current_merchant_id());

DROP TRIGGER IF EXISTS trigger_set_updated_at_referral_claim ON public.referral_claim;
CREATE TRIGGER trigger_set_updated_at_referral_claim
  BEFORE UPDATE ON public.referral_claim
  FOR EACH ROW EXECUTE FUNCTION public.trigger_set_updated_at();

CREATE INDEX IF NOT EXISTS idx_referral_claim_open_email
  ON public.referral_claim (merchant_id, platform, friend_email)
  WHERE status = 'open' AND friend_email IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_referral_claim_open_phone
  ON public.referral_claim (merchant_id, platform, friend_phone)
  WHERE status = 'open' AND friend_phone IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_referral_claim_referrer
  ON public.referral_claim (merchant_id, referrer_user_id, status);

CREATE TABLE IF NOT EXISTS public.referral_code (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id uuid NOT NULL REFERENCES public.merchant_master(id),
  claim_id uuid NOT NULL REFERENCES public.referral_claim(id) ON DELETE CASCADE,
  referrer_user_id uuid NOT NULL REFERENCES public.user_accounts(id),
  platform text NOT NULL,
  code text NOT NULL,
  expires_at timestamptz NOT NULL,
  status text NOT NULL DEFAULT 'minted',
  platform_voucher_id text,
  platform_discount_id text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT referral_code_platform_check CHECK (platform IN ('shopify', 'shopee', 'lazada')),
  CONSTRAINT referral_code_status_check CHECK (status IN ('pending_mint', 'minted', 'used', 'expired', 'aborted'))
);

ALTER TABLE public.referral_code ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS merchant_isolation ON public.referral_code;
CREATE POLICY merchant_isolation ON public.referral_code
  FOR ALL USING (merchant_id = get_current_merchant_id());

DROP TRIGGER IF EXISTS trigger_set_updated_at_referral_code ON public.referral_code;
CREATE TRIGGER trigger_set_updated_at_referral_code
  BEFORE UPDATE ON public.referral_code
  FOR EACH ROW EXECUTE FUNCTION public.trigger_set_updated_at();

CREATE UNIQUE INDEX IF NOT EXISTS uq_referral_code_platform_code
  ON public.referral_code (merchant_id, platform, code);
CREATE INDEX IF NOT EXISTS idx_referral_code_live
  ON public.referral_code (merchant_id, referrer_user_id, status, expires_at);

ALTER TABLE public.referral_ledger
  DROP CONSTRAINT IF EXISTS referral_ledger_claim_id_fkey;
ALTER TABLE public.referral_ledger
  ADD CONSTRAINT referral_ledger_claim_id_fkey
  FOREIGN KEY (claim_id) REFERENCES public.referral_claim(id);

ALTER TABLE public.referral_ledger
  DROP CONSTRAINT IF EXISTS referral_ledger_code_id_fkey;
ALTER TABLE public.referral_ledger
  ADD CONSTRAINT referral_ledger_code_id_fkey
  FOREIGN KEY (code_id) REFERENCES public.referral_code(id);

ALTER TABLE public.order_ledger_mkp
  ADD COLUMN IF NOT EXISTS discount_codes text[] NOT NULL DEFAULT '{}'::text[];

-- Cutover: existing active referral earn channels become signup-on programs.
INSERT INTO public.referral_program (merchant_id, is_active, signup_enabled)
SELECT DISTINCT ec.merchant_id, true, true
FROM public.earn_channel ec
WHERE ec.method_type = 'referral'
  AND COALESCE(ec.active, true) = true
ON CONFLICT (merchant_id) DO NOTHING;

COMMENT ON TABLE public.referral_program IS 'Referral program on/off and purchase/signup conversion config. Earn channel is CMS card only.';
COMMENT ON TABLE public.referral_claim IS 'Public friend claim before a purchase. Friend is not required to be a member.';
COMMENT ON TABLE public.referral_code IS 'Minted commerce code at claim. Expiry set at create.';
