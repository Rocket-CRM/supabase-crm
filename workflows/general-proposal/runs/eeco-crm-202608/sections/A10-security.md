## 5.6 Control who sees LOI/NDA/financials and keep an audit trail

Investment cases accumulate documents that must not be open to the whole office. **Roles** and **need-to-know** rules limit access; **dynamic watermarking** identifies the viewer on sensitive copies; and the **audit trail** records view, edit, and download events. These controls apply to the same cases, activities, and documents used in daily work.

## Security records and evidence

| Object | What it is | Why it matters |
|---|---|---|
| **Role** | Named permission set (e.g. Staff, Manager, Director, plus สกพอ.-specific roles) | Same case, different visible modules |
| **Permission** | Allow/deny on actions and sensitivity classes | Enforced on every read/download path |
| **Sensitivity class** | Label on a document or field group (e.g. LOI/NDA/financial) | Drives need-to-know |
| **Watermark event** | Overlay of account + datetime on view/download | Deters casual leakage; ties copy to a person |
| **Audit event** | Who / what / when on view, edit, download | Investigation and POC history scenarios |

Consent records are described in Section 5.1; warranty intake and resolution times are in Section 7.

## Access, watermark, and audit controls

| Feature | What happens | Includes (sub-capabilities) |
|---|---|---|
| Role-based access | The same investment case presents different modules and fields depending on the signed-in role, so need-to-know is enforced in the product rather than by convention. | Default Staff / Manager / Director packs; additional สกพอ.-specific roles from BRD; module-level and action-level allow/deny enforced in the API on every sensitive route. |
| Need-to-know on sensitive docs | LOI, NDA, and financial statements are limited to senior roles and/or the project owner; Staff do not open them by default. | Sensitivity class on each file; deny list for Staff by default; grant path for project owner and configured senior roles. |
| Dynamic watermark | On view or download of a sensitive document, the system overlays the account identity and time so a leaked copy can be traced. | Account name and date/time overlay; applies to in-app viewer and download/PDF path; pairs with an audit event. |
| Application audit trail | The system records who viewed, edited, or downloaded which record or document and when, for investigation and demonstration. | View, edit, and download events; retention ≥180 days; export for investigation; append-oriented history from the application’s point of view. |
| Consent-linked access | Sensitive use of personal data is gated by consent history captured in Section 5.1. | Check purpose and withdrawal state before sensitive use; guidance messaging when consent is missing or withdrawn. |
| Data protection in the product path | Sensitive payloads travel and rest under TLS and platform encryption as specified in Section 4; the application never embeds production secrets in source or client bundles. | TLS on officer HTTPS paths; secrets via สกพอ.-approved mechanism at install; PII minimized in non-production copies used for build/UAT. |
| OWASP-aligned secure development | Delivery follows current OWASP-aligned secure development practice through build and review with สกพอ. before go-live. | OWASP Top 10 mitigation mindset; input validation and parameterized queries; dependency hygiene; secure error handling; security-focused review; findings from joint security testing closed before acceptance. |
| สกพอ. SSL in production | Production HTTPS uses the certificate supplied by สกพอ., as required for go-live. | Buyer-supplied certificate on the public entry (TOR 5.10.2); TLS on officer access paths. |
| Observability handoff | The application emits structured application and audit logs that สกพอ. can retain or forward into the Authority’s monitoring tools. | Log fields aligned with audit events; retention guidance in the operations runbook; export path for Authority monitoring. |
| Joint UAT + security scan | Controls are proven with สกพอ. officers in joint UAT and security testing before acceptance. | Scenario scripts covering RBAC, watermark, and audit; vulnerability/security scan findings tracked to closure before Phase 2/3 gates. |

## Sensitive-document access

When an officer opens a case workspace (Section 5.3), the API loads modules allowed for their **roles**. A Staff user may see timeline and tasks but not the LOI file list; a Director or project owner may open the PDF — the viewer applies a **dynamic watermark** and writes an **audit event**. The same rules apply to exports and downloads. Admin configuration of roles and sensitivity classes is done in the product admin area; defaults are set in BRD with สกพอ.

Secure development—input validation, authorization checks, and dependency hygiene—is part of every release that reaches UAT. Rocket implements and tests the application controls officers use; production perimeter and monitoring responsibilities follow the ownership model in Section 4.4.

{{mockup:M16}}

{{mockup:M17}}

{{mockup:M18}}

Reference: TOR 5.8, 5.10.
