-- Invite-a-friend email is catalog/config only (action.referral_share).
-- Not on crm.events.referral. The notification-referral-router must ignore it.
-- Send path is the future share-via-email form.

INSERT INTO public.notification_event_catalog (
  event_key, sub_event, source_topic, description,
  available_fields, default_selected_fields, default_enabled, default_enabled_email, is_active
) VALUES (
  'referral', 'shared', 'action.referral_share',
  'Invite email when a member shares via email. Copy-link does not send this.',
  '["referrer_name","personal_message","share_url","offer"]'::jsonb,
  '["referrer_name","share_url","offer"]'::jsonb,
  false, true, true
)
ON CONFLICT (event_key, sub_event) DO UPDATE SET
  source_topic = EXCLUDED.source_topic,
  description = EXCLUDED.description,
  available_fields = EXCLUDED.available_fields,
  default_selected_fields = EXCLUDED.default_selected_fields,
  default_enabled = EXCLUDED.default_enabled,
  default_enabled_email = EXCLUDED.default_enabled_email,
  is_active = true,
  updated_at = now();

INSERT INTO public.notification_template (
  merchant_id, event_key, sub_event, channel, is_active, flex_template, email_template
)
SELECT
  NULL, 'referral', 'shared', 'email', true, NULL,
  jsonb_build_object(
    'subject', '${referrer_name} sent you an offer',
    'title', 'You have been invited',
    'description', '${referrer_name} shared an offer with you. ${personal_message}',
    'button', 'Accept offer',
    'banner_url', NULL
  )
WHERE NOT EXISTS (
  SELECT 1
  FROM public.notification_template
  WHERE merchant_id IS NULL
    AND event_key = 'referral'
    AND sub_event = 'shared'
    AND channel = 'email'
    AND is_active = true
);
