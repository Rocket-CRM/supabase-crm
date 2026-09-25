# Standard technical practices (general proposals)

Durable **Resource** for custom / government / non-productized bids. Distilled from Rocket’s technical-architecture narrative style (e.g. Caltex Part VI — Technical Architecture & System Design) and generalized so writers can reuse **patterns**, not paste a loyalty SaaS stack.

**Hard rule:** Never copy this document wholesale into a customer proposal. Select practices after the run’s **hosting / ops / scale context** is recorded in `dossier.md`. The **shape** of each practice in customer prose must match that context.

Companion: `REFERENCE.md` (when to pull), `SCAFFOLDS.md` (where it lands in section types).

---

## Why this exists

Caltex-style packs describe a **Rocket-operated, high-scale loyalty platform** (API gateway, Kafka, Redis, SIEM/SOC, multi-channel mobile). Most Thai government CRM bids describe **software delivered onto buyer-shared cloud or on-prem**, with the Authority owning production ops. The same *ideas* (layered security, OLTP vs analytics discipline, secure SDLC) apply; the *components and ownership* do not.

---

## Context dimensions (record in dossier before Write)

Resolve these in **Understand / Clarify**. Writers must not assume Caltex defaults.

### H1 — Production hosting model

| Code | Meaning | Typical government | Typical Rocket SaaS / loyalty |
|---|---|---|---|
| `buyer_cloud_install` | Buyer procures cloud hosts (e.g. GDCC); bidder supplies vendor-agnostic min specs + install/config | EECO, most e-bidding | Rare |
| `buyer_onprem_install` | Buyer data centre / on-prem; bidder install on buyer kit | Some agencies | Rare |
| `bidder_cloud_prod` | Bidder hosts production on bidder cloud | Uncommon in gov TOR | Common for SaaS demos |
| `rocket_saas_shared` | Multi-tenant Rocket platform; customer is a tenant | Usually **out of scope** for gov source-code bids | Caltex / product CRM |

### H2 — Production operations ownership

| Code | Who runs WAF, SIEM, patching, on-call, backups in prod |
|---|---|
| `buyer_ops` | Authority / buyer IT (or their cloud MSP) |
| `bidder_ops` | Rocket (or Rocket’s MSP) |
| `shared_ops` | Split by written RACI (name each control) |

### H3 — Async / messaging needs

| Code | Use when | Do **not** use when |
|---|---|---|
| `sync_api` | Low volume; request/response enough | — |
| `db_native_queue` | Modest async (SLA timers, import jobs, internal notifications) without a separate broker cluster | Buyer will not operate extra middleware |
| `external_broker` | High fan-out, multi-service streaming, audit/replay at loyalty scale (Kafka / RabbitMQ / equivalent) | **Buyer-hosted shared infra** where the Authority would also have to host/operate the broker unless TOR funds it |

### H4 — Reporting / analytics workload

| Code | Meaning |
|---|---|
| `oltp_embedded` | Reports run against primary (or same) DB; keep queries light; acceptable for ≤hundreds of users |
| `read_replica` | Heavy dashboards on replica / secondary |
| `warehouse` | ETL to warehouse / lake for BI (only if TOR/scale demands) |

### H5 — Domain / threat surface

| Code | Pull extra practices for… |
|---|---|
| `gov_crm` | RBAC, audit, PDPA, document sensitivity, SSO — not POS fraud matrices |
| `loyalty_retail` | Fraud, POS/EDC, multi-channel earn/burn, partner APIs (Caltex-depth) |
| `payments` | PCI-oriented controls only if in scope |

---

## Practice catalog

Each practice has an ID. **Apply when** / **Do not apply** are gates. **Lands in** maps to SCAFFOLDS section types (customer-facing). **Source note** = Caltex Part VI theme generalized.

### P01 — Layered logical architecture

| | |
|---|---|
| **Idea** | Separate client → API/application services → data; optional gateway / adapters for externals. One diagram showing concerns, not a product brochure. |
| **Apply when** | Any bid that scores architecture / tools (ภาคผนวก methodology). |
| **Do not apply** | As a **Rocket SaaS multi-tenant** diagram when H1 is `buyer_*_install`. Do not draw Kafka/Redis/CDN tiers the buyer will not run. |
| **Lands in** | `architecture_and_integration` (logical architecture). |
| **Shape by context** | `buyer_*_install`: thin stack (UI · API · DB · buyer IdP/adapters). `rocket_saas_shared` / `bidder_cloud_prod`: may show gateway, cache, object storage Rocket operates. |
| **Source note** | Caltex “Overall System Architecture” / API gateway → services → data — keep the *layering*, drop loyalty-only services. |

### P02 — Unified application backend

| | |
|---|---|
| **Idea** | All UI channels call one API so business rules (RBAC, journey, SLA) are not reimplemented per client. |
| **Apply when** | Web + tablet/mobile browser, or multiple UIs. |
| **Do not apply** | Inventing Flutter / LINE LIFF / POS channels the TOR does not ask for. |
| **Lands in** | `architecture_and_integration`. |
| **Shape by context** | Gov CRM: usually “browser/tablet → Next.js → Node API → PostgreSQL.” Loyalty: multi-channel diagram only if in scope. |
| **Source note** | Caltex “Unified Backend Architecture.” |

### P03 — Event-driven / async processing

| | |
|---|---|
| **Idea** | Decouple interactive requests from background work (jobs, notifications, fan-out). |
| **Apply when** | H3 ≠ `sync_api` and TOR/scale needs async. |
| **Do not apply** | **Default Kafka / Confluent / RabbitMQ** on `buyer_cloud_install` or `buyer_onprem_install` unless the TOR (or Clarify) funds buyer-operated messaging and names who hosts the cluster. Prefer `db_native_queue` or scheduled jobs inside the app/DB. |
| **Lands in** | `architecture_and_integration` (processing model); rarely a separate chapter. |
| **Shape by context** | `db_native_queue`: “in-database / application job queues for migration, SLA timers, digests.” `external_broker`: only with explicit ownership of broker ops. |
| **Source note** | Caltex PGMQ / Kafka / RabbitMQ split — that *split is SaaS-scale*; do not treat it as government default. |

### P04 — Database design philosophy (ledger / state / queue)

| | |
|---|---|
| **Idea** | (1) **Append-oriented** history where auditability matters. (2) **Mutable state** for current status. (3) **Queue / staging** for async or cutover work. Idempotency where retries exist. |
| **Apply when** | Architecture or data-model depth is scored; audit/history TOR clauses. |
| **Do not apply** | Claiming full **event sourcing** / loyalty **points ledgers** for a government case CRM unless the domain needs it. |
| **Lands in** | `architecture_and_integration` (database design). |
| **Shape by context** | Gov CRM: stage history + audit events append-only; case/ticket state mutable; Excel staging tables for migration. Loyalty: immutable currency ledgers. |
| **Source note** | Caltex “Database Design Philosophy” (Ledger / State / Queue patterns). |

### P05 — OLTP vs analytics / reporting isolation

| | |
|---|---|
| **Idea** | Interactive writes (cases, stages, tickets) must not be starved by heavy reporting. Separate paths by load. |
| **Apply when** | Dashboards + operational DB in same bid; or TOR cites performance. |
| **Do not apply** | Mandating a **data warehouse** on shared gov infra by default. |
| **Lands in** | `architecture_and_integration`; light cross-ref from reporting `capability_module`. |
| **Shape by context** | `oltp_embedded` (typical EECO): same PostgreSQL; constrain report queries; optional off-peak jobs. `read_replica` / `warehouse` only if H4 and hosting allow. |
| **Source note** | Caltex warehouse + primary DB separation — principle yes; warehouse component optional. |

### P06 — Performance & scaling (proportionate)

| | |
|---|---|
| **Idea** | State capacity targets and techniques that match named-user / transaction volume — indexes, pagination, connection pooling, horizontal app nodes if needed. |
| **Apply when** | TOR or scoring asks for capacity / SLA / concurrent users. |
| **Do not apply** | Caltex-scale metrics (e.g. 100k tx/hour, 500 stations) unless this bid’s numbers justify them. |
| **Lands in** | `architecture_and_integration` (infra minima or non-functional notes). |
| **Shape by context** | EECO-like: ≥100 named users → modest app HA + DB sizing in min infra table. |
| **Source note** | Caltex “Performance & Scaling Strategy” — keep techniques, replace metrics. |

### P07 — Defense-in-depth security (by layer)

| | |
|---|---|
| **Idea** | Controls at perimeter, application, data — not a single “we are secure” paragraph. |
| **Apply when** | Any security / OWASP / PDPA TOR clause. |
| **Do not apply** | Claiming **Rocket-operated WAF, CDN edge, DDoS, SIEM, 24/7 SOC** when H2 is `buyer_ops`. Those belong to the buyer’s cloud/SOC (or are out of scope). |
| **Lands in** | Split: stack placement in `architecture_and_integration`; operator-facing controls (RBAC, watermark, audit) in `security_and_compliance` / capability modules. |
| **Shape by context** | See **Ownership overlay** below. |
| **Source note** | Caltex “Security Architecture” defense-in-depth — keep layers; reassign ownership. |

### P08 — Authentication & authorization

| | |
|---|---|
| **Idea** | Strong identity; RBAC (and need-to-know where required); session hygiene; API enforces every sensitive action. |
| **Apply when** | Always for named-user systems. |
| **Do not apply** | Inventing MFA/biometrics/mobile OTP unless TOR or Clarify requires. Prefer buyer SSO when TOR mandates it. |
| **Lands in** | Integration/SSO capability + `security_and_compliance`. |
| **Shape by context** | Gov: SSO EECO / buyer IdP. SaaS loyalty: JWT/OAuth + MFA for admin as designed. |
| **Source note** | Caltex Auth JWT/OAuth2/MFA — map to buyer IdP when install model. |

### P09 — Data protection (transit, rest, secrets, PII)

| | |
|---|---|
| **Idea** | TLS in transit; encryption at rest where platform allows; secrets not in source; PII minimization / masking in non-prod. |
| **Apply when** | Security or PDPA clauses; always state for government packs. |
| **Do not apply** | Naming **HashiCorp Vault** / bidder KMS as production truth when secrets live in **buyer** secret store / cloud KMS unless Clarify says Rocket operates them. |
| **Lands in** | `architecture_and_integration` (infra/network) + `security_and_compliance`. |
| **Shape by context** | `buyer_*_install`: TLS + buyer SSL cert; DB private segment; secrets via buyer-approved mechanism. `bidder_ops`: may name Rocket secret management. |
| **Source note** | Caltex TLS/AES/Vault/tokenization — keep requirements; localize tooling. |

### P10 — Application audit & integrity

| | |
|---|---|
| **Idea** | Append-oriented application audit of sensitive view/edit/download; retention per TOR; export for investigation. |
| **Apply when** | TOR audit / evidence clauses (common in gov). |
| **Do not apply** | Substituting SIEM for application audit — different layers. |
| **Lands in** | `security_and_compliance` (and document/case modules that emit events). |
| **Source note** | Caltex audit/replay themes + gov watermark/audit TOR patterns. |

### P11 — Observability & security monitoring

| | |
|---|---|
| **Idea** | Logs, metrics, alerts so incidents are detectable. |
| **Apply when** | Always decide **who operates** monitoring — never imply Rocket SOC on buyer infra by default. |
| **Do not apply** | **Elastic SIEM + 24/7 SOC + automated threat response** as Rocket deliverables when H2 = `buyer_ops`. Instead: application/audit logs retained and exportable for the buyer’s monitoring stack. |
| **Lands in** | `architecture_and_integration` (ops interfaces) and/or delivery go-live; light touch in `security_and_compliance`. |
| **Shape by context** | `buyer_ops`: “system emits structured logs + audit; Authority integrates to SIEM if any.” `bidder_ops`: Rocket monitoring stack may be named. |
| **Source note** | Caltex SIEM/SOC — ownership-gated. |

### P12 — Secure development lifecycle (OWASP)

| | |
|---|---|
| **Idea** | OWASP-aligned coding, input validation, parameterized queries, dependency hygiene, security review before go-live; SAST/dependency scan when delivery model supports CI. |
| **Apply when** | TOR cites OWASP / secure SDLC (e.g. EECO 5.10); good default for scored methodology. |
| **Do not apply** | Claiming PCI DSS / ISO 27001 **certification** unless the company evidence pack supports it for this bid. |
| **Lands in** | `security_and_compliance`; optional methodology mention in delivery model. |
| **Source note** | Caltex “Secure Development Practices.” |

### P13 — Fraud prevention matrix (domain-specific)

| | |
|---|---|
| **Idea** | Multi-layer fraud controls and case matrix by channel. |
| **Apply when** | H5 = `loyalty_retail` (or similar) and TOR/commercial risk needs it. |
| **Do not apply** | Government CRM / investor case management by default. |
| **Lands in** | Dedicated security or earn/burn chapter in loyalty bids only. |
| **Source note** | Caltex fraud Part VI — **do not** import into EECO-style packs. |

### P14 — Multi-channel customer front ends

| | |
|---|---|
| **Idea** | Native app / PWA / LINE / POS as separate channels on one API. |
| **Apply when** | TOR requires those channels. |
| **Do not apply** | Government internal officer CRM with browser/tablet only. |
| **Lands in** | `architecture_and_integration` + channel capability modules. |
| **Source note** | Caltex front-end multi-channel — loyalty-gated. |

### P15 — SaaS / shared multi-tenant platform architecture

| | |
|---|---|
| **Idea** | Tenant isolation, shared control plane, Rocket-operated data plane. |
| **Apply when** | H1 = `rocket_saas_shared` and the commercial model is SaaS. |
| **Do not apply** | **Most government projects** on shared **buyer** infra with perpetual license + source code. Do not describe the customer as a tenant of Rocket’s SaaS control plane. |
| **Lands in** | Only SaaS proposals — not typical e-bidding technical approach. |
| **Source note** | Implicit in Caltex platform narrative — **exclude** for EECO-like H1. |

---

## Ownership overlay (P07–P11)

When writing customer prose, attribute each control:

| Control family | `buyer_ops` + `buyer_*_install` | `bidder_ops` / `rocket_saas_shared` |
|---|---|---|
| Edge WAF / DDoS / CDN | Buyer cloud / MSP | Rocket (or named CDN) |
| TLS certificate on public URL | Buyer-supplied (if TOR says so) | Rocket or buyer per contract |
| App RBAC, watermark, business audit | **Bidder-built product behavior** | Same |
| DB encryption / private network | Per buyer cloud capability + min spec | Rocket platform |
| Secrets store | Buyer-approved | Rocket Vault/KMS |
| SIEM / SOC | Buyer | Rocket |
| OS patching / host hardening | Buyer (hosts they procure) | Rocket |
| Secure SDLC / OWASP in code | **Bidder** | Bidder |

---

## Pull matrix by hosting model (writer cheat sheet)

| Practice | `buyer_cloud_install` / `buyer_onprem_install` | `bidder_cloud_prod` | `rocket_saas_shared` |
|---|---|---|---|
| P01 Layered architecture | **Yes** — thin stack | Yes | Yes — fuller platform |
| P02 Unified backend | **Yes** | Yes | Yes |
| P03 Event-driven | **Only** `sync_api` or `db_native_queue` unless TOR funds broker | Optional broker | Often Kafka/queues as designed |
| P04 DB philosophy | **Yes** — adapted to domain | Yes | Yes |
| P05 OLTP vs analytics | **Yes** — usually `oltp_embedded` | As needed | Often warehouse |
| P06 Performance | **Yes** — buyer user counts | Yes | Caltex-scale only if true |
| P07 Defense-in-depth | **Yes** — buyer edge + bidder app | Full stack bidder | Full stack Rocket |
| P08 AuthZ | **Yes** — prefer buyer SSO | As designed | As designed |
| P09 Data protection | **Yes** — buyer secret/KMS language | Bidder tools OK | Bidder tools OK |
| P10 App audit | **Yes** | Yes | Yes |
| P11 Observability | **Logs for buyer**; no Rocket SOC claim | Rocket monitoring OK | SIEM/SOC if true |
| P12 Secure SDLC | **Yes** | Yes | Yes |
| P13 Fraud matrix | No (unless domain) | Loyalty only | Loyalty only |
| P14 Multi-channel FE | Only if TOR | If in scope | If in scope |
| P15 SaaS tenancy | **No** | Rare | **Yes** |

---

## Where practices land (section types)

| Section type | Typical practice IDs | Customer shape |
|---|---|---|
| `architecture_and_integration` | P01–P06, slice of P07/P09/P11 | Diagrams + infra minima + DB philosophy + async model + ownership of edge/monitoring |
| `security_and_compliance` | P07–P12 (app-facing), not P15 | RBAC, audit, PDPA, OWASP, watermark; stack perimeter only as “relies on buyer cloud…” |
| `capability_module` (reporting) | P05 cross-ref | One sentence: reports do not block OLTP |
| `capability_module` (SSO/integration) | P08 | Buyer IdP |
| `delivery_plan` | P11/P12 gates | UAT + security scan; log handoff to buyer ops |
| Loyalty-only chapters | P13, P14 | Not used in gov CRM spine |

---

## Writer procedure (before Write — dossier/outline gate)

1. **Dossier** — fill H1–H5 (and any Clarify answers). Paste a short **Practices pull** bullet list: IDs in / IDs out / reason.
2. **Outline** — for each `architecture_and_integration` and `security_and_compliance` row, add `reads: …/standard-technical-practices.md (Pxx, Pyy)` and a `scope_note` naming the shape (e.g. “P03 as db jobs only — no Kafka”).
3. **Write** — open this file + TOR clauses for that section. Rewrite selected practices in **buyer vocabulary** and **this stack** (e.g. Next.js · Node · PostgreSQL). Do not paste Caltex service names (Wallet, Mission, Kong, Confluent) unless this bid uses them.
4. **Self-check** — no SaaS tenancy (P15) on buyer-install; no Rocket SIEM/SOC on `buyer_ops`; no external broker unless H3 = `external_broker` with ownership named.

**Customer prose rule:** Translate selected practices into the buyer’s operating language. Do not expose P-IDs, catalog rows, internal pull logic, or unrelated Caltex/SaaS component names in compiled documents.

---

## Worked example — EECO (`eeco-crm-202608`)

| Dimension | Value |
|---|---|
| H1 | `buyer_cloud_install` (สกพอ. procures; GDCC example; vendor-agnostic min spec) |
| H2 | `buyer_ops` (production hosts and edge); bidder builds app controls + emits logs |
| H3 | `db_native_queue` / scheduled jobs (SLA, migration, digests) — **not** Kafka |
| H4 | `oltp_embedded` (native dashboards; ≥100 users) |
| H5 | `gov_crm` |

| Pull in | Where | Shape |
|---|---|---|
| P01, P02 | §4 Architecture | Browser/tablet → Next.js → Node → PostgreSQL; SSO/OSS adapters |
| P03 | §4 | Application/DB jobs only — no broker cluster |
| P04 | §4 Database design | Append audit/stage history; mutable case state; staging for Excel |
| P05 | §4 + light §5.4 | Reports on same DB with query discipline; no warehouse claim |
| P06 | §4.2.1 min infra | Sized for ≥100 named users |
| P07–P09 | §4 (placement) + §5.6 (behavior) | Buyer edge/TLS cert; API RBAC; encryption/private DB per min spec; secrets on buyer infra |
| P10, P12 | §5.6 | Audit ≥180 days; OWASP-aligned build; joint UAT/scan |
| P11 | §4 / §5.6 / go-live | Structured app + audit logs for สกพอ. ops — **not** Rocket 24/7 SOC |
| **Out** | — | P13, P14, P15, Kafka/Redis-as-platform, Caltex fraud matrix, Flutter/LINE |

---

## Provenance

- Narrative patterns adapted from Caltex proposal **Part VI — Technical Architecture & System Design** (Rocket Innovation, confidential).
- This Resource is **internal**. Customer docs must not cite this filename or “Caltex architecture” unless that bid’s NDA/pack allows cross-reference (they almost never do).
