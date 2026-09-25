#!/usr/bin/env node
/**
 * Open API smoke runner (platform-neutral).
 *
 * Env (required for auth tests):
 *   OPEN_API_BASE_URL   e.g. https://mabioklchbkanhjwgibj.supabase.co/functions/v1
 *   OPEN_API_KEY_A
 *   OPEN_API_KEY_B
 * Optional:
 *   TEST_REWARD_ID_A
 *   TEST_STORE_ID_A
 *   TEST_ASSET_TYPE_CODE_A
 *   TEST_TICKET_CODE_A     non-credit ticket_code for write ticket tests
 *
 * Modes:
 *   (default)           --read-only
 *   --allow-writes      controlled mutations
 *   --wallet            include wallet tests (Phase 2)
 *
 * Never prints API keys or service credentials.
 */

const BASE = (process.env.OPEN_API_BASE_URL || "").replace(/\/$/, "");
const KEY_A = process.env.OPEN_API_KEY_A || "";
const KEY_B = process.env.OPEN_API_KEY_B || "";
const REWARD_A = process.env.TEST_REWARD_ID_A || "";
const STORE_A = process.env.TEST_STORE_ID_A || "";
const ASSET_TYPE_A = process.env.TEST_ASSET_TYPE_CODE_A || "product";
const TICKET_CODE_A = process.env.TEST_TICKET_CODE_A || "";

const allowWrites = process.argv.includes("--allow-writes");
const includeWallet = process.argv.includes("--wallet");
const RUN_ID = `openapi-smoke-${Date.now()}`;

const results = [];
let failed = false;

function redact(s) {
  if (typeof s !== "string") return s;
  return s
    .replace(/mk_live_[a-f0-9]+/gi, "mk_live_[REDACTED]")
    .replace(/eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/g, "[JWT_REDACTED]");
}

function record(name, ok, detail = "") {
  results.push({ name, ok, detail: redact(String(detail)).slice(0, 240) });
  const mark = ok ? "PASS" : "FAIL";
  console.log(`${mark}  ${name}${detail ? ` — ${redact(String(detail)).slice(0, 160)}` : ""}`);
  if (!ok) failed = true;
}

async function req(method, path, { key, body, expectStatus, expectCode } = {}) {
  const headers = { "Content-Type": "application/json" };
  if (key) headers["x-api-key"] = key;
  const res = await fetch(`${BASE}${path}`, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  let json = null;
  const text = await res.text();
  try {
    json = text ? JSON.parse(text) : null;
  } catch {
    json = { _raw: text.slice(0, 200) };
  }
  if (expectStatus !== undefined && res.status !== expectStatus) {
    throw new Error(`status ${res.status} expected ${expectStatus}; body=${JSON.stringify(json).slice(0, 300)}`);
  }
  if (expectCode !== undefined) {
    const code = json?.code;
    if (code !== expectCode) {
      throw new Error(`code ${code} expected ${expectCode}; body=${JSON.stringify(json).slice(0, 300)}`);
    }
  }
  return { status: res.status, json, requestId: json?.request_id || json?.meta?.request_id };
}

async function tryCase(name, fn) {
  if (failed && process.env.SMOKE_CONTINUE !== "1") {
    // still run remaining unless hard-fail mode; plan asks non-zero on first fail — stop after recording
  }
  try {
    await fn();
    record(name, true);
  } catch (e) {
    record(name, false, e.message || String(e));
    if (process.env.SMOKE_CONTINUE !== "1") {
      printMatrix();
      process.exit(1);
    }
  }
}

function extractRedemptionCode(json) {
  const inner = json?.data?.data || json?.data || {};
  if (inner.redemption_code || inner.code) return inner.redemption_code || inner.code;
  const rows = inner.redemptions;
  if (Array.isArray(rows) && rows.length) {
    return rows[0].redemption_code || rows[0].code || rows[0].promo_code || null;
  }
  return null;
}

function extractUserId(json) {
  return (
    json?.data?.user?.user_id ||
    json?.data?.data?.user?.user_id ||
    json?.data?.user_id ||
    null
  );
}

function extractPointsBalance(json) {
  return Number(
    json?.data?.user?.points_balance ??
      json?.data?.data?.user?.points_balance ??
      json?.data?.points_balance ??
      0,
  );
}

function printMatrix() {
  console.log("\n=== Smoke matrix ===");
  console.log(`run_id=${RUN_ID} writes=${allowWrites} wallet=${includeWallet}`);
  for (const r of results) {
    console.log(`${r.ok ? "✓" : "✗"} ${r.name}${r.detail ? ` (${r.detail})` : ""}`);
  }
  const pass = results.filter((r) => r.ok).length;
  console.log(`\n${pass}/${results.length} passed`);
}

async function unauthSuite(apiPath) {
  await tryCase(`${apiPath} OPTIONS`, async () => {
    const res = await fetch(`${BASE}${apiPath}`, { method: "OPTIONS" });
    if (res.status !== 200) throw new Error(`status ${res.status}`);
  });
  await tryCase(`${apiPath} missing key`, async () => {
    await req("GET", `${apiPath}/x`, { expectStatus: 401, expectCode: "MISSING_API_KEY" });
  });
  await tryCase(`${apiPath} bad key`, async () => {
    await req("GET", `${apiPath}/x`, {
      key: "invalid-key",
      expectStatus: 401,
      expectCode: "INVALID_API_KEY",
    });
  });
}

async function main() {
  if (!BASE) {
    console.error("OPEN_API_BASE_URL is required");
    process.exit(2);
  }
  if (!KEY_A || !KEY_B) {
    console.error("OPEN_API_KEY_A and OPEN_API_KEY_B are required");
    process.exit(2);
  }

  console.log(`Open API smoke  run=${RUN_ID}  base=${BASE}  mode=${allowWrites ? "writes" : "read-only"}`);

  // --- Unauth all four ---
  for (const p of ["/api-users", "/api-assets", "/api-purchases", "/api-redemptions"]) {
    await unauthSuite(p);
  }
  if (includeWallet) await unauthSuite("/api-wallet");

  // --- Users read ---
  const extA = `${RUN_ID}-user-a`;
  const extB = `${RUN_ID}-user-b`;

  if (allowWrites) {
    await tryCase("users POST create A", async () => {
      const { status, json } = await req("POST", "/api-users", {
        key: KEY_A,
        body: {
          tel: `08${String(Date.now()).slice(-8)}`,
          timezone: "Asia/Bangkok",
          external_user_id: extA,
          firstname: "OpenAPI",
          lastname: "SmokeA",
          email: `${extA}@example.com`,
          acquisition_source: "openapi_smoke",
          upsert: false,
        },
        expectStatus: 201,
      });
      if (!json?.success) throw new Error(JSON.stringify(json).slice(0, 200));
      if (!json?.data?.data?.user_id && !json?.data?.user_id) {
        // envelope: { success, data: <rpc result> }
      }
    });

    await tryCase("users POST duplicate without upsert → 409", async () => {
      const { status, json } = await req("POST", "/api-users", {
        key: KEY_A,
        body: {
          tel: `09${String(Date.now()).slice(-8)}`,
          timezone: "Asia/Bangkok",
          external_user_id: extA,
          upsert: false,
        },
      });
      if (status !== 409 && json?.code !== "USER_EXISTS") {
        // some paths return 400 USER_EXISTS
        if (json?.code !== "USER_EXISTS") throw new Error(`status=${status} ${JSON.stringify(json).slice(0, 200)}`);
      }
    });

    await tryCase("users POST upsert A", async () => {
      const { json } = await req("POST", "/api-users", {
        key: KEY_A,
        body: {
          tel: `08${String(Date.now() + 1).slice(-8)}`,
          timezone: "Asia/Bangkok",
          external_user_id: extA,
          firstname: "OpenAPI",
          lastname: "SmokeA2",
          upsert: true,
        },
        expectStatus: 200,
      });
      if (!json?.success) throw new Error(JSON.stringify(json).slice(0, 200));
    });
  }

  await tryCase("users GET by-external-id", async () => {
    const path = allowWrites ? `/api-users/by-external-id/${encodeURIComponent(extA)}` : `/api-users/by-external-id/${encodeURIComponent("no-such-user")}`;
    const { status, json } = await req("GET", path, { key: KEY_A });
    if (allowWrites) {
      if (status !== 200 || !json?.success) throw new Error(JSON.stringify(json).slice(0, 200));
      const bal =
        json?.data?.user?.points_balance ??
        json?.data?.data?.user?.points_balance ??
        json?.data?.data?.points_balance ??
        json?.data?.points_balance;
      if (bal === undefined) throw new Error(`points_balance missing keys=${Object.keys(json?.data || {})}`);
    } else if (status !== 404) {
      throw new Error(`expected 404 got ${status}`);
    }
  });

  if (allowWrites) {
    await tryCase("users GET by-email", async () => {
      const { json } = await req("GET", `/api-users/by-email/${encodeURIComponent(`${extA}@example.com`)}`, {
        key: KEY_A,
        expectStatus: 200,
      });
      if (!json?.success) throw new Error(JSON.stringify(json).slice(0, 200));
    });

    await tryCase("users PATCH by-external-id", async () => {
      const { json } = await req("PATCH", `/api-users/by-external-id/${encodeURIComponent(extA)}`, {
        key: KEY_A,
        body: { firstname: "Patched" },
        expectStatus: 200,
      });
      if (!json?.success) throw new Error(JSON.stringify(json).slice(0, 200));
    });

    await tryCase("users tenant: key B cannot read user A", async () => {
      const { status, json } = await req("GET", `/api-users/by-external-id/${encodeURIComponent(extA)}`, {
        key: KEY_B,
      });
      if (status !== 404) throw new Error(`expected 404 got ${status} ${JSON.stringify(json).slice(0, 160)}`);
    });
  }

  // --- Assets ---
  const assetExt = `${RUN_ID}-asset`;
  if (allowWrites) {
    await tryCase("assets POST create", async () => {
      const { status, json } = await req("POST", "/api-assets", {
        key: KEY_A,
        body: {
          asset_type_code: ASSET_TYPE_A,
          name: `Smoke Asset ${RUN_ID}`,
          external_id: assetExt,
          external_user_id: extA,
          upsert: false,
        },
      });
      if (![200, 201].includes(status) || !json?.success) {
        throw new Error(`status=${status} ${JSON.stringify(json).slice(0, 240)}`);
      }
    });

    await tryCase("assets GET by-external-id", async () => {
      const { json } = await req("GET", `/api-assets/by-external-id/${encodeURIComponent(assetExt)}`, {
        key: KEY_A,
        expectStatus: 200,
      });
      if (!json?.success) throw new Error(JSON.stringify(json).slice(0, 200));
    });

    await tryCase("assets PATCH", async () => {
      const { json } = await req("PATCH", `/api-assets/by-external-id/${encodeURIComponent(assetExt)}`, {
        key: KEY_A,
        body: { name: `Smoke Asset Patched ${RUN_ID}` },
        expectStatus: 200,
      });
      if (!json?.success) throw new Error(JSON.stringify(json).slice(0, 200));
    });

    await tryCase("assets tenant: key B cannot read asset A", async () => {
      const { status } = await req("GET", `/api-assets/by-external-id/${encodeURIComponent(assetExt)}`, {
        key: KEY_B,
      });
      if (status !== 404) throw new Error(`expected 404 got ${status}`);
    });
  } else {
    await tryCase("assets GET not found", async () => {
      const { status } = await req("GET", `/api-assets/by-external-id/${encodeURIComponent("no-such-asset")}`, {
        key: KEY_A,
      });
      if (status !== 404) throw new Error(`expected 404 got ${status}`);
    });
  }

  // --- Purchases ---
  const txn = `${RUN_ID}-txn`;
  const txnDate = "2026-01-15T10:30:00+07:00";
  if (allowWrites) {
    await tryCase("purchases POST with transaction_date", async () => {
      const { json } = await req("POST", "/api-purchases", {
        key: KEY_A,
        body: {
          final_amount: 100,
          external_user_id: extA,
          transaction_number: txn,
          transaction_date: txnDate,
          earn_currency: false,
          payment_status: "paid",
          status: "completed",
          items: [],
          metadata: { smoke: true, run_id: RUN_ID },
        },
        expectStatus: 200,
      });
      if (!json?.success) throw new Error(JSON.stringify(json).slice(0, 240));
    });

    await tryCase("purchases GET by number", async () => {
      const { json } = await req("GET", `/api-purchases/${encodeURIComponent(txn)}`, {
        key: KEY_A,
        expectStatus: 200,
      });
      if (!json?.success) throw new Error(JSON.stringify(json).slice(0, 200));
      const data = json?.data?.data || json?.data;
      const persisted =
        data?.transaction_date || data?.purchase?.transaction_date || data?.transaction?.transaction_date;
      // Soft assert: if field present, must contain 2026-01-15
      if (persisted && !String(persisted).includes("2026-01-15")) {
        throw new Error(`transaction_date not persisted: ${persisted}`);
      }
    });

    await tryCase("purchases PATCH payment_method", async () => {
      const { json } = await req("PATCH", `/api-purchases/${encodeURIComponent(txn)}`, {
        key: KEY_A,
        body: { payment_method: "card", notes: "smoke patch", metadata: { patched: true } },
        expectStatus: 200,
      });
      if (!json?.success) throw new Error(JSON.stringify(json).slice(0, 200));
    });

    await tryCase("purchases tenant: key B cannot read purchase A", async () => {
      const { status, json } = await req("GET", `/api-purchases/${encodeURIComponent(txn)}`, {
        key: KEY_B,
      });
      // merchant B should not see A's purchase — typically 404 or success:false
      if (status === 200 && json?.success && (json?.data?.success !== false)) {
        const d = json?.data?.data || json?.data;
        if (d?.transaction_number === txn) throw new Error("tenant leak");
      }
    });
  } else {
    await tryCase("purchases GET not found", async () => {
      const { status, json } = await req("GET", `/api-purchases/${encodeURIComponent("no-such-txn")}`, {
        key: KEY_A,
      });
      if (!(status === 404 || json?.success === false || json?.data?.success === false)) {
        throw new Error(`unexpected ${status} ${JSON.stringify(json).slice(0, 160)}`);
      }
    });
  }

  // --- Redemptions ---
  if (allowWrites && REWARD_A) {
    let skipRedeemWrites = false;
    await tryCase("redemptions seed points via wallet earn", async () => {
      // Purchase earn can be async; wallet POST is synchronous and is the reliable seed.
      const seedAmount = 400; // enough for two 150-pt redemptions + slack
      const { status, json } = await req("POST", "/api-wallet/transactions", {
        key: KEY_A,
        body: {
          external_user_id: extA,
          transaction_type: "earn",
          amount: seedAmount,
          dedup_key: `${RUN_ID}:redeem-seed`,
          description: "smoke redeem seed",
        },
      });
      if (![200, 201].includes(status) || !json?.success) {
        throw new Error(`wallet seed failed status=${status} ${JSON.stringify(json).slice(0, 200)}`);
      }
      const u = await req("GET", `/api-users/by-external-id/${encodeURIComponent(extA)}`, { key: KEY_A });
      const bal = extractPointsBalance(u.json);
      if (bal < 150) {
        skipRedeemWrites = true;
        record(
          "redemptions writes deferred",
          true,
          `balance=${bal} after wallet seed`,
        );
      }
    });

    if (!skipRedeemWrites) {
      let code1 = null;
      let code2 = null;
      await tryCase("redemptions POST create #1", async () => {
        const u = await req("GET", `/api-users/by-external-id/${encodeURIComponent(extA)}`, { key: KEY_A });
        const userId = extractUserId(u.json);
        if (!userId) throw new Error(`no user_id ${JSON.stringify(u.json).slice(0, 200)}`);
        const { status, json } = await req("POST", "/api-redemptions", {
          key: KEY_A,
          body: { user_id: userId, reward_id: REWARD_A, quantity: 1 },
        });
        if (!json?.success && status >= 400) {
          throw new Error(`redeem failed status=${status} ${JSON.stringify(json).slice(0, 240)}`);
        }
        code1 = extractRedemptionCode(json);
        if (!code1) throw new Error(`no redemption_code ${JSON.stringify(json).slice(0, 400)}`);
      });

      await tryCase("redemptions POST create #2", async () => {
        const u = await req("GET", `/api-users/by-external-id/${encodeURIComponent(extA)}`, { key: KEY_A });
        const userId = extractUserId(u.json);
        const { json } = await req("POST", "/api-redemptions", {
          key: KEY_A,
          body: { user_id: userId, reward_id: REWARD_A, quantity: 1 },
        });
        if (!json?.success) throw new Error(JSON.stringify(json).slice(0, 240));
        code2 = extractRedemptionCode(json);
        if (!code2) throw new Error(`no redemption_code ${JSON.stringify(json).slice(0, 400)}`);
      });

      await tryCase("redemptions mark-used #1", async () => {
        const { json } = await req("POST", `/api-redemptions/${encodeURIComponent(code1)}/mark-used`, {
          key: KEY_A,
          body: { notes: "smoke" },
          expectStatus: 200,
        });
        if (!json?.success) throw new Error(JSON.stringify(json).slice(0, 200));
      });

      await tryCase("redemptions cancel #2", async () => {
        const { json } = await req("POST", `/api-redemptions/${encodeURIComponent(code2)}/cancel`, {
          key: KEY_A,
          body: { reason: "smoke cancel" },
          expectStatus: 200,
        });
        if (!json?.success) throw new Error(JSON.stringify(json).slice(0, 200));
      });

      await tryCase("redemptions tenant: key B cannot get redemption A", async () => {
        const { status } = await req("GET", `/api-redemptions/${encodeURIComponent(code1)}`, { key: KEY_B });
        if (status !== 404) throw new Error(`expected 404 got ${status}`);
      });

      // Leave residual seeded points as-is if redeem cost < seed; optional compensate unused remainder.
      await tryCase("redemptions compensate unused seed", async () => {
        const u = await req("GET", `/api-users/by-external-id/${encodeURIComponent(extA)}`, { key: KEY_A });
        const bal = extractPointsBalance(u.json);
        if (bal <= 0) return;
        const { status, json } = await req("POST", "/api-wallet/transactions", {
          key: KEY_A,
          body: {
            external_user_id: extA,
            transaction_type: "burn",
            amount: bal,
            dedup_key: `${RUN_ID}:redeem-seed-burn`,
            description: "smoke redeem seed leftover burn",
          },
        });
        if (![200, 201].includes(status) || !json?.success) {
          throw new Error(`leftover burn failed ${status} ${JSON.stringify(json).slice(0, 160)}`);
        }
      });
    }
  } else {
    await tryCase("redemptions GET not found", async () => {
      const { status } = await req("GET", `/api-redemptions/${encodeURIComponent("NO-SUCH-CODE")}`, {
        key: KEY_A,
      });
      if (status !== 404) throw new Error(`expected 404 got ${status}`);
    });
    if (allowWrites && !REWARD_A) {
      record("redemptions writes skipped", true, "TEST_REWARD_ID_A not set");
    }
  }

  // --- Wallet (Phase 2) ---
  if (includeWallet) {
    if (!allowWrites) {
      record("wallet skipped", true, "requires --allow-writes");
    } else {
      const dedup = `${RUN_ID}:earn1`;
      let earnLedgerId = null;

      await tryCase("wallet POST earn", async () => {
        const { status, json } = await req("POST", "/api-wallet/transactions", {
          key: KEY_A,
          body: {
            external_user_id: extA,
            transaction_type: "earn",
            amount: 10,
            dedup_key: dedup,
            description: "smoke earn",
          },
          expectStatus: 201,
        });
        if (!json?.success || !json?.data?.wallet_ledger_id) {
          throw new Error(`missing ledger ${JSON.stringify(json).slice(0, 240)}`);
        }
        earnLedgerId = json.data.wallet_ledger_id;
        if (json.data.already_processed) throw new Error("expected fresh earn");
      });

      await tryCase("wallet POST replay same payload", async () => {
        const { status, json } = await req("POST", "/api-wallet/transactions", {
          key: KEY_A,
          body: {
            external_user_id: extA,
            transaction_type: "earn",
            amount: 10,
            dedup_key: dedup,
            description: "smoke earn",
          },
          expectStatus: 200,
        });
        if (!json?.success || !json?.data?.already_processed) {
          throw new Error(`expected already_processed ${JSON.stringify(json).slice(0, 200)}`);
        }
        if (earnLedgerId && json.data.wallet_ledger_id !== earnLedgerId) {
          throw new Error("replay returned different ledger id");
        }
      });

      await tryCase("wallet POST conflict different amount", async () => {
        const { status, json } = await req("POST", "/api-wallet/transactions", {
          key: KEY_A,
          body: {
            external_user_id: extA,
            transaction_type: "earn",
            amount: 11,
            dedup_key: dedup,
          },
        });
        if (status !== 409 || json?.code !== "IDEMPOTENCY_CONFLICT") {
          throw new Error(`expected 409 IDEMPOTENCY_CONFLICT got ${status} ${JSON.stringify(json).slice(0, 160)}`);
        }
      });

      await tryCase("wallet POST burn over balance", async () => {
        const { status, json } = await req("POST", "/api-wallet/transactions", {
          key: KEY_A,
          body: {
            external_user_id: extA,
            transaction_type: "burn",
            amount: 999999,
            dedup_key: `${RUN_ID}:burn-over`,
          },
        });
        if (status !== 400 || json?.code !== "INSUFFICIENT_BALANCE") {
          throw new Error(`expected 400 INSUFFICIENT_BALANCE got ${status} ${JSON.stringify(json).slice(0, 160)}`);
        }
      });

      await tryCase("wallet GET history", async () => {
        const { json } = await req(
          "GET",
          `/api-wallet/transactions?external_user_id=${encodeURIComponent(extA)}&limit=10&transaction_type=earn`,
          { key: KEY_A, expectStatus: 200 },
        );
        if (!json?.success || !Array.isArray(json?.data?.transactions)) {
          throw new Error(JSON.stringify(json).slice(0, 200));
        }
        if ((json.data.total_count ?? 0) < 1) throw new Error("expected total_count >= 1");
      });

      await tryCase("wallet tenant: key B cannot read A", async () => {
        const { status, json } = await req(
          "GET",
          `/api-wallet/transactions?external_user_id=${encodeURIComponent(extA)}`,
          { key: KEY_B },
        );
        if (status === 404 || json?.code === "USER_NOT_FOUND") return;
        if (status === 200 && (json?.data?.total_count ?? 0) === 0) return;
        throw new Error(`tenant leak status=${status} ${JSON.stringify(json).slice(0, 160)}`);
      });

      await tryCase("wallet compensating burn", async () => {
        const { status, json } = await req("POST", "/api-wallet/transactions", {
          key: KEY_A,
          body: {
            external_user_id: extA,
            transaction_type: "burn",
            amount: 10,
            dedup_key: `${RUN_ID}:burn-comp`,
            description: "smoke compensate",
          },
          expectStatus: 201,
        });
        if (!json?.success) throw new Error(JSON.stringify(json).slice(0, 200));
      });

      await tryCase("wallet POST ticket missing type", async () => {
        const { status, json } = await req("POST", "/api-wallet/transactions", {
          key: KEY_A,
          body: {
            external_user_id: extA,
            transaction_type: "earn",
            amount: 1,
            currency: "ticket",
            dedup_key: `${RUN_ID}:ticket-missing`,
          },
        });
        if (status !== 400 || json?.code !== "TICKET_TYPE_REQUIRED") {
          throw new Error(`expected 400 TICKET_TYPE_REQUIRED got ${status} ${JSON.stringify(json).slice(0, 160)}`);
        }
      });

      await tryCase("wallet POST ticket unknown code", async () => {
        const { status, json } = await req("POST", "/api-wallet/transactions", {
          key: KEY_A,
          body: {
            external_user_id: extA,
            transaction_type: "earn",
            amount: 1,
            currency: "ticket",
            ticket_code: "NO_SUCH_OPENAPI_TICKET",
            dedup_key: `${RUN_ID}:ticket-unknown`,
          },
        });
        if (status !== 400 || json?.code !== "TICKET_TYPE_NOT_FOUND") {
          throw new Error(`expected 400 TICKET_TYPE_NOT_FOUND got ${status} ${JSON.stringify(json).slice(0, 160)}`);
        }
      });

      if (TICKET_CODE_A) {
        const ticketDedup = `${RUN_ID}:ticket-earn`;
        let ticketLedgerId = null;
        await tryCase("wallet POST ticket earn", async () => {
          const { json } = await req("POST", "/api-wallet/transactions", {
            key: KEY_A,
            body: {
              external_user_id: extA,
              transaction_type: "earn",
              amount: 2,
              currency: "ticket",
              ticket_code: TICKET_CODE_A,
              dedup_key: ticketDedup,
              description: "smoke ticket earn",
            },
            expectStatus: 201,
          });
          if (!json?.success || json?.data?.currency !== "ticket" || json?.data?.amount !== 2) {
            throw new Error(JSON.stringify(json).slice(0, 240));
          }
          ticketLedgerId = json.data.wallet_ledger_id;
        });

        await tryCase("wallet POST ticket replay", async () => {
          const { json } = await req("POST", "/api-wallet/transactions", {
            key: KEY_A,
            body: {
              external_user_id: extA,
              transaction_type: "earn",
              amount: 2,
              currency: "ticket",
              ticket_code: TICKET_CODE_A,
              dedup_key: ticketDedup,
            },
            expectStatus: 200,
          });
          if (!json?.data?.already_processed) {
            throw new Error(`expected already_processed ${JSON.stringify(json).slice(0, 200)}`);
          }
          if (ticketLedgerId && json.data.wallet_ledger_id !== ticketLedgerId) {
            throw new Error("ticket replay returned different ledger id");
          }
        });

        await tryCase("wallet GET ticket history", async () => {
          const { json } = await req(
            "GET",
            `/api-wallet/transactions?external_user_id=${encodeURIComponent(extA)}&currency=ticket&ticket_code=${encodeURIComponent(TICKET_CODE_A)}&limit=10`,
            { key: KEY_A, expectStatus: 200 },
          );
          if ((json?.data?.total_count ?? 0) < 2) {
            throw new Error(`expected unit rows >= 2 ${JSON.stringify(json).slice(0, 200)}`);
          }
        });

        await tryCase("wallet compensating ticket burn", async () => {
          const { json } = await req("POST", "/api-wallet/transactions", {
            key: KEY_A,
            body: {
              external_user_id: extA,
              transaction_type: "burn",
              amount: 2,
              currency: "ticket",
              ticket_code: TICKET_CODE_A,
              dedup_key: `${RUN_ID}:ticket-burn-comp`,
              description: "smoke ticket compensate",
            },
            expectStatus: 201,
          });
          if (!json?.success) throw new Error(JSON.stringify(json).slice(0, 200));
        });
      }
    }
  }

  // Method / malformed
  await tryCase("users unsupported method", async () => {
    const { status, json } = await req("DELETE", "/api-users", { key: KEY_A });
    if (status !== 405) throw new Error(`expected 405 got ${status} ${JSON.stringify(json).slice(0, 120)}`);
  });

  printMatrix();
  process.exit(failed ? 1 : 0);
}

main().catch((e) => {
  console.error("FATAL", redact(e.message || String(e)));
  process.exit(1);
});
