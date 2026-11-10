-- Points earned / used: one definition.
-- A reversal row (component = 'reversal') undoes an earlier row and is never new activity.
--   earned = earn rows that are not reversals, minus burn rows that are reversals
--   used   = burn rows that are not reversals, minus earn rows that are reversals
-- For every row: earned_delta - used_delta = signed_amount.
create or replace view public.v_wallet_ledger_flow with (security_invoker = true) as
select wl.*,
  case
    when wl.transaction_type = 'earn' and wl.component is distinct from 'reversal' then  wl.amount
    when wl.transaction_type = 'burn' and wl.component = 'reversal'                then -wl.amount
    else 0
  end as earned_delta,
  case
    when wl.transaction_type = 'burn' and wl.component is distinct from 'reversal' then  wl.amount
    when wl.transaction_type = 'earn' and wl.component = 'reversal'                then -wl.amount
    else 0
  end as used_delta
from public.wallet_ledger wl;
