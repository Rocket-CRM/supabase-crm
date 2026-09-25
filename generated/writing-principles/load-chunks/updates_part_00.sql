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
commit;