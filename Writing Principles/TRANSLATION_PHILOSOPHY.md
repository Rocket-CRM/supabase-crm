# Translation Philosophy — Universal Principles

> **Purpose:** Shared localization rules that all market-specific context docs inherit. Read this first, then read the market-specific doc for the target language.
> **Applies to:** Japanese, Traditional Chinese (Taiwan), Thai, English

---

## Core Principle: Localize, Don't Translate

We don't swap words between languages. We rewrite each text component so it reads like it was written by a sharp marketer in that market. The test: would a native speaker in the target market assume this was originally written in their language?

**What this means in practice:**

| Approach | Example (JP) | Result |
|---|---|---|
| Translation (wrong) | "Turn customers into members" → "顧客をメンバーに変える" | Grammatically correct, sounds like a translation |
| Localization (right) | "Turn customers into members" → "顧客を会員に。全チャネルで。" | Sounds like a Japanese marketer wrote it |

---

## The Complexity Spectrum

Not every text component needs the same level of effort. Calibrate by complexity:

| Text type | Examples | What to do |
|---|---|---|
| **Simple / universal** | "Buy Now," "Gold," "15 Coupons," "Details →," "Settings" | Just translate. Use the natural equivalent a user expects to see. Don't overthink. |
| **Domain-specific** | "Tier," "Omnichannel," "Churn," "Segment," "AI Agent," "Double Points" | Check the vocabulary table in the market-specific doc. These terms have established translations — use them consistently. |
| **Marketing copy** | Headlines, subheadlines, feature descriptions, taglines | Use the product context + market context to make it read well locally. Not a literal translation — a local marketer's version. |

---

## English Term Policy

Industry-standard terms stay in English across all markets. The test: if a B2B SaaS website in the target market would use this term in English, keep it in English.

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

---

## Structure Fidelity

Match the original component structure. If the image shows a button, give a button-length string. If it shows a headline + subtext, give headline + subtext. Don't add or remove elements.

**Rules:**
- Button text → button-length translation (short, action-oriented)
- Headline + subheadline → maintain the hierarchy and relative lengths
- Feature card (title + description) → title stays punchy, description stays concise
- Data labels → match the terseness of the original
- If you need more words in the target language, find a shorter way to say it. Don't let translations break layouts.

---

## Currency & Number Formatting

Always convert to local currency and format. Never leave prices in a foreign currency.

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

---

## Tone Calibration

Each market has a different baseline tone. The market-specific doc specifies where on the spectrum, but here's the universal framework:

| Dimension | Formal end | Casual end | Notes |
|---|---|---|---|
| **Formality** | Enterprise Japanese (です/ます, honorifics) | Thai B2B/SME (direct, conversational, no corporate padding) | Match audience segment, not just market |
| **Directness** | English (direct, outcome-focused) | Japanese (implications, softer framing) | Cultural communication norms |
| **Tech confidence** | English/TW (AI is exciting, lean into it) | JP enterprise (AI is risky, pair with control/guardrails) | How the market perceives AI claims |
| **Urgency** | Specific numbers always (JP: "最短1ヶ月") | Vague superlatives never | All markets: precision beats superlatives |

**Thailand (B2B/SME):** Strip overly formal corporate padding and unnatural metaphors. Write like a sharp marketer talking to an operator — not a translated press release. If a literal English→Thai line sounds clever on paper but awkward spoken aloud, rewrite in neutral, natural business Thai.

**Structure fidelity in every market:** A title stays a punchy title; a description stays a concise mechanism explanation. Do not let localization bloat layout or force a redesign. If the target language needs more words, shorten the idea — do not add elements.

---

## AI & Technology Term Principles

These apply universally across all markets:

1. **Name the decision, not the technology.** "AI predicts which customers will stop buying and sends them a personalized offer" — not "AI-powered machine learning analytics engine."
2. **Frame as augmentation, not replacement.** AI helps the team do more, not replaces the team. Especially important in JP and TW enterprise contexts.
3. **Keep "AI" in the sentence when using analogy.** "AI acts like your best marketing intern — but works 24/7" keeps it grounded. Don't let the analogy erase the AI reference.
4. **Precision over claims.** "AI sends personalized offers to each customer automatically" > "cutting-edge AI technology." Show what it does, not what it is.

---

## Proper Noun Rules

| Category | Rule | Examples |
|---|---|---|
| **Brand names** | Never translate | Rocket, LINE, Shopify, Shopee, Lazada |
| **Product names** | Never translate | Agentic CRM |
| **Feature names (English origin)** | Keep English if established in market | Top Spender, Dashboard, Mission (in JP) |
| **Feature names (localized)** | Use market-specific term | 友達紹介 (JP for Referral), 會員經營 (TW for Membership Operations) |
| **Tier names** | Keep English unless market doc overrides | Gold, Silver, Platinum |

---

## Per-Market Context Docs

Each market has a dedicated doc that inherits these universal rules and adds:

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
| English | [ENGLISH_CONTEXT.md](ENGLISH_CONTEXT.md) | English (SEA/Global) |

**Proposals (Thai convert):** use [TRANSLATION_PRINCIPLES.md](TRANSLATION_PRINCIPLES.md) — formal proposal register, smoothness rules, and English-backup / `th/` layout. Do not use SME web tone as the default for government packs.
