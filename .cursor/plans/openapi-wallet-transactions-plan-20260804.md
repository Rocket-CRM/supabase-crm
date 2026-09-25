# Open API Compatibility Repair + Wallet Transactions Execution Plan

**Status:** Ready for execution in the next thread  
**Original date:** 2026-08-04  
**Reviewed:** 2026-08-05  
**Approved sequence:** Repair and regression-test all four existing Open APIs first; add wallet transactions only after the compatibility gate passes.  
**Scope:** Platform Open API for all merchants using an API key. Do not create merchant-specific forks.

---

## 1. Outcome

This work has two ordered phases:

1. **Restore confidence in the current Open API.** Compare each deployed edge with its current CRM RPC, repair confirmed drift, document the actual routes, and run authenticated end-to-end regression tests.
2. **Add wallet transactions.** Expose points earn/burn and points history through the same API-key gateway only after Phase 1 passes.

The wallet API is a ledger API, not an absolute balance setter:

- `POST /api-wallet/transactions` posts an earn or burn delta.
- `GET /api-wallet/transactions` returns points ledger history.
- Current balance remains available through `GET /api-users/...` as `points_balance`.
- Do not add `PUT /points/balance` or `GET /api-wallet` in v1.

---

## 2. Architecture and hard boundaries

| Project | Ref | Responsibility |
|---|---|---|
| Open API | `mabioklchbkanhjwgibj` | Public edge gateway, API-key validation, HTTP validation/routing/envelope |
| CRM | `wkevmsedchftztoolkmi` | Source of truth, API RPCs, users, purchases, redemptions, assets, wallet ledger |

Request flow:

```text
Partner
  → Open API edge with x-api-key
  → CRM validate_api_key(p_api_key)
  → merchant_id
  → merchant-scoped CRM api_* RPC
  → { success, data, meta: { request_id, response_time_ms } }
```

Hard rules:

- Keep all loyalty data and business writes in the CRM project.
- Deploy edge functions to the Open API project only.
- Use `p_merchant_id` in external `api_*` RPCs after the edge validates the key.
- Do not call admin BFFs from the Open API; they require JWT/admin context.
- Preserve existing public routes and successful response shapes.
- Use Supabase MCP for live SQL migrations, edge retrieval, deployment, and logs.
- Do not store API keys or service-role keys in files, test output, or the plan.

---

## 3. Verified baseline

### 3.1 Deployed edges

All four edges are active on `mabioklchbkanhjwgibj` with `verify_jwt: false`:

| Edge | Deployed version | Current CRM calls |
|---|---:|---|
| `api-users` | 5 | `validate_api_key`, `api_create_or_update_user`, `api_get_user`, `api_update_user` |
| `api-purchases` | 3 | `validate_api_key`, `api_create_purchase`, `api_get_purchase`, `api_update_purchase` |
| `api-redemptions` | 5 | `validate_api_key`, `redeem_reward_with_points`, `api_get_redemption`, `api_cancel_redemption`, `api_mark_redemption_used` |
| `api-assets` | 2 | `validate_api_key`, `api_create_or_update_asset`, `api_get_asset`, `api_update_asset` |

The Open API project contains no local loyalty/API RPCs. The edges call the CRM project through `CRM_PROJECT_URL` and `CRM_SERVICE_ROLE_KEY`.

### 3.2 Route inventory

#### Users

| Method | Route | CRM RPC |
|---|---|---|
| POST | `/api-users` | `api_create_or_update_user` |
| GET/PATCH | `/api-users/{user_id}` | `api_get_user` / `api_update_user` |
| GET/PATCH | `/api-users/by-external-id/{value}` | same |
| GET/PATCH | `/api-users/by-email/{value}` | same |
| GET/PATCH | `/api-users/by-tel/{value}` | same |
| GET/PATCH | `/api-users/by-line-id/{value}` | same |

#### Purchases

| Method | Route | CRM RPC |
|---|---|---|
| POST | `/api-purchases` | `api_create_purchase` |
| GET | `/api-purchases/{transaction_number}` | `api_get_purchase` |
| GET | `/api-purchases?transaction_number=...` | `api_get_purchase` |
| GET | `/api-purchases?transaction_id=...` | `api_get_purchase` |
| PATCH | `/api-purchases/{transaction_number}` | `api_update_purchase` |

There is no deployed public purchase-cancel route. `api_cancel_purchase` existing in CRM does not make it part of the Open API.

#### Redemptions

| Method | Route | CRM RPC |
|---|---|---|
| POST | `/api-redemptions` | `redeem_reward_with_points` |
| GET | `/api-redemptions/{redemption_code}` | `api_get_redemption` |
| GET | `/api-redemptions?redemption_id=...` | `api_get_redemption` |
| POST | `/api-redemptions/{redemption_code}/cancel` | `api_cancel_redemption` |
| POST | `/api-redemptions/{redemption_code}/mark-used` | `api_mark_redemption_used` |

#### Assets

| Method | Route | CRM RPC |
|---|---|---|
| POST | `/api-assets` | `api_create_or_update_asset` |
| GET/PATCH | `/api-assets/{asset_id}` | `api_get_asset` / `api_update_asset` |
| GET/PATCH | `/api-assets/by-external-id/{value}` | same |
| GET/PATCH | `/api-assets/by-asset-code/{value}` | same |
| GET/PATCH | `/api-assets/by-serial-number/{value}` | same |

### 3.3 What has and has not been proven

Proven during review:

- Direct Supabase URLs for all four edges return `OPTIONS 200`.
- Direct Supabase URLs reject an invalid `x-api-key` with `401 INVALID_API_KEY`.
- Every named CRM RPC exists and grants execute to `service_role`.
- Newer optional CRM parameters allow the currently deployed named-argument calls to resolve.

Not yet proven:

- Authenticated read/write behavior with a real sandbox key.
- Cross-merchant isolation through the complete edge-to-CRM path.
- The public custom domain. `open-api.rocket-loyalty.com` failed DNS resolution from the review environment while the direct Supabase URLs worked.
- Current documentation parity; the existing Euro Creations document omits purchase GET/PATCH and all redemption routes.

---

## 4. Confirmed compatibility drift

| Priority | Surface | Finding | Required action |
|---|---|---|---|
| P0 | Public hostname | Custom domain did not resolve from the review environment; direct Supabase endpoints worked | Check DNS/custom-domain configuration from an independent resolver. Public-domain failure blocks Phase 1 acceptance. |
| P0 | Purchases POST | The partner document accepts `transaction_date`, and the live CRM RPC accepts `p_transaction_date`, but edge v3 does not forward it | Forward `body.transaction_date`; regression-test persisted transaction time. |
| P1 | Purchases POST | CRM added safe public fields that edge v3 does not forward | Forward the approved allowlist below; do not expose internal bypass controls. |
| P1 | Purchases PATCH | A newer overload accepts payment/source metadata, but edge v3 selects the older overload | Forward the approved PATCH allowlist and select the newer overload by named arguments. |
| P1 | Users POST | CRM added `p_acquisition_source`; edge v5 still selects the old overload | Forward `body.acquisition_source` and test create/upsert. Keep the old overload for backward compatibility. |
| P1 | Redemptions | Edge routes are live but absent from partner documentation | Add all verified routes, request fields, state transitions, and error examples to platform documentation. |
| P1 | All edges | No repository regression suite or machine-readable route contract exists | Add a reusable smoke runner, OpenAPI document, and platform-neutral API reference. |
| P2 | All edges | Misconfigured `CRM_SERVICE_ROLE_KEY` is handled explicitly only by `api-purchases` | Add the same `GATEWAY_CONFIG_ERROR` guard to users, redemptions, assets, and wallet without changing normal responses. |

Approved purchase field allowlist:

- POST: existing fields plus `transaction_date`, `images`, `external_user_ref`, `transaction_source`, `transaction_type`, `store_id`, `earning_channel_id`, `transaction_source_id`, `payment_method`, `metadata`.
- PATCH: existing fields plus `payment_method`, `metadata`, `transaction_source`, `transaction_source_id`.
- Do not expose `batch_id` or `skip_duplicate_transaction_number`; those are internal controls.

Redemption policy for this repair:

- Preserve current routes and state behavior.
- Do not create new redemption routes.
- Do not expose `force_used`, `cancelled_by`, or internal event/source controls.
- Only add optional `store_id` and `selected_variants` if direct CRM and edge regression tests demonstrate the current RPC contract and merchant validation.

---

## 5. Execution prerequisites and safety

Before changing anything, the next thread must have:

- Two dedicated test merchants, A and B.
- One revocable Open API key for each test merchant, supplied only through environment variables.
- A known user, asset type, store, SKU, reward, and sufficient points in merchant A.
- At least one resource owned by merchant B for negative tenant tests.
- Permission to inspect both Supabase projects and edge logs.

Test environment variables:

```text
OPEN_API_BASE_URL
OPEN_API_KEY_A
OPEN_API_KEY_B
TEST_MERCHANT_A
TEST_MERCHANT_B
TEST_REWARD_ID_A
TEST_STORE_ID_A
```

Safety rules:

- Never test writes against a real partner merchant.
- Prefix all external IDs and transaction numbers with a unique run ID such as `openapi-smoke-<timestamp>`.
- Run reads and rejected requests first; run state-changing tests last.
- Do not delete ledger/audit rows. Use the dedicated test merchant and compensating wallet transactions.
- Create purchases with `earn_currency: false` unless the test explicitly verifies earning.
- Capture `request_id` and edge logs for every failed assertion.
- Before each edge deployment, retrieve its current source/version. If the post-deploy smoke fails, redeploy the captured prior source immediately.

---

## 6. Phase 1 — Existing API compatibility repair

### Step 1. Snapshot and contract diff

1. Retrieve all four deployed edge sources from `mabioklchbkanhjwgibj`.
2. Re-query live CRM signatures with defaults for every RPC in section 3.
3. Build an edge argument → CRM argument matrix.
4. Record the deployed version, `verify_jwt`, allowed methods, routes, and response/error shapes.
5. Resolve the custom-domain DNS failure before treating the public API as healthy.

Stop if the public hostname does not resolve from an independent network. Repair DNS/custom-domain routing before business-flow testing.

### Step 2. Repair existing edges

Deploy one edge at a time in this order:

1. `api-users`
   - Forward `acquisition_source`.
   - Keep all current lookup paths and response shapes.
   - Add explicit missing-service-key handling.
2. `api-assets`
   - No confirmed RPC mismatch; change only common configuration/error handling if needed.
   - Preserve all four lookup types.
3. `api-purchases`
   - Forward `transaction_date` first.
   - Add only the approved POST/PATCH fields from section 4.
   - Keep `batch_id` and duplicate-bypass controls inaccessible.
   - Preserve GET and PATCH route behavior.
4. `api-redemptions`
   - Preserve create/get/cancel/mark-used routes.
   - Add documentation and common configuration handling.
   - Add optional public fields only after the direct RPC test described in section 4.

After each deployment:

- Run that edge's unauthenticated, authenticated-read, mutation, and tenant-isolation tests.
- Inspect Open API edge logs and CRM side effects.
- Roll back that edge immediately if its matrix fails.
- Do not proceed to the next edge with a red test.

### Step 3. Add the contract and regression runner

Create `docs/openapi/openapi.yaml` as the executable contract for the verified existing routes. It must define:

- API-key security through `x-api-key`.
- Every method/path in section 3.
- Required and optional request fields after the allowlist repair.
- Existing success envelopes and error status/code combinations.
- Reusable schemas for request metadata, pagination, validation errors, and request IDs.
- No wallet paths until Phase 2 is deployed and green.

Create `.cursor/deploy/open-api/_smoke_all.mjs` with:

- Environment-only secrets.
- Route and response expectations aligned with `docs/openapi/openapi.yaml`.
- `--read-only` mode as the default.
- Explicit `--allow-writes` required for fixture mutations.
- A unique run ID.
- Assertions for status, error code, success envelope, `request_id`, and expected identifiers.
- Redacted output; never print keys or service credentials.
- A non-zero exit code on the first failed assertion and a concise final matrix.

Minimum test matrix:

| API | Auth/read tests | Controlled write tests | Tenant test |
|---|---|---|---|
| Users | missing key, bad key, not found, GET by all identifiers, `points_balance` | create, duplicate without upsert, upsert, PATCH | Key B cannot read/update user A |
| Assets | missing key, bad key, not found, GET by all identifiers | create, duplicate without upsert, upsert/PATCH | Key B cannot read/update asset A |
| Purchases | missing key, bad key, GET by number/id, not found | create with persisted `transaction_date`; PATCH; documented unknown-SKU behavior; one explicit earn test | Key B cannot read/update purchase A |
| Redemptions | missing key, bad key, GET by code/id, not found | create two fixtures; mark one used; cancel the other | Key B cannot get/mutate redemption A |

For every API:

- Unsupported method returns `405`.
- Malformed JSON returns a controlled `400`, not `500`.
- Missing required identifier returns a controlled `400`.
- Success keeps the existing `{ success, data, meta }` envelope.
- Missing/invalid key returns `401`.
- No response leaks another merchant's identifiers or data.

### Phase 1 compatibility gate

Wallet implementation is blocked until all checks pass:

- [ ] Public custom domain resolves and reaches the same active edges as the direct Supabase URL.
- [ ] All four edge inventories match the documented route matrix.
- [ ] All four edges pass unauthenticated and authenticated tests.
- [ ] All existing write routes pass with dedicated test fixtures.
- [ ] Cross-merchant reads and writes are rejected for every resource.
- [ ] `transaction_date` is persisted by `POST /api-purchases`.
- [ ] Existing success contracts remain backward compatible.
- [ ] `docs/openapi/openapi.yaml` matches the deployed four-API surface.
- [ ] The smoke runner passes in read-only and write-enabled modes.
- [ ] Edge logs show no unexpected 5xx or CRM RPC resolution errors.

---

## 7. Phase 2 — Wallet API

### 7.1 Locked v1 decisions

| Topic | Decision |
|---|---|
| API shape | Ledger deltas; no absolute balance PUT/SET |
| Currency | Points only |
| Balance read | Existing `GET /api-users/...` → `points_balance` |
| Edge slug/routes | `api-wallet`; `POST/GET /api-wallet/transactions` |
| Component | `adjustment` |
| Source type | Existing `manual`; add internal metadata `channel: openapi` instead of changing the enum |
| Burn behavior | Hard fail; no partial burn |
| Side effects | Use the normal chokepoint and emit `crm.events.wallet`; clients cannot set `_skip_emit` |
| Pagination | `limit` default 50, range 1–100; `offset` default 0 |
| Date range | `created_at >= from` and `created_at < to`; require `from < to` |
| Ticket currency | Out of scope |

Live truth to preserve:

- Point balance is `user_wallet.points_balance`, not `user_accounts.points_balance`.
- `wallet_ledger.dedup_key` has a global unique index.
- `chokepoint_post_wallet_transaction` inserts once and raises `23505` on duplicate; it does not return an idempotent replay response.
- The chokepoint hard-fails when a burn would make points negative.

### 7.2 CRM RPC: `api_post_wallet_transaction`

Create a `SECURITY DEFINER` RPC with a fixed `search_path` and service-role-only execution.

Inputs:

- `p_merchant_id`
- exactly one of `p_user_id`, `p_external_user_id`, `p_tel`, `p_email`, `p_line_id`
- `p_transaction_type`: `earn` or `burn`
- `p_amount`: positive integer
- `p_dedup_key`: required client key, 1–200 characters
- optional `p_description`, `p_metadata`

Behavior:

1. Validate amount, type, key length, metadata type, and exactly one user identifier.
2. Reject reserved metadata keys beginning with `_`.
3. Resolve the user through `api_find_user(p_merchant_id, ...)`; return `USER_NOT_FOUND` if absent.
4. Build the internal globally unique key:

   ```text
   openapi:<merchant_id>:<client_dedup_key>
   ```

5. Check for an existing row using both `merchant_id` and the internal key.
6. If an existing row matches user, type, currency, and amount, return `200` semantics with:
   - the original `wallet_ledger_id`
   - original `balance_after`
   - `already_processed: true`
   - the client key, never the internal prefixed key
7. If the same key has a different payload, return `IDEMPOTENCY_CONFLICT`.
8. Call `chokepoint_post_wallet_transaction` with every required argument:
   - `p_user_id`: resolved user
   - `p_currency`: `points`
   - `p_source_type`: `manual`
   - `p_component`: `adjustment`
   - `p_transaction_type`: request type
   - `p_amount`: request amount
   - `p_transaction_id`: `gen_random_uuid()`
   - `p_merchant_id`: API-key merchant
   - `p_description`: request description
   - `p_metadata`: internal metadata merged with partner metadata
   - `p_target_entity_id`: `NULL`
   - `p_dedup_key`: internal prefixed key
9. Catch `unique_violation` for concurrent retries. Re-read by merchant + internal key, compare the payload, and return replay or conflict as above.
10. Return the inserted ledger row and current balance.

Internal metadata shape:

```json
{
  "channel": "openapi",
  "client_dedup_key": "partner:order_456:earn",
  "partner": {}
}
```

Do not change `chokepoint_post_wallet_transaction` or the global dedup index in this phase.

### 7.3 CRM RPC: `api_get_wallet_transactions`

Create a separate service-role-only `SECURITY DEFINER` RPC. Do not call `bff_admin_get_member_wallet_history`; it requires admin JWT and permission context.

Inputs:

- `p_merchant_id`
- exactly one supported user identifier
- optional `p_from`, `p_to`, `p_transaction_type`
- `p_limit` and `p_offset`

Behavior:

- Resolve the user with `api_find_user` under the API-key merchant.
- Query `wallet_ledger` by `merchant_id`, `user_id`, and `currency = 'points'`.
- Apply optional date/type filters.
- Sort by `created_at DESC, id DESC`.
- Return `total_count`, `limit`, `offset`, and rows.
- Never return the internal merchant-prefixed dedup key. Return `metadata.client_dedup_key` as `dedup_key`.

Pinned row fields:

```text
id, created_at, currency, transaction_type, component,
amount, signed_amount, source_type, description,
balance_before, balance_after, expiry_date, dedup_key
```

### 7.4 Open API edge: `api-wallet`

Deploy to `mabioklchbkanhjwgibj` with `verify_jwt: false`.

Routes:

| Method | Route | CRM RPC |
|---|---|---|
| POST | `/api-wallet/transactions` | `api_post_wallet_transaction` |
| GET | `/api-wallet/transactions` | `api_get_wallet_transactions` |

HTTP behavior:

- `201` for a new wallet transaction.
- `200` for an idempotent replay and for history reads.
- `400` for validation and insufficient balance.
- `401` for missing/invalid API key.
- `404` for unknown user.
- `409` for idempotency-key payload conflict.
- `405` for unsupported methods.

Use the same CORS headers, request ID, response timing, API-key validation, CRM service-role client, field-length guard, and success envelope as the repaired existing edges.

### 7.5 Wallet tests

Add to `_smoke_all.mjs`:

1. Missing and invalid API keys return 401.
2. Earn points by `external_user_id`.
3. Confirm one `wallet_ledger` row and the expected `user_wallet.points_balance`.
4. Replay the same key and payload; receive the same ledger ID and no balance change.
5. Replay the same key with a different amount; receive 409 and no balance change.
6. Burn a valid amount.
7. Burn above balance; receive a controlled error and no write.
8. Read history with pagination, date range, and transaction-type filters.
9. Key B cannot post or read wallet activity for user A.
10. Use a compensating burn/earn to restore the sandbox balance; do not delete ledger rows.

### Phase 2 acceptance gate

- [ ] New RPCs are merchant-scoped and executable only by the gateway service role.
- [ ] New earn/burn writes update `wallet_ledger` and `user_wallet.points_balance` atomically.
- [ ] Same key/same payload is idempotent under sequential and concurrent replay.
- [ ] Same key/different payload returns 409.
- [ ] Cross-merchant dedup keys and users never leak data.
- [ ] Insufficient burn does not partially write.
- [ ] History filters, ordering, `total_count`, limit, and offset are correct.
- [ ] Normal wallet events still reach the existing event outbox/router path.
- [ ] Existing four-API regression matrix remains green after wallet deployment.

---

## 8. Documentation and registry updates

Complete in the same execution thread:

1. Extend `docs/openapi/openapi.yaml` with wallet only after Phase 2 passes.
2. Create a platform-neutral human-readable API reference covering users, assets, purchases, redemptions, and wallet.
3. Keep `docs/Rocket x Euro Creations - API Documentation v2.0.md` as a partner-specific guide, but correct its purchase `transaction_date` behavior and link to the platform reference.
4. Document request/response examples, route variants, API-key auth, errors, idempotency, and points balance location.
5. Add the Open API project and all five edge functions to `requirements/REGISTRY_RENDER.md`.
6. Regenerate `requirements/REGISTRY_SUPABASE.md` after creating the two CRM RPCs.
7. Update `requirements/Currency.md` with the external wallet contract and side effects.
8. Append a one-line entry to `requirements/CHANGELOG.md`.

Static IP wording:

- API-key auth protects inbound partner calls.
- Static egress applies only when Rocket calls a partner system that requires IP allowlisting.
- Do not claim Rocket has a static egress IP unless infrastructure provides one.

---

## 9. Rollout and rollback

Rollout:

1. Repair and test one existing edge at a time.
2. Pass the full Phase 1 gate.
3. Apply CRM wallet RPC migration and run direct RPC tests.
4. Deploy `api-wallet`.
5. Run wallet tests, then rerun all existing API tests.
6. Update docs and registries only after deployed behavior is green.

Rollback:

- Existing edge failure: redeploy its captured pre-change source/version.
- Wallet edge failure: redeploy or disable `api-wallet`; existing APIs remain independent.
- Wallet RPC failure: stop edge traffic first, then replace the RPCs with corrected versions through a new migration. Do not remove ledger rows or rewrite balances manually.
- Do not roll back by dropping enum values or deleting audit data; this plan adds no enum value.

---

## 10. Out of scope

- Absolute point balance PUT/SET.
- Ticket currency transactions.
- New purchase cancellation routes or other expansion of existing API surface.
- Merchant-specific/Gingen-only endpoints.
- Legacy `crm-api.rocket-tech.app` routes.
- Internal member-JWT `wallet-api` and `wallet-transactions` edges.
- Static egress infrastructure.
- Deleting test ledger/audit records.

---

## 11. First exact step for the next thread

Retrieve the current deployed source for `api-users`, `api-assets`, `api-purchases`, and `api-redemptions` from Open API project `mabioklchbkanhjwgibj`; query the live CRM signatures with defaults for every RPC listed in section 3; then produce the argument-diff matrix before deploying any change.
