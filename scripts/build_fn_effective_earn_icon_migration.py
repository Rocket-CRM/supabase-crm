#!/usr/bin/env python3
"""Build migration: fn_get_effective_earn_channels + icon_url. Reads base64 pg_get_functiondef from stdin JSON."""
from __future__ import annotations

import base64
import json
import sys
from pathlib import Path

PATCHES = [
    (
        "banner_urls text[], display_order integer",
        "banner_urls text[], icon_url text, display_order integer",
    ),
    (
        """      COALESCE(o.banner_urls, CASE WHEN ra.default_banner_url IS NOT NULL THEN ARRAY[ra.default_banner_url]::text[] ELSE NULL END) AS banner_urls,
      COALESCE(o.display_order, ra.sort_order, 0) AS display_order,""",
        """      COALESCE(o.banner_urls, CASE WHEN ra.default_banner_url IS NOT NULL THEN ARRAY[ra.default_banner_url]::text[] ELSE NULL END) AS banner_urls,
      COALESCE(o.icon_url, ra.default_icon_url) AS icon_url,
      COALESCE(o.display_order, ra.sort_order, 0) AS display_order,""",
    ),
    (
        """      ec.banner_urls,
      ec.display_order,""",
        """      ec.banner_urls,
      ec.icon_url,
      ec.display_order,""",
    ),
    (
        """    u.banner_urls,
    u.display_order,""",
        """    u.banner_urls,
    u.icon_url,
    u.display_order,""",
    ),
]

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "supabase/migrations/20260922144500_fn_get_effective_earn_channels_icon_url.sql"


def main() -> None:
    if len(sys.argv) > 1:
        payload = json.loads(Path(sys.argv[1]).read_text())
    else:
        payload = json.load(sys.stdin)

    if isinstance(payload, list):
        rows = payload
    else:
        rows = payload.get("result") if isinstance(payload, dict) else None
        if rows is None and isinstance(payload, dict):
            if "def_b64" in payload:
                rows = [payload]
            elif "def" in payload:
                rows = [payload]
            else:
                rows = [payload]

    if not rows:
        raise SystemExit("expected def or def_b64 in JSON")

    row = rows[0]
    if "def_b64" in row:
        def_text = base64.b64decode(row["def_b64"]).decode("utf-8")
    elif "def" in row:
        def_text = row["def"]
    else:
        raise SystemExit("expected def or def_b64 in JSON")

    for old, new in PATCHES:
        if old not in def_text:
            raise SystemExit(f"patch failed: missing {old[:60]!r}...")
        def_text = def_text.replace(old, new, 1)

    migration = (
        "-- fn_get_effective_earn_channels: expose icon_url for bff_get_earn_channels / Shopify hub\n"
        "-- Completes 20260922130000_earn_channel_icon_url (BFF already selects c.icon_url).\n\n"
        "DROP FUNCTION IF EXISTS public.fn_get_effective_earn_channels(uuid, text, boolean);\n\n"
        + def_text.replace("CREATE OR REPLACE FUNCTION", "CREATE FUNCTION", 1)
        + "\n"
    )
    OUT.write_text(migration)
    print(f"Wrote {OUT} ({OUT.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
