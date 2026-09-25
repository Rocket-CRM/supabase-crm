begin;

with input_items as (
  select *
  from jsonb_to_recordset($seed_json$[]$seed_json$::jsonb) as x(
    id uuid,
    parent_slug text,
    slug text,
    name text,
    item_type text,
    description text,
    sort_order integer,
    metadata jsonb,
    aliases text[],
    is_active boolean
  )
),
resolved_items as (
  select
    i.id,
    p.id as parent_id,
    i.slug,
    i.name,
    i.item_type::internal_knowledge_item_type as item_type,
    nullif(i.description, '') as description,
    i.sort_order,
    i.metadata,
    coalesce(i.aliases, '{}'::text[]) as aliases,
    coalesce(i.is_active, true) as is_active
  from input_items i
  left join public.internal_knowledge_feature_items p on lower(p.slug) = lower(i.parent_slug)
)
insert into public.internal_knowledge_feature_items (
  id, parent_id, slug, name, item_type, description, sort_order, metadata, aliases, is_active, updated_at
)
select id, parent_id, slug, name, item_type, description, sort_order, metadata, aliases, is_active, now()
from resolved_items
on conflict (id) do update set
  parent_id = excluded.parent_id,
  slug = excluded.slug,
  name = excluded.name,
  item_type = excluded.item_type,
  description = excluded.description,
  sort_order = excluded.sort_order,
  metadata = public.internal_knowledge_feature_items.metadata || excluded.metadata,
  aliases = excluded.aliases,
  is_active = excluded.is_active,
  updated_at = now();

with input_blocks as (
  select *
  from jsonb_to_recordset($seed_json$[{"id": "b79eb606-38e8-5caa-ab2a-3d2b159bb29a", "feature_slug": "translation", "title": "AI & Technology Term Principles", "content": "These apply universally across all markets:\n\n1. **Name the decision, not the technology.** \"AI predicts which customers will stop buying and sends them a personalized offer\" — not \"AI-powered machine learning analytics engine.\"\n2. **Frame as augmentation, not replacement.** AI helps the team do more, not replaces the team. Especially important in JP and TW enterprise contexts.\n3. **Keep \"AI\" in the sentence when using analogy.** \"AI acts like your best marketing intern — but works 24/7\" keeps it grounded. Don't let the analogy erase the AI reference.\n4. **Precision over claims.** \"AI sends personalized offers to each customer automatically\" > \"cutting-edge AI technology.\" Show what it does, not what it is.\n\n---", "content_format": "markdown", "knowledge_type": "rules", "perspectives": ["general", "marketing"], "output_uses": ["agent_context", "marketing_content", "proposal_content", "slide_generation"], "scope": "general", "source_ref": "Writing Principles/TRANSLATION_PHILOSOPHY.md#ai-technology-term-principles", "metadata": {"genre": "translation", "source_file": "TRANSLATION_PHILOSOPHY.md", "section_anchor": "ai-technology-term-principles", "feature_slug": "translation", "generation_batch": "writing_principles_seed_20260530T011413Z", "content_sha256": "c97f70d3858c3afdcd1ee6d7cebdbfe009badada8934d3b4ead56f9decfef5f4", "truncated": false}, "is_active": true}, {"id": "80a5f9a4-2eb7-5f31-b862-f259deab8b2f", "feature_slug": "translation", "title": "Core Principle: Localize, Don't Translate", "content": "We don't swap words between languages. We rewrite each text component so it reads like it was written by a sharp marketer in that market. The test: would a native speaker in the target market assume this was originally written in their language?\n\n**What this means in practice:**\n\n| Approach | Example (JP) | Result |\n|---|---|---|\n| Translation (wrong) | \"Turn customers into members\" → \"顧客をメンバーに変える\" | Grammatically correct, sounds like a translation |\n| Localization (right) | \"Turn customers into members\" → \"顧客を会員に。全チャネルで。\" | Sounds like a Japanese marketer wrote it |\n\n---", "content_format": "markdown", "knowledge_type": "rules", "perspectives": ["general", "marketing"], "output_uses": ["agent_context", "marketing_content", "proposal_content", "slide_generation"], "scope": "general", "source_ref": "Writing Principles/TRANSLATION_PHILOSOPHY.md#core-principle-localize-don-t-translate", "metadata": {"genre": "translation", "source_file": "TRANSLATION_PHILOSOPHY.md", "section_anchor": "core-principle-localize-don-t-translate", "feature_slug": "translation", "generation_batch": "writing_principles_seed_20260530T011413Z", "content_sha256": "2b26906b1fd3dd1bf2d219c04aa8cb0124e052bee153ecd4f66a48eab2d96abb", "truncated": false}, "is_active": true}, {"id": "773a0dd6-2f4a-5843-8f84-5bf55a33a264", "feature_slug": "translation", "title": "Currency & Number Formatting", "content": "Always convert to local currency and format. Never leave prices in a foreign currency.\n\n| Market | Currency | Format | Example |\n|---|---|---|---|\n| **Japan** | Yen (JPY) | ¥ prefix, no decimal, comma separator | ¥1,500 |\n| **Taiwan** | New Taiwan Dollar (TWD) | NT$ prefix, no decimal | NT$450 |\n| **Thailand** | Baht (THB) | ฿ prefix or \"บาท\" suffix | ฿500 or 500 บาท |\n| **English** | USD or contextual | $ prefix, 2 decimal places | $15.00 |\n\n**Numbers:**\n- Use local number formatting (comma/period conventions)\n- Quantities: use local counter words where natural (JP: 枚 for coupons, 人 for people; TW: 張 for coupons; TH: ใบ for coupons)\n- Percentages: use % universally\n\n---", "content_format": "markdown", "knowledge_type": "rules", "perspectives": ["general", "marketing"], "output_uses": ["agent_context", "marketing_content", "proposal_content", "slide_generation"], "scope": "general", "source_ref": "Writing Principles/TRANSLATION_PHILOSOPHY.md#currency-number-formatting", "metadata": {"genre": "translation", "source_file": "TRANSLATION_PHILOSOPHY.md", "section_anchor": "currency-number-formatting", "feature_slug": "translation", "generation_batch": "writing_principles_seed_20260530T011413Z", "content_sha256": "d55441993d356aebca22f1911b525ebed087dcf8bbd74ef64786e11fabf8ebf3", "truncated": false}, "is_active": true}, {"id": "ec98f011-f8ac-5fc6-aab2-c9bfed8aef44", "feature_slug": "translation", "title": "English Term Policy", "content": "Industry-standard terms stay in English across all markets. The test: if a B2B SaaS website in the target market would use this term in English, keep it in English.\n\n**Always keep in English:**\n\n| Category | Terms |\n|---|---|\n| **Technical** | AI, CRM, Dashboard, API, SaaS, POS, EC, QR, OTP, SLA, Push Notification, Omnichannel |\n| **Metrics** | ROI, LTV, CLV, KPI, CSAT, AOV, CAC |\n| **Platform names** | LINE, Shopify, Shopee, Lazada, TikTok, WhatsApp, Facebook, Instagram |\n| **Brand names** | Rocket, Agentic CRM |\n| **Tier names** | Gold, Silver, Platinum (keep English unless market doc overrides) |\n\n**Market-specific decisions:** Some terms are borderline. The market-specific doc decides:\n- \"Omnichannel\" — English in JP/EN, localized in TH/TW\n- \"Churn\" — English in EN, localized in JP/TH/TW\n- \"Mission\" — depends on market (ミッション in JP, kept English or ภารกิจ in TH)\n\n---", "content_format": "markdown", "knowledge_type": "rules", "perspectives": ["general", "marketing"], "output_uses": ["agent_context", "marketing_content", "proposal_content", "slide_generation"], "scope": "general", "source_ref": "Writing Principles/TRANSLATION_PHILOSOPHY.md#english-term-policy", "metadata": {"genre": "translation", "source_file": "TRANSLATION_PHILOSOPHY.md", "section_anchor": "english-term-policy", "feature_slug": "translation", "generation_batch": "writing_principles_seed_20260530T011413Z", "content_sha256": "13c715819c483645c8d83a171e1a65604bdbe5b2bed468dda018cee24cbfc683", "truncated": false}, "is_active": true}, {"id": "02a7a988-a6d0-5b2a-91f4-aa6a17da7f96", "feature_slug": "translation", "title": "Per-Market Context Docs", "content": "Each market has a dedicated doc that inherits these universal rules and adds:\n\n1. **Market context** — who buys, what they search for, cultural notes\n2. **Feature vocabulary table** — canonical translations for every domain-specific term\n3. **Feature nuances** — how features resonate differently in this market\n4. **UI translation patterns** — common component translations\n5. **CTA patterns** — call-to-action conventions\n\n| Market | Doc | Language |\n|---|---|---|\n| Japan | [JAPAN_CONTEXT.md](JAPAN_CONTEXT.md) | Japanese |\n| Taiwan | [TAIWAN_CONTEXT.md](TAIWAN_CONTEXT.md) | Traditional Chinese (zh-TW) |\n| Thailand | [THAILAND_CONTEXT.md](THAILAND_CONTEXT.md) | Thai |\n| English | [ENGLISH_CONTEXT.md](ENGLISH_CONTEXT.md) | English (SEA/Global) |", "content_format": "markdown", "knowledge_type": "rules", "perspectives": ["general", "marketing"], "output_uses": ["agent_context", "marketing_content", "proposal_content", "slide_generation"], "scope": "general", "source_ref": "Writing Principles/TRANSLATION_PHILOSOPHY.md#per-market-context-docs", "metadata": {"genre": "translation", "source_file": "TRANSLATION_PHILOSOPHY.md", "section_anchor": "per-market-context-docs", "feature_slug": "translation", "generation_batch": "writing_principles_seed_20260530T011413Z", "content_sha256": "26bf0a050ca63a893264cd2eb0d4bb0a8dd29569dcc405e81834a5e6d21227df", "truncated": false}, "is_active": true}, {"id": "4491cdc6-711f-5751-8b02-9a0276a3d7d6", "feature_slug": "translation", "title": "Proper Noun Rules", "content": "| Category | Rule | Examples |\n|---|---|---|\n| **Brand names** | Never translate | Rocket, LINE, Shopify, Shopee, Lazada |\n| **Product names** | Never translate | Agentic CRM |\n| **Feature names (English origin)** | Keep English if established in market | Top Spender, Dashboard, Mission (in JP) |\n| **Feature names (localized)** | Use market-specific term | 友達紹介 (JP for Referral), 會員經營 (TW for Membership Operations) |\n| **Tier names** | Keep English unless market doc overrides | Gold, Silver, Platinum |\n\n---", "content_format": "markdown", "knowledge_type": "rules", "perspectives": ["general", "marketing"], "output_uses": ["agent_context", "marketing_content", "proposal_content", "slide_generation"], "scope": "general", "source_ref": "Writing Principles/TRANSLATION_PHILOSOPHY.md#proper-noun-rules", "metadata": {"genre": "translation", "source_file": "TRANSLATION_PHILOSOPHY.md", "section_anchor": "proper-noun-rules", "feature_slug": "translation", "generation_batch": "writing_principles_seed_20260530T011413Z", "content_sha256": "f6ce319c7f18ae5f81833ab4796d8a749ce47894b7a01a4944a8bacc745afea0", "truncated": false}, "is_active": true}, {"id": "71278524-ba10-5537-9a73-12144b0f0e1b", "feature_slug": "translation", "title": "Structure Fidelity", "content": "Match the original component structure. If the image shows a button, give a button-length string. If it shows a headline + subtext, give headline + subtext. Don't add or remove elements.\n\n**Rules:**\n- Button text → button-length translation (short, action-oriented)\n- Headline + subheadline → maintain the hierarchy and relative lengths\n- Feature card (title + description) → title stays punchy, description stays concise\n- Data labels → match the terseness of the original\n- If you need more words in the target language, find a shorter way to say it. Don't let translations break layouts.\n\n---", "content_format": "markdown", "knowledge_type": "rules", "perspectives": ["general", "marketing"], "output_uses": ["agent_context", "marketing_content", "proposal_content", "slide_generation"], "scope": "general", "source_ref": "Writing Principles/TRANSLATION_PHILOSOPHY.md#structure-fidelity", "metadata": {"genre": "translation", "source_file": "TRANSLATION_PHILOSOPHY.md", "section_anchor": "structure-fidelity", "feature_slug": "translation", "generation_batch": "writing_principles_seed_20260530T011413Z", "content_sha256": "b07f71a01753a2c3a02991be6e4049fafc13c4026141a2a0678267a29494d2ba", "truncated": false}, "is_active": true}, {"id": "bf4f7929-e952-5e4a-b6bb-7690604c60de", "feature_slug": "translation", "title": "The Complexity Spectrum", "content": "Not every text component needs the same level of effort. Calibrate by complexity:\n\n| Text type | Examples | What to do |\n|---|---|---|\n| **Simple / universal** | \"Buy Now,\" \"Gold,\" \"15 Coupons,\" \"Details →,\" \"Settings\" | Just translate. Use the natural equivalent a user expects to see. Don't overthink. |\n| **Domain-specific** | \"Tier,\" \"Omnichannel,\" \"Churn,\" \"Segment,\" \"AI Agent,\" \"Double Points\" | Check the vocabulary table in the market-specific doc. These terms have established translations — use them consistently. |\n| **Marketing copy** | Headlines, subheadlines, feature descriptions, taglines | Use the product context + market context to make it read well locally. Not a literal translation — a local marketer's version. |\n\n---", "content_format": "markdown", "knowledge_type": "rules", "perspectives": ["general", "marketing"], "output_uses": ["agent_context", "marketing_content", "proposal_content", "slide_generation"], "scope": "general", "source_ref": "Writing Principles/TRANSLATION_PHILOSOPHY.md#the-complexity-spectrum", "metadata": {"genre": "translation", "source_file": "TRANSLATION_PHILOSOPHY.md", "section_anchor": "the-complexity-spectrum", "feature_slug": "translation", "generation_batch": "writing_principles_seed_20260530T011413Z", "content_sha256": "771d0e9f525fc24d618e3fa2d595f03238c798af7c187a3540bad9c8bf22ef74", "truncated": false}, "is_active": true}, {"id": "a409b461-9671-5b65-8d8f-8413e6e0302f", "feature_slug": "translation", "title": "Tone Calibration", "content": "Each market has a different baseline tone. The market-specific doc specifies where on the spectrum, but here's the universal framework:\n\n| Dimension | Formal end | Casual end | Notes |\n|---|---|---|---|\n| **Formality** | Enterprise Japanese (です/ます, honorifics) | Thai B2B/SME (direct, conversational, no corporate padding) | Match audience segment, not just market |\n| **Directness** | English (direct, outcome-focused) | Japanese (implications, softer framing) | Cultural communication norms |\n| **Tech confidence** | English/TW (AI is exciting, lean into it) | JP enterprise (AI is risky, pair with control/guardrails) | How the market perceives AI claims |\n| **Urgency** | Specific numbers always (JP: \"最短1ヶ月\") | Vague superlatives never | All markets: precision beats superlatives |\n\n**Thailand (B2B/SME):** Strip overly formal corporate padding and unnatural metaphors. Write like a sharp marketer talking to an operator — not a translated press release. If a literal English→Thai line sounds clever on paper but awkward spoken aloud, rewrite in neutral, natural business Thai.\n\n**Structure fidelity in every market:** A title stays a punchy title; a description stays a concise mechanism explanation. Do not let localization bloat layout or force a redesign. If the target language needs more words, shorten the idea — do not add elements.\n\n---", "content_format": "markdown", "knowledge_type": "rules", "perspectives": ["general", "marketing"], "output_uses": ["agent_context", "marketing_content", "proposal_content", "slide_generation"], "scope": "general", "source_ref": "Writing Principles/TRANSLATION_PHILOSOPHY.md#tone-calibration", "metadata": {"genre": "translation", "source_file": "TRANSLATION_PHILOSOPHY.md", "section_anchor": "tone-calibration", "feature_slug": "translation", "generation_batch": "writing_principles_seed_20260530T011413Z", "content_sha256": "7f8bfc8ecea8c83585a254f2c60aa29dc25ad5f4fe4ae2e5eacd0ebf7142e5ff", "truncated": false}, "is_active": true}, {"id": "a5f7bde0-b04c-5550-a314-316747340db3", "feature_slug": "translation", "title": "Translation & Localization — Overview", "content": "**When to use:** Add after genre playbook when output is Thai, JP, TW, or mixed EN/local. Localize-don't-translate, term policy, tone calibration.\n            **Source:** `TRANSLATION_PHILOSOPHY.md`\n            **Genre:** `translation`\n\n**Cross-cutting:** Add after the genre playbook when localizing.\n\n            Translation Philosophy — Universal Principles", "content_format": "markdown", "knowledge_type": "overview", "perspectives": ["general", "marketing"], "output_uses": ["agent_context", "marketing_content", "proposal_content", "slide_generation"], "scope": "general", "source_ref": "Writing Principles/TRANSLATION_PHILOSOPHY.md", "metadata": {"genre": "translation", "source_file": "TRANSLATION_PHILOSOPHY.md", "section_anchor": "overview", "feature_slug": "translation", "generation_batch": "writing_principles_seed_20260530T011413Z", "content_sha256": "6063af023db897399cbcd63dd03bce6ac054631b6cfaf16cc4adca2575ebcbf1", "truncated": false}, "is_active": true}]$seed_json$::jsonb) as x(
    id uuid,
    feature_slug text,
    title text,
    content text,
    content_format text,
    knowledge_type text,
    perspectives text[],
    output_uses text[],
    scope text,
    source_ref text,
    metadata jsonb,
    is_active boolean
  )
),
resolved_blocks as (
  select
    b.id,
    f.id as feature_item_id,
    b.title,
    b.content,
    b.content_format,
    b.knowledge_type::internal_knowledge_type as knowledge_type,
    b.perspectives::internal_knowledge_perspective[] as perspectives,
    b.output_uses::internal_knowledge_output_use[] as output_uses,
    b.scope::internal_knowledge_scope as scope,
    b.source_ref,
    b.metadata,
    coalesce(b.is_active, true) as is_active
  from input_blocks b
  join public.internal_knowledge_feature_items f on lower(f.slug) = lower(b.feature_slug)
)
insert into public.internal_knowledge_blocks (
  id, feature_item_id, title, content, content_format, knowledge_type,
  perspectives, output_uses, scope, source_ref, metadata, is_active, updated_at
)
select
  id, feature_item_id, title, content, content_format, knowledge_type,
  perspectives, output_uses, scope, source_ref, metadata, is_active, now()
from resolved_blocks
on conflict (id) do update set
  feature_item_id = excluded.feature_item_id,
  title = excluded.title,
  content = excluded.content,
  content_format = excluded.content_format,
  knowledge_type = excluded.knowledge_type,
  perspectives = excluded.perspectives,
  output_uses = excluded.output_uses,
  scope = excluded.scope,
  source_ref = excluded.source_ref,
  metadata = public.internal_knowledge_blocks.metadata || excluded.metadata,
  is_active = excluded.is_active,
  updated_at = now();

commit;
