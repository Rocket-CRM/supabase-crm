-- Ausiris demo seed helpers. Merchant-locked. No cron.
-- Merchant: ausiris / b7794d29-2df7-47e2-a707-5654fe9f71c4

CREATE TABLE IF NOT EXISTS public.custom_ausiris_demo_config (
  kind text NOT NULL,
  code text NOT NULL,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  is_active boolean NOT NULL DEFAULT true,
  sort_order integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (kind, code)
);

COMMENT ON TABLE public.custom_ausiris_demo_config IS
  'Ausiris one-shot demo bookkeeping (pools + resolved ids). Not a daily generator.';

CREATE OR REPLACE FUNCTION public.custom_ausiris_demo_rand(p_key text)
RETURNS double precision
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT (('x' || substr(md5(p_key), 1, 8))::bit(32)::bigint % 1000000)::double precision / 1000000.0;
$$;

CREATE OR REPLACE FUNCTION public.custom_ausiris_demo_merchant_id()
RETURNS uuid
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT 'b7794d29-2df7-47e2-a707-5654fe9f71c4'::uuid;
$$;

CREATE OR REPLACE FUNCTION public.custom_ausiris_demo_set_ctx()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM set_config(
    'request.headers',
    json_build_object('x-merchant-id', custom_ausiris_demo_merchant_id()::text)::text,
    true
  );
  PERFORM set_config('redemption.skip_emit', 'true', true);
  PERFORM set_config('statement_timeout', '900000', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.custom_ausiris_demo_cfg(p_kind text, p_code text)
RETURNS jsonb
LANGUAGE sql
STABLE
AS $$
  SELECT payload FROM public.custom_ausiris_demo_config
  WHERE kind = p_kind AND code = p_code AND is_active
  LIMIT 1;
$$;
