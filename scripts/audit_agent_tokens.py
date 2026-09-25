#!/usr/bin/env python3
"""
Agent-transcript token-waste audit.

Re-run this after rule/doc changes to see whether reads dropped.

Usage:
    python3 scripts/audit_agent_tokens.py            # all threads
    python3 scripts/audit_agent_tokens.py --last 50  # most recent 50 threads
    python3 scripts/audit_agent_tokens.py --since 2026-04-19   # threads mtime'd since date
    python3 scripts/audit_agent_tokens.py --compare  # human-readable diff vs baseline

Baseline is recorded to `scripts/.agent_token_baseline.json` on first run.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from collections import Counter, defaultdict
from datetime import datetime
from pathlib import Path

TRANSCRIPTS = Path(os.path.expanduser(
    "~/.cursor/projects/Users-rangwan-Documents-Supabase-CRM/agent-transcripts"
))
WORKSPACE = Path(__file__).resolve().parents[1]
BASELINE = Path(__file__).parent / ".agent_token_baseline.json"

# File-size lookup for token estimation (chars/4)
def approx_tokens_for(path_str: str) -> int:
    """Approximate tokens = bytes / 4 from the current workspace copy if the file exists."""
    p = Path(path_str)
    if not p.is_absolute():
        p = WORKSPACE / p
    try:
        return p.stat().st_size // 4
    except OSError:
        return 0

def norm_path(p: str) -> str:
    if not p:
        return ""
    for prefix in [str(WORKSPACE) + "/", "Supabase CRM/"]:
        if p.startswith(prefix):
            return p[len(prefix):]
    return p

def classify(p: str) -> str:
    n = norm_path(p)
    if ".cursor/rules/" in n and n.endswith(".mdc"):
        return "rule"
    if "/mcps/" in p and p.endswith(".json"):
        return "mcp_descriptor"
    if n.startswith("requirements/domains/"):
        return "domain_index_split"
    if n.startswith("requirements/archive/"):
        return "archived_draft"
    if "INDEX_FUNCTION" in n:
        return "index_function"
    if "INDEX_DOMAIN" in n:
        return "index_domain_monolith"
    if n.startswith("requirements/feature-docs/"):
        return "feature_guide"
    if n.startswith("requirements/"):
        return "requirement_doc"
    if n.startswith("Data migration/"):
        return "scratchpad_migration"
    if n.startswith(".cursor/plans/") and n.endswith(".plan.md"):
        return "scratchpad_plan"
    if n.startswith("Component prompts/"):
        return "scratchpad_component"
    if n.endswith(".md"):
        return "other_md"
    if n.endswith(".sql"):
        return "sql"
    if n.endswith(".ts") or n.endswith(".tsx"):
        return "code"
    return "other"

def iterate_threads(limit_last: int | None = None, since: str | None = None):
    entries = []
    for td in TRANSCRIPTS.iterdir():
        if not td.is_dir():
            continue
        jsonls = list(td.glob("*.jsonl"))
        if not jsonls:
            continue
        j = jsonls[0]
        entries.append((j.stat().st_mtime, td.name, j))
    entries.sort(reverse=True)
    if since:
        cutoff = datetime.fromisoformat(since).timestamp()
        entries = [e for e in entries if e[0] >= cutoff]
    if limit_last:
        entries = entries[:limit_last]
    return entries

def analyze(limit_last: int | None = None, since: str | None = None):
    read_count = Counter()
    read_threads = defaultdict(set)
    write_count = Counter()
    write_threads = defaultdict(set)
    mcp_calls = 0
    mcp_desc_reads = 0
    total_reads = 0
    total_writes = 0
    tokens_burned_reads = 0
    class_read = Counter()
    class_tokens = Counter()
    thread_count = 0
    entries = iterate_threads(limit_last=limit_last, since=since)
    for _, tid, jsonl in entries:
        thread_count += 1
        try:
            for line in jsonl.read_text(errors="ignore").split("\n"):
                if not line:
                    continue
                try:
                    ev = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if ev.get("role") != "assistant":
                    continue
                for item in ev.get("message", {}).get("content", []) or []:
                    if not isinstance(item, dict) or item.get("type") != "tool_use":
                        continue
                    name = item.get("name", "")
                    inp = item.get("input", {}) or {}
                    if name == "Read":
                        total_reads += 1
                        p = inp.get("path", "") or inp.get("target_file", "")
                        if not p:
                            continue
                        n = norm_path(p)
                        cls = classify(p)
                        read_count[n] += 1
                        read_threads[n].add(tid)
                        class_read[cls] += 1
                        # Cost estimate (full-file read)
                        tk = approx_tokens_for(p)
                        tokens_burned_reads += tk
                        class_tokens[cls] += tk
                        if cls == "mcp_descriptor":
                            mcp_desc_reads += 1
                    elif name in ("Write", "StrReplace"):
                        total_writes += 1
                        p = inp.get("path", "") or inp.get("target_file", "")
                        if p:
                            n = norm_path(p)
                            write_count[n] += 1
                            write_threads[n].add(tid)
                    elif name == "CallMcpTool":
                        mcp_calls += 1
        except OSError:
            continue
    return {
        "thread_count": thread_count,
        "total_reads": total_reads,
        "total_writes": total_writes,
        "mcp_calls": mcp_calls,
        "mcp_descriptor_reads": mcp_desc_reads,
        "tokens_burned_reads": tokens_burned_reads,
        "read_count": dict(read_count),
        "read_threads": {k: len(v) for k, v in read_threads.items()},
        "write_count": dict(write_count),
        "write_threads": {k: len(v) for k, v in write_threads.items()},
        "class_read": dict(class_read),
        "class_tokens": dict(class_tokens),
    }

def fmt_k(n):
    if n >= 1_000_000:
        return f"{n/1_000_000:.2f}M"
    if n >= 1_000:
        return f"{n/1_000:.1f}k"
    return str(n)

def print_report(r, label="CURRENT"):
    tc = r["thread_count"]
    print(f"=== {label} — {tc} threads ===")
    print(f"Reads: {r['total_reads']}  Writes: {r['total_writes']}  MCP: {r['mcp_calls']}")
    mcp_ratio = r["mcp_calls"] / max(r["mcp_descriptor_reads"], 1)
    print(f"MCP ratio: {mcp_ratio:.1f}x calls per descriptor read  (desc reads: {r['mcp_descriptor_reads']})")
    print(f"Est input tokens burned by full-file Reads: {fmt_k(r['tokens_burned_reads'])}")
    per_thread = r['tokens_burned_reads'] / max(tc, 1)
    print(f"Per-thread avg Read tokens: {fmt_k(int(per_thread))}")
    print()
    print("Reads by category:")
    for cls, c in sorted(r["class_read"].items(), key=lambda x: -x[1]):
        tok = r["class_tokens"].get(cls, 0)
        print(f"  {cls:28s} {c:>5d} reads  ~{fmt_k(tok):>7s} tokens")
    print()
    print("Top 15 read files:")
    for f, c in sorted(r["read_count"].items(), key=lambda x: -x[1])[:15]:
        t = r["read_threads"].get(f, 0)
        print(f"  {c:>5d} reads / {t:>3d} threads | {f}")
    print()
    print("Top 10 written files:")
    for f, c in sorted(r["write_count"].items(), key=lambda x: -x[1])[:10]:
        t = r["write_threads"].get(f, 0)
        print(f"  {c:>5d} writes / {t:>3d} threads | {f}")
    print()

def print_diff(cur, base):
    print("=== DIFF vs baseline ===")
    print(f"Threads:        {base['thread_count']} -> {cur['thread_count']}")
    # Normalize to per-thread rates
    def rate(r, k):
        return r[k] / max(r['thread_count'], 1)
    for k in ("total_reads", "total_writes", "mcp_calls", "tokens_burned_reads"):
        b, c = rate(base, k), rate(cur, k)
        delta = c - b
        pct = 100 * delta / b if b else 0
        print(f"  {k:24s} per-thread: {b:>10.1f} -> {c:>10.1f}  ({pct:+.1f}%)")
    print()
    print("Per-category read deltas (per-thread):")
    cls_all = set(cur["class_read"]) | set(base["class_read"])
    rows = []
    for cls in cls_all:
        b = base["class_read"].get(cls, 0) / max(base["thread_count"], 1)
        c = cur["class_read"].get(cls, 0) / max(cur["thread_count"], 1)
        rows.append((cls, b, c, c - b))
    for cls, b, c, d in sorted(rows, key=lambda x: -abs(x[3])):
        print(f"  {cls:28s} {b:>7.2f} -> {c:>7.2f}   (Δ {d:+.2f})")

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--last", type=int, default=None, help="Limit to N most recent threads")
    ap.add_argument("--since", type=str, default=None, help="ISO date: only threads mtime'd since")
    ap.add_argument("--save-baseline", action="store_true")
    ap.add_argument("--compare", action="store_true", help="Compare to saved baseline")
    args = ap.parse_args()

    cur = analyze(limit_last=args.last, since=args.since)
    print_report(cur, label="CURRENT")

    if args.save_baseline:
        BASELINE.write_text(json.dumps(cur, indent=2))
        print(f"Baseline saved to {BASELINE}")

    if args.compare:
        if not BASELINE.exists():
            print("No baseline found. Run with --save-baseline first.")
            sys.exit(1)
        base = json.loads(BASELINE.read_text())
        print_diff(cur, base)

if __name__ == "__main__":
    main()
