-- Speed up member RPCs that resolve user_accounts by auth.uid() / auth_user_id.
-- Production (3.7M+ rows): applied with CREATE INDEX CONCURRENTLY before this migration lands.

CREATE INDEX IF NOT EXISTS idx_user_accounts_auth_user_id
  ON public.user_accounts (auth_user_id);
