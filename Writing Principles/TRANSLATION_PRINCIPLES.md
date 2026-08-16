# Translation Principles — Proposals

> **Purpose:** Localization craft for customer-facing **proposals** (custom / government packs such as EECO, and Rocket loyalty proposals when the run language is Thai).  
> **Inherits:** [TRANSLATION_PHILOSOPHY.md](TRANSLATION_PHILOSOPHY.md) for universal localize-don’t-translate, English-term policy, and market tone. This file adds **proposal-specific** rules and the English→Thai convert procedure.  
> **Not for:** Landing pages, SEO blogs, or slide decks alone — use `WEB_PAGE_COPY_PRINCIPLES.md` / slide § Thai rules / market context docs for those.

---

## Core stance

Localize. Do not translate word-for-word.

Rewrite so a native Thai reader assumes the document was **written in Thai** for this buyer — not put through a machine. The test: would a Thai colleague say this aloud in a meeting with the Authority?

**What this means:**

| Approach | Result |
|---|---|
| Translation (wrong) | English grammar and imagery preserved; reads as “ChatGPT Thai” |
| Localization (right) | Meaning and commitments preserved; natural formal Thai prose |

---

## Workflow language model (general + EECO)

| Phase | Language | Where it lives |
|---|---|---|
| Draft, principles review, human Review 3 | **English** | Run root: `sections/`, `proposal.md`, other compiled customer docs |
| Thai convert | **Only when manually triggered** | `th/` under the same run (see below) |
| English after convert | **Kept as backup** | Run root English files stay; do **not** overwrite them with Thai |

Rocket loyalty proposal runs may use the same pattern when the brief asks for Thai submission after English review: keep English at the run root (or under `en/` if the run already treats Thai as primary), write Thai under `th/`.

### Manual trigger phrases

Run the Thai convert pass only when the human says something like:

- “localize to Thai”
- “Thai convert”
- “run Thai localization”
- “produce the Thai version”

Do **not** auto-localize at compile or Polish. Do not mix English review drafts and Thai submission text in the same file without being asked.

### Convert procedure (when triggered)

1. **Confirm English is review-ready** (or proceed with known gaps only if the human says so).
2. **Leave English in place** at the run root (`proposal.md`, `sections/`, comparison matrices, etc.). That tree is the backup and the source for future English edits.
3. **Snapshot (optional but recommended on first convert):** copy the current English compiled customer docs into `en/` so a frozen backup exists even if root English is later edited. If `en/` already exists, refresh only when the human asks to re-snapshot.
4. **Write Thai under `th/`:**
   - `th/proposal.md` (and other compiled customer docs as needed)
   - Optionally `th/sections/…` when converting section-by-section
5. **Apply this file’s craft rules** end-to-end. Treat English as a **brief**, not text-to-translate.
6. **Self-check** (§ Quick self-check). Persist a short note in the run (e.g. dossier or `th/README.md`) that Thai was generated from which English revision.
7. **Submission pack:** for Thai government packs, pack from `th/` (not from root English) unless the human says otherwise.

If the human later edits English, re-run Thai convert for affected sections — do not silently diverge.

If Thai review exposes structural AI slop, do not solve it by deleting only from `th/`. Apply the structural correction to the accepted English source first, record the before/after coverage and visual inventory, then re-localize the affected Thai sections. A human-authorized Thai-only divergence must be recorded in `th/translation-review.md` with the exact content/visuals changed and confirmation that no commitment or technical meaning was lost.

---

## Register: formal proposal Thai

Government / e-bidding packs need **formal agency Thai** — clear, official, systems-architect tone. Not marketing punch. Not SME conversational web copy.

| Do | Don’t |
|---|---|
| Commitments, process, ownership in plain formal Thai | Sales fluff, AI-brochure metaphors |
| Match TOR vocabulary where the buyer coined Thai terms | Paraphrase away buyer-chosen Thai wording |
| Keep structure fidelity (headings, tables, lists) | Inflate every sentence with สามารถ…ได้ / เพื่อที่จะ |

Universal marketing tone notes in `TRANSLATION_PHILOSOPHY.md` (Thai B2B/SME) apply to **marketing** surfaces. For **government proposals**, prefer the formal end of the spectrum.

---

## English term policy (proposals)

Keep industry-standard technical and product terms in English when Thai has no natural equivalent or when English is the market-standard phrase. Translate the surrounding explanation into natural Thai.

**Usually keep in English:**

| Category | Examples |
|---|---|
| Technical | AI, CRM, API, SaaS, POS, QR, OTP, SLA, Dashboard, Workflow, OAuth, SSO, HTTPS, ERD |
| Metrics | ROI, KPI, CSAT, SLA (when used as the metric label) |
| Platforms / brands | LINE, Shopify, Shopee, Lazada, TikTok, Rocket, AWS, GDCC |
| Buyer-standard English labels | When the TOR or glossary already uses the English form |

**First-use pattern (optional):** Thai paraphrase or short gloss with English in parentheses on first use only when it helps evaluators — e.g. `ระบบสมาชิก (loyalty)` — then use the chosen form consistently. Do not force awkward Thai coinages for terms evaluators already know in English.

**Never:** glue Thai noun-markers to English verbs (`การ activate`, `การ onboard`, `การ scale`). Either fully Thai the verb (`การเปิดใช้งาน`) or keep a clean English noun (`Activation`, `Onboarding`).

Exception: a few established pairs (`การ deploy`, `การ integrate`) are tolerated in architecture sections; still prefer clear Thai when an obvious equivalent exists.

---

## Thai prose smoothness (mandatory)

Default failure mode: word-by-word translation that keeps English grammar and English imagery. Native readers discount the proposal immediately.

### Numbers — Arabic numerals, not Thai longhand

| ❌ Don’t | ✅ Do |
|---|---|
| ภายในเวลาสามปี | ในเวลาเพียง 3 ปี |
| สมาชิกมากกว่าสิบล้านคน | สมาชิกกว่า 10 ล้านคน |
| ลูกค้าองค์กรกว่าหนึ่งร้อยราย | ลูกค้าองค์กรกว่า 100 ราย |

Cardinals ≥ 2 from the English source stay as numerals (`3`, `100`, `10 ล้าน`, `60–70`). Spell out only when “one/a” is doing disambiguation work in Thai.

### Idioms and metaphors — meaning, not image

| English | ❌ Literal | ✅ Prefer |
|---|---|---|
| umbrella platform | ร่ม / ใต้ร่ม | ครบในแพลตฟอร์มเดียว / แพลตฟอร์มเดียวครบ |
| pain point | จุดเจ็บปวด | ปัญหา / อุปสรรค (or keep “pain point” for SE-facing notes only) |
| backbone of … | กระดูกสันหลังของ… | แกนหลักของ… / โครงสร้างหลักของ… |
| ecosystem | ระบบนิเวศ (rarely natural for SaaS) | ระบบ / แพลตฟอร์ม |
| north star | ดาวเหนือ | เป้าหมายหลัก / ทิศทางหลัก |
| game changer | ตัวเปลี่ยนเกม | จุดเปลี่ยน / สร้างความแตกต่าง |
| spine / pile of cards | any literal calque | Rewrite in plain operational Thai (also banned in English proposal voice) |

### Calques — rewrite as natural Thai SVO

English “members’ intent doesn’t convert to redemptions” must not become a calque of “intent → convert → redemption.” Prefer a direct sentence a Thai officer would say.

Same for overused “X drives Y” → prefer `X ทำให้ Y…` or `Y เกิดจาก X` over `X ขับเคลื่อน Y` unless that verb is already natural in context.

### Templated English blocks

Company intros, USP lists, and executive-summary boilerplate authored in English are **briefs**. Do not mechanically translate headings and metaphors. Rewrite as if a Thai author drafted the section for this buyer.

### Filler

Cut Thai padding when the sentence works without it: `สามารถ…ได้`, `ทำการ`, `เพื่อที่จะ`, `ช่วยให้คุณสามารถ`.

---

## Source quoting (R2) and exact TOR text

When the TOR / Q&A / email chose specific wording and intent matters — and whenever customer-facing copy **presents the buyer’s requirement** (matrix buyer-requirement column, in-body TOR quote, buyer-coined term):

1. Open the clause in the run’s TOR source under `sources/` (not the English proposal paraphrase, not memory).
2. Quote **verbatim** (keep Thai script as-is when the source is Thai).
3. Add interpretation, proposal, or English gloss **beside** the quote — not instead of it.

**Thai convert:** for those surfaces, **copy** TOR Thai from `sources/` into `th/`. Do not translate our English summary of the TOR back into Thai. `Reference: TOR …` clause IDs must stay identical to the English draft and to the source numbering.

In Thai proposals, keep non-Thai source quotes verbatim when the customer supplied them that way; add a short Thai explanation after the quote.

Do not paraphrase away buyer-chosen vocabulary to “make it sound nicer.”

---

## Structure fidelity

- Match the English component shape: heading → heading, table → table, list → list.
- Title stays punchy; body stays the mechanism / commitment.
- If Thai needs more words, shorten the idea — do not add new claims or layout elements.
- Mermaid / diagram labels: localize when the diagram is customer-facing; keep code identifiers and API names in English.
- Preserve semantic visuals and technical detail. Branches, reverse transitions, actors, interfaces, authentication, data relations, controls, ownership boundaries, and dates are meaning—not layout.
- Language cleanup may compress repeated wording, but cannot remove a unique requirement, bidder commitment, or technical contract. When two surfaces appear duplicative, identify their unique semantics before choosing one.

---

## Quick self-check (before shipping Thai)

1. Are cardinals ≥ 2 written as numerals?
2. Any metaphorical `ร่ม` / `จุดเจ็บปวด` / `กระดูกสันหลัง` / `ระบบนิเวศ` / `ตัวเปลี่ยนเกม`? Rewrite.
3. Any `การ <english-word>` outside well-established technical pairs? Rewrite.
4. Do English root files still exist as the backup? Thai only under `th/` (unless the human ordered a different layout)?
5. Read the first paragraph aloud. Colleague-in-a-meeting Thai, or Google Translate? If the latter, rewrite — do not ship.
6. Commitments, dates, `Reference: TOR …` IDs, and `[GAP:…]` markers still accurate vs English source?
7. Where the Thai doc shows a buyer requirement (matrix col 1, TOR quotes): is the text **copied from `sources/`**, not retranslated from our English paraphrase?
8. Do architecture, system design, database, security, integration, migration, operations, and delivery retain the accepted English depth?
9. Compare diagram/mockup inventory with English. For every removed visual, is its unique meaning still explicit and recorded?
10. Does the proposal-owned matrix column use complete Thai commitments rather than translated keyword shorthand?

---

## Related docs

| Doc | Role |
|---|---|
| [TRANSLATION_PHILOSOPHY.md](TRANSLATION_PHILOSOPHY.md) | Universal localize rules, English-term categories, market tone spectrum |
| [PROPOSAL_WRITING_PRINCIPLES.md](PROPOSAL_WRITING_PRINCIPLES.md) | Proposal structure and section craft (language-agnostic) |
| [SALES_PRESENTATION_SLIDE_PRINCIPLES.md](SALES_PRESENTATION_SLIDE_PRINCIPLES.md) §6 | Slide-specific Thai term discipline |
| [WEB_PAGE_COPY_PRINCIPLES.md](WEB_PAGE_COPY_PRINCIPLES.md) §21 | Web Thai–English voice (not government proposal register) |
| `workflows/general-proposal/REFERENCE.md` | English-first draft; manual Thai convert into `th/` |
