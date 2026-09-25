#!/usr/bin/env python3
"""Compare staging exports vs live-mongo-snapshot.json (no Mongo calls)."""

from __future__ import annotations

import csv
import json
import re
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data"
EPS = 0.01


def fnum(x) -> float:
    if x is None or x == "":
        return 0.0
    return float(x)


def parse_sql_json(path: Path) -> list[dict]:
    raw = json.loads(path.read_text())
    if isinstance(raw, list):
        return raw
    if isinstance(raw, dict):
        outer = raw
        inner = outer.get("result", raw)
        if isinstance(inner, str):
            m = re.search(r"\[.*\]", inner, re.S)
            return json.loads(m.group(0)) if m else []
        return inner if isinstance(inner, list) else []
    return []


def load_earn_rows() -> list[dict]:
    rows: list[dict] = []
    for name in ("earn-rows-export.json", "remaining-138-earn-rows.json"):
        p = DATA / name
        if p.exists():
            rows.extend(parse_sql_json(p))
    return rows


def main() -> None:
    snap = json.loads((DATA / "live-mongo-snapshot.json").read_text())
    pb_user = snap.get("point_balance_by_user") or {}
    given_by_pid = snap.get("given_balance_by_point_id") or {}

    classification = json.loads((DATA / "classification-all-153.json").read_text())
    headline_rows: list[dict] = []
    for row in classification:
        mid = row["mongo_id"]
        stg = fnum(row.get("stg_point_balance"))
        live = pb_user.get(mid)
        diff = None
        flag = ""
        if live is None:
            flag = "live_missing"
        else:
            live_f = fnum(live)
            diff = live_f - stg
            if abs(diff) > EPS:
                flag = "stg_live_mismatch"
        headline_rows.append(
            {
                "mongo_id": mid,
                "stg_point_balance": stg,
                "live_point_balance": live,
                "diff": diff,
                "flag": flag,
            }
        )

    headline_mismatches = [r for r in headline_rows if r["flag"]]

    earn_mismatches: list[dict] = []
    for e in load_earn_rows():
            pid = e.get("mongo_id")
            if not pid:
                continue
            stg = e.get("stg_mongo_balance")
            live = given_by_pid.get(str(pid))
            stg_f = fnum(stg)
            flag = ""
            if live is None:
                flag = "live_missing"
            else:
                live_f = fnum(live)
                if abs(live_f - stg_f) > EPS:
                    flag = "stg_live_mismatch"
            if flag:
                earn_mismatches.append(
                    {
                        "member_mongo": e.get("member_mongo"),
                        "ledger_id": e.get("ledger_id"),
                        "mongo_id": pid,
                        "stg_mongo_balance": stg_f,
                        "live_balance": live,
                        "diff": (fnum(live) - stg_f) if live is not None else None,
                        "flag": flag,
                    }
                )

    by_user: dict[str, int] = defaultdict(int)
    for m in earn_mismatches:
        by_user[str(m["member_mongo"])] += 1
    top_users = sorted(by_user.items(), key=lambda x: -x[1])[:15]

    # markdown report
    lines = [
        "# Mongo verify report (staging vs live snapshot)",
        "",
        f"Snapshot: `{DATA / 'live-mongo-snapshot.json'}`",
        f"Fetched at: {snap.get('fetched_at', '?')}",
        f"Users in snapshot: {len(pb_user)}",
        f"GIVEN rows in snapshot: {len(given_by_pid)}",
        "",
        "## A) Headline (classification stg_point_balance vs live)",
        "",
        f"- Users checked: {len(headline_rows)}",
        f"- Mismatches / missing: **{len(headline_mismatches)}**",
        "",
    ]
    if headline_mismatches:
        lines.append("| mongo_id | stg | live | diff | flag |")
        lines.append("|----------|-----|------|------|------|")
        for r in headline_mismatches:
            lines.append(
                f"| {r['mongo_id']} | {r['stg_point_balance']} | {r['live_point_balance']} | {r['diff']} | {r['flag']} |"
            )
    else:
        lines.append("_No headline mismatches (|diff| ≤ 0.01 and live present for all)._")

    lines.extend(
        [
            "",
            "## B) Earn-level (migrated earns with mongo_id)",
            "",
            f"- Mismatches / missing: **{len(earn_mismatches)}**",
            "",
        ]
    )
    if top_users:
        lines.append("Top users by mismatch count:")
        lines.append("")
        for uid, cnt in top_users:
            lines.append(f"- `{uid}`: {cnt}")
    if earn_mismatches and len(earn_mismatches) <= 50:
        lines.append("")
        lines.append("| member_mongo | point mongo_id | stg | live | diff |")
        lines.append("|--------------|----------------|-----|------|------|")
        for m in earn_mismatches[:50]:
            lines.append(
                f"| {m['member_mongo']} | {m['mongo_id']} | {m['stg_mongo_balance']} | {m['live_balance']} | {m['diff']} |"
            )

    (DATA / "mongo-verify-report.md").write_text("\n".join(lines) + "\n")

    csv_path = DATA / "mongo-verify-mismatches.csv"
    with csv_path.open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["kind", "mongo_id", "detail", "stg", "live", "diff", "flag"])
        for r in headline_mismatches:
            w.writerow(
                [
                    "headline",
                    r["mongo_id"],
                    "",
                    r["stg_point_balance"],
                    r["live_point_balance"],
                    r["diff"],
                    r["flag"],
                ]
            )
        for m in earn_mismatches:
            w.writerow(
                [
                    "earn",
                    m["mongo_id"],
                    m["member_mongo"],
                    m["stg_mongo_balance"],
                    m["live_balance"],
                    m["diff"],
                    m["flag"],
                ]
            )

    print("headline mismatches", len(headline_mismatches))
    print("earn mismatches", len(earn_mismatches))
    print("wrote", DATA / "mongo-verify-report.md")
    print("wrote", csv_path)


if __name__ == "__main__":
    main()
