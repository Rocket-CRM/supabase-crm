begin;
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