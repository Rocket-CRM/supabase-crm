#!/usr/bin/env python3
"""Copy latest Mongo MCP export JSON into live-mongo-snapshot.json for build-apply-pack-all-153.py."""

from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data"
EXPORT_ROOT = Path.home() / ".mongodb" / "mongodb-mcp" / "exports"


def load_export_docs(path: Path) -> list[dict]:
    raw = json.loads(path.read_text())
    if isinstance(raw, list):
        return raw
    if isinstance(raw, dict) and "documents" in raw:
        return raw["documents"]
    return [raw]


def find_export(title_substr: str) -> Path | None:
    if not EXPORT_ROOT.exists():
        return None
    candidates: list[Path] = []
    for p in EXPORT_ROOT.glob("*/*.json"):
        if title_substr in p.name or title_substr in p.read_text(errors="ignore")[:500]:
            candidates.append(p)
    if not candidates:
        # fallback: largest recent json under exports (given export is huge)
        candidates = list(EXPORT_ROOT.glob("*/*.json"))
    if not candidates:
        return None
    return max(candidates, key=lambda p: p.stat().st_mtime)


def main() -> None:
    headlines_path = DATA / "live-mongo-headlines-export.json"
    given_path = DATA / "live-mongo-given-export.json"

    # Merge optional per-batch headline files (live-mongo/headlines-batch-*.json)
    batch_heads = sorted((DATA / "live-mongo").glob("headlines-batch-*.json"))
    if batch_heads and not headlines_path.exists():
        merged: list[dict] = []
        for p in batch_heads:
            merged.extend(json.loads(p.read_text()))
        headlines_path.write_text(json.dumps(merged, indent=2))
        print("merged headlines batches ->", headlines_path, "rows", len(merged))

    # Prefer explicit paths if user copied MCP export output here
    if not headlines_path.exists():
        src = find_export("jorakay-drift-headlines-all-153")
        if src:
            headlines_path.write_bytes(src.read_bytes())
            print("copied headlines from", src)
    if not given_path.exists():
        src = find_export("jorakay-drift-given-all-153")
        if src:
            given_path.write_bytes(src.read_bytes())
            print("copied given from", src)

    if not headlines_path.exists() or not given_path.exists():
        raise SystemExit(
            "Missing live Mongo exports. Run Mongo MCP export for "
            "data/mongo-pipeline-headlines-all.json and mongo-pipeline-given-all.json "
            "then copy to data/live-mongo-headlines-export.json and data/live-mongo-given-export.json"
        )

    headlines_docs = load_export_docs(headlines_path)
    given_docs = load_export_docs(given_path)

    point_balance_by_user: dict[str, float] = {}
    for d in headlines_docs:
        uid = d.get("userId") or (d.get("_id", {}) or {}).get("$oid")
        if uid:
            point_balance_by_user[str(uid)] = float(d.get("pointBalance") or 0)

    given_balance_by_point_id: dict[str, float] = {}
    given_meta_by_point_id: dict[str, dict] = {}
    for d in given_docs:
        pid = d.get("pointId") or (d.get("_id", {}) or {}).get("$oid")
        if not pid:
            continue
        pid = str(pid)
        given_balance_by_point_id[pid] = float(d.get("balance") or 0)
        given_meta_by_point_id[pid] = {
            "userId": d.get("userId"),
            "giveFrom": d.get("giveFrom"),
            "note": d.get("note"),
            "createdAt": d.get("createdAt"),
            "expiredDate": d.get("expiredDate"),
        }

    snapshot = {
        "source": "loyaltydb via user-mongodb MCP export",
        "fetched_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%MZ"),
        "merchant_mongo_id": "649e9524f43a5fc2f9705850",
        "point_balance_by_user": point_balance_by_user,
        "given_balance_by_point_id": given_balance_by_point_id,
        "given_meta_by_point_id": given_meta_by_point_id,
    }
    out = DATA / "live-mongo-snapshot.json"
    out.write_text(json.dumps(snapshot, indent=2))
    print("wrote", out)
    print("users", len(point_balance_by_user), "given rows", len(given_balance_by_point_id))


if __name__ == "__main__":
    main()
