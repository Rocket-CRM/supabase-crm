# Track B resolution F — new thread prompt

Jorakay points historical repair — Track B resolution **F** (manual review)

**Open:**
- `~/Documents/rocket/supabase-crm/bug-reports/20260902-points-historical-repair/Plan.md`
- `hold-resolution-table.csv` (filter `resolution = F`, 68 users)
- `hold-export.csv`

**Merchant:** Jorakay Family
- `merchant_id`: `7522af2c-a7f6-4ab8-8493-6875a3b19544`
- mongo: `649e9524f43a5fc2f9705850`
- Supabase: `wkevmsedchftztoolkmi`
- `sync_active`: false

**Context:** Track A (clean cohort) and Track B resolutions **A / B / C / E** are applied separately. This thread is **only** the 68 **F** users (~148,153 pts step3 at risk if applied blindly).

**Why F:** Post-migration ledger is too messy for automatic repair — typically one or more of:
- reward redemption after `last_ts`
- manual earn (e.g. maintenance credit)
- nightly expiry burn overlapping with still-open lots
- lots > wallet after NewCRM activity
- often combined with `mongo_sync_gap`

**Known case — Pitcha 🌻 `+66819048848`** (`169434fe-4c0c-46b4-9c9b-15dac2e90009`):
- hold: `{later_newcrm,mongo_sync_gap}`
- `last_ts`: 2026-06-16; `revised_last_ts`: 2026-08-18
- wallet 45,883 vs lots 52,510
- Jul-09: 4 Mongo GIVEN not in ledger
- Jul–Aug: purchase earns, manual earn 1565 after expiry burn, 3000 redemption, expiry burns
- blind step3 would be 357 pts — do **not** apply blind

**Your job:**
1. Load the 68 F rows from `hold-resolution-table.csv`.
2. For each user (or group by pattern), run Plan.md § Step 4 investigation checklist:
   - All points ledger rows with `created_at > last_ts`
   - `stg_mongo_points` GIVEN/REDEEMED after `last_ts` vs `wallet_ledger`
   - NewCRM earns/redeems/expiry burns; did nightly expiry already burn overlapping `expiry_date`s?
   - `user_wallet.points_balance` vs `stg_mongo_contacts` `pointBalance`
3. Pick a final resolution per user: **A | B | C | D** (manual step 3 with specific dates/amounts) | **E** | keep **F**
4. Output: `user_id`, `tel`, `hold_reasons`, `final_resolution`, `revised_last_ts`, approved `step1/2/3` pts, `investigation_notes`

**No writes** unless I explicitly approve after reviewing your table.
