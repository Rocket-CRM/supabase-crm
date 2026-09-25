# MongoDB Atlas M40 — Performance Diagnosis Summary

**Date:** 2026-06-06  
**Cluster:** `crm-prod` (4 shards, M40)  
**Sources:** Atlas metrics (CPU, IOPS, memory), MongoDB MCP (`$collStats`, `dbStats`, indexes, mongod logs)

This document summarizes two separate issues observed post-query-optimization. They have different causes, different charts, and different fixes.

---

## Issue 1 — Disk IOPS spikes every ~60 seconds (WiredTiger checkpoint)

### What you see

| Chart | Pattern |
|-------|---------|
| **Max Disk IOPS** | Sharp green spikes to **~4,000–8,000/s**, roughly **once per minute** |
| **Disk IOPS** (average) | Mostly **tens–low hundreds/s** between spikes |
| **System / Max System Memory** | **Flat** — no spike aligned with IOPS |

Granularity is **scoped by minute**: each point is the **peak ops/sec within that 60s window**, not total ops per minute.

### What it is

**WiredTiger checkpoint** — a built-in MongoDB storage-engine process, not application traffic.

> **สรุป (TH):** IOPS ที่พุ่งขึ้นในวินาทีสุดท้ายของทุกนาที เป็น system process ของ Mongo ชื่อ WiredTiger checkpoint (flush ข้อมูลที่เขียนค้างใน RAM ลง disk ทุก ~60 วินาที) ซึ่ง ignore ได้ เพราะเป็น burst สั้นๆ วินาทีเดียวต่อนาที ไม่ใช่โหลดจากลูกค้า

- MongoDB buffers writes in RAM (WiredTiger cache) throughout the minute.
- Every **~60 seconds** (default), it flushes **dirty pages** to disk in a short burst.
- **Max IOPS** captures that 1–3 second flush; **average IOPS** stays low.

This is **not**:

- Thousands of customers reading/writing per second
- One row per IOPS (IOPS = 4 KB disk **pages**, not documents)
- A memory problem (checkpoint writes cache **to** disk; it does not inflate RAM)

### What feeds the checkpoint (background writers)

Checkpoint magnitude depends on how much was buffered. Contributors on this cluster:

| Source | Role |
|--------|------|
| **CRM-PROD** (Go, Kubernetes) | Short-lived connections; writes/reads to MongoDB |
| **Marketplace order sync** | Upserts to `third_party_ecommerce.*` (Shopee/TikTok/Lazada) |
| **Point / receipt / wallet paths** | Ongoing loyalty and receipt workloads |
| **Oplog** (`local.oplog.rs`, ~16 GB on disk) | Every write replicated; adds write volume |

### Sizing implication (e.g. M30 downgrade)

| Verdict | Detail |
|---------|--------|
| **Safe to discount max write IOPS** | Sustained need is **tens–~100/s**, not 4k–8k/s |
| **Do not treat spikes as customer load** | Brief burst uses EBS burst credits or short overrun |
| **Watch instead** | Disk **latency** during spikes; sustained IOPS climbing toward baseline |

**Conclusion:** Max Disk IOPS spikes are **normal WiredTiger behavior**. They are **not** a reason to stay on M40 for disk alone.

---

## Issue 2 — Sustained high memory (~4.77 GB flat System Memory)

### What you see

| Chart | Pattern |
|-------|---------|
| **System Memory** | Flat green line ~**4.77 GB** |
| **Max System Memory** | Nearly identical — **no** end-of-minute spikes |
| Blue line (~8–9 GB) | Likely capacity/limit reference, not “peak usage blocking tier” |

Memory is **stable and chronic**, not periodic like IOPS.

### What it is

**WiredTiger cache** holding **hot application data** — MongoDB’s **internal page cache** (RAM on the Atlas node).

This is **not**:

- Redis (application cache runs separately; does not appear on MongoDB memory charts)
- The checkpoint process (that affects **disk**, not flat RAM)
- Proportional to live customer count

Redis caches **app answers**; WiredTiger caches **database pages** (collections + indexes). Both can exist; reducing Redis traffic does not remove MongoDB’s need for its own cache.

### Why it feels “high” with few customers

Historical volume + always-on backend access, not concurrent users:

| Domain | Scale (cluster) |
|--------|-----------------|
| Marketplace orders (synced) | **~94M** documents (`third_party_ecommerce`) |
| Oplog entries | **~95M** (~16 GB on disk) |
| Loyalty / points / receipts | **Millions** of ledger and receipt rows |

**CRM-PROD** (`mongo-go-driver`, `be_go_db`, ~600 connections) keeps hitting the same collections. WiredTiger keeps frequently used B-tree pages in RAM → **flat ~4.77 GB**.

When **cache size > collection disk size**, the entire collection is “hot” (common on receipt collections).

---

## Key collections that move the dial (memory)

Live attribution from MCP `$collStats` → `wiredTiger.cache.bytes currently in the cache` (one node; ranks and MB vary slightly per shard over time).

| Priority | Collection | ~In RAM | ~On disk | ~Docs | Why it matters |
|----------|------------|---------|----------|-------|----------------|
| **1** | `crm_point_db.point_transactions` | **~1.8 GB** | 1.5 GB | 6.8M | Hottest; **169M+** cache page requests; **15 indexes** (indexes > data size) |
| **2** | `crm_receipt_db.receipt_upload_transactions` | **~1.3 GB** | 0.6 GB | 2.6M | Entire collection pinned in cache |
| **3** | `crm_receipt_db.receipt_reprint_transactions` | **~1.25 GB** | 0.6 GB | 2.6M | Entire collection pinned in cache |
| **4** | `third_party_ecommerce.tiktok_order_transactions` | **~0.7 GB** | 16 GB | 51M | Hot **tail** of marketplace sync; bulk of 51M docs on disk, not all in RAM |
| **5** | `loyaltydb.points` | **~0.3 GB** | 3.3 GB | 11M | Legacy points; **14 indexes**; high read churn |

**Top 5 ≈ 5+ GB** on a single node — aligns with Atlas **~4.77 GB** system memory (Atlas uses a slightly different memory formula; chart averages four shards).

### Lower RAM impact (still large on disk / writes)

| Collection | Notes |
|------------|--------|
| `third_party_ecommerce.shopee_order_transactions` | **40M** docs, **20 GB** total; often **cold in cache** on sampled node — drives **disk size & checkpoint writes**, less flat RAM |
| `local.oplog.rs` | **16 GB** on disk; **~33 MB** in cache — replication log, not a RAM driver |
| `crm_wallet_db.wallet_transactions` | 6.5M docs; **cold in cache** on sampled node |

### Rough memory budget (one node)

```
~4.77 GB sustained System Memory (Atlas)
├── point_transactions           ~34%   ← point ledger
├── receipt_upload_transactions  ~27%   ← receipt earning
├── receipt_reprint_transactions ~26%   ← receipt reprint
├── tiktok_order_transactions    ~15%   ← marketplace sync tail
├── loyaltydb.points             ~6%    ← legacy points
└── mongod overhead + other      small
```

---

## Recommended actions (by issue)

### Issue 1 — Checkpoint / IOPS (low effort)

- **No action required** if disk latency stays healthy.
- Optional: monitor **WiredTiger checkpoint duration** in Atlas overlaid with Max Disk IOPS to confirm 60s alignment.
- Reducing **write volume** (fewer redundant marketplace upserts) shrinks burst size over time.

### Issue 2 — Hot cache / memory (where to invest)

**Highest leverage (no hot/cold tables, no TTL deletion):**

1. **Query discipline** — default `created_at` / `_id` range (e.g. last 90d–1y) on reads for `point_transactions`, `receipt_upload_transactions`, `receipt_reprint_transactions` so old pages **evict via LRU**.
2. **Find full scans** — Atlas Query Insights / Profiler on recon and batch jobs (`recon_*` indexes exist on points and marketplace).
3. **Connection pooling** — CRM-PROD currently connect → auth → one command → disconnect (~600 conns); use persistent `mongo.Client` pool.
4. **Redis read-through** — cache point balance and recent receipt lookups to reduce MongoDB page touches.
5. **Index audit** — drop unused indexes after `$indexStats` / Performance Advisor:
   - `point_transactions` (**15** indexes; duplicate `earned_item.receipt_id` pair)
   - `loyaltydb.points` (**14** indexes; many redundant single-field)

**Not chosen for this plan:** second archive collections, TTL expiry, or relying on Redis alone without query changes.

**Estimated RAM recovery if #1–#5 applied:** roughly **3–5 GB** cluster-wide → sustained memory potentially **~2–3 GB**, improving M30 viability.

---

## M30 downgrade — consolidated view

| Signal | Post-optimization | Blocks M30? |
|--------|-------------------|-------------|
| Sustained CPU (~10–15% normalized) | Low | No |
| Max normalized CPU (~100%) | Brief bursts | Caution only |
| Connections (~450/shard) | Well under 3,000 | No |
| **Max Disk IOPS (~4–8k/s, ~60s)** | WiredTiger checkpoint | **No** (ignore for sizing) |
| **Sustained memory (~4.77 GB)** | Hot collections above | **Yes**, until cache cooled |
| Total data (~100 GB) vs M30 cache (~3–4 GB) | Mismatch | **Yes**, if hot set unchanged |

**Summary:** Downgrade is **reasonable to trial** on CPU/IOPS after optimization, but **not blind** — memory is driven by **five application collections**, not by the checkpoint. Cool the hot set first (query filters + index cleanup + pooling), then trial M30 with auto-scale floor M30 / ceiling M40.

---

## Glossary

| Term | Meaning |
|------|---------|
| **WiredTiger** | MongoDB’s default storage engine (cache + disk + indexes) |
| **WiredTiger cache** | RAM inside `mongod` for database pages; shown indirectly as System Memory |
| **Checkpoint** | ~60s flush of dirty cache pages to disk → **Max Disk IOPS** spikes; flush ข้อมูลที่เขียนค้างใน RAM ลง disk |
| **Max vs average (scoped by min)** | Per-minute bucket; **max** = peak per second in that minute |
| **Redis cache** | Separate application-layer cache; does not replace WiredTiger |
| **Hot collection** | Most/all pages recently accessed; stays in WiredTiger cache |

---

## MCP / Atlas commands for follow-up

**Index usage (before dropping):**
```javascript
db.point_transactions.aggregate([{ $indexStats: {} }])
db.receipt_upload_transactions.aggregate([{ $indexStats: {} }])
```

**Cache snapshot (per collection):**
```javascript
db.point_transactions.aggregate([
  { $collStats: { storageStats: {} } },
  { $project: {
      ns: 1,
      cacheMB: { $divide: ["$storageStats.wiredTiger.cache.bytes currently in the cache", 1048576] },
      count: "$storageStats.count",
      totalGB: { $divide: ["$storageStats.totalSize", 1073741824] }
  }}
])
```

**Atlas UI:** Performance Advisor (drop indexes), Query Insights (full scans), overlay WiredTiger checkpoint metrics with Max Disk IOPS.
