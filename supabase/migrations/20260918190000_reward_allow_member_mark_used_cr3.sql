-- CR3: per-reward flag — members may self-mark redeemed rewards as used (default true).
-- Full function bodies were applied to project wkevmsedchftztoolkmi; this file records the schema change.
-- See _cr3_api_mark_redemption_used.sql in repo history / deploy runbook for api_mark_redemption_used body.

ALTER TABLE public.reward_master
  ADD COLUMN IF NOT EXISTS allow_member_mark_used boolean NOT NULL DEFAULT true;

COMMENT ON COLUMN public.reward_master.allow_member_mark_used IS
  'When false, members cannot call api_mark_redemption_used; staff paths unchanged.';
