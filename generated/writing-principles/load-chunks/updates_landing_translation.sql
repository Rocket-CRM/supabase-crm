UPDATE public.internal_knowledge_blocks SET content = E'These apply universally across all markets:

1. **Name the decision, not the technology.** "AI predicts which customers will stop buying and sends them a personalized offer" — not "AI-powered machine learning analytics engine."
2. **Frame as augmentation, not replacement.** AI helps the team do more, not replaces the team. Especially important in JP and TW enterprise contexts.
3. **Keep "AI" in the sentence when using analogy.** "AI acts like your best marketing intern — but works 24/7" keeps it grounded. Don''t let the analogy erase the AI reference.
4. **Precision over claims.** "AI sends personalized offers to each customer automatically" > "cutting-edge AI technology." Show what it does, not what it is.

---', metadata = metadata || '{"genre": "translation", "source_file": "TRANSLATION_PHILOSOPHY.md", "section_anchor": "ai-technology-term-principles", "feature_slug": "translation", "generation_batch": "writing_principles_seed_20260530T011413Z", "content_sha256": "c97f70d3858c3afdcd1ee6d7cebdbfe009badada8934d3b4ead56f9decfef5f4", "truncated": false}'::jsonb, updated_at = now() WHERE id = 'b79eb606-38e8-5caa-ab2a-3d2b159bb29a'::uuid;
UPDATE public.internal_knowledge_blocks SET content = E'We don''t swap words between languages. We rewrite each text component so it reads like it was written by a sharp marketer in that market. The test: would a native speaker in the target market assume this was originally written in their language?

**What this means in practice:**

| Approach | Example (JP) | Result |
|---|---|---|
| Translation (wrong) | "Turn customers into members" → "顧客をメンバーに変える" | Grammatically correct, sounds like a translation |
| Localization (right) | "Turn customers into members" → "顧客を会員に。全チャネルで。" | Sounds like a Japanese marketer wrote it |

---', metadata = metadata || '{"genre": "translation", "source_file": "TRANSLATION_PHILOSOPHY.md", "section_anchor": "core-principle-localize-don-t-translate", "feature_slug": "translation", "generation_batch": "writing_principles_seed_20260530T011413Z", "content_sha256": "2b26906b1fd3dd1bf2d219c04aa8cb0124e052bee153ecd4f66a48eab2d96abb", "truncated": false}'::jsonb, updated_at = now() WHERE id = '80a5f9a4-2eb7-5f31-b862-f259deab8b2f'::uuid;
UPDATE public.internal_knowledge_blocks SET content = E'Always convert to local currency and format. Never leave prices in a foreign currency.

| Market | Currency | Format | Example |
|---|---|---|---|
| **Japan** | Yen (JPY) | ¥ prefix, no decimal, comma separator | ¥1,500 |
| **Taiwan** | New Taiwan Dollar (TWD) | NT$ prefix, no decimal | NT$450 |
| **Thailand** | Baht (THB) | ฿ prefix or "บาท" suffix | ฿500 or 500 บาท |
| **English** | USD or contextual | $ prefix, 2 decimal places | $15.00 |

**Numbers:**
- Use local number formatting (comma/period conventions)
- Quantities: use local counter words where natural (JP: 枚 for coupons, 人 for people; TW: 張 for coupons; TH: ใบ for coupons)
- Percentages: use % universally

---', metadata = metadata || '{"genre": "translation", "source_file": "TRANSLATION_PHILOSOPHY.md", "section_anchor": "currency-number-formatting", "feature_slug": "translation", "generation_batch": "writing_principles_seed_20260530T011413Z", "content_sha256": "d55441993d356aebca22f1911b525ebed087dcf8bbd74ef64786e11fabf8ebf3", "truncated": false}'::jsonb, updated_at = now() WHERE id = '773a0dd6-2f4a-5843-8f84-5bf55a33a264'::uuid;
UPDATE public.internal_knowledge_blocks SET content = E'Industry-standard terms stay in English across all markets. The test: if a B2B SaaS website in the target market would use this term in English, keep it in English.

**Always keep in English:**

| Category | Terms |
|---|---|
| **Technical** | AI, CRM, Dashboard, API, SaaS, POS, EC, QR, OTP, SLA, Push Notification, Omnichannel |
| **Metrics** | ROI, LTV, CLV, KPI, CSAT, AOV, CAC |
| **Platform names** | LINE, Shopify, Shopee, Lazada, TikTok, WhatsApp, Facebook, Instagram |
| **Brand names** | Rocket, Agentic CRM |
| **Tier names** | Gold, Silver, Platinum (keep English unless market doc overrides) |

**Market-specific decisions:** Some terms are borderline. The market-specific doc decides:
- "Omnichannel" — English in JP/EN, localized in TH/TW
- "Churn" — English in EN, localized in JP/TH/TW
- "Mission" — depends on market (ミッション in JP, kept English or ภารกิจ in TH)

---', metadata = metadata || '{"genre": "translation", "source_file": "TRANSLATION_PHILOSOPHY.md", "section_anchor": "english-term-policy", "feature_slug": "translation", "generation_batch": "writing_principles_seed_20260530T011413Z", "content_sha256": "13c715819c483645c8d83a171e1a65604bdbe5b2bed468dda018cee24cbfc683", "truncated": false}'::jsonb, updated_at = now() WHERE id = 'ec98f011-f8ac-5fc6-aab2-c9bfed8aef44'::uuid;
UPDATE public.internal_knowledge_blocks SET content = E'Each market has a dedicated doc that inherits these universal rules and adds:

1. **Market context** — who buys, what they search for, cultural notes
2. **Feature vocabulary table** — canonical translations for every domain-specific term
3. **Feature nuances** — how features resonate differently in this market
4. **UI translation patterns** — common component translations
5. **CTA patterns** — call-to-action conventions

| Market | Doc | Language |
|---|---|---|
| Japan | [JAPAN_CONTEXT.md](JAPAN_CONTEXT.md) | Japanese |
| Taiwan | [TAIWAN_CONTEXT.md](TAIWAN_CONTEXT.md) | Traditional Chinese (zh-TW) |
| Thailand | [THAILAND_CONTEXT.md](THAILAND_CONTEXT.md) | Thai |
| English | [ENGLISH_CONTEXT.md](ENGLISH_CONTEXT.md) | English (SEA/Global) |', metadata = metadata || '{"genre": "translation", "source_file": "TRANSLATION_PHILOSOPHY.md", "section_anchor": "per-market-context-docs", "feature_slug": "translation", "generation_batch": "writing_principles_seed_20260530T011413Z", "content_sha256": "26bf0a050ca63a893264cd2eb0d4bb0a8dd29569dcc405e81834a5e6d21227df", "truncated": false}'::jsonb, updated_at = now() WHERE id = '02a7a988-a6d0-5b2a-91f4-aa6a17da7f96'::uuid;
UPDATE public.internal_knowledge_blocks SET content = E'| Category | Rule | Examples |
|---|---|---|
| **Brand names** | Never translate | Rocket, LINE, Shopify, Shopee, Lazada |
| **Product names** | Never translate | Agentic CRM |
| **Feature names (English origin)** | Keep English if established in market | Top Spender, Dashboard, Mission (in JP) |
| **Feature names (localized)** | Use market-specific term | 友達紹介 (JP for Referral), 會員經營 (TW for Membership Operations) |
| **Tier names** | Keep English unless market doc overrides | Gold, Silver, Platinum |

---', metadata = metadata || '{"genre": "translation", "source_file": "TRANSLATION_PHILOSOPHY.md", "section_anchor": "proper-noun-rules", "feature_slug": "translation", "generation_batch": "writing_principles_seed_20260530T011413Z", "content_sha256": "f6ce319c7f18ae5f81833ab4796d8a749ce47894b7a01a4944a8bacc745afea0", "truncated": false}'::jsonb, updated_at = now() WHERE id = '4491cdc6-711f-5751-8b02-9a0276a3d7d6'::uuid;
UPDATE public.internal_knowledge_blocks SET content = E'Match the original component structure. If the image shows a button, give a button-length string. If it shows a headline + subtext, give headline + subtext. Don''t add or remove elements.

**Rules:**
- Button text → button-length translation (short, action-oriented)
- Headline + subheadline → maintain the hierarchy and relative lengths
- Feature card (title + description) → title stays punchy, description stays concise
- Data labels → match the terseness of the original
- If you need more words in the target language, find a shorter way to say it. Don''t let translations break layouts.

---', metadata = metadata || '{"genre": "translation", "source_file": "TRANSLATION_PHILOSOPHY.md", "section_anchor": "structure-fidelity", "feature_slug": "translation", "generation_batch": "writing_principles_seed_20260530T011413Z", "content_sha256": "b07f71a01753a2c3a02991be6e4049fafc13c4026141a2a0678267a29494d2ba", "truncated": false}'::jsonb, updated_at = now() WHERE id = '71278524-ba10-5537-9a73-12144b0f0e1b'::uuid;
UPDATE public.internal_knowledge_blocks SET content = E'Not every text component needs the same level of effort. Calibrate by complexity:

| Text type | Examples | What to do |
|---|---|---|
| **Simple / universal** | "Buy Now," "Gold," "15 Coupons," "Details →," "Settings" | Just translate. Use the natural equivalent a user expects to see. Don''t overthink. |
| **Domain-specific** | "Tier," "Omnichannel," "Churn," "Segment," "AI Agent," "Double Points" | Check the vocabulary table in the market-specific doc. These terms have established translations — use them consistently. |
| **Marketing copy** | Headlines, subheadlines, feature descriptions, taglines | Use the product context + market context to make it read well locally. Not a literal translation — a local marketer''s version. |

---', metadata = metadata || '{"genre": "translation", "source_file": "TRANSLATION_PHILOSOPHY.md", "section_anchor": "the-complexity-spectrum", "feature_slug": "translation", "generation_batch": "writing_principles_seed_20260530T011413Z", "content_sha256": "771d0e9f525fc24d618e3fa2d595f03238c798af7c187a3540bad9c8bf22ef74", "truncated": false}'::jsonb, updated_at = now() WHERE id = 'bf4f7929-e952-5e4a-b6bb-7690604c60de'::uuid;
UPDATE public.internal_knowledge_blocks SET content = E'Each market has a different baseline tone. The market-specific doc specifies where on the spectrum, but here''s the universal framework:

| Dimension | Formal end | Casual end | Notes |
|---|---|---|---|
| **Formality** | Enterprise Japanese (です/ます, honorifics) | Thai B2B/SME (direct, conversational, no corporate padding) | Match audience segment, not just market |
| **Directness** | English (direct, outcome-focused) | Japanese (implications, softer framing) | Cultural communication norms |
| **Tech confidence** | English/TW (AI is exciting, lean into it) | JP enterprise (AI is risky, pair with control/guardrails) | How the market perceives AI claims |
| **Urgency** | Specific numbers always (JP: "最短1ヶ月") | Vague superlatives never | All markets: precision beats superlatives |

**Thailand (B2B/SME):** Strip overly formal corporate padding and unnatural metaphors. Write like a sharp marketer talking to an operator — not a translated press release. If a literal English→Thai line sounds clever on paper but awkward spoken aloud, rewrite in neutral, natural business Thai.

**Structure fidelity in every market:** A title stays a punchy title; a description stays a concise mechanism explanation. Do not let localization bloat layout or force a redesign. If the target language needs more words, shorten the idea — do not add elements.

---', metadata = metadata || '{"genre": "translation", "source_file": "TRANSLATION_PHILOSOPHY.md", "section_anchor": "tone-calibration", "feature_slug": "translation", "generation_batch": "writing_principles_seed_20260530T011413Z", "content_sha256": "7f8bfc8ecea8c83585a254f2c60aa29dc25ad5f4fe4ae2e5eacd0ebf7142e5ff", "truncated": false}'::jsonb, updated_at = now() WHERE id = 'a409b461-9671-5b65-8d8f-8413e6e0302f'::uuid;
UPDATE public.internal_knowledge_blocks SET content = E'**When to use:** Add after genre playbook when output is Thai, JP, TW, or mixed EN/local. Localize-don''t-translate, term policy, tone calibration.
            **Source:** `TRANSLATION_PHILOSOPHY.md`
            **Genre:** `translation`

**Cross-cutting:** Add after the genre playbook when localizing.

            Translation Philosophy — Universal Principles', metadata = metadata || '{"genre": "translation", "source_file": "TRANSLATION_PHILOSOPHY.md", "section_anchor": "overview", "feature_slug": "translation", "generation_batch": "writing_principles_seed_20260530T011413Z", "content_sha256": "6063af023db897399cbcd63dd03bce6ac054631b6cfaf16cc4adca2575ebcbf1", "truncated": false}'::jsonb, updated_at = now() WHERE id = 'a5f7bde0-b04c-5550-a314-316747340db3'::uuid;
UPDATE public.internal_knowledge_blocks SET content = E'---

### 1. Instant Comprehension

A visitor must understand **what it is** and **who it''s for** within five seconds. If they scroll to guess, the page has already failed.

The hero section answers two questions only:
1. What does this do?
2. Is this for me?

Everything else — features, proof, pricing — comes after.

### 2. Customer is the Hero

The customer is the hero of the story. The brand is the guide. Every sentence should be about the customer''s situation, not the brand''s achievements.

- **Brand as hero:** "We built the first AI CRM" / "Rocket เป็น Loyalty CRM ตัวแรกที่ใช้ Agentic AI"
- **Customer as hero:** "A CRM that sends the right offer to each customer automatically" / "ลูกค้าซื้อจากหลายช่องทาง ระบบรวมทุกยอดซื้อเป็นโปรไฟล์เดียวให้อัตโนมัติ"

The first talks about Rocket. The second talks about the customer''s reality, with Rocket as the tool that fixes it. Don''t lead with brand history, awards, or what the company is "trying to do." The reader doesn''t care about your story. They care about theirs.

### 3. No Metaphors

Ban "unleash," "supercharge," "revolutionize," "next-gen," "cutting-edge." These are emotional placeholders where a specific claim should be.

- **Metaphor:** "Supercharge your customer engagement."
- **Descriptive:** "Automate your post-purchase follow-ups."

The second tells the reader exactly what happens. The first tells them you have a copywriter.

**Exception — punchy taglines that generate emotion.** A short metaphor or provocative phrase is allowed as a hero tagline IF it creates genuine emotion — FOMO, inspiration, urgency, or a feeling of possibility. FlowAccount''s "รีเซ็ตธุรกิจ" works because it''s two words that make the reader feel something. The test: does the phrase trigger an emotional reaction, or is it just decoration? "Supercharge your workflow" is decoration. "รีเซ็ตธุรกิจ" is a provocation. This exception only applies to brand-level taglines and homepages where the audience already knows the product. On ads and SEO pages for cold traffic, descriptive copy always wins.

### 4. No Vague Modifiers

Words like "ตามกลยุทธ์ของคุณ," "ตามต้องการ," "ที่ยืดหยุ่น," "flexible," "customizable" feel specific but are empty. They describe *that* something is configurable without showing *what* changes. If you can''t picture what the customization looks like, the modifier is doing nothing.

- **Vague:** "ระบบสะสมแต้มที่ออกแบบได้ตามกลยุทธ์ของคุณ"
- **Concrete:** "ให้คะแนนได้มากกว่าแค่ยอดซื้อ — รีวิว ชวนเพื่อน Check-in ก็ให้คะแนนได้"

The fix is always the same: replace the modifier with an example of what it enables.

**Abstraction as container, not crutch.** High-level words are powerful when they attach to a category the reader already understands — they act as a clean container for the reader''s mental model. Use them there; avoid them when they mask a vague concept or when you should be naming identity instead.

- **Container (good):** "Fully customizable CMS" — the reader knows what a CMS is; "customizable" frames the scope.
- **Crutch (bad):** "Flexible loyalty solution" — "loyalty solution" is already vague; "flexible" adds nothing concrete.
- **Too low (bad):** "Customizable headers and descriptions" — correct but hurts the big picture on a hero or category headline.

### 5. Outcome vs. Mechanism Balance

Balance the promise of the result with the clarity of the tool. Sometimes they conflict — when they do, judge which one the reader needs more at that moment.

**Default — sell the outcome:**
- **Mechanism:** "AI Analytics Dashboard."
- **Outcome:** "Get answers from your data in plain English."

**Exception — high-intent buyers.** Most visitors arrive via search. They already know *what* they want. They''re confirming *whether you have it*. For these readers, naming the mechanism builds confidence that you actually solve the problem, not just promise to.

- "One-click Shopify install" — they searched for Shopify integrations, confirming mechanism matters more than outcome here.
- "Postgres database" — a technical buyer needs to know the stack, not be told "your data is safe."
- "Syncs orders in < 500ms" — the outcome (synced orders) is obvious. The mechanism (speed) is the differentiator.

**Third case — obvious outcome.** When the audience already knows the outcome of your product category, restating it is redundant. Everyone knows loyalty programs exist to drive retention and repeat purchases. Saying "ระบบ CRM ที่ทำให้ลูกค้ากลับมาซื้อซ้ำ" tells them nothing they didn''t already know. In this case, skip the outcome entirely. Be ultra-clear about **what the product IS** and **who it''s for** instead.

- **Redundant outcome:** "ระบบ CRM ที่ทำให้ลูกค้ากลับมาซื้อซ้ำ"
- **Ultra-clear identity:** "ระบบสะสมแต้มสำหรับแบรนด์ B2C"

**How to decide:** Ask whether the reader already knows the outcome they want. If yes and the outcome is non-obvious, the mechanism is what closes the gap. If the outcome is obvious to the entire category, skip it — lead with identity and scope instead.

### 6. Category Clarity Over Cleverness

When a heading describes a capability, the reader must instantly know which product category they''re looking at. If the same heading could describe three different product types, it''s too abstract.

- **Ambiguous:** "รวมทุกช่องทางขายในที่เดียว" — could be an order management system, an online store builder, or a CRM.
- **Clear:** "สะสมแต้มได้ครบทุกช่องทาง ไม่ว่าจะซื้อจากที่ไหน" — unmistakably about loyalty points across channels.

Industry terms like "Omnichannel" are useful here precisely because they anchor the reader in the right category. Don''t avoid jargon when the jargon is what the reader is looking for. But the sentence must still read naturally — if adding the term makes it clunky, restructure the sentence around it.

---', metadata = metadata || '{"genre": "landing", "source_file": "WEB_PAGE_COPY_PRINCIPLES.md", "section_anchor": "i-foundation-what-the-page-must-do-in-5-seconds", "part": 1, "feature_slug": "web-landing-copy", "generation_batch": "writing_principles_seed_20260530T011413Z", "content_sha256": "3e289b15bbcffa3509cdcf555d654304ccbf6eb19000aae2d49048437a9a1125", "truncated": false}'::jsonb, updated_at = now() WHERE id = 'bd7ad243-22d8-5f6a-964c-40e4b630d562'::uuid;
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
UPDATE public.internal_knowledge_blocks SET content = E'---

### 11. Three Layers of Problem

Every customer problem has three layers. Most copy only addresses the first. Addressing all three creates emotional resonance — the reader thinks "they understand me," not just "they have the feature I need."

- **External (practical):** "ข้อมูลลูกค้ากระจายอยู่หลายระบบ"
- **Internal (emotional):** "ไม่รู้ด้วยซ้ำว่าลูกค้าคนเดียวกันซื้อจากกี่ช่องทาง"
- **Philosophical (why it''s wrong):** "แบรนด์ที่ลงทุนกับ Loyalty ไม่ควรต้องเดาว่าลูกค้าเป็นใคร"

The external layer states the fact. The internal layer names how it feels. The philosophical layer validates that the reader''s frustration is justified. You don''t need all three in every sentence, but the page as a whole should touch all three levels.

**Name real pain, not manufactured pain.** The problem you describe must be something the reader actually experiences — not something you constructed to fit your product''s strengths. If the reader hasn''t felt this frustration in their own work, the copy reads as manipulation, not empathy.

- **Manufactured:** "ไม่ต้องปะติดปะต่อหลายเครื่องมือ" — sounds like a tool integration problem. If the reader isn''t actually stitching together 5 tools today, this pain doesn''t resonate.
- **Real:** "ฟีเจอร์รองรับแบรนด์ใหญ่ ในราคา SME" — addresses a genuine objection: "this looks powerful but probably costs more than I can afford."

**Test:** Ask "would the reader say this sentence to a colleague in a meeting?" If nobody has ever complained about this problem out loud, you invented it.

### 12. Objection Judo

Name the fear, dissolve it in the same line.

| Fear | Copy |
|---|---|
| Setup takes forever | "Launch in 3 hours, not 3 months." |
| It''s expensive | "Enterprise features, SME price tag." |
| I''ll need a developer | "No code. No developer. No ticket to IT." |

Structure: **Specific fear → Specific counterclaim.**

**Two forms of Objection Judo:**
- **Inline** — dissolve the fear within feature copy. Handles "should I keep reading?"
- **Structured (FAQ section)** — a dedicated section near the bottom that systematically addresses common objections: security, implementation time, support availability, pricing, technical requirements. Handles "should I fill out this form?" For enterprise/B2B SaaS, a FAQ section gives you a second chance to address objections the reader didn''t even realize they had.

### 13. Social Proof Placement

Place hard numbers (user count, brand count, transactions processed) between the hero and the feature sections. The reader should trust you before you start selling.

- **Logo bar** (brand logos) confirms "companies like mine use this."
- **Hard numbers** (130,000+ ผู้ประกอบการ, 500+ แบรนด์) confirm scale.
- **Position both early** — after the hero, before features. If the reader trusts you by the time they start reading features, every claim lands harder.

Numbers must be specific and verifiable. "Thousands of businesses" is generic. "500+ แบรนด์ B2C" is specific. Round numbers feel made up. Odd numbers feel real.

### 14. Hook Strategies

Angles that give a headline its edge. Pick one per section. Never stack.

**Contrast must be real opposition.** When using a contrast structure ("X — not just Y"), the two sides must be things the reader naturally sees as alternatives or trade-offs. If A and B aren''t in tension in the reader''s mind, the contrast creates confusion, not clarity.

- **Broken contrast:** "AI ที่ตัดสินใจได้ — ไม่ใช่แค่ Dashboard" — AI is a decision layer, Dashboard is a display layer. Nobody chooses between them — they expect both.
- **Real contrast:** "AI ที่ลงมือทำเอง — ไม่ใช่แค่วิเคราะห์ให้คุณตัดสินใจ" — "acts autonomously" vs "just reports for you to decide" is a real spectrum of AI capability.
- **Real contrast:** "ฟีเจอร์รองรับแบรนด์ใหญ่ ในราคา SME" — "expensive" vs "affordable" is a real trade-off in the buyer''s mind.

**Test:** Ask "does the reader ever have to choose between these two things?" If yes, the contrast works. If no, the two sides aren''t opposites — they''re just unrelated concepts placed next to each other.

**Name the Enemy.** Be the explicit alternative to the thing they already resent.
> "The CRM for people who hate Salesforce."

**The "Without" Clause.** Promise the benefit, explicitly remove the associated cost.
> "Enterprise-grade security **without** the enterprise sales cycle."
> "Launch a rewards program **without** paying commissions on revenue."

**Identity Callout.** Define who belongs. Define who doesn''t.
> "Loyalty for **brands**, not dropshippers."
> "Built for **operators**, not executives who''ll never log in."

**Counter-Intuitive Truth.** Tell them to stop doing the thing they think they should be doing.
> "Stop optimizing for clicks. Start optimizing for retention."
> "Send fewer emails. Make more money."

**Stakes / Cost of Inaction.** Show what the customer loses by doing nothing. Different from Objection Judo which removes fears — this *creates* urgency. Two angles:

*Loss-based:* Show what slips away every day they don''t act.
> "ทุกยอดซื้อที่ไม่ถูกบันทึก คือลูกค้าที่คุณไม่รู้จัก"
> "ลูกค้าที่ไม่มีแต้มสะสม ไม่มีเหตุผลต้องกลับมา"

*FOMO-based:* Show that leading brands already use this — not acting means falling behind, not just standing still. The reader should feel that the brands they admire or compete with are already doing this, and not doing it makes their brand look behind the curve.
> "แบรนด์ชั้นนำใช้ Loyalty CRM ดูแลลูกค้าทุกราย — แบรนด์ที่ยังไม่มีระบบ ลูกค้ารู้สึกได้"
> "ลูกค้ายุคนี้คาดหวังระบบสมาชิกที่ฉลาด แบรนด์ที่ยังใช้บัตรสะสมแต้มเริ่มดูตามไม่ทัน"

People are more motivated to avoid loss than to gain something. FOMO adds a social dimension — it''s not just about losing customers, it''s about looking outdated compared to peers.

### 15. "Why You" Must Answer "Why You"

If a section asks "ทำไมต้อง [Brand]?" — every block under it must contain something that differentiates from competitors, not just describe standard features. Standard features belong in the features section. The "why" section must answer what you do that others don''t, or what you do differently.

- **Standard feature (not a "why"):** "ให้คะแนนลูกค้าจากทุกพฤติกรรม"
- **Differentiator (actual "why"):** "Loyalty Program ที่ไม่ได้แค่สะสมแต้ม — สร้างแคมเปญ วิเคราะห์ลูกค้า และดูแลลูกค้าแต่ละรายด้วย AI"

Ask: "Could a competitor say the same thing?" If yes, it''s a feature, not a differentiator. Move it to the features section and find what''s actually unique.

### 16. Ads Headlines Must Drive Action

SEO headlines can be informational — they answer a query. Ads headlines cannot afford to be informational alone. The reader already clicked an ad. They''re considering you. The headline must create urgency, desire, or a direct challenge — not just describe a product category.

- **Informational (fine for SEO):** "ระบบ CRM สะสมแต้ม เพิ่มยอดซื้อซ้ำ ขับเคลื่อนด้วย AI"
- **Conversion-driven (ads):** Must make the reader feel something — cost of inaction, a possibility, or a direct challenge that pulls them in.

_Source section truncated in seed; see `source_ref` for full text._', metadata = metadata || '{"genre": "landing", "source_file": "WEB_PAGE_COPY_PRINCIPLES.md", "section_anchor": "iii-persuasion-how-to-frame-the-message", "part": 1, "feature_slug": "web-landing-copy", "generation_batch": "writing_principles_seed_20260530T011413Z", "content_sha256": "79ecde415f1b8111a36e45b865dab608ce88cfd967a7189e865cf4f894aafea0", "truncated": true}'::jsonb, updated_at = now() WHERE id = '11a5714e-48a6-5bee-adcb-e22decf3f260'::uuid;
UPDATE public.internal_knowledge_blocks SET content = E'---

### 18. Punchy Specificity

Specific does not mean long. If it takes two lines to read, cut it. Every word must earn its place.

**Kill filler.** Remove "that helps you," "enabling you to," "in order to," "designed for." These are verbal throat-clearing.

**The One-Breath Test.** If you can''t read the headline in a single short breath, rewrite.

| Too Long | Punchy |
|---|---|
| "We help you stop the manual process of pasting data from Stripe into Excel every single Monday morning." | "Stop pasting Stripe data into Excel." |
| "A platform designed for high-growth brands that want to stand out from the competition." | "Loyalty for category-leading brands." |
| "Our AI automatically segments your customers based on their purchase behavior and engagement history." | "Auto-segments customers by what they buy and how they engage." |

The punchy version carries the same information with the scaffolding removed. Being descriptive and being concise are not opposites — they''re the same discipline. Choose exact words, remove everything else.

### 19. CTA: Shortest, Punchiest Line on the Page

The CTA headline is where hesitation lives. Long CTAs create friction. The reader is deciding whether to fill out a form — every extra word gives them time to reconsider.

The CTA does not need to re-explain the product. The reader has already scrolled the whole page. They know what it is. Just push them over the edge.

- **Too padded:** "พร้อมเพิ่มยอดซื้อซ้ำด้วยระบบ CRM หรือยัง?"
- **Punchy:** "เพิ่มยอดซื้อซ้ำ เริ่มได้ใน 2 สัปดาห์"

Pair the outcome with a speed/ease claim. That''s it. No re-selling.

### 20. Specificity Filter

Reference table. Every line you write, check it against this. Left column means rewrite.

| Category | Generic (Delete) | Specific (Keep) |
|---|---|---|
| **Identity** | "Next-gen loyalty platform." | "The loyalty engine for category-leading brands." |
| **Utility** | "Flexible reward options." | "Reward any action, not just purchases." |
| **Value** | "Affordable pricing." | "Enterprise features, SME price tag." |
| **Pain** | "Stop manual work." | "Stop pasting Stripe data into Excel." |
| **Speed** | "Fast integration." | "Syncs orders in < 500ms." |
| **Scope** | "Comprehensive solution." | "Points. Tiers. Referrals. Gift cards." |
| **Tech** | "AI-powered insights." | "Predicts which customers will churn next month." |
| **Customization** | "Fully customizable." | "ให้คะแนนได้มากกว่าแค่ยอดซื้อ — รีวิว ชวนเพื่อน Check-in ก็ให้ได้" |

---', metadata = metadata || '{"genre": "landing", "source_file": "WEB_PAGE_COPY_PRINCIPLES.md", "section_anchor": "iv-craft-sentence-level-discipline", "part": 1, "feature_slug": "web-landing-copy", "generation_batch": "writing_principles_seed_20260530T011413Z", "content_sha256": "e3fcba24f234fc55c11e3c000e09b40343ecd2fd8b0dcdddb07f1d6be8597eb9", "truncated": false}'::jsonb, updated_at = now() WHERE id = '920753ab-fd86-5897-933d-49ce94416d18'::uuid;
UPDATE public.internal_knowledge_blocks SET content = E'For any line of copy:

1. **Comprehension** — Does the reader know what it is and who it''s for in 5 seconds?
2. **Hero** — Is the sentence about the customer''s situation, or about the brand?
3. **Clarity** — Am I using a metaphor where a description should be? (Exception: punchy tagline that generates real emotion)
4. **Precision** — Am I using a vague modifier where an example should be? Or a high-level word without a clear category container?
5. **Balance** — Should I lead with outcome, mechanism, or identity for this audience? If using a heading + description pair, is the heading strategic and the description operational?
6. **Category** — Would the reader know exactly which product type this is?
7. **Validation** — Am I listing capabilities? Same abstraction level AND same grammatical form? Does each item convey the right meaning?
8. **Visibility** — Is the feature abstract? Add narrative motion.
9. **After-state** — Have I painted a concrete scene of the customer''s life after using this?
10. **Utility** — Am I describing features using the user''s daily workflow verbs? Is AI the subject doing verbs, or a modifier bolted on?
11. **Problem depth** — Am I addressing the external, internal, and philosophical layers? Is the pain real or manufactured?
12. **Objections** — Am I handling fears inline? Is there a structured FAQ for bottom-of-page objections?
13. **Trust** — Is social proof (numbers, logos) positioned early, before features?
14. **Hooks** — Have I shown the cost of inaction AND the FOMO of falling behind peers? Do contrast structures set up real opposition?
15. **Differentiation** — If this is a "why us" section, could a competitor say the same thing?
16. **Intent** — Is the headline informational or conversion-driven? Does it match the page type?
17. **Simplicity** — Is there a 3-step plan that makes the path feel easy?
18. **Economy** — Can I read this in one breath? Is every word earning its place?
19. **CTA** — Is the closing line the shortest, punchiest line on the page?
20. **Specificity** — Would this pass the filter table?
21. **Language** — Does the Thai read like Thai? English terms integrated naturally? Reader''s vocabulary?
22. **Keywords** — Is keyword usage calibrated to the page type (SEO vs. Ads)?

If it passes all twenty-two, ship it.

---

---', metadata = metadata || '{"genre": "landing", "source_file": "WEB_PAGE_COPY_PRINCIPLES.md", "section_anchor": "quick-decision-tree", "part": 1, "feature_slug": "web-landing-copy", "generation_batch": "writing_principles_seed_20260530T011413Z", "content_sha256": "6d104a0e9d46f43bb83cb58da474f0305ff580a7ab9a762409d5525175fa34e6", "truncated": false}'::jsonb, updated_at = now() WHERE id = '152ac3e8-d295-5a3a-b936-1c5d7fcad01d'::uuid;
UPDATE public.internal_knowledge_blocks SET content = E'---

### 21. Thai-English Language Rules

Content will be written in Thai and English. Thai copy must read like it was written in Thai — not translated from English.

**Core rule:** Write the thought in Thai first. If it sounds like something a Thai business owner would actually say, keep it. If it sounds like Google Translate output, rewrite from scratch.

**English loanwords.** Terms that are universally used in English within the Thai business context stay in English. Do not force a Thai translation when none exists naturally.

- **Keep in English:** AI, CRM, Dashboard, Loyalty Program, API, Shopify, LINE, Omnichannel, Marketplace, ROI, Churn
- **Write in Thai:** everything else — especially verbs, benefits, and descriptions of what the product does

**Examples:**

- **Natural:** "ใช้ AI วิเคราะห์พฤติกรรมลูกค้า" — AI stays English, the rest is natural Thai.
- **Forced:** "ใช้ปัญญาประดิษฐ์ในการวิเคราะห์พฤติกรรมของลูกค้า" — nobody says ปัญญาประดิษฐ์ in a business context.
- **Natural:** "เชื่อมต่อกับ Shopify ได้ทันที" — Shopify stays English, verb is natural Thai.
- **Forced:** "สามารถทำการเชื่อมต่อระบบเข้ากับแพลตฟอร์ม Shopify ของคุณได้อย่างรวดเร็ว" — over-formal, padded with unnecessary structure.

**Watch for Thai filler patterns.** Thai copy tends to accumulate polite padding: สามารถ...ได้, ทำการ, เพื่อที่จะ, ช่วยให้คุณสามารถ. These are the Thai equivalent of "enabling you to" — cut them the same way.

**English terms must integrate into Thai grammar.** Don''t append English words to Thai sentences using แบบ, ในรูปแบบ, or ในลักษณะ as a bridge. If the term doesn''t fit the sentence flow, restructure the sentence around it.

- **Awkward graft:** "สะสมแต้มได้ครบทุกช่องทาง แบบ Omnichannel"
- **Natural integration:** "ระบบสะสมแต้ม Omnichannel — ขายที่ไหนก็ให้แต้มลูกค้าได้"

In the first, "แบบ Omnichannel" is bolted on. In the second, "Omnichannel" sits as a modifier before the dash, and the Thai explanation follows naturally.

**Use the reader''s vocabulary, not the builder''s.** If the audience is marketers, they "ดึงรายงาน" not "เขียน Query." If the audience is business owners, they care about "ยอดขาย" not "conversion rate." Always match the words the reader would use to describe their own daily work. If you wouldn''t hear it in a meeting with that audience, don''t put it on the page.

### 22. Keyword Strategy

Each prompt will specify two things: the **page type** (SEO or Ads) and the **primary keyword**. How you handle keywords differs between them.

**SEO pages — optimize for ranking.** The primary objective is search visibility. Follow SEO best practices:

- Place the keyword in the H1, at least one H2, the meta title, meta description, and the first 100 words.
- Use it at a frequency that may feel slightly above natural — this is intentional. Search engines need repetition to understand page relevance.
- Use semantic variations and related terms throughout the body to build topical authority.
- The copy still needs to read well, but SEO density takes priority over conversational flow where the two conflict.

**Ads pages — optimize for conversion.** The visitor already clicked an ad. They already searched the keyword. The primary objective is now conversion, not ranking.

- Use the keyword enough that the reader feels they''ve landed on the right page — it should mirror their search intent and appear in the headline and early body copy.
- Beyond that, let the keyword appear naturally. Do not repeat it artificially. Every additional instance should serve the reader, not a crawler.
- The copy should feel like it''s speaking to the reader, not performing for an algorithm.

**The difference in practice:**

| | SEO Page | Ads Page |
|---|---|---|
| **Goal** | Rank for the keyword | Convert the visitor |
| **Keyword in H1** | Required | Required |
| **Keyword density** | Higher than natural, per SEO best practice | Natural — enough to confirm relevance |
| **Repetition logic** | Serve the algorithm | Serve the reader |
| **Tone priority** | Informational, comprehensive | Direct, persuasive, concise |

---', metadata = metadata || '{"genre": "landing", "source_file": "WEB_PAGE_COPY_PRINCIPLES.md", "section_anchor": "v-language-keywords", "part": 1, "feature_slug": "web-landing-copy", "generation_batch": "writing_principles_seed_20260530T011413Z", "content_sha256": "20aa125f3527da9314e2a214fbec4cba3e30f87612e7fd15b5f9188f68ae6b4e", "truncated": false}'::jsonb, updated_at = now() WHERE id = 'f67d3bcf-2fd6-5902-9f9b-0306bed0cadd'::uuid;
UPDATE public.internal_knowledge_blocks SET content = E'**When to use:** Product landing pages, homepage hero, feature LPs. 5-second clarity, customer-as-hero, CTAs, Thai/English voice.
**Source:** `WEB_PAGE_COPY_PRINCIPLES.md` (Part 1)
**Genre:** `landing`

I. Foundation: What the Page Must Do in 5 Seconds', metadata = metadata || '{"genre": "landing", "source_file": "WEB_PAGE_COPY_PRINCIPLES.md", "section_anchor": "overview", "part": 1, "feature_slug": "web-landing-copy", "generation_batch": "writing_principles_seed_20260530T011413Z", "content_sha256": "722afacdb6ad9df20d454f89fef54ebbe5906b73bcdb2c968ef6c7b56d92bc3b", "truncated": false}'::jsonb, updated_at = now() WHERE id = '263c9a39-2e07-5e84-bc71-b4da9cf0df88'::uuid;
UPDATE public.internal_knowledge_blocks SET content = E'Single source of truth for **Rocket web content** — product landing pages, SEO blog/knowledge articles, on-page SEO signals, and internal link architecture.

**Read first:** `CORE_WRITING_PRINCIPLES.md` for pyramid structure, MECE, same-level grouping, and specificity rules that apply across all formats.

**Localization:** Non-Thai markets → `TRANSLATION_PHILOSOPHY.md` (separate doc).', metadata = metadata || '{"genre": "web", "source_file": "WEB_PAGE_COPY_PRINCIPLES.md", "section_anchor": "about-this-document", "feature_slug": "web-page-copy", "generation_batch": "writing_principles_seed_20260530T011413Z", "content_sha256": "6b6776e070b4161c8df697c06096399fa961fecbb925e5fffeedc6ebc827d0dd", "truncated": false}'::jsonb, updated_at = now() WHERE id = 'aa593046-43b9-5eaa-9dae-724b45b904ca'::uuid;
UPDATE public.internal_knowledge_blocks SET content = E'**When to use:** Routing parent only — read Which part to use before fetching a part slug. Do not load all four parts at once.
**Source:** `WEB_PAGE_COPY_PRINCIPLES.md`
**Genre:** `web`

Landing pages, blog articles, SEO, and internal linking', metadata = metadata || '{"genre": "web", "source_file": "WEB_PAGE_COPY_PRINCIPLES.md", "section_anchor": "overview", "feature_slug": "web-page-copy", "generation_batch": "writing_principles_seed_20260530T011413Z", "content_sha256": "63145af38cdbda2a2fc2769f820d4e39eb715cc1d6380dff8a70bc34f91229d3", "truncated": false}'::jsonb, updated_at = now() WHERE id = '329c68a8-c090-5b4b-a92b-0b4f4b72e711'::uuid;
UPDATE public.internal_knowledge_blocks SET content = E'| Page type | Primary part | Also read |
|-----------|--------------|-----------|
| Product landing page | **Part 1** — Landing Page Copy | Part 3 (SEO signals), Part 4 (links in/out) |
| Blog / knowledge article | **Part 2** — Blog & Knowledge Articles | Part 3, Part 4 |
| SEO planning / on-page audit | **Part 3** — SEO Strategy | Part 1 or 2 depending on page type |
| Link architecture / new article workflow | **Part 4** — Internal Linking | Part 3 (clusters, intent tiers) |

---', metadata = metadata || '{"genre": "web", "source_file": "WEB_PAGE_COPY_PRINCIPLES.md", "section_anchor": "which-part-to-use", "feature_slug": "web-page-copy", "generation_batch": "writing_principles_seed_20260530T011413Z", "content_sha256": "b8b5104129c8fd1b94ae60f4585ea649e3f08cd194730149e1b8f0df60f6d145", "truncated": false}'::jsonb, updated_at = now() WHERE id = '541ddee2-05ff-5933-a43d-4bb5c39a5a0e'::uuid;