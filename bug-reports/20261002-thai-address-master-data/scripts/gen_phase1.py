#!/usr/bin/env python3
"""Generate phase1.sql and verify.sql for Thai address master data fix (Plan.md Phase 1)."""
from __future__ import annotations

import csv
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data"
OUT_SQL = ROOT / "phase1.sql"
OUT_VERIFY = ROOT / "verify.sql"

REF_COMMIT = "7d689e4"
BANGKOK_LIVE_PROVINCE_ID = 10

# Plan.md step 3 — verified remap targets (handoff table).
USER_ADDRESS_REMAPS = [
    {
        "from_sub": "104701",
        "to_sub": "104702",
        "to_district": None,
        "expect_rows": 6,
    },
    {
        "from_sub": "105001",
        "to_sub": "105002",
        "to_district": None,
        "expect_rows": 3,
    },
    {
        "from_sub": "110105",
        "to_sub": "110116",
        "to_district": None,
        "expect_rows": 4,
    },
    {
        "from_sub": "402615",
        "to_sub": "402902",
        "to_district": "4029",
        "expect_rows": 1,
    },
    {
        "from_sub": "530306",
        "to_sub": "530407",
        "to_district": "5304",
        "expect_rows": 48,
    },
]

DELETE_SUBDISTRICT_IDS = [
    "104701",
    "105001",
    "110105",
    "402602",
    "402608",
    "402615",
    "440828",
    "490501",
    "530306",
]
DELETE_DISTRICT_IDS = ["4026"]

PHASE2_HELD_ZIP_SUBDISTRICTS = ("200409", "920221", "920222", "920414")
CORRUPT_EXCLUDE = {"850406", "200409"}

# Live code holds a neighbouring subdistrict's name; resolve against DOPA in Phase 2.
CODE_SHIFT_HOLD_INSERTS = {"830104", "500108", "410116"}
CODE_SHIFT_HOLD_NAMES = {"110401"}
CODE_SHIFT_HOLD_EN = {"380103", "410111", "500109", "830105"}
# Reference EN is wrong or disagrees with our Thai name.
DISTRICT_EN_HOLD = {"3801", "6008", "6011", "7107"}


def sql_str(val: str | None) -> str:
    if val is None:
        return "NULL"
    return "'" + str(val).replace("'", "''") + "'"


def load_json(name: str):
    path = DATA / name
    if not path.exists():
        sys.exit(f"Missing required data file: {path}")
    return json.loads(path.read_text(encoding="utf-8"))


def index_ref(rows: list[dict], key="id") -> dict[str, dict]:
    out: dict[str, dict] = {}
    for row in rows:
        rid = row[key]
        if isinstance(rid, int):
            rid = str(rid)
        out[rid] = row
    return out


def district_prefix_th(live_province_id: int) -> str:
    return "เขต" if live_province_id == BANGKOK_LIVE_PROVINCE_ID else "อ."


def subdistrict_prefix_th(live_province_id: int) -> str:
    return "แขวง" if live_province_id == BANGKOK_LIVE_PROVINCE_ID else "ต."


def prefixed_name(prefix: str, bare: str) -> str:
    bare = (bare or "").strip()
    if bare.startswith(prefix):
        return bare
    return f"{prefix}{bare}"


def main() -> None:
    ref_prov = index_ref(load_json("ref_province.json"))
    ref_dist = index_ref(load_json("ref_district.json"))
    ref_sub = index_ref(load_json("ref_sub_district.json"))

    live_provinces = {p["id"]: p for p in load_json("live_provinces.json")}
    live_districts = {d["id"]: d for d in load_json("live_districts.json")}
    live_sub_ids = set(load_json("live_subdistrict_ids.json")["ids"])
    live_en_zero = load_json("live_subdistrict_en_zero.json")["ids"]
    remap_counts = load_json("live_user_address_remap_counts.json")

    csv_rows = list(csv.DictReader(open(DATA / "DrPong_address_data_issues.csv", encoding="utf-8-sig")))
    missing_sub_ids = sorted(
        r["code"]
        for r in csv_rows
        if r["result"] == "ไม่มีในเว็บ" and r["level"] == "subdistrict"
    )
    if len(missing_sub_ids) != 85:
        sys.exit(f"Expected 85 missing subdistricts in CSV, got {len(missing_sub_ids)}")
    missing_sub_ids = [i for i in missing_sub_ids if i not in CODE_SHIFT_HOLD_INSERTS]

    district_en_ids = sorted(
        {
            r["code"]
            for r in csv_rows
            if r["level"] == "district"
            and "ชื่ออังกฤษไม่ตรง" in r["result"]
            and r["code"] not in DISTRICT_EN_HOLD
        }
    )
    corrupt_ids = sorted(
        r["code"]
        for r in csv_rows
        if r["result"] == "ข้อมูลเสีย"
        and r["code"] not in CORRUPT_EXCLUDE
        and r["code"] not in CODE_SHIFT_HOLD_NAMES
    )

    # --- sanity (pre-apply) ---
    absent = [i for i in missing_sub_ids if i in live_sub_ids]
    if absent:
        sys.exit(f"Sanity fail: missing-subdistrict codes already live: {absent[:5]}… ({len(absent)} total)")

    remap_targets = {m["to_sub"] for m in USER_ADDRESS_REMAPS}
    missing_targets = [t for t in remap_targets if t not in missing_sub_ids and t not in live_sub_ids]
    if missing_targets:
        sys.exit(f"Sanity fail: remap targets neither live nor in insert set: {missing_targets}")

    for m in USER_ADDRESS_REMAPS:
        key = m["from_sub"]
        exp = m["expect_rows"]
        act = remap_counts.get(key)
        if act != exp:
            sys.exit(f"Sanity fail: user_address count for {key}: expected {exp}, live snapshot {act}")
    if remap_counts.get("district_4026") != 1:
        sys.exit("Sanity fail: district_code 4026 user_address count != 1")

    stats: dict[str, int | list[str]] = {}

    lines: list[str] = []
    lines.append("-- Generated by scripts/gen_phase1.py — fix_thai_address_master_phase1")
    lines.append(f"-- Reference: kongvut/thai-province-data @ {REF_COMMIT}")
    lines.append("")

    # Backup
    remapped_subs = [m["from_sub"] for m in USER_ADDRESS_REMAPS]
    lines.append("-- Backup (RLS enabled, no policies)")
    lines.append(
        "CREATE TABLE public._bak_20261002_user_address_th_remap AS"
        "\nSELECT id, province_code, district_code, subdistrict_code, city, district, subdistrict"
        "\nFROM public.user_address"
        f"\nWHERE subdistrict_code IN ({', '.join(sql_str(x) for x in remapped_subs)})"
        "\n   OR district_code = '4026';"
    )
    lines.append("ALTER TABLE public._bak_20261002_user_address_th_remap ENABLE ROW LEVEL SECURITY;")

    backup_sub_ids = sorted(
        set(DELETE_SUBDISTRICT_IDS)
        | set(corrupt_ids)
        | set(live_en_zero)
    )
    backup_dist_ids = sorted(set(DELETE_DISTRICT_IDS) | set(district_en_ids))
    lines.append(
        "CREATE TABLE public._bak_20261002_address_th_subdistrict AS"
        "\nSELECT * FROM public.address_th_subdistrict"
        f"\nWHERE id IN ({', '.join(sql_str(x) for x in backup_sub_ids)});"
    )
    lines.append("ALTER TABLE public._bak_20261002_address_th_subdistrict ENABLE ROW LEVEL SECURITY;")
    lines.append(
        "CREATE TABLE public._bak_20261002_address_th_district AS"
        "\nSELECT * FROM public.address_th_district"
        f"\nWHERE id IN ({', '.join(sql_str(x) for x in backup_dist_ids)});"
    )
    lines.append("ALTER TABLE public._bak_20261002_address_th_district ENABLE ROW LEVEL SECURITY;")
    lines.append(
        "CREATE TABLE public._bak_20261002_address_th_province AS"
        "\nSELECT * FROM public.address_th_province WHERE id = '11';"
    )
    lines.append("ALTER TABLE public._bak_20261002_address_th_province ENABLE ROW LEVEL SECURITY;")
    lines.append("")

    # Step 1 — district 4029
    ref_d4029 = ref_dist["4029"]
    live_p40 = live_provinces.get("40") or next(
        (live_provinces[str(d["province_id"])] for d in live_districts.values() if str(d["id"]).startswith("40")),
        None,
    )
    if not live_p40:
        live_p40 = {"province_name_th": "จ.ขอนแก่น", "province_name_en": "Khon Kaen"}
    max_sort = max(int(d["sort_order"]) for d in live_districts.values() if d["province_id"] == 40)
    sort_4029 = max_sort + 1
    d_th = prefixed_name("อ.", ref_d4029["name"]["th"])
    d_en = ref_d4029["name"]["en"]
    lines.append("-- Step 1: insert district 4029")
    lines.append(
        "INSERT INTO public.address_th_district (id, district_name_th, district_name_en, province_id,"
        " province_name_th, province_name_en, sort_order)"
        f"\nVALUES ({sql_str('4029')}, {sql_str(d_th)}, {sql_str(d_en)}, 40,"
        f" {sql_str(live_p40['province_name_th'])}, {sql_str(live_p40['province_name_en'])}, {sort_4029});"
    )
    stats["districts_inserted"] = 1

    # Step 2 — 85 subdistricts
    insert_values: list[str] = []
    for sid in missing_sub_ids:
        rs = ref_sub.get(sid)
        if not rs:
            sys.exit(f"No reference subdistrict for insert id {sid}")
        did = str(rs["district_id"])
        if did == "4029":
            ld = {
                "province_id": 40,
                "province_name_th": live_provinces.get("40", {}).get("province_name_th", "จ.ขอนแก่น"),
                "province_name_en": live_provinces.get("40", {}).get("province_name_en", "Khon Kaen"),
                "district_name_th": prefixed_name("อ.", ref_d4029["name"]["th"]),
                "district_name_en": ref_d4029["name"]["en"],
            }
        else:
            ld = live_districts.get(did)
            if not ld:
                sys.exit(f"No live district {did} for subdistrict {sid}")
        prov_id = int(ld["province_id"])
        p_th = ld.get("province_name_th") or live_provinces.get(str(prov_id), {}).get("province_name_th")
        p_en = ld.get("province_name_en") or live_provinces.get(str(prov_id), {}).get("province_name_en")
        d_th_row = ld["district_name_th"]
        d_en_row = ld["district_name_en"]
        if did == "4029":
            d_th_row = prefixed_name("อ.", ref_d4029["name"]["th"])
            d_en_row = ref_d4029["name"]["en"]
        sp = subdistrict_prefix_th(prov_id)
        s_th = prefixed_name(sp, rs["name"]["th"])
        s_en = rs["name"]["en"]
        zip_code = int(rs["zip_code"])
        insert_values.append(
            f"({sql_str(sid)}, {zip_code}, {sql_str(s_th)}, {sql_str(s_en)}, {did}::bigint,"
            f" {sql_str(d_th_row)}, {sql_str(d_en_row)})"
        )
    lines.append(f"-- Step 2: insert {len(insert_values)} missing subdistricts")
    lines.append(
        "INSERT INTO public.address_th_subdistrict"
        " (id, zip_code, subdistrict_name_th, subdistrict_name_en, district_id, district_name_th, district_name_en)"
        "\nVALUES\n  " + ",\n  ".join(insert_values) + ";"
    )
    stats["subdistricts_inserted"] = len(insert_values)

    # Step 3 — user_address remaps (text mirrors match master prefixed names)
    lines.append("-- Step 3: re-point user_address codes and text mirrors")
    remap_name_cache: dict[str, tuple[str, str | None]] = {}

    def master_sub(sub_id: str, dist_override: str | None = None) -> tuple[str, str, str]:
        rs = ref_sub[sub_id]
        did = dist_override or str(rs["district_id"])
        if did == "4029":
            dist_th = prefixed_name("อ.", ref_d4029["name"]["th"])
            ld = {"province_id": 40}
        elif did in live_districts:
            ld = live_districts[did]
            dist_th = ld["district_name_th"]
        else:
            ld = live_districts[str(rs["district_id"])]
            dist_th = ld["district_name_th"]
        prov_id = int(ld["province_id"])
        sp = subdistrict_prefix_th(prov_id)
        sub_th = prefixed_name(sp, rs["name"]["th"])
        return sub_id, sub_th, dist_th

    ua_updates = 0
    for m in USER_ADDRESS_REMAPS:
        to_sub, sub_th, dist_th = master_sub(m["to_sub"], m.get("to_district"))
        sets = [
            f"subdistrict_code = {sql_str(to_sub)}",
            f"subdistrict = {sql_str(sub_th)}",
        ]
        if m.get("to_district"):
            sets.append(f"district_code = {sql_str(m['to_district'])}")
            sets.append(f"district = {sql_str(dist_th)}")
        lines.append(
            "UPDATE public.user_address"
            f"\nSET {', '.join(sets)}"
            f"\nWHERE subdistrict_code = {sql_str(m['from_sub'])};"
        )
        ua_updates += m["expect_rows"]
    lines.append(
        "UPDATE public.user_address"
        "\nSET district_code = '4029', district = "
        + sql_str(prefixed_name("อ.", ref_d4029["name"]["th"]))
        + "\nWHERE district_code = '4026';"
    )
    ua_updates += 1
    stats["user_address_rows_remapped"] = ua_updates

    # Step 4 — assert + delete invented masters
    lines.append("-- Step 4: assert no user_address references, then delete invented rows")
    lines.append(
        "DO $$\nDECLARE n integer;\nBEGIN"
        f"\n  SELECT COUNT(*) INTO n FROM public.user_address"
        f"\n  WHERE subdistrict_code IN ({', '.join(sql_str(x) for x in DELETE_SUBDISTRICT_IDS)})"
        "\n     OR district_code = '4026';"
        "\n  IF n > 0 THEN"
        "\n    RAISE EXCEPTION 'user_address still references deleted Thai admin codes (% rows)', n;"
        "\n  END IF;\nEND $$;"
    )
    lines.append(
        "DELETE FROM public.address_th_subdistrict"
        f" WHERE id IN ({', '.join(sql_str(x) for x in DELETE_SUBDISTRICT_IDS)});"
    )
    lines.append(
        "DELETE FROM public.address_th_district"
        f" WHERE id IN ({', '.join(sql_str(x) for x in DELETE_DISTRICT_IDS)});"
    )
    stats["subdistricts_deleted"] = len(DELETE_SUBDISTRICT_IDS)
    stats["districts_deleted"] = len(DELETE_DISTRICT_IDS)

    # Step 5 — corrupt Thai names (name only)
    lines.append("-- Step 5: fix corrupt subdistrict_name_th (exclude 850406, 200409, 110401)")
    corrupt_updates = 0
    for sid in corrupt_ids:
        rs = ref_sub.get(sid)
        if not rs:
            stats.setdefault("corrupt_skipped_no_ref", []).append(sid)
            continue
        ld = live_districts.get(str(rs["district_id"]))
        prov_id = int(ld["province_id"]) if ld else 0
        sp = subdistrict_prefix_th(prov_id)
        new_th = prefixed_name(sp, rs["name"]["th"])
        lines.append(
            f"UPDATE public.address_th_subdistrict SET subdistrict_name_th = {sql_str(new_th)} WHERE id = {sql_str(sid)};"
        )
        corrupt_updates += 1
    stats["corrupt_names_fixed"] = corrupt_updates

    # Step 6 — English names
    lines.append("-- Step 6a: district English names (CSV ชื่ออังกฤษไม่ตรง)")
    dist_en_changed: list[str] = []
    for did in district_en_ids:
        rd = ref_dist.get(did)
        if not rd:
            stats.setdefault("district_en_skipped_no_ref", []).append(did)
            continue
        new_en = rd["name"]["en"]
        lines.append(
            f"UPDATE public.address_th_district SET district_name_en = {sql_str(new_en)} WHERE id = {sql_str(did)};"
        )
        dist_en_changed.append(did)
    stats["district_en_fixed"] = len(dist_en_changed)

    lines.append("-- Step 6b: province 11 → Samut Prakan")
    lines.append(
        "UPDATE public.address_th_province SET province_name_en = 'Samut Prakan' WHERE id = '11';"
    )
    stats["provinces_en_fixed"] = 1

    lines.append("-- Step 6c: subdistrict_name_en = '0' → reference (skip if no ref match)")
    en_zero_updates: list[str] = []
    en_zero_skipped: list[str] = []
    for sid in live_en_zero:
        if sid in DELETE_SUBDISTRICT_IDS or sid in CODE_SHIFT_HOLD_EN:
            continue
        rs = ref_sub.get(sid)
        if not rs:
            en_zero_skipped.append(sid)
            continue
        new_en = rs["name"]["en"]
        en_zero_updates.append(f"({sql_str(sid)}, {sql_str(new_en)})")
    if en_zero_updates:
        lines.append(
            "UPDATE public.address_th_subdistrict AS s"
            "\nSET subdistrict_name_en = v.name_en"
            "\nFROM (VALUES\n  "
            + ",\n  ".join(en_zero_updates)
            + "\n) AS v(id, name_en)"
            "\nWHERE s.id = v.id AND s.subdistrict_name_en = '0';"
        )
    stats["subdistrict_en_zero_fixed"] = len(en_zero_updates)
    stats["subdistrict_en_zero_skipped_no_ref"] = en_zero_skipped

    # Denormalised parent names on children
    lines.append("-- Step 6d: refresh denormalised parent EN/TH on child rows")
    lines.append(
        "UPDATE public.address_th_district AS d"
        "\nSET province_name_en = p.province_name_en,"
        "\n    province_name_th = p.province_name_th"
        "\nFROM public.address_th_province AS p"
        "\nWHERE d.province_id = p.id::bigint AND p.id = '11';"
    )
    lines.append(
        "UPDATE public.address_th_subdistrict AS s"
        "\nSET district_name_en = d.district_name_en,"
        "\n    district_name_th = d.district_name_th"
        "\nFROM public.address_th_district AS d"
        "\nWHERE s.district_id = d.id::bigint"
        f"\n  AND d.id IN ({', '.join(sql_str(x) for x in dist_en_changed)});"
    )
    lines.append(
        "UPDATE public.address_th_subdistrict AS s"
        "\nSET province_name_en = d.province_name_en,"
        "\n    province_name_th = d.province_name_th"
        "\nFROM public.address_th_district AS d"
        "\nWHERE s.district_id = d.id::bigint AND d.province_id = 11;"
    )
    # Subdistrict table has no province_name columns — only district denorm on subdistrict.
    # Remove erroneous province denorm on subdistrict if columns absent (live schema check).
    # Live subdistrict columns: no province_name_* — drop last statement.
    lines.pop()  # remove province denorm on subdistrict

    lines.append(
        "UPDATE public.address_th_subdistrict AS s"
        "\nSET district_name_en = d.district_name_en,"
        "\n    district_name_th = d.district_name_th"
        "\nFROM public.address_th_district AS d"
        "\nWHERE s.district_id = d.id::bigint AND d.id = '4029';"
    )

    OUT_SQL.write_text("\n".join(lines) + "\n", encoding="utf-8")

    # verify.sql
    held = ", ".join(sql_str(x) for x in PHASE2_HELD_ZIP_SUBDISTRICTS)
    verify = f"""-- Post-apply checks (Plan.md) — each query returns expected vs actual
-- Bangkok subdistrict count → 180
SELECT 'bangkok_subdistrict_count' AS check_name, 180 AS expected, COUNT(*)::int AS actual
FROM public.address_th_subdistrict s
JOIN public.address_th_district d ON s.district_id = d.id::bigint
WHERE d.province_id = {BANGKOK_LIVE_PROVINCE_ID};

-- Chatuchak (1030) subdistrict count → 5
SELECT 'chatuchak_subdistrict_count' AS check_name, 5 AS expected, COUNT(*)::int AS actual
FROM public.address_th_subdistrict WHERE district_id = 1030;

-- No doubled ต.ต. prefix
SELECT 'no_doubled_t_prefix' AS check_name, 0 AS expected, COUNT(*)::int AS actual
FROM public.address_th_subdistrict
WHERE subdistrict_name_th LIKE 'ต.ต.%';

-- No replacement char in names
SELECT 'no_replacement_char' AS check_name, 0 AS expected, COUNT(*)::int AS actual
FROM public.address_th_subdistrict
WHERE subdistrict_name_th LIKE '%�%';

-- zip_code 0 or NULL except Phase 2 held codes
SELECT 'bad_zip_except_held' AS check_name, 0 AS expected, COUNT(*)::int AS actual
FROM public.address_th_subdistrict
WHERE (zip_code IS NULL OR zip_code = 0)
  AND id NOT IN ({held});

-- No subdistrict_name_en = '0'
SELECT 'no_en_zero_except_held' AS check_name, 0 AS expected, COUNT(*)::int AS actual
FROM public.address_th_subdistrict
WHERE subdistrict_name_en = '0'
  AND id NOT IN ('200409', '920221', '920222', '920414', '380103', '410111', '500109', '830105');

-- Phayao (province 56) districts: 9 distinct English names
SELECT 'phayao_distinct_district_en' AS check_name, 9 AS expected,
       COUNT(DISTINCT district_name_en)::int AS actual
FROM public.address_th_district
WHERE province_id = 56;

-- user_address must not reference deleted codes
SELECT 'user_address_deleted_codes' AS check_name, 0 AS expected, COUNT(*)::int AS actual
FROM public.user_address
WHERE subdistrict_code IN ({', '.join(sql_str(x) for x in DELETE_SUBDISTRICT_IDS)})
   OR district_code = '4026';

-- Province 11 English name
SELECT 'province_11_en' AS check_name, 'Samut Prakan' AS expected, province_name_en AS actual
FROM public.address_th_province WHERE id = '11';
"""
    OUT_VERIFY.write_text(verify, encoding="utf-8")

    if "--skip-regen-check" not in sys.argv:
        import subprocess

        first_bytes = OUT_SQL.read_bytes()
        subprocess.run(
            [sys.executable, __file__, "--skip-regen-check"],
            check=True,
            cwd=ROOT,
        )
        if first_bytes != OUT_SQL.read_bytes():
            sys.exit("Regeneration check failed: phase1.sql not byte-identical on second run")

    if "--skip-regen-check" in sys.argv:
        print(json.dumps({"paths": [str(OUT_SQL), str(OUT_VERIFY)], "stats": stats}, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
