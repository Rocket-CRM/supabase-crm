-- Notification engine: per-channel settings + email templates.
-- LINE send path stays backward compatible (resolver default channel = 'line').
-- notification_log unique is unchanged this migration — email send lands with the router.

-- ── Catalog: email defaults ────────────────────────────────────────────────
ALTER TABLE public.notification_event_catalog
  ADD COLUMN IF NOT EXISTS default_enabled_email boolean NOT NULL DEFAULT false;

UPDATE public.notification_event_catalog
   SET default_enabled_email = true
 WHERE is_active = true
   AND (
     (event_key = 'redemption' AND sub_event = 'issued')
     OR (event_key = 'tier' AND sub_event = 'upgrade')
   );

-- ── Settings: channel ─────────────────────────────────────────────────────
ALTER TABLE public.merchant_notification_settings
  ADD COLUMN IF NOT EXISTS channel text NOT NULL DEFAULT 'line';

ALTER TABLE public.merchant_notification_settings
  DROP CONSTRAINT IF EXISTS uq_merchant_notification_settings;

ALTER TABLE public.merchant_notification_settings
  ADD CONSTRAINT uq_merchant_notification_settings
  UNIQUE (merchant_id, event_key, sub_event, channel);

ALTER TABLE public.merchant_notification_settings
  DROP CONSTRAINT IF EXISTS merchant_notification_settings_channel_chk;

ALTER TABLE public.merchant_notification_settings
  ADD CONSTRAINT merchant_notification_settings_channel_chk
  CHECK (channel IN ('line', 'email', 'sms'));

DROP INDEX IF EXISTS ix_merchant_notification_settings_enabled;
CREATE INDEX ix_merchant_notification_settings_enabled
  ON public.merchant_notification_settings (merchant_id, event_key, sub_event, channel)
  WHERE enabled = true;

-- ── Templates: channel + email_template ───────────────────────────────────
ALTER TABLE public.notification_template
  ADD COLUMN IF NOT EXISTS channel text NOT NULL DEFAULT 'line';

ALTER TABLE public.notification_template
  ADD COLUMN IF NOT EXISTS email_template jsonb;

ALTER TABLE public.notification_template
  ALTER COLUMN flex_template DROP NOT NULL;

DROP INDEX IF EXISTS uq_notification_template_merchant_active;
DROP INDEX IF EXISTS uq_notification_template_system_active;

CREATE UNIQUE INDEX uq_notification_template_merchant_active
  ON public.notification_template (merchant_id, event_key, sub_event, channel)
  WHERE merchant_id IS NOT NULL AND is_active = true;

CREATE UNIQUE INDEX uq_notification_template_system_active
  ON public.notification_template (event_key, sub_event, channel)
  WHERE merchant_id IS NULL AND is_active = true;

ALTER TABLE public.notification_template
  DROP CONSTRAINT IF EXISTS notification_template_channel_chk;

ALTER TABLE public.notification_template
  ADD CONSTRAINT notification_template_channel_chk
  CHECK (channel IN ('line', 'email', 'sms'));

-- ── Appearance (email theme) ──────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.merchant_notification_appearance (
  merchant_id   uuid PRIMARY KEY REFERENCES public.merchant_master(id) ON DELETE CASCADE,
  from_name     text,
  logo_url      text,
  primary_color text,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.merchant_notification_appearance ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS merchant_isolation ON public.merchant_notification_appearance;
CREATE POLICY merchant_isolation ON public.merchant_notification_appearance
  FOR ALL
  USING (merchant_id = public.get_current_merchant_id())
  WITH CHECK (merchant_id = public.get_current_merchant_id());

DROP TRIGGER IF EXISTS set_updated_at ON public.merchant_notification_appearance;
CREATE TRIGGER set_updated_at
  BEFORE UPDATE ON public.merchant_notification_appearance
  FOR EACH ROW EXECUTE FUNCTION public.trigger_set_updated_at();

-- ── Email template helpers ────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_validate_notification_email_template(
  p_event_key text,
  p_sub_event text,
  p_template jsonb
) RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $function$
DECLARE
  v_allowlist      jsonb;
  v_invalid        text[];
  v_text           text;
  v_refs           text[];
BEGIN
  IF p_template IS NULL OR jsonb_typeof(p_template) IS DISTINCT FROM 'object' THEN
    RETURN jsonb_build_object(
      'valid', false,
      'error_code', 'INVALID_INPUT',
      'title', 'email_template must be a JSON object',
      'description', format('Event %s.%s', p_event_key, p_sub_event)
    );
  END IF;

  IF COALESCE(btrim(p_template->>'subject'), '') = '' THEN
    RETURN jsonb_build_object(
      'valid', false,
      'error_code', 'INVALID_TEMPLATE_STRUCTURE',
      'title', 'Email subject is required',
      'description', format('Event %s.%s', p_event_key, p_sub_event)
    );
  END IF;

  v_allowlist := public.fn_notification_template_field_allowlist(p_event_key, p_sub_event);

  v_text := concat_ws(' ',
    p_template->>'subject',
    p_template->>'title',
    p_template->>'description',
    p_template->>'button',
    p_template->>'banner_url'
  );

  SELECT array_agg(DISTINCT m[1])
    INTO v_refs
    FROM regexp_matches(v_text, '\$\{([a-z][a-z0-9_]*)\}', 'gi') AS m;

  IF v_refs IS NOT NULL THEN
    SELECT array_agg(r.ref ORDER BY r.ref)
      INTO v_invalid
      FROM unnest(v_refs) AS r(ref)
     WHERE NOT (v_allowlist ? r.ref);
  END IF;

  IF v_invalid IS NOT NULL AND array_length(v_invalid, 1) > 0 THEN
    RETURN jsonb_build_object(
      'valid', false,
      'error_code', 'INVALID_TEMPLATE_FIELDS',
      'title', 'Template references unknown fields',
      'description', format('Event %s.%s: invalid %s', p_event_key, p_sub_event, v_invalid::text)
    );
  END IF;

  RETURN jsonb_build_object('valid', true);
END;
$function$;

-- Allowlist: only walk LINE flex system templates (email rows have no flex).
CREATE OR REPLACE FUNCTION public.fn_notification_template_field_allowlist(
  p_event_key text,
  p_sub_event text
) RETURNS jsonb
LANGUAGE sql
STABLE
AS $function$
  SELECT COALESCE(jsonb_agg(DISTINCT val ORDER BY val), '[]'::jsonb)
  FROM (
    SELECT jsonb_array_elements_text(c.available_fields) AS val
    FROM public.notification_event_catalog c
    WHERE c.event_key = p_event_key
      AND c.sub_event = p_sub_event
      AND c.is_active = true
    UNION
    SELECT unnest(public.fn_notification_system_template_fields()) AS val
    UNION
    SELECT jsonb_array_elements_text(
      public.fn_extract_notification_template_field_refs(sys_t.flex_template)->'marker_fields'
    ) AS val
    FROM public.notification_template sys_t
    WHERE sys_t.event_key = p_event_key
      AND sys_t.sub_event = p_sub_event
      AND sys_t.merchant_id IS NULL
      AND sys_t.is_active = true
      AND sys_t.channel = 'line'
      AND sys_t.flex_template IS NOT NULL
    UNION
    SELECT jsonb_array_elements_text(
      public.fn_extract_notification_template_field_refs(sys_t.flex_template)->'placeholder_fields'
    ) AS val
    FROM public.notification_template sys_t
    WHERE sys_t.event_key = p_event_key
      AND sys_t.sub_event = p_sub_event
      AND sys_t.merchant_id IS NULL
      AND sys_t.is_active = true
      AND sys_t.channel = 'line'
      AND sys_t.flex_template IS NOT NULL
  ) allowed;
$function$;

-- ── Seed system email templates ───────────────────────────────────────────
INSERT INTO public.notification_template (
  merchant_id, event_key, sub_event, channel, flex_template, email_template, is_active
)
SELECT
  NULL,
  c.event_key,
  c.sub_event,
  'email',
  NULL,
  CASE
    WHEN c.event_key = 'currency' AND c.sub_event = 'earned' THEN
      jsonb_build_object(
        'subject', 'You earned ${amount} ${currency}',
        'title', 'You earned points',
        'description', 'We added ${amount} ${currency} to your account.',
        'button', 'View rewards',
        'banner_url', NULL
      )
    WHEN c.event_key = 'currency' AND c.sub_event = 'burned' THEN
      jsonb_build_object(
        'subject', 'You spent ${amount} ${currency}',
        'title', 'Points used',
        'description', '${amount} ${currency} were used from your account.',
        'button', 'View activity',
        'banner_url', NULL
      )
    WHEN c.event_key = 'currency' AND c.sub_event = 'expired' THEN
      jsonb_build_object(
        'subject', '${amount} ${currency} expired',
        'title', 'Points expired',
        'description', '${amount} ${currency} have expired.',
        'button', 'Earn more',
        'banner_url', NULL
      )
    WHEN c.event_key = 'purchase' AND c.sub_event = 'created' THEN
      jsonb_build_object(
        'subject', 'We received your order',
        'title', 'Order received',
        'description', 'Order ${transaction_number} has been received.',
        'button', 'View order',
        'banner_url', NULL
      )
    WHEN c.event_key = 'purchase' AND c.sub_event = 'completed' THEN
      jsonb_build_object(
        'subject', 'Your order is complete',
        'title', 'Order complete',
        'description', 'Order ${transaction_number} is complete.',
        'button', 'View order',
        'banner_url', NULL
      )
    WHEN c.event_key = 'purchase' AND c.sub_event = 'cancelled' THEN
      jsonb_build_object(
        'subject', 'Your order was cancelled',
        'title', 'Order cancelled',
        'description', 'Order ${transaction_number} was cancelled.',
        'button', 'View order',
        'banner_url', NULL
      )
    WHEN c.event_key = 'purchase' AND c.sub_event = 'refunded' THEN
      jsonb_build_object(
        'subject', 'Your order was refunded',
        'title', 'Order refunded',
        'description', 'Order ${transaction_number} was refunded.',
        'button', 'View order',
        'banner_url', NULL
      )
    WHEN c.event_key = 'purchase_item' AND c.sub_event = 'completed' THEN
      jsonb_build_object(
        'subject', 'An item on your order is complete',
        'title', 'Item complete',
        'description', '${product_name} is complete.',
        'button', 'View order',
        'banner_url', NULL
      )
    WHEN c.event_key = 'receipt' AND c.sub_event = 'submitted' THEN
      jsonb_build_object(
        'subject', 'We received your receipt',
        'title', 'Receipt received',
        'description', 'Your receipt is waiting for review.',
        'button', 'View status',
        'banner_url', NULL
      )
    WHEN c.event_key = 'receipt' AND c.sub_event = 'rejected' THEN
      jsonb_build_object(
        'subject', 'Your receipt needs attention',
        'title', 'Receipt not approved',
        'description', 'Reason: ${reject_reason}',
        'button', 'Try again',
        'banner_url', NULL
      )
    WHEN c.event_key = 'redemption' AND c.sub_event = 'issued' THEN
      jsonb_build_object(
        'subject', 'Your ${reward_name} is ready',
        'title', 'Enjoy your reward',
        'description', 'Your ${reward_name} is in your account. Code: ${redemption_code}',
        'button', 'View reward',
        'banner_url', NULL
      )
    WHEN c.event_key = 'redemption' AND c.sub_event = 'used' THEN
      jsonb_build_object(
        'subject', 'You used ${reward_name}',
        'title', 'Reward used',
        'description', 'You used ${reward_name}.',
        'button', 'View rewards',
        'banner_url', NULL
      )
    WHEN c.event_key = 'redemption' AND c.sub_event = 'cancelled' THEN
      jsonb_build_object(
        'subject', 'Your ${reward_name} was cancelled',
        'title', 'Reward cancelled',
        'description', '${reward_name} was cancelled. ${cancelled_reason}',
        'button', 'View rewards',
        'banner_url', NULL
      )
    WHEN c.event_key = 'redemption' AND c.sub_event = 'entitlement_used' THEN
      jsonb_build_object(
        'subject', 'You used ${reward_name}',
        'title', 'Reward used',
        'description', 'You used ${reward_name}.',
        'button', 'View rewards',
        'banner_url', NULL
      )
    WHEN c.event_key = 'redemption' AND c.sub_event = 'entitlement_expired' THEN
      jsonb_build_object(
        'subject', 'Your ${reward_name} expired',
        'title', 'Reward expired',
        'description', '${reward_name} expired on ${use_expire_date}.',
        'button', 'View rewards',
        'banner_url', NULL
      )
    WHEN c.event_key = 'redemption' AND c.sub_event = 'package_granted' THEN
      jsonb_build_object(
        'subject', 'You received ${reward_name}',
        'title', 'Package added',
        'description', '${reward_name} was added to your account.',
        'button', 'View rewards',
        'banner_url', NULL
      )
    WHEN c.event_key = 'signup' AND c.sub_event = 'signup' THEN
      jsonb_build_object(
        'subject', 'Welcome to the rewards program',
        'title', 'Welcome',
        'description', 'Your account is ready. Start earning rewards.',
        'button', 'Explore rewards',
        'banner_url', NULL
      )
    WHEN c.event_key = 'tier' AND c.sub_event = 'upgrade' THEN
      jsonb_build_object(
        'subject', 'You reached ${tier_name}',
        'title', 'New tier unlocked',
        'description', 'Congratulations — you are now ${tier_name}.',
        'button', 'View benefits',
        'banner_url', NULL
      )
    WHEN c.event_key = 'tier' AND c.sub_event = 'initial' THEN
      jsonb_build_object(
        'subject', 'Your tier is ${tier_name}',
        'title', 'Welcome to your tier',
        'description', 'You have been placed in ${tier_name}.',
        'button', 'View benefits',
        'banner_url', NULL
      )
    WHEN c.event_key = 'tier' AND c.sub_event = 'downgrade' THEN
      jsonb_build_object(
        'subject', 'Your tier is now ${tier_name}',
        'title', 'Tier updated',
        'description', 'Your tier is now ${tier_name}.',
        'button', 'View benefits',
        'banner_url', NULL
      )
    ELSE
      jsonb_build_object(
        'subject', 'You have a new update',
        'title', 'Loyalty update',
        'description', 'Something changed on your account.',
        'button', 'Open rewards',
        'banner_url', NULL
      )
  END,
  true
FROM public.notification_event_catalog c
WHERE c.is_active = true
  AND NOT EXISTS (
    SELECT 1
      FROM public.notification_template t
     WHERE t.merchant_id IS NULL
       AND t.event_key = c.event_key
       AND t.sub_event = c.sub_event
       AND t.channel = 'email'
       AND t.is_active = true
  );
