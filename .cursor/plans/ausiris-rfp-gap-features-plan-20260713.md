# Ausiris RFP — Gap Feature Plan

**Date:** 2026-07-13  
**Context:** Close product gaps vs Ausiris Co., Ltd. Retail CRM RFP (B2C gold / silver / saving / small bar / jewelry across LINE, social, marketplace, app, POS).  
**Scope of this doc:** Feature groups to develop (problem, RFP examples, locked direction). Not detailed schema/API design.

Sections are ordered by RFP salience; build/dependency order is at the end (foundation is §5 Activity extensibility).

### Explicitly out of this build list

| RFP ask | Handling |
|---------|----------|
| ROI / exec dashboard UI | Defer — ship data model + events first; reporting is joins later |
| Churn prevention as its own system | Covered by RFM audiences + existing workflows/outbound |
| Sales conversion (chatbot / salespage / LINE close) | Existing Customer Service AI |
| AI personalized campaign | Existing AI decisioning |
| Loyalty cross-channel | Assume existing unless separately scoped as incomplete |
| Deep connector / migration build | Separate integration scoping |

---

## 1. RFM as Audience extension

### What we are trying to solve

Ausiris wants a central CDP where **Tier (RFM) updates automatically** from behavior across touchpoints, so they can segment and act without sales manually tagging VIPs vs lapsed buyers.

Classic RFM is **state over time**, not a one-shot trigger:

- **R (Recency):** days since something last happened (often purchase; should be configurable by activity type)
- **F (Frequency):** how often in a window
- **M (Monetary):** how much in a window

Scores change when people buy **and** when the calendar moves (someone becomes “at risk” because nothing happened). That needs **scheduled scoring** plus audience membership refresh — not purchase webhooks alone.

### RFP examples

- “อัปเดท Tier (RFM) ของลูกค้าในฐานข้อมูลจากทุก Touchpoints”
- Objective: CDP with Tier (RFM) updated automatically
- Churn-style use: identify cooling customers → reach via chosen channel (workflow on RFM audience)
- Vendor understanding: Thai omnichannel journey (LINE + marketplace + store), not B2B lead scoring only

### Locked direction

- **Extension of the Audience app**, not a separate product.
- **RFM segment ≠ loyalty Tier.** The RFP's "Tier (RFM)" maps to Audience segments in our model, not the loyalty tier system. Loyalty tiers are untouched by this build; whether tier conditions may later reference RFM scores is a separate decision, out of scope here.
- **Merchant-configurable RFM params** (windows, score bands / segment labels).
- **Scheduled RFM compute job** (e.g. daily) writes `r_score` / `f_score` / `m_score` / `rfm_segment` on the member.
- **Recency by activity type** (default purchase; e.g. days since last `page_view`, LINE open, custom activity).
- Audiences filter on computed RFM fields; optional default RFM audiences from settings.
- **Raw AMP conditions** already help F/M (`purchase_ledger` count/sum + time window). True day-based R and scored segments are the net-new RFM layer.
- Dynamic audiences are **already cron-reconciled** (`amp-reconcile-dynamic-audiences`); RFM scoring feeds that model.

---

## 2. Funnel / journey stages (special audiences)

### What we are trying to solve

They want a visible **Sales Pipeline & Journey Stage** with conversion between stages, updated **automatically** from behavior — not a salesperson dragging B2B deal stages.

For retail gold this looks like lifecycle, e.g. Lead (added LINE) → Engaged → Registered / KYC → First purchase → Repeat — across LINE, app, ecom, POS.

### RFP examples

- “สร้าง Sales Pipeline ที่ชัดเจนและวัดผล Conversion ได้ในแต่ละ Journey Stage”
- “กำหนดและวัดผลขั้นตอนการขาย (Sales Pipeline & Milestone)”
- “บันทึกและอัปเดท Journey Stage, Pipelines ในฐานข้อมูลอัตโนมัติ”
- Evaluation: understanding of “Journey Stage แบบ Omnichannel แบบไทยๆ”

### Locked direction

- **Funnel = container**; **stage = special audience** with `funnel_id` + `sort_order` + entry rules (same condition language as audiences, including RFM later).
- **Latest-stage-wins:** a member is in exactly one stage per funnel — the highest-ordered stage whose entry rules currently match. Stages are rule-derived, so members may skip stages or regress; traversal is not assumed linear.
- **Stage transitions are recorded as first-class events** — a new capability, since audience reconciliation today updates membership without history. Conversion metrics (stage N → N+1) read from this transition log; viz follows once transitions exist.
- Not a classic Salesforce opportunity pipeline object.

---

## 3. Attribution schema (UTM) & typed metadata

### What we are trying to solve

They need **lead source / campaign entry** tracking when people come from social ads, LINE links, salespages, etc. Facebook does **not** give CRM the FB user graph; attribution works by stamping first-party events when the click carries tracking params (or later identify).

UTM / attribution fields are a **structured schema** (with types for operators), separate from generic profile custom fields, and usable in **Audience + AMP workflows**.

### RFP examples

- “ระบุแหล่งที่มาของลูกค้า (Lead Source Tracking) และวัดผล ROI ได้ในแต่ละ Campaign”
- “ระบุแหล่งที่มาของลูกค้าได้ว่ามาจาก Campaign ไหน ช่องทางไหน”
- Demo: “การตั้งค่า Campaign และการวัดผล ROI”
- Touchpoints: many FB/IG/TikTok pages, LINE OAs, Express / My Gold Plus — ads and links into those properties

### Locked direction

- **Default UTM dimensions** + **custom UTM / attribution keys** (merchant-configurable).
- **Separate from profile custom fields** (attribution taxonomy ≠ CRM attributes like nickname).
- **Both storages:**
  - **Acquisition source** on **profile** — first recorded attribution, written once (distinct from the per-purchase "first-touch" attribution model in §4)
  - Time series on **activities / orders** (every later touch)
- URL query params are **transport only** — they fill attribution fields on the activity (and maybe profile), they are not activity types.
- Typing and condition-contract registration ride on the **typed field registry** defined in §5 — attribution fields are one consumer of that shared mechanism. This section owns only the UTM/attribution taxonomy itself.
- This section owns the **attribution stamp** concept (UTM / `campaign_id` dimensions on an event row); §4 and §5 reference it.

---

## 4. Marketing campaign object & purchase ROI attribution

### What we are trying to solve

A **campaign** is a named marketing push (channel, offer, budget, schedule) — e.g. summer LINE coupon, FB→LINE gift-bar ads, TikTok Live Iris Jewel, TooMush + J POINT launch. They need ROI: attributed revenue vs cost, for **new and existing** members (not acquisition-only).

Attribution = rule that assigns (or splits) purchase value across campaign-tagged touches in a lookback window; merchant chooses the model.

### RFP examples

- “วัด ROI ของ Campaign การตลาดได้อย่างชัดเจนในแต่ละช่องทาง”
- “มี AI วิเคราะห์… และวัดผล Personalized Campaign” (measurement side; AI engine = existing decisioning)
- Functional: Lead Source Tracking + ROI Dashboard (data side here; UI later)
- Demo: create/manage campaigns and measure ROI

### Locked direction

- New **marketing / attribution campaign** domain — do **not** overload existing loyalty `campaign` / `campaign_master`.
- Campaign fields: channel, offer, budget, schedule, status, etc.
- **Tracking keys** bind external carriers → `campaign_id` (UTM values, tracked links, LINE params, vouchers).
- When keys appear, **stamp timeline events and purchases** for new and returning members.
- **Campaign relates to the activity instance** as an attribution stamp (`campaign_id` / UTM on the event row) — **not** as the activity’s content value (path/SKU/amount).
- Attribution models (merchant-selectable): e.g. first-touch, last-touch, multi-touch linear split of purchase value in lookback window. ("First-touch" here is a per-purchase lookback model — distinct from the once-only acquisition source on the profile, §3.)
- **ROI** = attributed value vs campaign cost (formula can be ratio or (value − cost) / cost; pick one in detail design).
- Reporting UI deferred; structure must support joins for dashboards later.

---

## 5. Activity log extensibility (standard + custom)

### What we are trying to solve

CDP “Customer Activity Log” must record omnichannel behavior. Many client events **won’t map** to fixed objects (purchase, redeem, etc.) — e.g. vending dispense, price-alert view, LINE rich-menu click, custom app events. Need **custom activities** while keeping first-class standard types.

### RFP examples

- “บันทึกประวัติกิจกรรมลูกค้า (Customer Activity Log) อัตโนมัติ”
- CDP gathering data from all touchpoints (LINE, social entry, marketplace, app, POS, 3rd party, vending)
- Downstream: funnel stage rules, RFM recency-by-type, campaign stamps on those events

### Locked direction

| Layer | Meaning | Example |
|-------|---------|---------|
| **Activity type** | Master list (standard + merchant-defined custom types) | `page_view`, `purchase`, `vending_dispense` |
| **Activity values / properties** | Facts on the instance | `page_path`, `amount`, `device_id` |
| **Attribution on the same row** | Optional UTM / `campaign_id` | `utm_campaign=summer` |

- **Typed field registry (shared mechanism, defined here):** every configurable field declares a **type** (string, number, date, boolean, enum, entity ref) so AMP condition operators are correct, and is registered into the condition contract for Audience + Workflow. Consumers: custom activity properties (this section), attribution/UTM fields (§3), and future configurable metadata.
- **Values are free by default** (typed). No global master of every URL/value.
- **Master/enum only when** a property is configured as enum/select (options list scoped to that field only), or the value is an existing CRM entity (SKU, store, reward).
- Page view example: type `page_view` + properties from URL (path + UTM). UTM fills attribution fields; path is content value — same row, different dimensions.
- Activities **without** URL still work (POS, LINE webhook, vending); attribution may come from voucher / LINE campaign id / none.
- Custom activities: `name` + typed properties; expose property schema to AMP conditions where configured.
- Campaigns link via **tracking keys → stamp on activity**, not via an “activity value = campaign name” catalog.

---

## Conceptual cheat sheet (locked)

```text
PROFILE
  acquisition source (first-touch UTM / lead source, written once)
  RFM scores + segment
  (funnel stage via audience membership; latest-stage-wins)

ACTIVITY (timeline event)
  type (master)
  values/properties (free typed; enum optional)
  optional attribution: utm_* , campaign_id

MARKETING CAMPAIGN
  object + budget + schedule
  tracking keys → campaign_id

AUDIENCE
  normal segments
  RFM-based (on computed scores)
  funnel stages (ordered special audiences)

AMP WORKFLOWS
  same condition contract; typed metadata/UTM/RFM/activity fields usable when registered
```

**UTM ≠ activity type.** UTM = attribution dimensions on profile and/or activities.  
**Campaign ≠ activity value.** Campaign = stamp on the activity for ROI.  
**RFM ≠ only triggers.** Score on a schedule; audiences reconcile on cron (already supported).  
**RFM segment ≠ loyalty tier.** The RFP's "Tier (RFM)" is an Audience segment in our model; loyalty tiers are untouched.  
**Acquisition source (profile) ≠ first-touch model (per purchase).** One is written once at acquisition; the other is a lookback attribution rule.

---

## Suggested detail-planning order

1. **Activity extensibility + typed metadata** — foundation for stamps and conditions  
2. **Attribution schema (UTM)** — profile first-touch + event history  
3. **Marketing campaign + attribution models** — depends on 1–2  
4. **RFM scoring + Audience extension** — depends on activity types for recency-by-type  
5. **Funnel as special audiences** — reuses audience conditions (incl. RFM/activity)

---

## Open items for detail design (not blocking this plan)

- Exact RFM band formulas and default activity type for R  
- Whether F/M also refresh on purchase (in addition to the scheduled compute) in v1  
- Attribution lookback default and which models ship in v1  
- Naming of marketing campaign tables vs loyalty `campaign*`  
- How latest-stage-wins is enforced during audience reconciliation, and whether any funnels need a monotonic (no-regression) mode  
- Which standard activity types ship in v1 vs custom-only  
