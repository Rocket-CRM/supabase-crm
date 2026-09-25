## 5.4 See workload and export reports

Managers and directors need to see overdue work before the weekly meeting. After SSO login, their dashboards show **where work is concentrating** and **which cases or tickets are approaching or exceeding SLA**, using the same investment cases, stage timers, and tickets as the operational teams.

## Management views

| Object | What it is | Why it matters |
|---|---|---|
| **Dashboard / home** | Role-appropriate landing view after login | Different roles see different pressure widgets (see Section 5.6) |
| **Heat map cell** | Aggregation of open work by bureau/team (or other dimension agreed in BRD) | Shows concentration and overload at a glance |
| **SLA-at-risk row** | Case or ticket past warning/breach | Drill path into the case workspace (Section 5.3) or ticket (Section 5.2) |
| **Report view** | Saved or ad hoc breakdown (country, industry, value, …) | Board packs without a separate offline status tracker |
| **Export file** | Excel or PDF snapshot of a view | Offline sharing under existing access rules |

## Workload, SLA, and reporting controls

| Feature | What the user does | Includes (sub-capabilities) |
|---|---|---|
| Post-login dashboard | After SSO sign-in, the user lands on a home view sized to their role so pressure and work queues are visible immediately. | Role-specific widget set; deep links into case workspace or ticket; same data model as Sections 5.2–5.3 (no second status store). |
| Heat map | Managers and directors see where open work concentrates across bureaus or teams at a glance. | Dimension by bureau/team (or other BRD dimension); color by load; click-through to the underlying case/ticket list. |
| SLA-at-risk list | The user drills into cases or tickets that are in warning or breach so action can be taken before the next meeting. | Separate warning vs breach states; sort by age; open case workspace (Section 5.3) or ticket (Section 5.2) from the row. |
| Filter by พ.ศ. | The user constrains heat map and lists to a Buddhist Era calendar range used in สกพอ. reporting. | Range select on the shared filter bar; applies to heat map, SLA list, and report views. |
| Filter by fiscal year | The user aligns the same views to budget years for board and planning packs. | Fiscal-year control on the same filter bar as พ.ศ.; persists for the session or saved view. |
| Configurable report views | The user breaks down promotion work by dimensions such as country, industry, or investment value when the data supports it. | Ad hoc and saved views; dimensions from available case fields; reopen saved view without rebuilding filters. |
| Export Excel / PDF | The user exports the current filtered view for offline board packs without maintaining a separate status workbook. | Export respects active filters; sensitive columns follow RBAC (Section 5.6); Excel and PDF outputs. |
| Role-aware widgets | Staff, managers, and directors do not see the same sensitive slices of the same underlying cases. | Default widget packs by role; administrator can adjust; LOI/NDA/financial widgets hidden where RBAC denies. |

### Recommended enhancement (beyond TOR minimum)

**Scheduled executive digests.** Heat-map and aging summaries can be delivered on a schedule (for example weekly) so directors receive workload and delay updates without opening the dashboard each time. Recipients and cadence are configured by administrators.

## Reporting from live case data

Heat map and SLA lists use the same **stage SLA** and **ticket SLA** events as the investment cases; there is no second status store to reconcile. Filters constrain those records by พ.ศ. and fiscal year, and exports render the current filtered view. RBAC hides or redacts widgets that would expose LOI, NDA, or financial content to an unauthorized role.

Reporting is **native** by default on the same PostgreSQL system of record (Section 4.3.1): heat map and dashboards use constrained reads so they do not starve transactional case updates; scheduled digests run as application jobs off the interactive path. No separate warehouse is required at ≥100 named users. If BRD requires an external BI tool for unrestricted drill-down, Rocket funds licenses for all project named users for the period TOR 5.6.2 requires.

{{mockup:M02}}

Reference: TOR 5.5.5, 5.6, 2.2.
