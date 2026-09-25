# Open API Edge ↔ CRM Argument Diff Matrix
Date: 2026-08-05
Open API project: mabioklchbkanhjwgibj
CRM project: wkevmsedchftztoolkmi

## Deployed inventory
| Edge | Version | verify_jwt | GATEWAY_CONFIG_ERROR |
|---|---:|---|---|
| api-users | 5 | false | missing |
| api-assets | 2 | false | missing |
| api-purchases | 3 | false | present |
| api-redemptions | 5 | false | missing |

## DNS
open-api.rocket-loyalty.com → NXDOMAIN (Google 8.8.8.8). Direct URL OPTIONS 200.

## Diffs (edge body field → CRM param)

### api-users POST → api_create_or_update_user
Edge forwards: tel, timezone, external_user_id, firstname, lastname, email, line_id, id_card, birth_date, user_type, user_stage, channel_*, upsert, addresses, address_mode, form_submissions
MISSING vs newer CRM overload: acquisition_source → p_acquisition_source
GET/PATCH identifiers: match api_get_user / api_update_user

### api-assets → api_*_asset
POST/GET/PATCH fields: MATCH (no RPC drift)
Change: GATEWAY_CONFIG_ERROR only

### api-purchases POST → api_create_purchase
Edge forwards existing core fields.
MISSING approved allowlist:
- transaction_date → p_transaction_date (P0)
- images → p_images
- external_user_ref → p_external_user_ref
- transaction_source → p_transaction_source
- transaction_type → p_transaction_type
- store_id → p_store_id
- earning_channel_id → p_earning_channel_id
- transaction_source_id → p_transaction_source_id
- payment_method → p_payment_method
- metadata → p_metadata
CORRECTLY NOT exposed: batch_id, skip_duplicate_transaction_number

### api-purchases PATCH → api_update_purchase
Edge selects older overload (no payment/source metadata).
MISSING vs newer overload:
- payment_method → p_payment_method
- metadata → p_metadata
- transaction_source → p_transaction_source
- transaction_source_id → p_transaction_source_id

### api-redemptions
Routes preserved. redeem_reward_with_points optional store_id/selected_variants NOT forwarded (deferred per plan).
api_cancel_redemption internal force_used/cancelled_by NOT exposed (correct).
Change: GATEWAY_CONFIG_ERROR + docs.
