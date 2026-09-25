begin;
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
commit;