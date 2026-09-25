begin;
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
commit;