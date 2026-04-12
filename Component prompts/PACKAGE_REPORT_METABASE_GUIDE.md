# Package Report — Metabase Setup Guide

## What Is a Package?

A package is a **bundle of rewards with quantities** assigned to a user. Think of it like a welcome gift set or a purchased healthcare plan.

Example: "Connex VIP Welcome Pack" contains 2× Spa sessions, 4× Airport Lounge passes, 12× Dining vouchers, and 1× Health Checkup upgrade.

When a user gets a package, the system creates individual **entitlement rows** — one per item in the bundle — each with a balance (granted vs used). The user then consumes these over time. The key metric is **utilization rate**: how much of the granted entitlements has been actually used.

Packages can come from different sources:
- **persona_assignment** — auto-granted when user joins a persona level (e.g., Corporate Executive)
- **purchase** — user bought the package (e.g., Divine Elite Annual Package ฿29,900)
- **admin** — manually assigned by hospital staff (e.g., VIP apology gift)
- **campaign**, **tier_upgrade**, **his_event**, **mission** — other system triggers

This is NOT the same as regular reward redemptions. Regular redemptions are one-shot (redeem once, done). Package entitlements are **multi-use with a depleting balance** over a validity period.

---

## Tables Involved

| Table | What It Holds |
|---|---|
| `package_assignment` | Who got which package, when, from what source, validity dates, status |
| `package_master` | Package definitions — name, price, validity days |
| `package_items` | Template: what rewards are bundled in each package (with quantities) |
| `reward_redemptions_ledger` | The actual entitlements per user — qty granted, qty used, expiry. Filtered by `source_type = 'package_assignment'` |
| `reward_master` | Reward/item details — name, description, images |
| `user_accounts` | User profile — name, email, tel, persona, tier |
| `persona_master` | Persona level name (e.g., "Connex", "Executive") |
| `persona_group_master` | Contract/group info — group name, company name, contract type/status |
| `redemption_usage_log` | Audit trail — each individual use event with timestamp and who performed it |

---

## Main Table: Package Assignment Overview (Question 1)

This is the primary report — one row per package assignment, showing who got what and how much they've used.

```sql
SELECT
  pa.id                          AS assignment_id,
  ua.fullname                    AS user_name,
  ua.email,
  ua.tel,
  pm_pkg.name                   AS package_name,
  pm_pkg.price                  AS package_price,
  pa.source_type,
  pa.assigned_by,
  pa.created_at                 AS assigned_date,
  pa.effective_from,
  pa.effective_to,
  pa.status                     AS assignment_status,
  pers.persona_name,
  pgm.group_name                AS contract_name,
  pgm.company_name,
  pgm.contract_type,
  COUNT(rrl.id)                 AS total_items,
  SUM(rrl.qty)                  AS total_qty_granted,
  COALESCE(SUM(rrl.used_qty), 0) AS total_used,
  SUM(rrl.qty) - COALESCE(SUM(rrl.used_qty), 0) AS total_remaining,
  ROUND(
    COALESCE(SUM(rrl.used_qty), 0)::numeric
    / NULLIF(SUM(rrl.qty), 0) * 100, 1
  )                             AS utilization_pct,
  CASE
    WHEN pa.effective_to < NOW() THEN 'Expired'
    WHEN COALESCE(SUM(rrl.used_qty), 0) = SUM(rrl.qty) THEN 'Fully Used'
    WHEN COALESCE(SUM(rrl.used_qty), 0) = 0 THEN 'Untouched'
    ELSE 'In Progress'
  END                           AS consumption_status
FROM package_assignment pa
  JOIN package_master pm_pkg ON pm_pkg.id = pa.package_id
  JOIN user_accounts ua ON ua.id = pa.user_id
  LEFT JOIN reward_redemptions_ledger rrl
    ON rrl.package_assignment_id = pa.id
  LEFT JOIN persona_master pers ON pers.id = ua.persona_id
  LEFT JOIN persona_group_master pgm ON pgm.id = pers.group_id
WHERE pa.merchant_id = '68d8c437-556b-412e-b9ca-ae5a8a23b18d'
  [[AND pa.status = {{status}}]]
  [[AND pa.source_type = {{source_type}}]]
  [[AND pm_pkg.name = {{package_name}}]]
GROUP BY
  pa.id, ua.fullname, ua.email, ua.tel,
  pm_pkg.name, pm_pkg.price,
  pa.source_type, pa.assigned_by, pa.created_at,
  pa.effective_from, pa.effective_to, pa.status,
  pers.persona_name, pgm.group_name,
  pgm.company_name, pgm.contract_type
ORDER BY pa.created_at DESC
```

> **Metabase tip:** The `[[AND ...]]` syntax creates optional filters in Metabase native queries. Create filter widgets for `status`, `source_type`, and `package_name`.

---

## Drill-Down: Entitlement Item Detail (Question 2)

When someone clicks a row in the main table, drill into the individual items within that package assignment.

```sql
SELECT
  rm.name                       AS item_name,
  rrl.qty                       AS qty_granted,
  rrl.used_qty,
  (rrl.qty - COALESCE(rrl.used_qty, 0)) AS remaining,
  ROUND(
    COALESCE(rrl.used_qty, 0)::numeric
    / NULLIF(rrl.qty, 0) * 100, 0
  )                             AS item_utilization_pct,
  rrl.used_status               AS fully_consumed,
  rrl.use_expire_date           AS expiry_date,
  rrl.created_at                AS entitled_date,
  (SELECT MAX(rul.performed_at)
   FROM redemption_usage_log rul
   WHERE rul.redemption_id = rrl.id
  )                             AS last_used_date
FROM reward_redemptions_ledger rrl
  JOIN reward_master rm ON rm.id = rrl.reward_id
WHERE rrl.package_assignment_id = {{assignment_id}}
ORDER BY rm.name
```

> **Metabase tip:** Link this question to the main table. In the main table, click the column settings for `assignment_id` and set "Clicked → Go to a custom destination → Saved Question → this drill-down question", passing `assignment_id` as the parameter.

---

## Drill-Down: Usage Audit Trail (Question 3)

From the item detail, drill further into when/how each item was used.

```sql
SELECT
  rul.performed_at              AS used_at,
  rm.name                       AS item_name,
  rul.action,
  rul.qty_change,
  rul.used_qty_after,
  rul.performed_by,
  rul.source_type               AS usage_source,
  rul.source_ref                AS reference_id,
  rul.notes
FROM redemption_usage_log rul
  JOIN reward_redemptions_ledger rrl ON rrl.id = rul.redemption_id
  JOIN reward_master rm ON rm.id = rrl.reward_id
WHERE rrl.package_assignment_id = {{assignment_id}}
ORDER BY rul.performed_at DESC
```

---

## Dashboard: Aggregate Boxes (Number Cards)

### Box 1 — Total Packages Assigned

```sql
SELECT COUNT(*) AS total_assigned
FROM package_assignment
WHERE merchant_id = '68d8c437-556b-412e-b9ca-ae5a8a23b18d'
  AND status = 'active'
```

### Box 2 — Total Entitlements Granted

```sql
SELECT SUM(rrl.qty) AS total_qty_granted
FROM reward_redemptions_ledger rrl
  JOIN package_assignment pa ON pa.id = rrl.package_assignment_id
WHERE pa.merchant_id = '68d8c437-556b-412e-b9ca-ae5a8a23b18d'
  AND rrl.source_type = 'package_assignment'
```

### Box 3 — Total Used

```sql
SELECT SUM(rrl.used_qty) AS total_used
FROM reward_redemptions_ledger rrl
  JOIN package_assignment pa ON pa.id = rrl.package_assignment_id
WHERE pa.merchant_id = '68d8c437-556b-412e-b9ca-ae5a8a23b18d'
  AND rrl.source_type = 'package_assignment'
```

### Box 4 — Overall Utilization %

```sql
SELECT ROUND(
  SUM(rrl.used_qty)::numeric / NULLIF(SUM(rrl.qty), 0) * 100, 1
) AS overall_utilization_pct
FROM reward_redemptions_ledger rrl
  JOIN package_assignment pa ON pa.id = rrl.package_assignment_id
WHERE pa.merchant_id = '68d8c437-556b-412e-b9ca-ae5a8a23b18d'
  AND rrl.source_type = 'package_assignment'
```

### Box 5 — Fully Consumed Packages

```sql
SELECT COUNT(*) AS fully_consumed
FROM (
  SELECT pa.id
  FROM package_assignment pa
    JOIN reward_redemptions_ledger rrl ON rrl.package_assignment_id = pa.id
  WHERE pa.merchant_id = '68d8c437-556b-412e-b9ca-ae5a8a23b18d'
    AND rrl.source_type = 'package_assignment'
  GROUP BY pa.id
  HAVING SUM(rrl.used_qty) = SUM(rrl.qty)
) sub
```

### Box 6 — Untouched Packages (0% used)

```sql
SELECT COUNT(*) AS untouched
FROM (
  SELECT pa.id
  FROM package_assignment pa
    JOIN reward_redemptions_ledger rrl ON rrl.package_assignment_id = pa.id
  WHERE pa.merchant_id = '68d8c437-556b-412e-b9ca-ae5a8a23b18d'
    AND rrl.source_type = 'package_assignment'
  GROUP BY pa.id
  HAVING COALESCE(SUM(rrl.used_qty), 0) = 0
) sub
```

---

## Dashboard: Line Charts

### Chart 1 — Package Assignments Over Time (by month)

```sql
SELECT
  DATE_TRUNC('month', pa.created_at) AS month,
  pa.source_type,
  COUNT(*)                          AS assignments
FROM package_assignment pa
WHERE pa.merchant_id = '68d8c437-556b-412e-b9ca-ae5a8a23b18d'
GROUP BY DATE_TRUNC('month', pa.created_at), pa.source_type
ORDER BY month
```

> **Visualization:** Line chart, X = month, Y = assignments, Series = source_type. Shows trend of how packages are being distributed and through which channel.

### Chart 2 — Entitlement Usage Over Time (by month)

```sql
SELECT
  DATE_TRUNC('month', rul.performed_at) AS month,
  COUNT(*)                              AS usage_events,
  SUM(rul.qty_change)                   AS total_qty_used
FROM redemption_usage_log rul
WHERE rul.merchant_id = '68d8c437-556b-412e-b9ca-ae5a8a23b18d'
GROUP BY DATE_TRUNC('month', rul.performed_at)
ORDER BY month
```

> **Visualization:** Line chart, X = month, Y = total_qty_used. Shows consumption velocity — are users actually using their entitlements?

### Chart 3 — Utilization by Package Type (bar chart)

```sql
SELECT
  pm.name                       AS package_name,
  COUNT(DISTINCT pa.id)         AS total_assigned,
  SUM(rrl.qty)                  AS total_granted,
  SUM(rrl.used_qty)             AS total_used,
  ROUND(
    SUM(rrl.used_qty)::numeric / NULLIF(SUM(rrl.qty), 0) * 100, 1
  )                             AS utilization_pct
FROM package_assignment pa
  JOIN package_master pm ON pm.id = pa.package_id
  JOIN reward_redemptions_ledger rrl ON rrl.package_assignment_id = pa.id
WHERE pa.merchant_id = '68d8c437-556b-412e-b9ca-ae5a8a23b18d'
GROUP BY pm.name
ORDER BY utilization_pct DESC
```

> **Visualization:** Horizontal bar chart, Y = package_name, X = utilization_pct. Instantly shows which packages are being used vs wasted.

### Chart 4 — Top Items by Usage (bar chart)

```sql
SELECT
  rm.name                       AS item_name,
  SUM(rrl.qty)                  AS total_granted,
  SUM(rrl.used_qty)             AS total_used,
  ROUND(
    SUM(rrl.used_qty)::numeric / NULLIF(SUM(rrl.qty), 0) * 100, 1
  )                             AS utilization_pct
FROM reward_redemptions_ledger rrl
  JOIN reward_master rm ON rm.id = rrl.reward_id
  JOIN package_assignment pa ON pa.id = rrl.package_assignment_id
WHERE pa.merchant_id = '68d8c437-556b-412e-b9ca-ae5a8a23b18d'
  AND rrl.source_type = 'package_assignment'
GROUP BY rm.name
ORDER BY total_used DESC
```

> **Visualization:** Bar chart, X = item_name, Y = total_used (with total_granted as a second series). Shows which specific items get consumed most — useful for forecasting and procurement.

### Chart 5 — Utilization by Source Type (donut chart)

```sql
SELECT
  pa.source_type,
  COUNT(DISTINCT pa.id)         AS assignment_count,
  SUM(rrl.used_qty)             AS total_used
FROM package_assignment pa
  JOIN reward_redemptions_ledger rrl ON rrl.package_assignment_id = pa.id
WHERE pa.merchant_id = '68d8c437-556b-412e-b9ca-ae5a8a23b18d'
GROUP BY pa.source_type
ORDER BY total_used DESC
```

> **Visualization:** Donut/pie chart showing distribution by source. Answers: "Are most packages coming from contracts, purchases, or manual admin assignments?"

---

## Suggested Dashboard Layout

```
┌──────────────┬──────────────┬──────────────┐
│  Total       │  Total       │  Total       │
│  Assigned    │  Granted     │  Used        │
│     10       │     130      │     57       │
├──────────────┼──────────────┼──────────────┤
│  Overall     │  Fully       │  Untouched   │
│  Util %      │  Consumed    │  Packages    │
│    43.8%     │      1       │      0       │
├──────────────┴──────────────┴──────────────┤
│  Chart 1: Assignments Over Time (line)     │
│  Chart 2: Usage Over Time (line)           │
├────────────────────┬───────────────────────┤
│  Chart 3: Util by  │  Chart 5: Source      │
│  Package (bar)     │  Breakdown (donut)    │
├────────────────────┴───────────────────────┤
│  Chart 4: Top Items by Usage (bar)         │
├────────────────────────────────────────────┤
│  Main Table: Package Assignment Overview   │
│  (click row → drill into item detail)      │
└────────────────────────────────────────────┘
```

---

## Quick Filters to Add

- **Package Name** — dropdown from `SELECT DISTINCT name FROM package_master WHERE merchant_id = '...'`
- **Source Type** — dropdown: persona_assignment, purchase, admin, campaign, tier_upgrade
- **Status** — dropdown: active, expired, cancelled
- **Date Range** — on `pa.created_at` for assignment date
- **Contract/Group** — dropdown from `SELECT DISTINCT group_name FROM persona_group_master WHERE merchant_id = '...'`
