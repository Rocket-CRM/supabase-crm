# Yuanta Securities — Customer Service Demo Configuration

**Merchant:** Yuanta Securities (Thailand) — Yuanta Rewards programme  
**Document type:** Demo / UAT / implementation seed (not deployed to production by default)  
**Aligned to:** Yuanta MCA dossier (AMP + CS AI optional modules), FR-C-01 through FR-C-11, NFR-01 Phase 1 POC  
**Platform tables:** `cs_merchant_config`, `cs_merchant_guardrails`, `cs_procedures`, `cs_knowledge_*`, `cs_conversations`, `cs_messages`, `cs_voice_calls`, `cs_sla_policies`, `cs_business_hours`, channel credentials (logical)

**Live merchant ID (seeded in Supabase):** `fe754adc-766b-4553-abda-7bc80dcc9724` (`Yuanta Demo` / `yuanta-demo`)

---

## 1. POC operating model

| Setting | Value | Rationale (dossier) |
|---|---|---|
| POC channels | LINE OA (primary), Web chat (secondary) | FR-C-08; voice via SIP REFER is a later track |
| POC traffic slice | 3% of eligible LINE + web sessions | Within 2–5% guidance; FAQ / loyalty / reward ops only |
| AI autonomy (POC) | `suggest_and_send` on allow-listed intents; human queue for escalation | Per-resolution pricing story; clean handoff |
| Voice POC | Disabled in Phase 1 config; voice_config stub only | CUCM REFER + compliance workshop pending |
| Languages | Thai (primary), English (secondary) | FR-C-05 |
| Business hours | Mon–Fri 08:30–17:00 ICT; Sat 09:00–12:00 (reward hotline) | Bangkok retail brokerage pattern |
| Excluded from AI (hard) | Trade orders, order modifications, price opinions, regulated complaints, AML reporting, account opening KYC | FR-C-08, SEC/AML narrative |

**Eligible AI intents (POC):**

- `loyalty_points_balance`
- `loyalty_tier_status`
- `reward_catalog_inquiry`
- `reward_redemption_assist`
- `physical_reward_delivery_status`
- `promotion_campaign_faq`
- `ysinvest_app_help`
- `account_profile_non_trade` (display-only fields synced from Yuanta back-end)

---

## 2. Brand AI configuration

Maps to `cs_bff_upsert_brand_config` / `cs_merchant_config` (brand row).

```json
{
  "merchant_id": "00000000-0000-4000-8000-000000000001",
  "display_name": "Yuanta Rewards Support",
  "persona": "Professional securities loyalty specialist for Yuanta Rewards members. You help with points, tiers, rewards, and app guidance. You are patient with elderly members and never rush verification steps.",
  "tone": "Warm, clear, and trustworthy — like a branch service officer. Use polite Thai particles (ครับ/ค่ะ) when replying in Thai. Avoid slang, memes, and investment hype.",
  "primary_language": "th",
  "secondary_languages": ["en"],
  "voice_preset": "formal_thai",
  "voice_description": "Calm female Thai voice, moderate pace, suitable for members 45+",
  "model_config": {
    "intent_model": "gpt-4o-mini",
    "reasoning_model": "gpt-4o",
    "embedding_model": "text-embedding-3-small",
    "verification_model": "gpt-4o-mini"
  },
  "outbound_config": {
    "max_messages_per_hour_per_contact": 8,
    "quiet_hours": { "start": "21:00", "end": "08:00", "timezone": "Asia/Bangkok" },
    "csat_delay_minutes": 15
  },
  "guidance_rules": [
    "Always verify member identity (YSInvest ID or registered mobile last 4 digits) before discussing points balance or initiating redemption assistance.",
    "Tier and AUM values are display-only from Yuanta back-end — never recalculate tier in conversation.",
    "If the member asks to buy/sell securities, change orders, or requests investment advice, refuse politely and offer human agent escalation to licensed staff.",
    "For physical reward delivery, cite tracking status from loyalty API only; if status is unknown, create an internal ticket — do not invent carrier events.",
    "When assisting elderly members, offer step-by-step LINE or YSInvest instructions; offer agent callback if they prefer voice.",
    "PDPA: do not ask for national ID in chat; use channels already authenticated via LINE LIFF or web SSO where possible."
  ],
  "forbidden_phrases": [
    "guaranteed return",
    "risk-free",
    "แนะนำซื้อขาย",
    "รับประกันกำไร",
    "I'll place the trade for you",
    "คุณควรซื้อหุ้น"
  ],
  "escalation_triggers": [
    "trade_instruction_detected",
    "complaint_regulatory_keywords",
    "member_requests_human_twice",
    "sentiment_angry",
    "identity_verification_failed",
    "reward_value_above_auto_limit"
  ],
  "ai_routing": {
    "poc_enabled": true,
    "poc_traffic_percent": 3,
    "poc_channels": ["line", "web_chat"],
    "default_mode": "ai_first",
    "escalation_queue": "Loyalty & Rewards L1"
  },
  "voice_config": {
    "_comment": "Phase 2 — SIP REFER from CUCM",
    "enabled": false,
    "language": "th",
    "greeting_mode": "personalized",
    "max_call_duration_seconds": 600,
    "inbound_phone_numbers": ["+6620298000"]
  }
}
```

---

## 3. Merchant guardrails

Maps to `cs_merchant_guardrails` (ordered by `priority` ascending).

| Priority | Category | Rule |
|---:|---|---|
| 10 | `compliance` | Never execute or instruct securities trades, order changes, or portfolio allocation. Escalate to licensed human queue `Securities Dealing Desk`. |
| 20 | `compliance` | Never provide stock tips, price targets, or "should I buy/sell" answers. Offer general education links only if in knowledge base. |
| 30 | `compliance` | Regulated complaints (SEC, SET, fraud allegations) → immediate human escalation; AI may acknowledge receipt only. |
| 40 | `identity` | No full national ID collection in chat. Verification: YSInvest member code + DOB month/year OR SSO-authenticated session. |
| 50 | `loyalty` | Auto redemption on behalf of member only when `agent_assisted_redemption` action confirms identity and SKU is e-voucher ≤ 2,000 THB points equivalent. |
| 60 | `loyalty` | Physical rewards: never promise delivery date not returned by `get_reward_fulfillment_status` tool. |
| 70 | `brand` | Do not mention HubSpot, Cisco, or internal vendors to customers. |
| 80 | `brand` | Competitor brokers may be named only in factual comparison articles in KB — not in AI free-form replies. |
| 90 | `language` | If customer writes English, reply in English unless they switch to Thai. |
| 100 | `escalation` | After 2 failed verification attempts, escalate to human with summary. |

---

## 4. Agent Operating Procedures (AOPs)

Each row maps to `cs_procedures` (`trigger_intent`, `flexibility`, `raw_content`, `compiled_steps` auto-generated on save).

### 4.1 `loyalty_points_balance` — **guided**

**Name:** Points balance inquiry  
**Description:** Member asks how many points they have or when points expire.

**raw_content (excerpt):**

```text
## Goal
Tell the member their current Yuanta Rewards points and nearest expiry bucket (if any).

## Steps
1. Verify identity: @get_customer_profile requires verified session OR member_code + mobile_last4.
2. Prefetch: @get_customer_profile → read points_balance, points_expiring_soon.
3. If verification fails → explain what is needed; do not disclose balance.
4. Reply in customer's language with balance and expiry date; link to YSInvest Rewards screen.
5. If member disputes balance → @create_ticket category=points_dispute, escalate human.

## Tools allowed
@get_customer_profile, @create_ticket, @close_conversation, @trigger_csat_survey

## Escalate when
Dispute, suspected fraud, or member mentions SEC/complaint.
```

---

### 4.2 `loyalty_tier_status` — **guided**

**Name:** Tier status & progress  
**Description:** Member asks current tier, how to upgrade, or next review date.

**raw_content (excerpt):**

```text
## Goal
Explain tier name, benefits summary, and progress — using synced fields only.

## Steps
1. Verify identity (same as points AOP).
2. @get_customer_profile → tier_code, tier_name_th, tier_review_date, aum_display, points_ytd.
3. Explain: tier is calculated by Yuanta back-end (points OR AUM); Rocket displays status only.
4. If member asks to change tier manually → refuse; offer human if system looks wrong.
5. Optional: @search_knowledge query="tier benefits {tier_code}".

## Never
Recalculate tier or promise upgrade by a specific date.
```

---

### 4.3 `reward_redemption_assist` — **strict**

**Name:** Agent-assisted reward redemption (elderly / LINE assist)  
**Description:** Member cannot self-redeem in app; AI guides or triggers assisted redemption after verification.

**raw_content (excerpt):**

```text
## Goal
Help member redeem an e-voucher or initiate physical reward redemption without trade advice.

## Steps
1. Verify identity (strict): SSO session OR member_code + mobile_last4 + OTP confirmed flag.
2. Ask which reward (name or SKU). @search_products or @search_knowledge "reward catalogue".
3. Confirm points cost and remaining balance after redemption.
4. CODE CONDITION: if points_cost > 5000 OR physical_reward → escalate human (no auto redeem).
5. If e-voucher ≤ 5000 points: @redeem_reward_on_behalf (requires_confirmation=true) → wait tool result.
6. Send redemption confirmation + how to view code in YSInvest / LINE message.
7. @trigger_csat_survey on success.

## Escalate
Physical rewards, out-of-stock, custom hampers, any error from redeem tool.
```

**Per-procedure config:**

```json
{ "tone_override": "extra_patient", "max_turns": 12, "timeout_minutes": 20 }
```

---

### 4.4 `physical_reward_delivery_status` — **strict**

**Name:** Physical reward delivery tracking  
**Description:** Member calls/chats to ask where their gift is — primary dossier pain point.

**raw_content (excerpt):**

```text
## Goal
Show latest fulfillment status for a physical reward order.

## Steps
1. Verify identity.
2. If no redemption_id: @get_recent_redemptions limit=5 → ask member to pick one.
3. @get_reward_fulfillment_status redemption_id → status, carrier, tracking_number, last_event_at.
4. If status=partner_pending > 7 days → @create_ticket priority=normal, tag=fulfillment_delay.
5. Reply with timeline expectations from KB article "Physical reward delivery SLA".
6. Never invent tracking events.

## Tools
@get_recent_redemptions, @get_reward_fulfillment_status, @create_ticket, @search_knowledge
```

---

### 4.5 `promotion_campaign_faq` — **guided**

**Name:** Promotion & campaign FAQ  
**Description:** Marketing campaigns, bonus points events, spin wheel, mission rules (no trade promos).

**Flexibility:** guided — may combine multiple KB articles.

---

### 4.6 `ysinvest_app_help` — **agentic**

**Name:** YSInvest app navigation  
**Description:** How to open Rewards webview, change language, find e-vouchers.

**Escalation:** App bugs / login failures → ticket + human.

---

### 4.7 `account_profile_non_trade` — **strict**

**Name:** Non-trade account display  
**Description:** Display-only fields: registered email mask, branch, advisor name (if synced).

**Hard stop:** Any trade or funding instruction → `trade_instruction_detected` escalation.

---

### 4.8 Escalation-only stub — `trade_instruction_detected`

**Name:** Trade instruction blocker  
**Flexibility:** strict  
**Behavior:** Single-step: apologize, state AI cannot process trades, warm transfer message, `@create_ticket`, assign queue `Securities Dealing Desk`, no further AI turns.

---

## 5. Knowledge base

### 5.1 Categories

| Category code | Label (TH) | Label (EN) | Articles |
|---|---|---|---:|
| `loyalty_tiers` | ระดับสมาชิก Yuanta Rewards | Membership tiers | 6 |
| `points_earning` | การสะสมคะแนน | Earning points | 5 |
| `points_expiry` | คะแนนหมดอายุ | Points expiry | 3 |
| `rewards_catalog` | ของรางวัล | Rewards catalogue | 12 |
| `redemption` | แลกของรางวัล | Redemption | 8 |
| `physical_delivery` | จัดส่งของรางวัล | Physical delivery | 4 |
| `ysinvest_app` | แอป YSInvest | YSInvest app | 7 |
| `line_oa` | LINE Official Account | LINE OA | 4 |
| `promotions` | โปรโมชั่น | Promotions | 6 |
| `policies` | นโยบายและข้อกำหนด | Policies | 5 |
| `compliance_cs` | ข้อจำกัดการให้บริการ AI | AI service boundaries | 3 |

**Knowledge sources (logical):**

| Source name | Type | Sync |
|---|---|---|
| Yuanta Rewards FAQ (TH) PDF | `document_upload` | Manual quarterly |
| Yuanta Rewards FAQ (EN) PDF | `document_upload` | Manual quarterly |
| YSInvest help centre scrape | `website_scraper` | Weekly |
| Operations SOP — reward fulfillment | `manual` | Owner: Ops lead |
| Compliance — AI boundary script | `manual` | Owner: Compliance |

### 5.2 Sample articles (representative)

#### Article: `KB-TIER-001` — Five tiers overview

- **Category:** `loyalty_tiers`  
- **Languages:** TH + EN bodies  
- **TH title:** ระดับสมาชิก Yuanta Rewards มีกี่ระดับ  
- **TH content (summary):** ระดับ Standard, Silver, Gold, Platinum, Private — สิทธิประโยชน์ต่างกัน; การปรับระดับทุก 6 เดือนจากคะแนนสะสมหรือมูลค่าสินทรัพย์ (AUM) ตามที่ Yuanta คำนวณ; แสดงผลใน YSInvest > Rewards  
- **EN title:** Yuanta Rewards tier levels  
- **Tags:** `tier`, `aum`, `review_cycle`  
- **Status:** `published`

#### Article: `KB-REDEEM-003` — Elderly assisted redemption

- **Category:** `redemption`  
- **TH content (summary):** สมาชิกที่ใช้แอปไม่ถนัด สามารถติดต่อ LINE @YuantaRewards หรือโทร 02-029-8000 กด 2; เจ้าหน้าที่ยืนยันตัวตนและแลก e-voucher แทนได้; ของรางวัล physical ต้องยืนยันที่อยู่จัดส่ง  
- **Linked AOP:** `reward_redemption_assist`

#### Article: `KB-DELIVERY-001` — Physical reward delivery SLA

- **Category:** `physical_delivery`  
- **TH content (summary):** e-voucher ทันทีหลังแลก; physical 7–14 วันทำการ (กรุงเทพฯ), 14–21 วันต่างจังหวัด; สถานะติดตามใน YSInvest > ของรางวัลของฉัน > การจัดส่ง; หากเกิน 14 วันโทรติดตามได้  
- **Tags:** `sla`, `tracking`, `fulfillment`

#### Article: `KB-COMP-001` — What the AI assistant cannot do

- **Category:** `compliance_cs`  
- **TH content (summary):** ผู้ช่วย AI ไม่รับคำสั่งซื้อขายหลักทรัพย์ ไม่ให้คำแนะนำการลงทุน ไม่เปิดบัญชีใหม่ — โปรดติดต่อเจ้าหน้าที่ใบอนุญาตหรือสาขา  
- **Status:** `published`, pinned for AI grounding

*(Full catalogue in `yuanta-cs-demo-seed.json` lists 63 article stubs.)*

---

## 6. Channels & credentials (logical)

| Channel | Credential name | POC AI | Notes |
|---|---|:---:|---|
| LINE OA | `Yuanta Rewards LINE` | Yes | Official account; LIFF for SSO; replaces Little Help plugin |
| Web chat | `yuanta.co.th/rewards` widget | Yes | Embedded on rewards landing |
| Facebook Messenger | `Yuanta Securities FB` | No (Phase 2) | Routed to human inbox only in POC |
| WhatsApp | `Yuanta WA Business` | No | Human queue |
| Email | `rewards@yuanta.co.th` | No | SLA 24h |
| Voice | `CUCM REFER POC trunk` | Stub | `+6620298000` — Phase 2 |

**LINE greeting (auto-reply rule, not AI):**

> สวัสดีครับ ยินดีต้อนรับสู่ Yuanta Rewards 🤝  
> พิมพ์ **คะแนน** เช็คยอดคะแนน · **แลกรางวัล** · **ติดตามพัสดุ** · **เจ้าหน้าที่** คุยกับที่ปรึกษา

---

## 7. SLA policies & business hours

### Business hours — `cs_business_hours`

| Name | Schedule (ICT) | Applies to |
|---|---|---|
| `Contact centre standard` | Mon–Fri 08:30–17:00 | Chat, email |
| `Rewards hotline extended` | Sat 09:00–12:00 | Voice + chat tag `rewards` |
| `After hours` | Outside above | Auto-reply + AI POC only |

### SLA policies — `cs_sla_policies`

| Policy | First response | Resolution | Priority |
|---|---|---|---|
| Chat — AI POC | 2 min (AI) | 15 min (AI) or escalate | normal |
| Chat — human L1 | 5 min | 4 hr | normal |
| Chat — human L2 fulfillment | 15 min | 24 hr | normal |
| Email | 4 hr | 2 business days | low |
| Fulfillment delay ticket | 1 hr | 3 business days | high |

---

## 8. Rules engine (deterministic samples)

| Rule name | Trigger | Conditions | Actions |
|---|---|---|---|
| `POC route LINE to AI` | New message | channel=line, intent in POC list, random≤3% | Assign AI agent `yuanta-ai-poc` |
| `Trade keyword block` | New message | regex `(ซื้อ\|ขาย\|order\|trade)` + not FAQ context | Tag `trade_risk`, skip AI, queue Dealing Desk |
| `Angry sentiment` | Sentiment detected | negative/angry | Priority high, notify supervisor Slack |
| `Fulfillment delay tag` | Intent | `physical_reward_delivery_status` + status>7d | Tag `fulfillment_delay`, add macro |
| `CSAT after AI resolve` | Conversation resolved | resolved_by=ai | `trigger_csat_survey` delay 15m |
| `Saturday rewards queue` | New conversation | Sat 09:00–12:00, tag rewards | Route team `Rewards Weekend` |

---

## 9. CS action limits (merchant overrides)

Seeded via `cs_fn_seed_action_config` + overrides for securities context:

| Action | Auto-approve limit | Notes |
|---|---|---|
| `redeem_reward_on_behalf` | ≤ 2,000 THB points equivalent, e-voucher only | Elderly assist use case |
| `create_ticket` | Always allowed | |
| `award_bonus_points` | Disabled in POC | Compensation requires human |
| `lookup_trade` | **Disabled** | Not in POC scope |
| `cancel_order` | **Disabled** | Marketplace actions N/A |

---

## 10. Agent roster (demo)

| Agent ID | Name | Team | Skills | Channels |
|---|---|---|---|---|
| `agent-001` | สมชาย ใจดี (Somchai) | Loyalty L1 | `loyalty`, `th`, `en` | LINE, web |
| `agent-002` | วิภา รุ่งเรือง (Wipha) | Loyalty L1 | `loyalty`, `th` | LINE, voice (Phase 2) |
| `agent-003` | Michael Chen | Loyalty L2 | `loyalty`, `en`, `escalation` | All chat |
| `agent-004` | ปิยะ ธรรมมา (Piya) | Fulfillment | `physical_rewards` | LINE, email |
| `supervisor-01` | กมล ศรีสุข (Kamon) | Supervisors | `all` | All |

**AI agent (virtual):** `yuanta-ai-poc` — handles POC slice only.

---

## 11. Mock conversation logs

Synthetic data for demos; IDs are fictional.

### 11.1 CONV-2026-0412-001 — LINE — AI resolved (points)

| Field | Value |
|---|---|
| Contact | คุณประเสริฐ มั่นคง · YSInvest `YT-884201` · tier Gold |
| Channel | LINE OA |
| Status | `resolved` |
| Assigned | `yuanta-ai-poc` → resolved without human |
| Duration | 4 min |

**Transcript:**

| Time | Sender | Message |
|---|---|---|
| 09:12 | Customer | สวัสดีครับ อยากรู้คะแนนคงเหลือ |
| 09:12 | AI | สวัสดีครับคุณประเสริฐ ยินดีช่วยครับ รบกวนยืนยันรหัสสมาชิก YSInvest 4 หลักท้าย หรือเชื่อมผ่านเมนู Rewards ในแอปครับ |
| 09:13 | Customer | 8201 |
| 09:13 | AI | ขอบคุณครับ คุณประเสริฐ มั่นคง ระดับ Gold คะแนนคงเหลือ **12,450 คะแนน** คะแนน 2,000 คะแนนจะหมดอายุ **30 ก.ย. 2026** ดูรายละเอียดได้ที่ YSInvest > Rewards > คะแนนของฉน |
| 09:14 | Customer | ขอบคุณครับ |
| 09:14 | AI | ยินดีครับ หากต้องการแลกของรางวัล พิมพ์ "แลกรางวัล" ได้เลยครับ |
| 09:15 | System | CSAT sent (score 5) |

**Procedure:** `loyalty_points_balance`  
**AOP steps completed:** verify → prefetch profile → reply → CSAT

---

### 11.2 CONV-2026-0412-002 — LINE — AI → human (physical delivery)

| Field | Value |
|---|---|
| Contact | คุณสมหญิง วัยทอง · `YT-102938` · tier Silver · tag `elderly_assist` |
| Status | `resolved` |
| Assigned | AI → `agent-004` (fulfillment) |

**Transcript (abbreviated):**

| Time | Sender | Message |
|---|---|---|
| 10:05 | Customer | แลกกระเป๋าเมื่อสัปดาห์ก่อน ยังไม่ได้รับเลย |
| 10:05 | AI | ขออภัยในความล่าช้าครับ ขอทราบเลขที่แลกรางวัล หรือให้ตรวจรายการล่าสุดได้ไหมครับ |
| 10:06 | Customer | ไม่รู้เลข แต่เป็นกระเป๋าสีน้ำตาล |
| 10:06 | AI | พบรายการ RED-2026-03891 กระเป๋า Travel Brown สถานะ **อยู่ระหว่างจัดส่ง** ผู้ให้บริการ Kerry เลขพัสดุ TH123456789 อัปเดตล่าสุด 8 เม.ย. คาดจัดส่งภายใน 14–21 วันครับ |
| 10:08 | Customer | ช้าไปไหม อยากให้คนช่วย |
| 10:08 | System | Escalated — fulfillment_delay > 7 days |
| 10:09 | Agent (Wipha) | สวัสดีค่ะคุณสมหญิง ดิฉันติดตาม Kerry ให้ และได้เปิดเคส FLT-2026-1204 แล้วค่ะ จะแจ้งทาง LINE เมื่อมีการอัปเดต |
| 10:22 | Customer | ขอบคุณค่ะ |
| 10:23 | Agent | ยินดีค่ะ |

**Ticket:** `FLT-2026-1204` · category `fulfillment_delay`

---

### 11.3 CONV-2026-0412-003 — Web chat — trade blocked

| Field | Value |
|---|---|
| Contact | Guest → identified `YT-551002` |
| Status | `resolved` |
| Queue | Securities Dealing Desk (human) |

**Transcript:**

| Time | Sender | Message |
|---|---|---|
| 14:20 | Customer | อยากสั่งซื้อ CPALL 100 หุ้น |
| 14:20 | AI | ขออภัยครับ ผู้ช่วย Rewards ไม่สามารถรับคำสั่งซื้อขายหลักทรัพย์ได้ กรุณาติดต่อเจ้าหน้าที่ผ่าน YSInvest > ซื้อขาย หรือโทรสายตรง 02-xxx-xxxx ครับ |
| 14:20 | System | Rule `Trade keyword block` — AI disabled |
| 14:21 | System | Assigned human queue `Securities Dealing Desk` |

**Procedure:** `trade_instruction_detected`

---

### 11.4 CONV-2026-0411-004 — LINE — assisted redemption (strict AOP)

| Time | Sender | Message |
|---|---|---|
| 11:30 | Customer | แม่ใช้แอปไม่เป็น อยากแลก Starbucks 300 บาท |
| 11:31 | AI | ยินดีช่วยแลกให้ครับ ขอทราบรหัสสมาชิกและเบอร์ท้าย 4 หลักเพื่อยืนยันตัวตน |
| 11:32 | Customer | YT-220011 0912 |
| 11:33 | AI | คะแนนคงเหลือ 8,200 ค่า e-voucher Starbucks 300 บาท ใช้ 3,000 คะแนน ยืนยันแลกไหมครับ |
| 11:33 | Customer | ยืนยัน |
| 11:34 | AI | แลกสำเร็จแล้วครับ รหัส e-voucher ส่งในแอบ YSInvest > ของรางวัลของฉน และส่งซ้ำทาง LINE |
| 11:34 | System | Action `redeem_reward_on_behalf` — approved, audit log `AUD-2026-8891` |

---

## 12. Mock voice call logs (Phase 2 preview)

`cs_voice_calls` — disabled in POC but sample rows for demo UI / UAT scripts.

### CALL-2026-0408-V001

| Field | Value |
|---|---|
| Direction | inbound |
| From | +66891234567 |
| To | +6620298000 |
| Duration | 272 sec |
| Status | completed |
| Disposition | escalated |
| Agent | `agent-002` (warm transfer) |
| Conversation | linked `CONV-2026-0408-V001` |

**Transcript excerpt:**

```
[00:00] IVR: ยินดีต้อนรับสู่ Yuanta Rewards กด 1 คะแนนและของรางวัล กด 2 ซื้อขายหลักทรัพย์
[00:08] Customer: (DTMF 1)
[00:12] AI: สวัสดีครับ ยินดีช่วยเรื่องคะแนนและของรางวัล ครับ
[00:45] Customer: อยากรู้ว่าพัสดุถึงไหนแล้ว
[01:10] AI: ขอทราบรหัสสมาชิกครับ
...
[03:20] Customer: ขอคุยกับเจ้าหน้าที่
[03:22] AI: โอนสายให้เจ้าหน้าที่ครับ กรุณารอสักครู่
[03:25] System: SIP REFER → supervisor queue (CUCM)
[04:32] Agent: สวัสดีค่ะ...
```

**transfer_summary (AI-generated):** Member YT-102938 asking about physical reward RED-2026-03891; tracking shown in transit; member requested human; sentiment calm.

---

### CALL-2026-0409-V002 — abandoned

| Field | Value |
|---|---|
| Duration | 18 sec |
| Disposition | abandoned |
| Note | Dropped during identity verification |

---

## 13. CSAT configuration

| Setting | Value |
|---|---|
| Scale | 1–5 stars |
| Channels | LINE (flex message), web (in-widget), post-voice SMS (Phase 2) |
| Question (TH) | คุณพอใจกับการให้บริการครั้งนี้แค่ไหน |
| Question (EN) | How satisfied were you with this support experience? |
| Follow-up | Score ≤ 2 → auto ticket `CSAT_recovery`, assign supervisor |

**Mock CSAT aggregates (30 days demo):**

| Channel | Responses | Avg score | AI-only avg | Human avg |
|---|---:|---:|---:|---:|
| LINE | 412 | 4.6 | 4.7 | 4.4 |
| Web | 89 | 4.4 | 4.5 | 4.2 |
| Voice | 12 | 4.2 | — | 4.2 |

---

## 14. Watchtower & Live Assist (demo thresholds)

| Monitor | Threshold | Action |
|---|---|---|
| AI hallucination flag | Verification model mismatch | Pause POC traffic 1% |
| Procedure skip | Step bypass detected | Alert supervisor |
| Forbidden phrase | Match in outbound | Block send, escalate |
| Copilot usage | Agent accepts < 40% suggestions | Coaching review |

**Live Assist:** Enabled for all human agents; sources = knowledge + past conversations; cite sources required.

---

## 15. Loyalty context panel (agent workspace)

When contact linked to loyalty member, workspace shows (synced from Yuanta back-end):

| Field | Example |
|---|---|
| Member code | YT-884201 |
| Tier | Gold |
| Points balance | 12,450 |
| Points expiring | 2,000 on 2026-09-30 |
| AUM band (display) | 1–5M THB |
| Last redemption | Starbucks 300 THB e-voucher · 2026-04-01 |
| Open fulfillment | RED-2026-03891 · in_transit |
| Tags | `frequent_trader`, `rewards_active` |

**Quick actions:** Redeem on behalf · Resend e-voucher · Open fulfillment ticket · View in YSInvest (deep link)

---

## 16. Implementation checklist

- [ ] Create Yuanta merchant row; replace placeholder UUID
- [ ] `cs_bff_upsert_brand_config` with §2 JSON
- [ ] Insert guardrails §3
- [ ] `cs_bff_upsert_procedure` for each AOP §4 (auto-compile)
- [ ] Import KB articles §5 / seed JSON
- [ ] Configure LINE + web credentials §6
- [ ] SLA + business hours §7
- [ ] Rules §8 in rules engine admin
- [ ] `cs_fn_seed_action_config` + overrides §9
- [ ] Load mock conversations for demo tenant (optional fixture table or script)
- [ ] Compliance review of §4.8 and KB-COMP-* before enabling voice POC

---

## 17. Related dossier requirements map

| Dossier FR | This document section |
|---|---|
| FR-C-05 Knowledge base | §5 |
| FR-C-06 CSAT | §13 |
| FR-C-07 AI agent, AOPs, Watchtower, Live Assist | §2–4, §14 |
| FR-C-08 POC deployment | §1, §8 |
| FR-C-09 Voice POC | §12 (preview), §2 voice_config stub |
| FR-C-11 Delivery status | §4.4, §11.2, KB-DELIVERY-* |
| FR-L-06 Agent-assisted redemption | §4.3, §11.4 |

---

*End of configuration. Machine-readable article stubs and JSON blocks: `yuanta-cs-demo-seed.json`.*
