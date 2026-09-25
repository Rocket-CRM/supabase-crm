# 3. Delivery model and methodology

## What Rocket delivers

| Layer | What Rocket delivers |
|---|---|
| Configurable product core | Organizations, persons, cases, activities, tasks, tickets, pipelines, roles, audit, dashboards — administrators can change stages, checklists, and routing without a code release for every policy tweak |
| Custom build for สกพอ. | Pre-incentive journey semantics, bureau-crossing escalation, SSO EECO login, EEC OSS status pull, dynamic watermark on sensitive files, migration from bureau Excel |
| Handover | Perpetual license, source code, training, clean structured database |

## How the work runs

| Stage | Features / artefacts สกพอ. can use or review | TOR |
|---|---|---|
| Plan | Schedule and role coverage | 5.1 |
| BA | BRD; journey and ticket workflows | 5.2 |
| Design | SDD, ERD, UI designs, vendor-agnostic infra min specs, OSS API interface scope | 5.3 |
| Risk | Impact notes for OSS and related systems | 5.4 |
| Build | Working CRM modules below | 5.5–5.7 |
| Secure / migrate | Watermark, audit, RBAC; staging → clean DB | 5.8–5.9 |
| Prove | Joint UAT; OWASP-aligned hardening; สกพอ. SSL | 5.10 |
| Hand over | Admin/User TTT, manuals, license, source, backup/DR | 5.11, 7.3 |

## Application stack

| Layer | Choice |
|---|---|
| UI | Next.js — form-based, mobile-friendly |
| API | Node.js — rules, SLA, integrations (REST; SOAP if required) |
| Data | PostgreSQL |
| Login | SSO EECO |

The integrated delivery timeline is in **Section 6**; warranty intake and technical operations are in **Section 7**.

Reference: TOR 5.1–5.4, 10.2(4); ภาคผนวก ก 2.1.
