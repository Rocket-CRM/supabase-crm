#!/usr/bin/env python3
"""
Compute apply-ready end state for remaining 138 Jorakay drift users.
Same rules as DATA-ADJUSTMENT-MANIFEST.md / Plan.md / 15-user deep dives.

Inputs (under bug-report data/):
  - remaining-138-classification.csv
  - remaining-138-earn-rows.json
  - remaining-138-native-ledger.json

Outputs:
  - data/user-targets-remaining-138.json
  - data/row-level-targets-remaining-138.csv
  - data/ledger-inserts-remaining-138.csv  (NO_POINTS_LEDGER only)
  - DATA-ADJUSTMENT-MANIFEST-REMAINING-138.md
"""

from __future__ import annotations

import csv
import json
import math
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data"
EPS = 0.01

DONE15 = {
    "65413f78d6b1732a1ec616f1",
    "6811e84c6fc1032760808710",
    "65e992956fdff6649db70844",
    "65413f89d6b1732a1ec6255d",
    "67cd2a13865b399021ce9895",
    "67510f45a33a4dc033969a91",
    "699efc2f2ec2d76e1eae0dd6",
    "65e54b99d3d42fdf0cf61c93",
    "681421cab1e202f9103ec1a0",
    "669f3ec760ab0274d8e31ed4",
    "67c917a2c336839338cc12a8",
    "6a4869e18a5ea7b763b65992",
    "66aa305cddfe1420692eff91",
    "65413f4fd6b1732a1ec5f415",
    "6787827bb0d6038e49a36ed6",
}


def fnum(x) -> float:
    if x is None or x == "":
        return 0.0
    return float(x)


@dataclass
class EarnRow:
    ledger_id: str
    mongo_id: str | None
    created_at: str
    amount: float
    current_deductible: float
    stg_mongo_balance: float | None
    is_native: bool
    expiry_date: str | None
    target: float = 0.0
    reason: str = ""


def fifo_reduce(earns: list[EarnRow], total: float, reason: str) -> None:
    remaining = total
    if remaining <= EPS:
        return
    ordered = sorted(earns, key=lambda e: e.created_at)
    for e in ordered:
        if remaining <= EPS:
            break
        take = min(e.target, remaining)
        if take > EPS:
            e.target -= take
            e.reason = reason if not e.reason else e.reason + "; " + reason
            remaining -= take
    if remaining > EPS:
        raise ValueError(f"FIFO could not consume {remaining} ({reason})")


def trim_surplus_migrated(earns: list[EarnRow], surplus: float) -> None:
    """Reduce migrated deductibles when Σ open lots > wallet_target (headline mismatch)."""
    remaining = surplus
    migrated = [e for e in earns if not e.is_native and e.target > EPS]
    # Prefer rows already at 0 stg balance, then expired, then oldest
    def sort_key(e: EarnRow):
        expired = 0 if e.expiry_date and e.expiry_date < "2026-09-12" else 1
        stg_zero = 0 if (e.stg_mongo_balance or 0) <= EPS else 1
        return (stg_zero, expired, e.created_at)

    for e in sorted(migrated, key=sort_key):
        if remaining <= EPS:
            break
        take = min(e.target, remaining)
        if take > EPS:
            e.target -= take
            e.reason = (
                "headline_mismatch_trim"
                if not e.reason
                else e.reason + "; headline_mismatch_trim"
            )
            remaining -= take
    if remaining > EPS:
        for e in sorted(earns, key=lambda x: x.created_at):
            if remaining <= EPS:
                break
            take = min(e.target, remaining)
            if take > EPS:
                e.target -= take
                e.reason = (
                    "headline_mismatch_trim_fallback"
                    if not e.reason
                    else e.reason + "; headline_mismatch_trim_fallback"
                )
                remaining -= take


def allocate_zero_lots(earns: list[EarnRow], wallet_target: float) -> None:
    """Spread wallet_target across earns when all deductibles are 0."""
    if not earns:
        return
    ordered = sorted(earns, key=lambda e: e.created_at)
    remaining = wallet_target
    for e in ordered:
        if remaining <= EPS:
            e.target = 0.0
            e.reason = "zero_lots_allocate"
            continue
        cap = e.amount if e.is_native else (e.stg_mongo_balance or e.amount or 0)
        give = min(cap, remaining) if cap > EPS else min(remaining, e.amount or remaining)
        give = min(give, remaining)
        e.target = give
        e.reason = "zero_lots_allocate"
        remaining -= give


def classify_fix_class(
    pattern: str,
    has_native_burn: bool,
    has_expiry: bool,
    wallet_update: float | None,
    insert_only: bool,
) -> str:
    if insert_only:
        return "insert_earn_orphan_wallet"
    if wallet_update and abs(wallet_update) > EPS:
        return "user_wallet_plus_earn_fifo"
    if has_expiry and has_native_burn:
        return "migrated_sync_plus_native_burns_and_expiry"
    if has_expiry:
        return "migrated_sync_plus_expiry_fifo_on_earns"
    if has_native_burn:
        return "migrated_sync_plus_native_fifo"
    if pattern in ("TTL_ZERO_LOTS_MIGRATION", "ZERO_LOTS_NATIVE_ACTIVITY"):
        return "allocate_deductible_after_ttl_repair"
    return "migrated_sync_live_mongo"


def process_user(row: dict, earns: list[EarnRow], native_burns: list[dict]) -> dict:
    mongo_id = row["mongo_id"]
    user_id = row["user_id"]
    wallet_now = fnum(row["wallet"])
    pattern = row["primary_pattern"]

    stg_pb = fnum(row["stg_point_balance"]) if row.get("stg_point_balance") not in ("", None) else None
    native_earn = fnum(row["native_earn"])
    native_burn = fnum(row["native_burn"])
    expiry_burn = fnum(row["expiry_burn"])

    if pattern == "NO_POINTS_LEDGER" or not earns:
        wallet_target = wallet_now
        lots_target = wallet_now
        inserts = [
            {
                "mongo_id": mongo_id,
                "user_id": user_id,
                "amount": wallet_target,
                "deductible_balance": wallet_target,
                "reason": "orphan_wallet_no_points_ledger",
            }
        ]
        return {
            "mongo_id": mongo_id,
            "user_id": user_id,
            "wallet_now": wallet_now,
            "wallet_target": wallet_target,
            "lots_target": lots_target,
            "wallet_update": None,
            "fix_class": "insert_earn_orphan_wallet",
            "primary_pattern": pattern,
            "earn_rows": [],
            "inserts": inserts,
            "review_flags": [],
        }

    wallet_target = (
        (stg_pb or 0) + native_earn - native_burn - expiry_burn
    )
    wallet_target = round(wallet_target, 2)
    lots_target = wallet_target

    # Step 1: base targets from Mongo staging + native earn amounts
    for e in earns:
        if e.is_native:
            e.target = e.amount
            e.reason = "native_earn_full_amount"
        else:
            bal = e.stg_mongo_balance
            e.target = bal if bal is not None else 0.0
            e.reason = "migrated_sync_stg_mongo_balance"

    # Zero-lots patterns: redistribute if sum target ~ 0
    if fnum(row["lots"]) <= EPS and wallet_target > EPS:
        allocate_zero_lots(earns, wallet_target)
    else:
        if expiry_burn > EPS:
            fifo_reduce(earns, expiry_burn, "fifo_existing_expiry_burn")
        if native_burn > EPS:
            fifo_reduce(earns, native_burn, "fifo_existing_native_burn")

    lot_sum = sum(e.target for e in earns)
    surplus = lot_sum - wallet_target
    if surplus > EPS:
        trim_surplus_migrated(earns, surplus)
        lot_sum = sum(e.target for e in earns)

    deficit = wallet_target - lot_sum
    review_flags: list[str] = []
    if abs(deficit) > EPS:
        # Bump migrated rows where staging balance exceeds target (under-allocated CRM)
        if deficit > 0:
            for e in sorted(earns, key=lambda x: x.created_at):
                if not e.is_native and e.stg_mongo_balance and e.stg_mongo_balance > e.target + EPS:
                    add = min(e.stg_mongo_balance - e.target, deficit)
                    e.target += add
                    e.reason += "; migrated_under_crm_bump"
                    deficit -= add
                    if deficit <= EPS:
                        break
        lot_sum = sum(e.target for e in earns)
        if abs(wallet_target - lot_sum) > EPS:
            review_flags.append(
                f"lot_sum_residual={lot_sum:.2f}_vs_wallet_target={wallet_target:.2f}"
            )

    wallet_update = None
    if abs(wallet_now - wallet_target) > EPS:
        # Credit wallet only when lots already equal target (ledger posted, wallet lag)
        if abs(lot_sum - wallet_target) <= EPS and wallet_now < wallet_target - EPS:
            wallet_update = round(wallet_target - wallet_now, 2)
        elif abs(lot_sum - wallet_target) <= EPS and wallet_now > wallet_target + EPS:
            wallet_update = round(wallet_target - wallet_now, 2)
        else:
            # Wallet truth is mongo+native formula; fix earns first — no wallet move unless aligned
            if abs(wallet_now - wallet_target) > EPS and abs(lot_sum - wallet_target) <= EPS:
                wallet_update = round(wallet_target - wallet_now, 2)

    fix_class = classify_fix_class(
        pattern,
        native_burn > EPS,
        expiry_burn > EPS,
        wallet_update,
        False,
    )

    return {
        "mongo_id": mongo_id,
        "user_id": user_id,
        "wallet_now": wallet_now,
        "wallet_target": wallet_target,
        "lots_target": lots_target,
        "wallet_update": wallet_update,
        "fix_class": fix_class,
        "primary_pattern": pattern,
        "earn_rows": earns,
        "inserts": [],
        "review_flags": review_flags,
        "native_fifo_burn_total": native_burn if native_burn > EPS else None,
        "expiry_burn_total": expiry_burn if expiry_burn > EPS else None,
        "stg_point_balance": stg_pb,
    }


def main() -> None:
    class_path = ROOT / "remaining-138-classification.csv"
    earns_path = DATA / "remaining-138-earn-rows.json"
    native_path = DATA / "remaining-138-native-ledger.json"

    if not earns_path.exists() or not native_path.exists():
        raise SystemExit(
            f"Missing exports. Run sql/export-earn-rows-remaining-138.sql and "
            f"sql/export-native-ledger-remaining-138.sql into {DATA}/"
        )

    class_rows = {r["mongo_id"]: r for r in csv.DictReader(open(class_path))}
    earn_raw = json.loads(earns_path.read_text())
    native_raw = json.loads(native_path.read_text())

    earns_by_user: dict[str, list[EarnRow]] = defaultdict(list)
    for r in earn_raw:
        mid = r["member_mongo"]
        earns_by_user[mid].append(
            EarnRow(
                ledger_id=r["ledger_id"],
                mongo_id=r.get("mongo_id"),
                created_at=r["created_at"],
                amount=fnum(r["amount"]),
                current_deductible=fnum(r["current_deductible"]),
                stg_mongo_balance=(
                    None if r.get("stg_mongo_balance") is None else fnum(r["stg_mongo_balance"])
                ),
                is_native=bool(r.get("is_native_earn")),
                expiry_date=r.get("expiry_date"),
            )
        )

    native_by_user: dict[str, list[dict]] = defaultdict(list)
    for r in native_raw:
        if r.get("transaction_type") == "burn":
            native_by_user[r["member_mongo"]].append(r)

    results = []
    row_level = []
    inserts = []
    errors = []

    for mongo_id, crow in class_rows.items():
        if mongo_id in DONE15:
            continue
        try:
            out = process_user(crow, earns_by_user.get(mongo_id, []), native_by_user.get(mongo_id, []))
            results.append(out)
            for e in out["earn_rows"]:
                if abs(e.target - e.current_deductible) > EPS:
                    row_level.append(
                        {
                            "mongo_id": mongo_id,
                            "user_id": out["user_id"],
                            "ledger_id": e.ledger_id,
                            "mongo_earn_id": e.mongo_id or "",
                            "current_deductible": e.current_deductible,
                            "target_deductible": round(e.target, 2),
                            "reason": e.reason,
                        }
                    )
            for ins in out.get("inserts", []):
                inserts.append(ins)
        except Exception as ex:
            errors.append({"mongo_id": mongo_id, "error": str(ex)})

    user_targets = {
        "merchant_id": "7522af2c-a7f6-4ab8-8493-6875a3b19544",
        "mongo_merchant_ref": "649e9524f43a5fc2f9705850",
        "exported_at": datetime.utcnow().strftime("%Y-%m-%d"),
        "user_count": len(results),
        "users": [
            {
                "mongo_id": u["mongo_id"],
                "user_id": u["user_id"],
                "wallet_now": u["wallet_now"],
                "wallet_target": u["wallet_target"],
                "lots_target": u["lots_target"],
                "wallet_update": u["wallet_update"],
                "fix_class": u["fix_class"],
                "primary_pattern": u["primary_pattern"],
                "review_flags": u.get("review_flags") or [],
                "native_fifo_burn_total": u.get("native_fifo_burn_total"),
                "expiry_burn_total": u.get("expiry_burn_total"),
            }
            for u in results
        ],
        "errors": errors,
    }

    DATA.mkdir(parents=True, exist_ok=True)
    (DATA / "user-targets-remaining-138.json").write_text(
        json.dumps(user_targets, indent=2)
    )

    with open(DATA / "row-level-targets-remaining-138.csv", "w", newline="") as f:
        w = csv.DictWriter(
            f,
            fieldnames=[
                "mongo_id",
                "user_id",
                "ledger_id",
                "mongo_earn_id",
                "current_deductible",
                "target_deductible",
                "reason",
            ],
        )
        w.writeheader()
        w.writerows(row_level)

    with open(DATA / "ledger-inserts-remaining-138.csv", "w", newline="") as f:
        w = csv.DictWriter(
            f,
            fieldnames=["mongo_id", "user_id", "amount", "deductible_balance", "reason"],
        )
        w.writeheader()
        w.writerows(inserts)

    review = [u for u in results if u.get("review_flags")]
    wallet_moves = [u for u in results if u.get("wallet_update")]

    class_rows = {r["mongo_id"]: r for r in csv.DictReader(open(class_path))}
    chg = Counter(r["mongo_id"] for r in row_level)
    end_state_rows = []
    for u in results:
        c = class_rows[u["mongo_id"]]
        end_state_rows.append(
            {
                "mongo_id": u["mongo_id"],
                "user_id": u["user_id"],
                "wallet_before": c["wallet"],
                "wallet_after": u["wallet_target"],
                "wallet_update_delta": u["wallet_update"] if u["wallet_update"] is not None else 0,
                "lots_before": c["lots"],
                "lots_after": u["lots_target"],
                "fix_class": u["fix_class"],
                "earn_rows_to_update": chg.get(u["mongo_id"], 0),
                "earn_rows_to_insert": 1 if u["fix_class"] == "insert_earn_orphan_wallet" else 0,
            }
        )
    with open(DATA / "user-end-state-remaining-138.csv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(end_state_rows[0].keys()))
        w.writeheader()
        w.writerows(end_state_rows)

    md = f"""# Jorakay — remaining 138 users (apply-ready manifest)

**Generated:** {user_targets['exported_at']} · Same rules as 15-user `DATA-ADJUSTMENT-MANIFEST.md` / `Plan.md`.

| Artifact | Path |
|----------|------|
| User targets | `data/user-targets-remaining-138.json` |
| Earn UPDATE rows | `data/row-level-targets-remaining-138.csv` ({len(row_level)} rows) |
| Earn INSERT rows | `data/ledger-inserts-remaining-138.csv` ({len(inserts)} rows) |

**Wallet target:** `stg_point_balance` + native earns − native burns − expiry burns (staging Mongo headline; **verify live Mongo at apply**).

**Before apply:** Re-run `sql/export-earn-rows-remaining-138.sql` + `sql/export-native-ledger-remaining-138.sql`; confirm `stg_mongo_balance` vs live `GIVEN.balance`.

## Summary

- Users computed: **{len(results)}**
- Earn row UPDATEs: **{len(row_level)}**
- Orphan-wallet INSERTs: **{len(inserts)}**
- `user_wallet` deltas: **{len(wallet_moves)}**
- Residual lot-sum flags: **{len(review)}**
- Errors: **{len(errors)}**

## `user_wallet` UPDATE candidates

| mongo_id | user_id | now → target | delta |
|----------|---------|--------------|-------|
"""
    for u in sorted(wallet_moves, key=lambda x: -abs(x["wallet_update"] or 0)):
        md += f"| `{u['mongo_id']}` | `{u['user_id']}` | {u['wallet_now']} → **{u['wallet_target']}** | {u['wallet_update']} |\n"

    if review:
        md += "\n## Review flags (earn math residual)\n\n"
        for u in review:
            md += f"- `{u['mongo_id']}`: {', '.join(u['review_flags'])}\n"

    (ROOT / "DATA-ADJUSTMENT-MANIFEST-REMAINING-138.md").write_text(md)

    print("users", len(results))
    print("row updates", len(row_level))
    print("inserts", len(inserts))
    print("wallet updates", len(wallet_moves))
    print("review", len(review))
    print("errors", len(errors))


if __name__ == "__main__":
    main()
