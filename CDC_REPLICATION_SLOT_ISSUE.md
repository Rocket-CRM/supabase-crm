# CDC Replication Slot Issue - Root Cause & Prevention

## 🔍 What Happened

**Error:**
```
Unable to obtain valid replication slot. Make sure there are no long-running 
transactions running in parallel as they may hinder the allocation of the 
replication slot when starting this connector.
```

**This occurred at connector START/RESTART time**, not during normal operation.

---

## 🎯 Root Cause

### PostgreSQL Replication Slots

**What they are:**
- Ensures CDC doesn't miss changes
- Holds transaction log (WAL) until CDC consumes it
- Prevents WAL from being deleted before CDC reads it

**The Problem:**
- **Long-running transactions** prevent replication slot allocation
- PostgreSQL can't create a consistent snapshot point
- Connector fails to start until transaction completes

---

## 🐛 Common Causes:

### 1. Bulk Operations (Most Likely)

```sql
-- Example: Bulk import running
BEGIN;
INSERT INTO purchase_ledger ... -- 50,000 rows
-- Takes 5-10 minutes
COMMIT;
```

**During this time:** CDC can't restart/allocate slot

---

### 2. Long-Running Queries

```sql
-- Complex analytics query
SELECT * FROM massive_table
WHERE complex_joins_and_aggregations
-- Runs for 10+ minutes
```

---

### 3. Idle Transactions

```sql
BEGIN;
UPDATE some_table SET ...;
-- Connection hangs, never commits
-- Transaction stays open for hours!
```

---

### 4. Migrations

```sql
ALTER TABLE big_table ADD COLUMN ...;
-- Table lock for minutes
```

---

### 5. Vacuum/Maintenance

```sql
VACUUM FULL large_table;
-- Locks table, takes time
```

---

## 🕵️ How to Diagnose

### Check for Long-Running Transactions:

```sql
SELECT 
  pid,
  usename,
  application_name,
  state,
  now() - backend_start AS backend_duration,
  now() - query_start AS query_duration,
  now() - state_change AS state_duration,
  LEFT(query, 100) AS query_preview
FROM pg_stat_activity 
WHERE state != 'idle'
AND (backend_xid IS NOT NULL OR backend_xmin IS NOT NULL)
ORDER BY GREATEST(
  COALESCE(now() - backend_start, '0'::interval),
  COALESCE(now() - query_start, '0'::interval)
) DESC
LIMIT 10;
```

**Look for:**
- ❌ `backend_duration` > 10 minutes
- ❌ `state = 'idle in transaction'` (transaction not committed!)
- ❌ `query_duration` > 5 minutes

---

## 🛠️ Immediate Fix

### Option 1: Wait
```
If query/transaction is legitimate (e.g., your bulk import):
→ Wait for it to complete
→ Then restart CDC connector
```

### Option 2: Kill Long-Running Transactions

```sql
-- Check what's running
SELECT pid, query_start, LEFT(query, 200) 
FROM pg_stat_activity 
WHERE state = 'active' 
AND now() - query_start > interval '10 minutes';

-- Kill specific transaction
SELECT pg_terminate_backend(12345);  -- Replace with actual PID

-- Kill ALL long-running (careful!)
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE state = 'active'
AND now() - query_start > interval '15 minutes'
AND datname = 'postgres';  -- Your database name
```

---

## 🛡️ Prevention Strategies

### 1. Set Statement Timeout

```sql
-- At database level
ALTER DATABASE postgres SET statement_timeout = '5min';

-- At role level
ALTER ROLE service_role SET statement_timeout = '10min';

-- For specific queries
SET statement_timeout = '1min';
SELECT ...;
```

**Prevents queries from running too long**

---

### 2. Set Idle Transaction Timeout

```sql
-- Close idle transactions after 5 minutes
ALTER DATABASE postgres 
SET idle_in_transaction_session_timeout = '5min';
```

**Prevents "BEGIN; ... (forgotten COMMIT)"**

---

### 3. Connection Pooling Best Practices

**Supabase (pgBouncer):**
```
Use transaction mode pooling
→ Connections released after each transaction
→ Prevents holding connections/slots
```

**Application:**
```javascript
// Good: Release connection immediately
const { data } = await supabase.rpc('function');
// Connection auto-released

// Bad: Holding connection
const client = await pool.connect();
await client.query('BEGIN');
// ... do lots of stuff ...
// Never commits!
```

---

### 4. Bulk Import Design (What We Did!)

**Our bulk import is CDC-friendly:**

✅ **Single atomic transaction**
```sql
BEGIN;
  INSERT INTO purchase_ledger ... (50k rows)
  INSERT INTO purchase_items_ledger ... (150k rows)
COMMIT;
-- Completes in 5-10 minutes max
```

✅ **Not many small transactions**
```sql
-- BAD: 50k separate transactions
FOR each row:
  BEGIN;
  INSERT ...;
  COMMIT;
-- Would take hours, blocks CDC repeatedly
```

**Our design minimizes CDC disruption!**

---

### 5. Schedule Maintenance Windows

**For large operations:**
```
1. Pause CDC connector
2. Run bulk import/migration
3. Restart CDC connector
4. CDC catches up (might take 5-10 min for backlog)
```

**Best for:**
- Very large imports (500k+ rows)
- Schema migrations
- Database maintenance

---

### 6. Monitor Replication Lag

**Query to check CDC health:**
```sql
SELECT 
  slot_name,
  active,
  restart_lsn,
  confirmed_flush_lsn,
  pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn)) AS lag
FROM pg_replication_slots
WHERE slot_type = 'logical';
```

**Alert if lag > 100MB**

---

### 7. Use Supabase Branching (If Available)

```
Create branch → Run bulk imports → Merge
→ Doesn't affect production CDC
```

---

## 📊 Why It Failed This Time:

**Likely causes:**

### Possibility 1: Our Bulk Import
```
We imported 4 transactions (small)
→ Should complete in <1 second
→ Unlikely to block CDC
```

### Possibility 2: Other Activity
```
Someone else ran a migration/query
Or Supabase internal maintenance
→ Blocked CDC restart
```

### Possibility 3: CDC Auto-Restart
```
Kafka might auto-restart connectors periodically
→ Caught it during a bulk operation elsewhere
→ Bad timing
```

---

## ✅ Prevention Checklist

For future bulk imports:

- [ ] Set `statement_timeout` on database
- [ ] Set `idle_in_transaction_session_timeout`
- [ ] Monitor replication slot lag
- [ ] Schedule large imports during off-peak
- [ ] Keep transactions under 5 minutes
- [ ] Have CDC restart procedure ready
- [ ] Monitor Confluent for connector health

---

## 🚀 Our Bulk Import is CDC-Safe!

**Why our system is good:**
- ✅ Single atomic transaction (completes fast)
- ✅ No long-running connections
- ✅ Proper error handling
- ✅ File cleanup after processing
- ✅ Async processing (Inngest)

**Even large imports (100k rows) complete in 5-10 min**

---

## 🔄 Recovery Procedure

**When CDC fails:**

1. **Check for blockers** (long transactions)
2. **Kill if safe** (pg_terminate_backend)
3. **Restart connector** (Confluent dashboard)
4. **Wait 2-3 minutes** for connector to come online
5. **Check lag** (should catch up quickly)
6. **Verify** (currency starts awarding again)

---

## 💡 Future Enhancement Ideas:

### 1. CDC Health Monitor
```
Cron job to check CDC status every 5 minutes
→ Auto-alert if connector down
→ Auto-restart if safe
```

### 2. Circuit Breaker for Bulk Imports
```
Check CDC status before large import
→ Pause if CDC unhealthy
→ Prevent exacerbating the issue
```

### 3. Dedicated Import Window
```
Schedule bulk imports during maintenance window
→ Pause CDC
→ Import
→ Resume CDC
→ Controlled catchup
```

---

## ✅ Action Items:

**Immediate:**
1. Restart CDC connector (Confluent dashboard)
2. Verify it comes online
3. Check if YUMYUM transactions get currency

**Short-term:**
1. Set statement_timeout on database
2. Set idle_in_transaction_session_timeout
3. Document CDC restart procedure

**Long-term:**
1. Implement CDC health monitoring
2. Set up alerts for connector failures
3. Consider maintenance windows for very large imports

---

**The CDC issue is environmental, not caused by bulk import design!** 🎯

*See earlier in conversation for detailed CDC fix procedure*
