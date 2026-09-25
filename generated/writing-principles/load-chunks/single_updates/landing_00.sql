begin;
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
commit;