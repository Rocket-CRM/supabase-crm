#!/usr/bin/env python3
"""Execute apply-batch-*.sql against prod via Supabase Management API."""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data"
PROJECT = "wkevmsedchftztoolkmi"


def run_sql(sql: str) -> list:
    token = os.environ["SUPABASE_ACCESS_TOKEN"]
    req = urllib.request.Request(
        f"https://api.supabase.com/v1/projects/{PROJECT}/database/query",
        data=json.dumps({"query": sql}).encode(),
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=300) as resp:
        body = resp.read().decode()
        if not body.strip():
            return []
        return json.loads(body)


def main() -> None:
    batches = sorted(DATA.glob("apply-batch-*.sql"))
    if not batches:
        raise SystemExit("no apply-batch-*.sql files; run apply-all-153.py first")
    for i, path in enumerate(batches):
        sql = path.read_text()
        print(f"batch {i} ({path.name}) bytes={len(sql)} ...", flush=True)
        try:
            run_sql(sql)
        except urllib.error.HTTPError as e:
            err = e.read().decode()
            print(f"FAILED batch {i}: {err}", file=sys.stderr)
            raise SystemExit(1) from e
        print(f"batch {i} OK", flush=True)
    print("all batches applied")


if __name__ == "__main__":
    main()
