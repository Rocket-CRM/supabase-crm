#!/usr/bin/env python3
"""Her Hyness Reward marketplace gap fill — insert-only, claim-ready, no auto-award.

Path: POST marketplace-orders-backfill → fn_promote_marketplace_backfill.
Source of truth: platform create_time list minus order_ledger_mkp.
Shopee-only resume (Lazada/TikTok skipped). max_save stays at 50 (Shopee API cap).
"""
from __future__ import annotations

import datetime as dt
import json
import os
import time
import traceback
import urllib.error
import urllib.request
from pathlib import Path

BF = "https://wkevmsedchftztoolkmi.supabase.co/functions/v1/marketplace-orders-backfill"
PR = "https://wkevmsedchftztoolkmi.supabase.co/rest/v1/rpc/fn_promote_marketplace_backfill"
LEDGER = "https://wkevmsedchftztoolkmi.supabase.co/rest/v1/order_ledger_mkp"
MERCHANT = "ffe8519e-49a2-467b-a0ec-57d28ba8be49"
SUPPORT_SN = "260725JRE8WNNT"
SHOPS = {
    "lazada": "100184574113",
    "tiktok": "7495127669839399750",
    "shopee": "224882570",
}
# Bangkok 2026-07-01 00:00 → 2026-08-11 00:00
START = dt.datetime(2026, 6, 30, 17, tzinfo=dt.timezone.utc)
END = dt.datetime(2026, 8, 10, 17, tzinfo=dt.timezone.utc)

PROGRESS = Path("/tmp/herhyness-mkp-fill.progress")
PIDFILE = Path("/tmp/herhyness-mkp-fill.pid")


def detach():
    """Survive Cursor shell abort. Double-fork; fds already pointed at the log."""
    if os.getenv("HERHYNESS_NODAEMON") == "1":
        PIDFILE.write_text(str(os.getpid()))
        return
    if os.fork() > 0:
        os._exit(0)
    os.setsid()
    if os.fork() > 0:
        os._exit(0)
    PIDFILE.write_text(str(os.getpid()))


def load_anon() -> str:
    env = os.environ.get("CRM_SUPABASE_ANON_KEY") or os.environ.get("SUPABASE_ANON_KEY")
    if env:
        return env.strip()
    secrets = Path.home() / ".cursor" / "secrets.env"
    for line in secrets.read_text().splitlines():
        if line.startswith("CRM_SUPABASE_ANON_KEY="):
            return line.split("=", 1)[1].strip().strip('"').strip("'")
    raise SystemExit("missing CRM_SUPABASE_ANON_KEY")


ANON = load_anon()
HEADERS = {
    "Authorization": f"Bearer {ANON}",
    "apikey": ANON,
    "Content-Type": "application/json",
}


def log(*a):
    print(*a, flush=True)


def utc_label(unix: int) -> str:
    return dt.datetime.fromtimestamp(unix, dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def write_progress(obj: dict):
    PROGRESS.write_text(json.dumps(obj, ensure_ascii=False, indent=2) + "\n")


def post(url: str, body: dict, timeout: int):
    data = json.dumps(body).encode()
    req = urllib.request.Request(url, data=data, headers=HEADERS, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read()
            return json.loads(raw.decode() or "{}"), resp.status
    except urllib.error.HTTPError as e:
        raw = e.read()[:4000]
        text = raw.decode("utf-8", "replace")
        parsed = None
        try:
            parsed = json.loads(text)
        except Exception:
            parsed = {"error": f"http_{e.code}", "raw": text[:500]}
        return parsed, e.code
    except Exception as e:
        return {"error": str(e)[:400]}, 0


def is_fatal_platform_error(status: int, payload: dict) -> bool:
    """429 / Shopee API error / token error — stop immediately, do not retry."""
    if status == 429:
        return True
    err = str(payload.get("error") or "").lower()
    needles = (
        "429",
        "rate limit",
        "invalid_access_token",
        "invalid_acceess_token",
        "access_token_expired",
        "error_auth",
        "error_permission",
        "error_banned",
        "credentials_not_found",
        "shopee list error",
        "shopee detail error",
        "shopee list http",
        "shopee detail http",
    )
    return any(x in err for x in needles)


def is_rate_or_timeout(status: int, payload: dict) -> bool:
    if is_fatal_platform_error(status, payload):
        return False
    if status in (408, 502, 503, 504):
        return True
    err = str(payload.get("error") or "").lower()
    return any(x in err for x in ("504", "timeout", "timed out", "502", "503"))


def fatal_stop(platform: str, label: str, ge: int, lt: int, status: int, payload: dict, where: str) -> None:
    body = {
        "where": where,
        "platform": platform,
        "window": label,
        "ge": ge,
        "lt": lt,
        "cursor": payload.get("cursor") or payload.get("next_cursor"),
        "status": status,
        "error": payload.get("error"),
    }
    log("FATAL_STOP", json.dumps(body, ensure_ascii=False, default=str))
    write_progress({**body, "fatal": True, "updated_at": utc_label(int(time.time()))})
    raise SystemExit(2)


def dry_run(platform: str, shop: str, ge: int, lt: int):
    max_pages = 40 if platform == "shopee" else 20
    t0 = time.time()
    payload, status = post(
        BF,
        {
            "platform": platform,
            "shop_id": shop,
            "dry_run": True,
            "create_time_ge": ge,
            "create_time_lt": lt,
            "max_pages": max_pages,
        },
        timeout=150,
    )
    ms = int((time.time() - t0) * 1000)
    payload.setdefault("duration_ms", ms)
    return payload, status, max_pages


def fill_sns_chunk(platform: str, shop: str, ge: int, lt: int, sns: list[str]):
    t0 = time.time()
    payload, status = post(
        BF,
        {
            "platform": platform,
            "shop_id": shop,
            "dry_run": False,
            "create_time_ge": ge,
            "create_time_lt": lt,
            "stage_order_sns": sns[:50],
            "max_save": 50,
        },
        timeout=150,
    )
    ms = int((time.time() - t0) * 1000)
    payload.setdefault("duration_ms", ms)
    return payload, status


def fill_chunk(platform: str, shop: str, ge: int, lt: int, max_save: int):
    max_pages = 40 if platform == "shopee" else 20
    t0 = time.time()
    payload, status = post(
        BF,
        {
            "platform": platform,
            "shop_id": shop,
            "dry_run": False,
            "create_time_ge": ge,
            "create_time_lt": lt,
            "max_pages": max_pages,
            "max_save": max_save,
        },
        timeout=150,
    )
    ms = int((time.time() - t0) * 1000)
    payload.setdefault("duration_ms", ms)
    return payload, status


def promote_drain(platform: str, batch: int = 120, max_rounds: int = 20) -> int:
    inserted = 0
    for _ in range(max_rounds):
        t0 = time.time()
        payload, status = post(
            PR,
            {
                "p_batch_size": batch,
                "p_merchant_id": MERCHANT,
                "p_platform": platform,
            },
            timeout=90,
        )
        ms = int((time.time() - t0) * 1000)
        if status != 200:
            log("PROMOTE_FAIL", json.dumps({"platform": platform, "status": status, "ms": ms, "body": payload}))
            time.sleep(2)
            break
        n = int(payload.get("inserted") or 0)
        skipped = int(payload.get("skipped_exists") or 0)
        errors = int(payload.get("errors") or 0)
        inserted += n
        log("PROMOTE", json.dumps({
            "platform": platform, "inserted": n, "skipped_exists": skipped,
            "errors": errors, "ms": ms,
        }))
        if n + skipped + errors == 0:
            break
        time.sleep(0.5)
    return inserted


def initial_max_save(platform: str) -> int:
    return {"lazada": 30, "tiktok": 50, "shopee": 50}[platform]


def min_span_secs(platform: str, listed: int) -> int:
    if platform == "lazada":
        return 15 * 60 if listed >= 100 else 30 * 60
    if platform == "tiktok":
        return 4 * 3600
    return 2 * 3600


def should_split(platform: str, listed: int, span: int, max_pages: int) -> bool:
    if span <= min_span_secs(platform, listed):
        return False
    cap = {"lazada": 100, "tiktok": 250, "shopee": 400}[platform]
    if listed >= cap:
        return True
    page_size = 100 if platform == "lazada" else 50
    if listed >= max_pages * page_size:
        return True
    return False


def process_window(platform: str, shop: str, ge: int, lt: int, totals: dict) -> int:
    span = lt - ge
    label = f"{utc_label(ge)}..{utc_label(lt)}"
    write_progress({
        "platform": platform, "ge": ge, "lt": lt, "label": label,
        "totals": totals, "updated_at": utc_label(int(time.time())),
    })

    dry_payload, dry_status, max_pages = (None, 0, 20)
    for attempt in range(4):
        dry_payload, dry_status, max_pages = dry_run(platform, shop, ge, lt)
        listed = int(dry_payload.get("orders_listed") or 0)
        in_ledger = int(dry_payload.get("already_in_ledger") or 0)
        wf = int(dry_payload.get("would_fetch_detail") or 0)
        err = dry_payload.get("error")
        log("DRY", json.dumps({
            "platform": platform, "window": label, "status": dry_status,
            "listed": listed, "in_ledger": in_ledger, "would_fetch": wf,
            "duration_ms": dry_payload.get("duration_ms"), "errors": err,
        }))
        time.sleep(1)
        if is_fatal_platform_error(dry_status, dry_payload):
            fatal_stop(platform, label, ge, lt, dry_status, dry_payload, "dry_run")
        if dry_status == 200 and not err:
            break
        if is_rate_or_timeout(dry_status, dry_payload) or dry_status == 0:
            log("DRY_RETRY_SLEEP", platform, label, "attempt", attempt + 1)
            time.sleep(20)
            if attempt >= 1 and span > min_span_secs(platform, 999):
                mid = ge + span // 2
                return process_window(platform, shop, ge, mid, totals) + process_window(platform, shop, mid, lt, totals)
            continue
        log("DRY_FAIL", platform, label, dry_status, err)
        return 0
    else:
        return 0

    listed = int(dry_payload.get("orders_listed") or 0)
    wf = int(dry_payload.get("would_fetch_detail") or 0)
    if listed >= 100 and platform == "lazada" and span <= min_span_secs(platform, listed):
        log("LAZADA_CAP_LOWER_BOUND", json.dumps({"window": label, "listed": listed, "span_s": span}))

    if should_split(platform, listed, span, max_pages):
        mid = ge + span // 2
        log("SPLIT", json.dumps({"platform": platform, "window": label, "listed": listed, "span_s": span}))
        return process_window(platform, shop, ge, mid, totals) + process_window(platform, shop, mid, lt, totals)

    if wf <= 0:
        return 0

    sns = [str(x).strip() for x in (dry_payload.get("missing_order_sns") or []) if str(x).strip()]
    inserted = 0
    if platform == "shopee" and sns:
        log("SNS_FILL", json.dumps({"window": label, "sns": len(sns), "would_fetch": wf}))
        rounds = 0
        i = 0
        while i < len(sns) and rounds < 80:
            rounds += 1
            chunk = sns[i:i + 50]
            payload, status = fill_sns_chunk(platform, shop, ge, lt, chunk)
            staged = int(payload.get("staged") or 0)
            stage_errors = int(payload.get("stage_errors") or 0)
            err = payload.get("error")
            ms = payload.get("duration_ms")
            log("STAGE", json.dumps({
                "platform": platform, "window": label, "round": rounds, "status": status,
                "mode": payload.get("mode") or "stage_order_sns",
                "chunk": len(chunk), "staged": staged, "duration_ms": ms,
                "errors": err or stage_errors, "max_save": 50,
            }))
            time.sleep(2)
            if is_fatal_platform_error(status, payload):
                fatal_stop(platform, label, ge, lt, status, payload, "stage_sns")
            if is_rate_or_timeout(status, payload) or (status not in (200, 201) and staged == 0):
                log("FILL_RETRY_SLEEP", platform, label, "status", status)
                time.sleep(20)
                continue
            if staged:
                n = promote_drain(platform)
                inserted += n
                totals[platform] = totals.get(platform, 0) + n
            elif err:
                time.sleep(8)
                continue
            i += 50
        return inserted

    max_save = initial_max_save(platform)
    remaining = wf
    rounds = 0
    while remaining > 0 and rounds < 60:
        rounds += 1
        payload, status = fill_chunk(platform, shop, ge, lt, max_save)
        listed_f = int(payload.get("orders_listed") or 0)
        in_ledger_f = int(payload.get("already_in_ledger") or 0)
        staged = int(payload.get("staged") or 0)
        stage_errors = int(payload.get("stage_errors") or 0)
        err = payload.get("error")
        ms = payload.get("duration_ms")
        log("STAGE", json.dumps({
            "platform": platform, "window": label, "round": rounds, "status": status,
            "listed": listed_f, "in_ledger": in_ledger_f, "would_fetch": remaining,
            "staged": staged, "inserted": 0, "duration_ms": ms, "errors": err or stage_errors,
            "max_save": max_save,
        }))
        time.sleep(2)

        if is_fatal_platform_error(status, payload):
            fatal_stop(platform, label, ge, lt, status, payload, "stage")

        if is_rate_or_timeout(status, payload) or (status not in (200, 201) and staged == 0):
            log("FILL_RETRY_SLEEP", platform, label, "status", status)
            time.sleep(20)
            if rounds >= 2 and span > min_span_secs(platform, listed_f or 999):
                mid = ge + span // 2
                log("SHRINK_AFTER_504", json.dumps({"platform": platform, "window": label}))
                return inserted + process_window(platform, shop, ge, mid, totals) + process_window(platform, shop, mid, lt, totals)
            if platform == "lazada" and max_save > 25:
                max_save = 25
            continue

        if staged:
            n = promote_drain(platform)
            inserted += n
            totals[platform] = totals.get(platform, 0) + n
            still = max(0, listed_f - in_ledger_f - staged)
            if still == 0:
                break
            remaining = still
        else:
            if err:
                if is_fatal_platform_error(status, payload):
                    fatal_stop(platform, label, ge, lt, status, payload, "stage_empty")
                time.sleep(8)
                continue
            break
    if wf > 0:
        dry2, st2, _ = dry_run(platform, shop, ge, lt)
        if is_fatal_platform_error(st2, dry2):
            fatal_stop(platform, label, ge, lt, st2, dry2, "dry_confirm")
        wf2 = int(dry2.get("would_fetch_detail") or 0)
        log("DRY_CONFIRM", json.dumps({
            "platform": platform, "window": label, "status": st2,
            "would_fetch": wf2, "duration_ms": dry2.get("duration_ms"),
        }))
        time.sleep(1)
        if wf2 > 0 and inserted > 0:
            log("WINDOW_CONTINUE", json.dumps({"window": label, "would_fetch": wf2}))
            return inserted + process_window(platform, shop, ge, lt, totals)
        if wf2 > 0:
            log("WINDOW_STUCK_GAP", json.dumps({"window": label, "would_fetch": wf2}))
    return inserted


def windows(step_hours: float):
    ge_dt = START
    step = dt.timedelta(hours=step_hours)
    while ge_dt < END:
        lt_dt = min(ge_dt + step, END)
        yield int(ge_dt.timestamp()), int(lt_dt.timestamp())
        ge_dt = lt_dt


def check_support_sn() -> dict:
    q = f"{LEDGER}?order_sn=eq.{SUPPORT_SN}&select=order_sn,platform,merchant_id,transaction_date"
    req = urllib.request.Request(q, headers=HEADERS, method="GET")
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            rows = json.loads(resp.read().decode() or "[]")
            return {"ok": True, "rows": rows, "present": bool(rows)}
    except Exception as e:
        return {"ok": False, "error": str(e)[:300], "present": None}


def main():
    totals = {"lazada": 0, "tiktok": 0, "shopee": 0}
    log("START", json.dumps({
        "merchant_id": MERCHANT,
        "merchant_code": "herhynessreward",
        "start": START.isoformat(),
        "end": END.isoformat(),
        "pid": os.getpid(),
        "platforms": ["shopee"],
        "max_save": 50,
    }))
    plan = [("shopee", 4)]
    for platform, hours in plan:
        shop = SHOPS[platform]
        log("########", platform, shop, "########")
        pre = promote_drain(platform, batch=200, max_rounds=500)
        log("PRE_DRAIN", json.dumps({"platform": platform, "inserted": pre}))
        totals[platform] += pre
        for ge, lt in windows(hours):
            try:
                process_window(platform, shop, ge, lt, totals)
            except Exception:
                log("WINDOW_FAIL", platform, utc_label(ge))
                traceback.print_exc()
                time.sleep(8)
        leftover = promote_drain(platform, batch=200, max_rounds=500)
        totals[platform] += leftover
        log("PLATFORM_DONE", json.dumps({"platform": platform, "inserted": totals[platform]}))

    sn = check_support_sn()
    log("ALL_DONE", json.dumps({
        "totals": totals,
        "sum_inserted": sum(totals.values()),
        "support_sn": SUPPORT_SN,
        "support_sn_in_ledger": sn.get("present"),
        "support_sn_check": sn,
    }))
    write_progress({"done": True, "totals": totals, "support_sn": sn, "updated_at": utc_label(int(time.time()))})


if __name__ == "__main__":
    detach()
    main()
