#!/usr/bin/env python3
"""Generate per-user SQL transactions for Jorakay wallet/lot apply pack."""

from __future__ import annotations

import csv
import json
import re
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data"
MERCHANT = "7522af2c-a7f6-4ab8-8493-6875a3b19544"


def esc(s: str) -> str:
    return s.replace("'", "''")


def num(x: str | float) -> str:
    return str(int(round(float(x))))


def load_row_updates() -> dict[str, list[dict]]:
    by_user: dict[str, list[dict]] = defaultdict(list)
    with (DATA / "row-level-targets-all-153.csv").open() as f:
        for row in csv.DictReader(f):
            by_user[row["user_id"]].append(row)
    return by_user


def load_inserts() -> dict[str, list[dict]]:
    by_user: dict[str, list[dict]] = defaultdict(list)
    p = DATA / "ledger-inserts-all-153.csv"
    if not p.exists():
        return by_user
    with p.open() as f:
        for row in csv.DictReader(f):
            by_user[row["user_id"]].append(row)
    return by_user


def load_wallet_updates() -> dict[str, dict]:
    out: dict[str, dict] = {}
    with (DATA / "wallet-updates-all-153.csv").open() as f:
        for row in csv.DictReader(f):
            out[row["user_id"]] = row
    return out


def insert_sql(row: dict) -> str:
    meta = row["metadata"].strip()
    if not meta.startswith("{"):
        meta = json.dumps(json.loads(meta.replace('""', '"')))
    created_at = row["created_at"] or "now()"
    if created_at != "now()":
        created_at = f"'{esc(created_at)}'::timestamptz"
    else:
        created_at = "now()"
    expiry = "NULL"
    if row.get("expiry_date"):
        expiry = f"'{esc(row['expiry_date'])}'::date"
    target_entity = f"'{row['target_entity_id']}'::uuid" if row.get("target_entity_id") else "NULL"
    created_by = f"'{esc(row['created_by'])}'" if row.get("created_by") else "NULL"
    dedup = esc(row["dedup_key"])
    return f"""
INSERT INTO wallet_ledger (
  merchant_id, user_id, currency, transaction_type, component,
  amount, signed_amount, balance_before, balance_after, deductible_balance,
  source_type, description, metadata, target_entity_id, expiry_date,
  created_by, dedup_key, created_at, skip_cdc
) SELECT
  '{MERCHANT}'::uuid, '{row['user_id']}'::uuid,   'points'::currency, 'earn'::currency_transaction_type,
  'base'::currency_component,
  {num(row['amount'])}, {num(row['signed_amount'])}, {num(row['balance_before'])},
  {num(row['balance_after'])}, {num(row['deductible_balance'])},
  'manual'::wallet_transaction_source_type, '{esc(row['description'])}', '{esc(meta)}'::jsonb,
  {target_entity}, {expiry},
  {created_by}, '{dedup}', {created_at}, false
WHERE NOT EXISTS (
  SELECT 1 FROM wallet_ledger wl
  WHERE wl.merchant_id = '{MERCHANT}'::uuid AND wl.dedup_key = '{dedup}'
);
""".strip()


def user_transaction(
    user_id: str,
    earns: list[dict],
    inserts: list[dict],
    wallet: dict | None,
) -> str:
    parts = ["BEGIN;"]
    for e in earns:
        lid = e["ledger_id"]
        target = float(e["target_deductible"])
        parts.append(
            f"UPDATE wallet_ledger SET deductible_balance = {target} "
            f"WHERE id = '{lid}'::uuid AND merchant_id = '{MERCHANT}'::uuid "
            f"AND user_id = '{user_id}'::uuid;"
        )
    for ins in inserts:
        parts.append(insert_sql(ins) + ";")
    if wallet:
        after = float(wallet["wallet_after"])
        parts.append(
            f"UPDATE user_wallet SET points_balance = {after} "
            f"WHERE user_id = '{user_id}'::uuid AND merchant_id = '{MERCHANT}'::uuid;"
        )
    parts.append(
        f"""DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '{user_id}'::uuid AND merchant_id = '{MERCHANT}'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '{user_id}'::uuid AND merchant_id = '{MERCHANT}'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '{user_id}', w, l;
  END IF;
END $v$;"""
    )
    parts.append("COMMIT;")
    return "\n".join(parts)


def main() -> None:
    earns = load_row_updates()
    inserts = load_inserts()
    wallets = load_wallet_updates()
    all_users = sorted(set(earns) | set(inserts) | set(wallets))
    out_dir = DATA / "apply-sql"
    out_dir.mkdir(exist_ok=True)
    batches: list[str] = []
    batch: list[str] = []
    batch_users: list[str] = []

    for uid in all_users:
        sql = user_transaction(uid, earns.get(uid, []), inserts.get(uid, []), wallets.get(uid))
        (out_dir / f"{uid}.sql").write_text(sql + "\n")
        batch.append(sql)
        batch_users.append(uid)
        if len(batch_users) >= 20:
            batches.append("\n".join(batch))
            batch = []
            batch_users = []
    if batch:
        batches.append("\n".join(batch))

    manifest = {
        "users": len(all_users),
        "earn_updates": sum(len(v) for v in earns.values()),
        "inserts": sum(len(v) for v in inserts.values()),
        "wallet_updates": len(wallets),
        "batches": len(batches),
    }
    (DATA / "apply-batch-manifest.json").write_text(json.dumps(manifest, indent=2))
    for i, b in enumerate(batches):
        (DATA / f"apply-batch-{i}.sql").write_text(b + "\n")
    print(json.dumps(manifest))


if __name__ == "__main__":
    main()
