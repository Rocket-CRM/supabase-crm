# Thailand Context — Thai (th-TH)

> **Purpose:** Market-specific localization context for Thai. The vocabulary table below is the canonical Thai for Rocket product terms.
> **Inherits:** [TRANSLATION_PHILOSOPHY.md](TRANSLATION_PHILOSOPHY.md) — localize-don't-translate, English term policy, complexity spectrum, structure fidelity.
> **Craft rules:** [TRANSLATION_PRINCIPLES.md](TRANSLATION_PRINCIPLES.md) § Thai prose smoothness applies to **all** Thai surfaces (numerals, calques, filler, no `การ <english-verb>`) — even though that file's *register* is proposal-only.

**Provenance:** §2 and §3 were derived from the 2026-08-16 localize pass on the canonical views (pricing sheet + features summary). Every "wrong" column entry is a real defect that shipped, not a hypothetical.

---

## 1. Register — pick before writing

Thai has no single house voice. Choose by surface, then stay in it.

| Surface | Register | Source |
|---|---|---|
| Canonical views, sales sheets, web, decks | **Thai B2B/SME operator** — direct, spoken, no corporate padding | `TRANSLATION_PHILOSOPHY.md` § Tone Calibration |
| Government / e-bidding proposals | **Formal agency Thai** | `TRANSLATION_PRINCIPLES.md` § Register |

The commercial default is the operator register. The test from the philosophy doc: *would a sharp Thai marketer say this to an operator, out loud?* If a line is clever on paper but awkward spoken, rewrite it.

**Do not** apply proposal formality to a pricing sheet. `สามารถ…ได้` padding on every bullet is the tell.

---

## 2. Feature vocabulary — canonical Thai

Use these exactly. They are the terms Thai loyalty operators actually use.

### Loyalty mechanics

| English | ✅ Thai | ❌ Do not use | Note |
|---|---|---|---|
| earn (points), verb | สะสมคะแนน / ได้รับคะแนน | — | `ได้คะแนน` is fine mid-sentence as a verb (`แล้วได้คะแนนหลังตรวจ`), never as a noun compound |
| earn rate | อัตราสะสมคะแนน | อัตราได้คะแนน | |
| earn channels | ช่องทางสะสมคะแนน | ช่องทางได้คะแนน | |
| redeem | แลก / แลกของรางวัล | | |
| reward | ของรางวัล | | |
| burn / points-to-discount | ใช้คะแนนเป็นส่วนลด | | `Burn` may stay as a bold keyword (Earn/Burn is market-standard in Thai loyalty B2B); the description must be Thai |
| points balance | ยอดคะแนน | | |
| points expiry | วันหมดอายุของคะแนน | | |
| double points | คะแนน 2 เท่า | ดับเบิลพอยท์ | Numeral, per smoothness rule |
| tier | Tier | ทีเออร์ | Keep English |
| tier ladder | ชุด Tier / ระดับสมาชิก | **บันได** | `บันได` is a physical ladder |
| tier maintenance | การรักษาระดับ | รักษาสิทธิ์ | It is the *tier* being kept, not a privilege |
| tier upgrade | การเลื่อนขั้น | | |
| evaluation window | รอบประเมิน | ช่วงเวลาประเมิน | |
| lifecycle | วงจรสมาชิก | วงจรชีวิต | `วงจรชีวิต` is biological |
| mission | ภารกิจ / Missions | | |
| streak | สะสมวันต่อเนื่อง | | |
| lucky draw entry | สิทธิ์ลุ้นรางวัล | | Entry is bought with points/tickets — **not** `สกุลเงิน` (fiat) |
| quota | โควตา | โควต้า | Spelling: no ไม้โท |
| promo code | โค้ดโปรโมชัน / โค้ดส่วนลด | โปรโมโค้ด | |
| transactions (in reports) | รายการเคลื่อนไหว | ธุรกรรม | `ธุรกรรม` skews financial/legal |
| receipt | ใบเสร็จ | | |

### Members and targeting

| English | ✅ Thai | ❌ Do not use |
|---|---|---|
| member | สมาชิก | |
| member types | ประเภทสมาชิก | |
| persona | persona | เพอร์โซนา |
| tag | แท็ก | |
| segment | Segment / แบ่งกลุ่มสมาชิก | |
| targeting | จัดกลุ่มเป้าหมาย | **กำหนดเป้า** |
| eligibility | สิทธิ์ | |
| student | นักเรียน/นักศึกษา | นักเรียน alone |

### Platform, commercial, and service

| English | ✅ Thai | ❌ Do not use | Note |
|---|---|---|---|
| source of truth | ต้นทางข้อมูล | **แหล่งความจริง** | Pure calque; reads as philosophy |
| ledger | เก็บและคิดคะแนน | สมุดบัญชี | Describe the job, don't translate the metaphor |
| per seat | ต่อผู้ใช้งาน | **ต่อที่นั่ง** | `ที่นั่ง` is a cinema seat |
| per resolved case | ต่อเคสที่ปิดสำเร็จ | ต่อเคสที่ปิดได้ | |
| per month | ต่อเดือน | | |
| admin backend | หลังบ้าน | | Market-standard Thai B2B |
| customer record | ข้อมูลลูกค้า / ประวัติลูกค้า | **บันทึกลูกค้า** | |
| agent (human, CS) | เจ้าหน้าที่ | เอเจนต์ | Non-technical readers |
| agent (AI) | agent | | Keep English — distinguishes it from the human |
| escalation | การส่งต่อ | | |
| containment | สัดส่วนเคสที่ปิดได้โดยไม่ต้องส่งต่อคน | | No short Thai equivalent; explain it |
| customer service | บริการลูกค้า | **ลูกค้าสัมพันธ์** | That means customer *relations* |
| trigger | ทริกเกอร์ | ตัวจุดชนวน | |
| privacy consent | การขอความยินยอมตาม PDPA | | Keep PDPA in English |

### Counting and classifiers

| Counting | ✅ | ❌ |
|---|---|---|
| reports | รายงานกว่า 30 **แบบ** | 30 **ฉบับ** (`ฉบับ` = paper copies) |
| messages | ข้อความละ / กี่ข้อความ | |
| coupons | ใบ | |

---

## 3. Recurring failure modes

These four produced almost every bad line in the 2026-08 pass.

1. **Calque an English idiom.** `source of truth`, `ladder`, `seat`, `record`, `drop`. Translate the *job*, not the image.
2. **Noun-stack a verb phrase.** English compresses ("earn rate", "shared quotas"); Thai needs a verb. `อัตราได้คะแนน` → `อัตราสะสมคะแนน`; `โควต้าร่วมแบบละเอียด` → `ตั้งโควตาร่วมกันหลายรางวัลได้ละเอียด`.
3. **Mismatched list grammar.** English lists tolerate mixed parts of speech; Thai does not. `วันเกิด ตอนสมัคร วันครบรอบ` mixes a noun, a time phrase, and a noun — make every item the same kind.
4. **Translate a term of art literally.** "currency-entry lucky draw" became `เข้าด้วยสกุลเงิน` (fiat money), which describes a product we do not sell. When a term is jargon in English, ask what it *does* before writing Thai.

---

## 4. Structure rules for Thai canonical views

- **Module and feature-group headings stay English** (`rocket-sales/commercial/REFERENCE.md` § Locales). A Thai gloss in parentheses is allowed only when it adds meaning.
- **Drop the gloss when it is a transliteration** — `Loyalty (ลอยัลตี้)`, `Omnichannel (ออมนิชาแนล)` teach the reader nothing. Gloss `Loyalty` as `(ระบบสมาชิกและสะสมคะแนน)` or not at all.
- **The heading gloss and the table-row label must match**, or the HTML export shows two different names for one group.
- **Keep EN/TH structurally identical** — same `billable_unit_key` / `feature_group_key`, same row count. The exporter is locale-agnostic; verify with the row counts it prints.
- Thai runs longer than English. Per structure fidelity, **shorten the idea** rather than let a bullet wrap to three lines.

---

## 5. Not yet established

These sections exist in the per-market template (`TRANSLATION_PHILOSOPHY.md` § Per-Market Context Docs) but have no grounded Rocket content yet. Do not invent them — add them from real work.

| Section | Status | Interim source |
|---|---|---|
| Market context (who buys, search behavior) | Not written | — |
| UI translation patterns | Not written | Member-app strings, when a UI localize pass happens |
| CTA patterns | Not written | `WEB_PAGE_COPY_PRINCIPLES.md` Part 1 § Thai/English voice |
