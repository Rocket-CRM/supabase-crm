# Open API Compatibility Repair + Wallet — checkpoint 2026-08-05 (final)

**Task:** Execute `.cursor/plans/openapi-wallet-transactions-plan-20260804.md` — Phase 1 repair + Phase 2 wallet.

**Status — working**
- Phase 1: repaired `api-users` / `api-assets` / `api-purchases` / `api-redemptions` on `mabioklchbkanhjwgibj`.
- Phase 2: CRM `api_post_wallet_transaction` / `api_get_wallet_transactions`; edge `api-wallet` v1 (`verify_jwt: false`).
- Full smoke `--allow-writes --wallet`: **45/45** on direct URL (includes redemption create / mark-used / cancel seeded via wallet earn).
- Docs/registries/CHANGELOG updated.
- Temp smoke keys revoked (`openapi-smoke-wallet-*`, `openapi-smoke-redeem-*`).

**Still open (ops / separate)**
1. **Custom domain:** `open-api.rocket-loyalty.com` does not reliably resolve from this environment (NXDOMAIN / empty). Direct gateway works: `https://mabioklchbkanhjwgibj.supabase.co/functions/v1`.
2. Pre-existing: `bff_create_merchant_api_key` SHA-256 vs `validate_api_key` bcrypt — BFF-minted keys may not validate.

**Next exact step (only if needed)**
1. Ops: finish DNS / Cloudflare custom domain for `open-api.rocket-loyalty.com` → Supabase Open API project.
2. Optional separate task: fix BFF API-key mint to bcrypt.

**Critical context**
- Open API: `mabioklchbkanhjwgibj` · CRM: `wkevmsedchftztoolkmi`
- Working copies: `.cursor/deploy/open-api/{api-users,api-assets,api-purchases,api-redemptions,api-wallet}/index.ts`
- Smoke: `.cursor/deploy/open-api/_smoke_all.mjs`
- Docs: `docs/openapi/PLATFORM_API_REFERENCE.md`, `docs/openapi/openapi.yaml`
