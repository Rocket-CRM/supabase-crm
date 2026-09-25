#!/usr/bin/env python3
"""
Build unified apply pack for all 153 Jorakay wallet/lot drift users.

Uses live Mongo snapshot (loyaltydb via MCP) when data/live-mongo-snapshot.json exists.
Falls back to staging columns with a warning.

Outputs (data/):
  - row-level-targets-all-153.csv
  - wallet-updates-all-153.csv
  - ledger-inserts-all-153.csv
  - user-end-state-all-153.csv
  - user-targets-all-153.json
"""

from __future__ import annotations

import csv
import json
import re
from collections import defaultdict
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data"
MERCHANT_PG = "7522af2c-a7f6-4ab8-8493-6875a3b19544"
EPS = 0.01

PILOT15 = {
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
    for e in sorted(earns, key=lambda x: x.created_at):
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
    remaining = surplus
    migrated = [e for e in earns if not e.is_native and e.target > EPS]

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
    if not earns:
        return
    remaining = wallet_target
    for e in sorted(earns, key=lambda x: x.created_at):
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


def parse_sql_json(path: Path) -> list[dict]:
    raw = path.read_text()
    if raw.strip().startswith("{"):
        outer = json.loads(raw)
        inner = outer.get("result", raw)
        if isinstance(inner, str):
            m = re.search(r"\[.*\]", inner, re.S)
            return json.loads(m.group(0)) if m else []
        return inner if isinstance(inner, list) else []
    return json.loads(raw)


def load_earn_rows() -> list[dict]:
    rows = []
    for name in ("earn-rows-export.json", "remaining-138-earn-rows.json"):
        p = DATA / name
        if p.exists():
            rows.extend(parse_sql_json(p))
    return rows


def load_native_burns() -> list[dict]:
    rows = []
    for name in ("native-ledger-export.json", "remaining-138-native-ledger.json"):
        p = DATA / name
        if p.exists():
            data = parse_sql_json(p)
            rows.extend([r for r in data if r.get("transaction_type") == "burn"])
    return rows


def load_live_snapshot() -> dict:
    p = DATA / "live-mongo-snapshot.json"
    if not p.exists():
        print("WARN: live-mongo-snapshot.json missing — using staging balances")
        return {}
    return json.loads(p.read_text())


def pattern_for_row(row: dict, pattern_map: dict[str, str]) -> str:
    if fnum(row.get("points_ledger_rows")) <= EPS and fnum(row["wallet"]) > EPS:
        return "NO_POINTS_LEDGER"
    return pattern_map.get(row["mongo_id"], "MIGRATED_LOTS_UNDER_STG_OPEN")


def live_balance_for_earn(e: EarnRow, live_given: dict[str, float]) -> float | None:
    if e.is_native or not e.mongo_id:
        return None
    if e.mongo_id in live_given:
        return live_given[e.mongo_id]
    return e.stg_mongo_balance


def process_user_live(row: dict, earns: list[EarnRow], live: dict) -> dict:
    """Same as c138.process_user but wallet/GIVEN from live Mongo snapshot."""
    mongo_id = row["mongo_id"]
    user_id = row["user_id"]
    wallet_now = fnum(row["wallet"])
    pattern = row["primary_pattern"]

    live_pb = (live.get("point_balance_by_user") or {}).get(mongo_id)
    live_given = live.get("given_balance_by_point_id") or {}

    native_earn = fnum(row["native_earn"])
    native_burn = fnum(row["native_burn"])
    expiry_burn = fnum(row["expiry_burn"])

    stg_pb = fnum(row.get("stg_point_balance")) if row.get("stg_point_balance") not in ("", None) else None
    headline = live_pb if live_pb is not None else (stg_pb or 0)

    if pattern == "NO_POINTS_LEDGER" or not earns:
        wallet_target = wallet_now
        return {
            "mongo_id": mongo_id,
            "user_id": user_id,
            "wallet_now": wallet_now,
            "wallet_target": wallet_target,
            "lots_target": wallet_target,
            "wallet_update": None,
            "fix_class": "insert_earn_orphan_wallet",
            "primary_pattern": pattern,
            "earn_rows": [],
            "inserts": [{"mongo_id": mongo_id, "user_id": user_id, "amount": wallet_target}],
            "review_flags": [],
            "mongo_headline_live": live_pb,
            "mongo_headline_stg": stg_pb,
        }

    wallet_target = round(headline + native_earn - native_burn - expiry_burn, 2)
    lots_target = wallet_target

    for e in earns:
        if e.is_native:
            e.target = e.amount
            e.reason = "native_earn_full_amount"
        else:
            bal = live_balance_for_earn(e, live_given)
            e.target = bal if bal is not None else 0.0
            e.reason = (
                "migrated_sync_live_mongo_balance"
                if e.mongo_id in live_given
                else "migrated_sync_stg_mongo_balance"
            )

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
    if abs(deficit) > EPS and deficit > 0:
        for e in sorted(earns, key=lambda x: x.created_at):
            if not e.is_native:
                cap = live_balance_for_earn(e, live_given) or 0
                if cap > e.target + EPS:
                    add = min(cap - e.target, deficit)
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
    lot_sum = sum(e.target for e in earns)
    if abs(lot_sum - wallet_target) <= EPS:
        if abs(wallet_now - wallet_target) > EPS:
            wallet_update = round(wallet_target - wallet_now, 2)

    fix_class = classify_fix_class(
        pattern, native_burn > EPS, expiry_burn > EPS, wallet_update, False
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
        "mongo_headline_live": live_pb,
        "mongo_headline_stg": stg_pb,
        "native_fifo_burn_total": native_burn if native_burn > EPS else None,
        "expiry_burn_total": expiry_burn if expiry_burn > EPS else None,
    }


def build_insert_row(ins: dict, wallet_now: float) -> dict:
    amt = int(round(fnum(ins["amount"])))
    wb = int(round(wallet_now))
    wa = wb  # wallet unchanged; earn explains balance
    return {
        "mongo_id": ins["mongo_id"],
        "user_id": ins["user_id"],
        "merchant_id": MERCHANT_PG,
        "currency": "points",
        "transaction_type": "earn",
        "component": "base",
        "amount": amt,
        "signed_amount": amt,
        "balance_before": wb,
        "balance_after": wa,
        "deductible_balance": amt,
        "source_type": "manual",
        "source_id": "",
        "description": "Legacy wallet balance",
        "metadata": json.dumps(
            {
                "backfill": "jorakay_wallet_lot_drift_20260912",
                "reason": "orphan_wallet_no_points_ledger",
            }
        ),
        "target_entity_id": "",
        "expiry_date": "",
        "created_by": ins["user_id"],
        "dedup_key": f"jorakay-orphan-{ins['mongo_id']}",
        "mongo_id_ledger": "",
        "created_at": "2026-06-15T00:00:00+00:00",
        "reason": "orphan_wallet_no_points_ledger",
    }


def main() -> None:
    class_rows = json.loads((DATA / "classification-all-153.json").read_text())
    pattern_map = {}
    rem_csv = ROOT / "remaining-138-classification.csv"
    if rem_csv.exists():
        for r in csv.DictReader(rem_csv.open()):
            pattern_map[r["mongo_id"]] = r["primary_pattern"]

    live = load_live_snapshot()
    earn_raw = load_earn_rows()
    native_raw = load_native_burns()

    earns_by_user: dict[str, list[EarnRow]] = defaultdict(list)
    for r in earn_raw:
        mid = r.get("member_mongo") or r.get("mongo_id")
        earns_by_user[mid].append(
            EarnRow(
                ledger_id=str(r["ledger_id"]),
                mongo_id=r.get("mongo_id"),
                created_at=str(r.get("created_at") or r.get("created_date") or ""),
                amount=fnum(r["amount"]),
                current_deductible=fnum(r.get("current_deductible")),
                stg_mongo_balance=(
                    None
                    if r.get("stg_mongo_balance") is None
                    else fnum(r["stg_mongo_balance"])
                ),
                is_native=bool(r.get("is_native_earn")),
                expiry_date=r.get("expiry_date"),
            )
        )

    native_by_user: dict[str, list[dict]] = defaultdict(list)
    for r in native_raw:
        mid = r.get("member_mongo")
        if mid:
            native_by_user[mid].append(r)

    pilot15 = PILOT15
    results = []
    row_level = []
    wallet_updates = []
    inserts = []
    errors = []

    for row in class_rows:
        row = dict(row)
        row["primary_pattern"] = pattern_for_row(row, pattern_map)
        try:
            out = process_user_live(row, earns_by_user.get(row["mongo_id"], []), live)
            results.append(out)
            cohort = "pilot_15" if row["mongo_id"] in pilot15 else "remaining_138"
            for e in out["earn_rows"]:
                if abs(e.target - e.current_deductible) > EPS:
                    row_level.append(
                        {
                            "cohort": cohort,
                            "mongo_id": row["mongo_id"],
                            "user_id": out["user_id"],
                            "ledger_id": e.ledger_id,
                            "mongo_earn_id": e.mongo_id or "",
                            "current_deductible": e.current_deductible,
                            "target_deductible": round(e.target, 2),
                            "reason": e.reason,
                        }
                    )
            if out.get("wallet_update") not in (None, 0) and abs(out["wallet_update"]) > EPS:
                wallet_updates.append(
                    {
                        "cohort": cohort,
                        "mongo_id": row["mongo_id"],
                        "user_id": out["user_id"],
                        "wallet_before": out["wallet_now"],
                        "wallet_after": out["wallet_target"],
                        "wallet_update_delta": out["wallet_update"],
                        "reason": out["fix_class"],
                    }
                )
            for ins in out.get("inserts", []):
                inserts.append(build_insert_row(ins, out["wallet_now"]))
        except Exception as ex:
            errors.append({"mongo_id": row["mongo_id"], "error": str(ex)})

    fetched = live.get("fetched_at", "staging-fallback")
    user_targets = {
        "merchant_id": MERCHANT_PG,
        "mongo_merchant_ref": "649e9524f43a5fc2f9705850",
        "live_mongo_fetched_at": fetched,
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
                "mongo_headline_live": u.get("mongo_headline_live"),
                "mongo_headline_stg": u.get("mongo_headline_stg"),
            }
            for u in results
        ],
        "errors": errors,
    }

    DATA.mkdir(parents=True, exist_ok=True)
    (DATA / "user-targets-all-153.json").write_text(json.dumps(user_targets, indent=2))

    with (DATA / "row-level-targets-all-153.csv").open("w", newline="") as f:
        w = csv.DictWriter(
            f,
            fieldnames=[
                "cohort",
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

    with (DATA / "wallet-updates-all-153.csv").open("w", newline="") as f:
        w = csv.DictWriter(
            f,
            fieldnames=[
                "cohort",
                "mongo_id",
                "user_id",
                "wallet_before",
                "wallet_after",
                "wallet_update_delta",
                "reason",
            ],
        )
        w.writeheader()
        w.writerows(wallet_updates)

    ins_fields = list(inserts[0].keys()) if inserts else []
    if inserts:
        with (DATA / "ledger-inserts-all-153.csv").open("w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=ins_fields)
            w.writeheader()
            w.writerows(inserts)

    end_state = []
    chg = defaultdict(int)
    for r in row_level:
        chg[r["mongo_id"]] += 1
    for u in results:
        end_state.append(
            {
                "mongo_id": u["mongo_id"],
                "user_id": u["user_id"],
                "wallet_before": u["wallet_now"],
                "wallet_after": u["wallet_target"],
                "wallet_update_delta": u["wallet_update"] or 0,
                "lots_before": next(
                    (fnum(r["lots"]) for r in class_rows if r["mongo_id"] == u["mongo_id"]),
                    0,
                ),
                "lots_after": u["lots_target"],
                "fix_class": u["fix_class"],
                "earn_rows_to_update": chg.get(u["mongo_id"], 0),
                "earn_rows_to_insert": 1 if u["fix_class"] == "insert_earn_orphan_wallet" else 0,
                "review_flags": ";".join(u.get("review_flags") or []),
            }
        )
    with (DATA / "user-end-state-all-153.csv").open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(end_state[0].keys()))
        w.writeheader()
        w.writerows(end_state)

    md = f"""# Jorakay — apply pack (153 users)

**Generated:** {datetime.now(timezone.utc).strftime("%Y-%m-%d")}  
**Live Mongo snapshot:** `{fetched}`

| Artifact | Rows |
|----------|------|
| `data/row-level-targets-all-153.csv` | {len(row_level)} earn UPDATEs |
| `data/wallet-updates-all-153.csv` | {len(wallet_updates)} wallet UPDATEs |
| `data/ledger-inserts-all-153.csv` | {len(inserts)} earn INSERTs |
| `data/user-end-state-all-153.csv` | {len(end_state)} users |

Errors: {len(errors)}
"""
    (ROOT / "DATA-ADJUSTMENT-MANIFEST-ALL-153.md").write_text(md)

    print("users", len(results))
    print("earn updates", len(row_level))
    print("wallet updates", len(wallet_updates))
    print("inserts", len(inserts))
    print("errors", len(errors))
    print("live mongo", fetched)


if __name__ == "__main__":
    main()
