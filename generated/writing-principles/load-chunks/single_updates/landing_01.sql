begin;
UPDATE public.internal_knowledge_blocks SET content = E'---

### 7. Mental Validation

When you claim "comprehensive" or "all-in-one," the reader doesn''t believe you until you prove it. Proof is a list of recognizable components that match the checklist already in their head.

A buyer shopping for a loyalty platform already knows what one should contain. They''re scanning for confirmation. Name those components so they can mentally check each box.

**Good:**
> ระบบสมาชิก, สะสมแต้ม, แลกคูปอง, แลกรับของรางวัล, วิเคราะห์พฤติกรรมลูกค้า, Dashboard รวมข้อมูลลูกค้าทั้งหมด

Six items. Six yeses.

**Bad:**
> "Comprehensive loyalty platform with everything you need."

Zero yeses. The reader has to trust you instead of verify you. They won''t.

**Constraint 1 — same level of abstraction.** Every item must be the same "size." This applies to feature grids, bento boxes, step lists, and comparison rows — anywhere the reader scans a set of peers in one glance.

- **Consistent:** Tiers, Rewards, Campaigns, Points, Analytics
- **Broken:** Tiers, Rewards, LINE Notification, Custom Form

The second jumps from strategic modules to implementation details. It feels wrong even if the reader can''t say why. It''s listing "Bedroom, Kitchen, Garden, Doorknob."

**Constraint 2 — same grammatical form.** Items in a list should be the same type of phrase — all nouns, or all verb phrases. Mixing them makes the list feel jumbled even if the abstraction level is consistent.

- **Jumbled:** "สมาชิก สะสมแต้ม แลกรางวัล แคมเปญ วิเคราะห์ลูกค้าด้วย AI" — mixes bare nouns (สมาชิก, แคมเปญ), verb phrases (สะสมแต้ม, แลกรางวัล), and a clause (วิเคราะห์ลูกค้าด้วย AI).
- **Consistent (all nouns):** "ระดับสมาชิก สะสมแต้ม แลกรางวัล แคมเปญ AI Analytics"
- **Consistent (all verb phrases):** "ตั้งระดับสมาชิก สะสมแต้ม แลกรางวัล สร้างแคมเปญ วิเคราะห์ลูกค้า"

Also check that each item conveys the right meaning. "สมาชิก" alone means "member" — it doesn''t convey the tier system. "ระดับสมาชิก" does.

**Qualifiers are allowed if proven immediately.** Words like "ครบวงจร," "หลายมิติ," or "ครบทุกฟีเจอร์" are generic on their own. But if the very next sentence is a concrete list that proves the claim, the qualifier becomes a useful preview — it tells the reader what to expect before the evidence arrives. "แคมเปญหลายมิติ" followed by five specific campaign types is earned. "แคมเปญหลายมิติ" followed by nothing is fluff.

### 8. Narrative Mechanics

Abstract features — "omnichannel," "unified profile," "real-time sync" — are invisible. They describe a state. States don''t move. The brain processes movement.

To make a feature real, describe **what happens** — the data moving or the customer moving through the system.

**Good:**
> ไม่ว่าลูกค้าจะซื้อผ่านช่องทางไหน ออนไลน์ ออฟไลน์ หรือ Marketplace ทุกยอดซื้อถูกบันทึกและคำนวณคะแนนให้อัตโนมัติ รวมเป็นโปรไฟล์ลูกค้าเดียวในระบบ CRM

A micro-story. The reader watches a customer buy somewhere, then watches data flow into one profile. They see it happen. That is comprehension.

**Bad:**
> "Unified customer profile across all channels."

Same thing technically. But nobody can picture it.

**When to use:** Any time the capability spans multiple touchpoints, channels, or time periods. The more abstract the feature, the more it needs a concrete step-by-step of what actually happens.

### 9. Success Vision

Narrative Mechanics describes how the product works (feature-level). Success Vision describes how the customer''s life changes (outcome-level). Paint a concrete scene of their daily work *after* they use the product.

- **Abstract outcome:** "เพิ่มยอดซื้อซ้ำ"
- **Success vision:** "เปิด Dashboard เห็นทันทีว่าใครกำลังจะ Churn ใครพร้อมอัพเกรด Tier"
- **Success vision:** "AI ส่งข้อเสนอให้ลูกค้าแต่ละรายอัตโนมัติ ไม่ต้องเลือกเอง"

The reader should be able to picture a specific moment in their workday that becomes better. Not a vague improvement — a concrete scene.

### 10. Operational Utility

**Strategic label, operational proof.** Pair an abstract noun (the capability category) with daily workflow verbs (what actually happens). Use the heading for strategic value; use the line below for operational utility.

| Strategic (heading) | Operational (description) |
|---|---|
| Advanced Churn Prediction | AI detects when a customer stops buying and sends a win-back offer. |
| Omnichannel Loyalty | Every purchase — online, offline, or marketplace — earns points into one profile automatically. |

If the description only repeats the heading in longer words, rewrite the description with verbs the operator or customer performs.

Technology names — AI, machine learning, automation — mean nothing until you define exactly **which decision or task** the technology handles so the human doesn''t have to.

Don''t sell the tool. Sell the specific thinking it removes.

**This applies to all features, not just AI.** Describe every feature using verbs the user performs daily. FlowAccount doesn''t say "comprehensive financial management solution" — they say "เปิดบิล บันทึกค่าใช้จ่าย จัดการสต็อก ลงบัญชี." Four daily actions. The reader immediately sees their own workflow reflected. Apply the same pattern to loyalty: "สร้างแคมเปญชวนเพื่อน," "ตั้งเงื่อนไขให้คะแนน," "ดูรายงาน Campaign ROI" — not "campaign management," "points configuration," "analytics dashboard."

**Good:**
> ใช้ AI วิเคราะห์พฤติกรรมลูกค้า แนะนำสิทธิพิเศษหรือของรางวัลที่เหมาะสมกับลูกค้าแต่ละราย

**Bad:**
> "AI-powered personalization."

**Test:** Remove the word "AI." If the sentence still communicates value, it''s written correctly. If it collapses, you sold a label, not relief.

**AI as subject, not modifier.** When describing AI capabilities, make AI the grammatical subject performing specific verbs — not a modifier tacked onto the end of a sentence. "ด้วย AI" and "powered by AI" are labels. "AI วิเคราะห์...และส่ง..." is a capability.

- **AI as modifier (bad):** "วิเคราะห์ลูกค้าด้วย AI" — "ด้วย AI" is bolted on. Remove it and the sentence becomes "วิเคราะห์ลูกค้า" — vague, no specific action.
- **AI as subject (good):** "AI วิเคราะห์ลูกค้าและส่งข้อเสนออัตโนมัติ" — AI is the subject doing two verbs (วิเคราะห์ + ส่ง). The reader sees what happens.

This is especially important when the AI''s value is in *taking action*, not just analyzing. If the AI predicts churn and sends an offer, the sentence must show both steps — analysis alone undersells the capability.

**AI framing: augmentation, not replacement.** When the audience is the team that will use the product (marketers, operators), never frame AI as replacing them. "AI ที่คิดแทนทีมคุณ" reads as a threat, not a benefit. Instead, frame AI as enabling something the team *wants* to do but physically *can''t* at scale.

- **Threatening:** "AI ที่คิดแทนทีมคุณ"
- **Empowering:** "เหมือนมี AI เป็นนักการตลาดส่วนตัวให้ลูกค้าทุกคน"

The AI isn''t replacing them. It''s multiplying them.

_Source section truncated in seed; see `source_ref` for full text._', metadata = metadata || '{"genre": "landing", "source_file": "WEB_PAGE_COPY_PRINCIPLES.md", "section_anchor": "ii-expression-how-to-communicate-features-effectively", "part": 1, "feature_slug": "web-landing-copy", "generation_batch": "writing_principles_seed_20260530T011413Z", "content_sha256": "a4965b20193bc3c03354efead7740702e9a0a220a6b8fb9f9f8f33f3544fceaa", "truncated": true}'::jsonb, updated_at = now() WHERE id = 'bea629fa-3b7b-5d97-ae0a-df464e35d44c'::uuid;
commit;