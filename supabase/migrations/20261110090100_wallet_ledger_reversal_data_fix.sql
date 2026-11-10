-- One-time data correction: rows that break "a reversal row has component = 'reversal'".
-- Balances, point lots, amount, deductible_balance, source_id, dedup_key are NOT touched.
-- Aborts (whole migration rolls back) if any count differs or a migrated row has a deductible_balance.

create table public.wallet_ledger_reversal_fix_20261110 as
select id, transaction_type, source_type, component, signed_amount
from public.wallet_ledger
where source_type = 'redemption_cancellation'
  and (
    (currency = 'points' and mongo_id is not null)
    or (component = 'base' and mongo_id is null)
    or component = 'adjustment'
  );

alter table public.wallet_ledger_reversal_fix_20261110 enable row level security;

do $$
declare
  n int;
begin
  if exists (
    select 1 from public.wallet_ledger
    where source_type = 'redemption_cancellation' and currency = 'points'
      and mongo_id is not null and deductible_balance is not null
  ) then
    raise exception 'migrated reversal rows with deductible_balance present';
  end if;

  update public.wallet_ledger
     set transaction_type = 'burn', source_type = 'purchase', component = 'reversal',
         signed_amount = -amount
   where source_type = 'redemption_cancellation' and currency = 'points' and mongo_id is not null;
  get diagnostics n = row_count;
  if n <> 12841 then raise exception 'migrated reversals: expected 12841, got %', n; end if;

  update public.wallet_ledger
     set component = 'reversal'
   where source_type = 'redemption_cancellation' and component = 'base' and mongo_id is null;
  get diagnostics n = row_count;
  if n <> 65 then raise exception 'shopify refunds: expected 65, got %', n; end if;

  update public.wallet_ledger
     set component = 'reversal'
   where source_type = 'redemption_cancellation' and component = 'adjustment';
  get diagnostics n = row_count;
  if n <> 8 then raise exception 'adjustment cancels: expected 8, got %', n; end if;
end $$;
