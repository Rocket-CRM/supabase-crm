begin;
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
commit;
