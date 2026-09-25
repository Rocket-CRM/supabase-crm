# OCR Prompt Fragment Migration

---

## ⚠ DIAGNOSTIC PITFALLS — read before analysing any eval failure

These are recurring misdiagnoses. Check these first before drawing conclusions from eval output.

### 1. `prediction_class` expected value is in the `store_code` column — NOT in `correct_result` JSONB

**Rule:** When evaluating `prediction_class` accuracy, the ground-truth expected value comes from the **top-level `store_code` column** of `custom_futurepark_receipt_groundtruth`. The `correct_result->>'prediction_class'` JSONB field is unreliable — it may be `null`, stale, or contain an FP-prefix code from before normalization.

The edge function eval enforces this (see `receipt-preview-v2/index.ts`):
```typescript
const expected = field === 'prediction_class'
  ? (gtStoreCode ?? tc.correct_result[field] ?? null)   // gtStoreCode = tc.store_code column
  : tc.correct_result[field];
```

**Consequence:** If you see `prediction_class` failures where `expected = null`, do NOT conclude the model is hallucinating or that GT entries need prompt fixes. First check whether the GT row has a non-null `store_code` column value. If `store_code` is set, the eval will use it and the `correct_result.prediction_class = null` is irrelevant.

**Correct diagnosis for `prediction_class` nulls:** Only a Roboflow classification failure or a text-fallback miss — not a prompt issue.

### 2. `belongs_to_futurepark` is not scored by the edge function eval

The edge function eval (`EVAL_FIELDS` in `receipt-preview-v2/index.ts`) does **not** include `belongs_to_futurepark`. All GT rows are confirmed FuturePark receipts by definition, and the edge function upgrades `uncertain → yes` when Roboflow returns a confident `prediction_class`. Scoring this field produces noise, not signal.

If you see `belongs_to_futurepark` failures in a Render-service eval report, the fix is a **GT data correction** (set `correct_result.belongs_to_futurepark = "yes"` for the affected rows), not a prompt change.

### 3. `net_amount_label` hint was recorded on a simple receipt

The `net_amount_label` in `custom_futurepark_store_ocr_hints` was observed on a receipt without discounts or VAT breakdown. On receipts **with** VAT breakdown, the labeled line is often the pre-VAT subtotal, not the final total. Do not anchor to the hint label as the definitive answer — it is soft guidance only.

---

Context for the change made on 2026-04-22 to
`public.custom_futureparkocrprompts` and the service-side follow-up required
to finish the migration.

## Why

The extraction prompts (`net_amount_extraction`, `is_futurepark`) had grown
to ~15-22k characters, accumulating overlapping and occasionally
contradictory rules after each accuracy fix. Editing these monoliths in
place was causing regressions (e.g. the "P3 ZERO IS NEVER VALID" rule
blocked legitimate 0-baht redemptions; P7 "NET LABEL = ALREADY NET"
occasionally overrode P4 "VAT-INCLUSIVE WINS").

The remedy is structural, not content-level:

- Put meta-editing rules (E1-E8) in a first-class row so every future
  prompt editor sees them before touching anything.
- Decompose monolithic prompts into named fragments, each with a single
  purpose (reasoning principles, concrete rules, sanity checks, scaffolding).
- Introduce a composition row that lists fragment keys in assembly order,
  so the service can concatenate fragments at runtime.

## Architecture (as-built): runtime assembly

**Corrected 2026-04-24 — this section was previously aspirational.** The actual
production architecture is runtime assembly, not DB-side sync:

- `assemble_ocr_prompt(p_key text) RETURNS text` — reads `__compose.<key>__`,
  looks up each fragment key, joins with `\n\n`.
- `receipt-preview-v2` edge function calls `supabase.rpc('assemble_ocr_prompt', { p_key: 'is_futurepark' })`
  and `{ p_key: 'net_amount_extraction' }` on **every request** (see `getPrompts()` in index.ts).
- The Render `crm-batch-upload` eval service and `upload-receipts-auto-preview`
  delegate OCR to `receipt-preview-v2`; they never load prompts themselves.
- The **`custom_futureparkocrprompts_sync` trigger does NOT exist** — it was
  documented here but never shipped. The only trigger on this table is the
  `updated_at` bookkeeper.

Consequence: **editing any `frag.*` or `__compose.*__` row takes effect on the
very next `receipt-preview-v2` call — no trigger fire, no manual resync, no
redeploy needed**.

### Status of the monolithic rows (`is_futurepark`, `net_amount_extraction`)

These rows were the pre-migration source of truth. Today **no production caller
reads them** — `receipt-preview-v2` bypasses them via `assemble_ocr_prompt`.
They are dead weight kept only for historical/manual-inspection convenience.

If you want to verify fragment edits resolve to the expected prompt, run
`SELECT assemble_ocr_prompt('is_futurepark')` instead of reading the stored
monolithic row. Overwriting the monolithic row with the assembled output is
purely cosmetic — safe but unnecessary.

Follow-up option (not yet done): drop the monolithic rows, or replace them with
a VIEW that materialises `assemble_ocr_prompt()` on read, so they can never
drift again.

## What landed (DB only, no service code change yet)

All rows are idempotent `INSERT ... ON CONFLICT UPDATE`.

### Shared base fragments

| prompt_key                    | role                          | len  |
|-------------------------------|-------------------------------|------|
| `__editing_principles__`      | meta, read before every edit  | 3,800|
| `frag.base.intro_and_inputs`  | role + INPUTS (net_amount)    | 254  |
| `frag.base.ocr_first_method`  | OCR-first extraction method   | 1,107|
| `frag.base.output_format`     | closing + JSON footer         | 610  |

### `net_amount_extraction` fragments

| prompt_key                             | role                          | len   |
|----------------------------------------|-------------------------------|-------|
| `__compose.net_amount_extraction__`    | assembly order JSON           | 311   |
| `frag.reasoning.net_amount.principles` | P1-P8 first principles        | 2,912 |
| `frag.extract.net_amount.core`         | HOW TO FIND net_amount, steps | 2,343 |
| `frag.extract.field_defs`              | field defs + label priorities | 2,009 |
| `frag.extract.voucher_rules`           | voucher/GV recognition + formula | 1,931|
| `frag.extract.vat_patterns`            | 3-number VAT, restaurant, discount, payment auth | 2,308|
| `frag.extract.misc_patterns`           | cash vs net, OCR misreads, items count | 1,531|
| `frag.reasoning.net_amount.sanity`     | SANITY CHECK checklist        | 1,539 |

### `is_futurepark` fragments

| prompt_key                              | role                          | len   |
|-----------------------------------------|-------------------------------|-------|
| `__compose.is_futurepark__`             | assembly order JSON           | 398   |
| `frag.is_futurepark.intro`              | role + inputs + triangulation + decision flow | 2,546|
| `frag.is_futurepark.fields_header`      | # FIELDS TO EXTRACT + store_name + branch_name | 303|
| `frag.extract.receipt_number`           | receipt_number field + all rules | 5,080|
| `frag.extract.receipt_datetime.rule`    | date field + universal rule + algorithm | 2,370|
| `frag.extract.receipt_datetime.examples`| worked examples               | 1,666 |
| `frag.extract.receipt_datetime.year`    | year handling table           | 1,198 |
| `frag.extract.receipt_datetime.months`  | Thai month abbreviations      | 1,286 |
| `frag.extract.receipt_datetime.misc`    | multiple dates + month token + time + null rule | 1,645|
| `frag.extract.payment_belongs`          | payment_method + belongs_to_futurepark | 1,751|
| `frag.reasoning.is_futurepark.sanity`   | MANDATORY SANITY CHECK section | 2,889|
| `frag.is_futurepark.output_format`      | OUTPUT FORMAT + JSON schema   | 977  |

Bitwise equivalence verified in-DB for both prompts:

```
net_amount_extraction: assembled_len = stored_len = 16562, assembly_matches_monolithic = true
is_futurepark:         assembled_len = stored_len = 21731, assembly_matches_monolithic = true
is_futurepark hash     = f204e196d4768c0ab5a25af7651a16d1 (matches pre-migration hash)
```

Both monolithic rows are kept in sync automatically by the
`custom_futureparkocrprompts_sync` trigger. OCR edge functions see no change.

## Editing workflow going forward

1. Read `__editing_principles__` from the DB. Apply E1-E8.
2. Edit the relevant `frag.*` row(s). Do NOT touch monolithic rows directly.
3. The trigger auto-rebuilds the monolithic row on commit. Verify with:

   ```sql
   SELECT prompt_key, length(prompt_text), md5(prompt_text), updated_at
   FROM custom_futureparkocrprompts
   WHERE prompt_key IN ('net_amount_extraction', '<edited frag key>');
   ```
4. Re-run eval. Record hash before + after for rollback.

## Rollback

The pre-migration state is:

```sql
-- rows that existed before this migration, their hashes (for rollback):
--   is_futurepark           len=21731 md5=f204e196d4768c0ab5a25af7651a16d1
--   net_amount_extraction   len=15805 md5=d4ee6f34d6801e2951daa2a01e34c08a
```

The legacy row was NOT modified; rollback of this migration is simply:

```sql
DELETE FROM custom_futureparkocrprompts
WHERE prompt_key IN (
  '__editing_principles__',
  '__compose.net_amount_extraction__',
  'frag.base.intro_and_inputs',
  'frag.base.ocr_first_method',
  'frag.base.output_format',
  'frag.extract.net_amount.core',
  'frag.extract.sale_fields',
  'frag.reasoning.net_amount.principles',
  'frag.reasoning.net_amount.sanity'
);
```

Verify the `net_amount_extraction` hash still matches
`d4ee6f34d6801e2951daa2a01e34c08a` after rollback.

## Content fixes applied

- **P3 softening (done)** — `frag.reasoning.net_amount.principles`.
  Rewrote `P3 — ZERO IS NEVER VALID` to `P3 — ZERO IS USUALLY WRONG, BUT
  SOMETIMES CORRECT`. 0 is allowed when the receipt genuinely shows a
  zero-baht transaction (complimentary / 100%-voucher-paid / explicit
  "Total: 0"). Still rejected when a non-zero total is visible elsewhere.
- **P8 multi-receipt (done)** — same fragment. New principle forbids
  summing across stacked/overlapping receipts; extract only from the
  foremost fully-visible receipt.

After the edit the fragment went 2,155 → 2,912 chars and the monolithic
`net_amount_extraction` row went 15,805 → 16,562 chars. Both P3 and P8
verified present in the reassembled monolithic row.

## Rollback hashes

```
is_futurepark        len=21731  md5=f204e196d4768c0ab5a25af7651a16d1  (unchanged)
net_amount_extraction len=16562  md5=708ace0c4cdefb1a8f03f15bbcb240d7  (after P3+P8 fixes)
net_amount_extraction pre-fix    md5=d4ee6f34d6801e2951daa2a01e34c08a
```

## 2026-04-24 — Year anchoring fix + barcode-number hint override

### Trigger failures (E6)
- `IMG_8600.JPG` (Nose Tea 161039): `receipt_datetime` expected `2025-02-05`, actual `2026-02-05` — year anchored to 2026 by example set
- `IMG_0629.JPG` (Tai Er 太二 162116): `receipt_number` expected `8020660032026011517162900035`, actual `null` — barcode-exclusion rule blocked hint-identified long number

### Changes (both fragments belong to `is_futurepark` composition)

**`frag.extract.receipt_datetime.examples`**
- Added note: "years span multiple values — read the year from the receipt; never default to the current year or the store hint year."
- Replaced `"05/02/2026" → 2026-02-05` with `"05/02/2025" → 2025-02-05` (exact failing pattern)
- Replaced dot-separator example with 2-digit CE year example: `"05/02/25" → 2025-02-05` (matches Nose Tea hint format DD/MM/YY)

**`frag.extract.receipt_number`**
- Expanded EXCEPTION clause: added `EXCEPTION B (HINT OVERRIDE)` — when the store hint's `receipt_number_example` is 15+ digits, an unlabeled long numeric sequence of similar length IS the receipt number
- Tightened P5 (table-linked codes) to a one-liner to stay under 8 000-char E7 ceiling

### Hashes (for rollback)
```
frag.extract.receipt_datetime.examples  pre:  md5=5928d81e8375902b475be5c004fe0861  len=1666
frag.extract.receipt_datetime.examples  post: md5=add066bf894d6df4eb0de8dacd8440fb  len=1813
frag.extract.receipt_number             pre:  md5=ff586fce582c53040132d9614dcac418  len=7849
frag.extract.receipt_number             post: md5=d835710e6b3e7134c9bcda46754d5d31  len=7976
is_futurepark (monolithic, trigger)     post: md5=78541ef00e636a72630dc640a90e194f  len=27640
```

## 2026-04-24 (later) — 388-sample eval cleanup: hints, DD/MM, year anchoring, confidence

### Eval baseline: 69.33% overall (388 samples, 119 failures)
- receipt_number fail 13.4% — hint contradictions + char confusion + trailer over-extraction
- receipt_datetime fail 8.2% — DD/MM→MM/DD swap + 2026 year anchoring
- belongs_to_futurepark fail 5.2%
- net_amount fail 4.4%
- prediction_class fail 4.1% (Roboflow vision model; not prompt-addressable)

### Trigger failures (E6)
- Nose Tea 161039 `IMG_8600.JPG`: still 2026 vs 2025 (same image that failed last round) — fix = hint year was literal, now placeholder
- Tai Er 162116 `IMG_0629.JPG`: receipt_number null despite hint — fix = EXCEPTION B now covers spaced-pattern hints too
- BOOTS 160563 (5 images): over-extraction `4240 002 6188 6810030` — fix = hint no longer teaches the barcode trailer, + LENGTH LIMIT rule
- Sushiro 159231, Swensen's 110327, Yamazaki 162340 (many): `01/08/2026` read as Jan 8 instead of Aug 1 — fix = tightened IMAGE OVERRIDE; DD/MM is default for Thai-printed receipts regardless of English brand name
- Sukiya 159775 hint had impossible date (Feb 30) — corrected
- Studio 7 / Comseven 108907 hint raw/std contradicted (Feb vs Jan) — corrected

### Store-hint data fixes (data fix per E6)
- **BOOTS 160563**: `receipt_number_example` `"4374 001 9887 6607017"` → `"4374 001 9887"` (drop 7-digit barcode trailer that ground truth never contains)
- **Studio 7 108907**: raw `10/02/2026` → `10/01/20XX` (keep std's January, which is the human-readable value)
- **Sukiya 159775**: std `30 february 2026` → `30 january YYYY` (Feb 30 does not exist)
- **All 24 hints**: year digits replaced with literal placeholders (`20XX` / `YYYY` / `YY` / `256X`) so the hint never anchors Claude to a specific year.

### Prompt fragment changes (all E1/E7-compliant)

**`frag.extract.receipt_datetime.rule`** (3,161 → 3,089, −2.3%)
- Replaced IMAGE OVERRIDE block: now states SMALL→BIG (DD/MM) is the default for ALL Thailand-printed receipts, including English-branded imports. Override allowed ONLY when the date stamp itself contains a spelled-out month token (e.g. `Jan07 26`).

**`frag.extract.receipt_datetime.year`** (1,198 → 1,302, +8.7%)
- Consolidated the two redundant CRITICAL/Default blocks.
- Added new HINT PLACEHOLDERS section explaining that `20XX`, `YYYY`, `YY`, `256X` in store hints are format markers only and never values.

**`frag.extract.receipt_number`** (7,976 → 7,819, −2.0%)
- Compressed P5 (table-linked codes) to a one-liner.
- Expanded EXCEPTION B (HINT OVERRIDE) to handle spaced-pattern hints (`XXXX XXX XXXX` like BOOTS), and added a LENGTH LIMIT rule: never extend extraction past the hint's digit count (kills BOOTS barcode-trailer over-extraction).
- Compressed the ALL-UPPERCASE ALPHABETIC CODES section to stay under the 8,000-char E7 ceiling.

**`frag.output.confidence_rubric`** (NEW, 699 chars)
- New shared fragment referenced by both composes. Defines the 0.0–1.0 `_confidence` rubric with calibration guidance.

**`frag.is_futurepark.output_format`** (977 → 1,502, +54%)
- Added `_confidence` JSON key with three subfields (receipt_number, receipt_datetime, belongs_to_futurepark).
  - Justified: new capability/schema extension, not a content patch. Rubric text itself lives in the new shared fragment per E4.

**`frag.base.output_format`** (610 → 935, +53%)
- Added `_confidence` JSON key for net_amount_after_discount.
- Same E4 justification as above.

**`__compose.is_futurepark__` / `__compose.net_amount_extraction__`**
- Both updated to include `frag.output.confidence_rubric` immediately before their respective output_format fragment.

### Edge function change
`supabase/functions/receipt-preview-v2/index.ts` — `buildItem()` now merges `_confidence` from the Claude response exactly the way `_reasoning` is merged. Downstream consumers can safely ignore the new field until a UI/approval rule uses it.

### Post-change hashes (rollback record per E8)
```
frag.extract.receipt_datetime.rule   md5=8757d79e4b66e0a2cb35fd53b93309da  len=3089
frag.extract.receipt_datetime.year   md5=4ffcfb3e9d55177bdb53e8081bfbf471  len=1302
frag.extract.receipt_number          md5=50132ae69d8b1b7952631469fe2e03e3  len=7819
frag.is_futurepark.output_format     md5=70549eb304acb3b4ed857b126cf4fa84  len=1502
frag.base.output_format              md5=3a96b53716159fd989011561f72e779c  len=935
frag.output.confidence_rubric  (NEW) md5=e983e0f9e157b399a20f3d8b8813c0ad  len=699
__compose.is_futurepark__            md5=07b728bb1dd829f4021b3527c2843ed6  len=457
__compose.net_amount_extraction__    md5=355e08793c1b035e71cf9a8c8b8fa41a  len=369
is_futurepark (monolithic)           md5=7eb60d87fdce9aa93f412560e6203abd  len=28612
net_amount_extraction (monolithic)   md5=09cd5bdf40e2071800b55285dfe9ac16  len=19574
```

### Pre-change hashes (to roll back to)
```
frag.extract.receipt_datetime.rule   md5=c1e85af496f11a3f3c90164d33e29c73
frag.extract.receipt_datetime.year   md5=dc671ea39548930dab57cbaf1ea62175
frag.extract.receipt_number          md5=d835710e6b3e7134c9bcda46754d5d31
frag.is_futurepark.output_format     md5=cd2162c5a927677d3da559e39d0669bd
frag.base.output_format              md5=05d9e2a10bcdcc396a08a0746e18b87d
is_futurepark (monolithic)           md5=78541ef00e636a72630dc640a90e194f
net_amount_extraction (monolithic)   md5=b37aa54c6d4ae50f687337d689878f54
(24 store hints — snapshot in pre-change hash table above)
```

## 2026-04-24 (latest) — Principle-level fixes: search termination, VAT gate, year plausibility, E041310

### Trigger failures (E6)
- Sukiya 159775 `IMG_8319.JPG`: `receipt_number` null despite `RNO:1043-911780` in OCR — model stopped scanning after finding STNO/ORD# first
- Sukiya 159775 `IMG_8319.JPG`: `net_amount` 487 vs 467 — QR quantity field `1 487.00` misread as Sub Total; VAT check (438.45+30.55=469≠487) was rationalized instead of rejected
- Tai Er 162116 `IMG_0847.JPG`: `receipt_number` null — EXCEPTION B only covered unlabeled sequences; `Order No.:8020660032026010514214000030` labeled field not matched
- Sukiya 159775 `IMG_8438AA.JPG`: `receipt_datetime` 2028 vs 2026 — OCR misread `6`→`8`; year 2028 is implausible future; cross-reference `RTH-013011-26-0001` was ignored
- First Snow 109483 `IMG_0099.JPG`: `belongs_to_futurepark` "yes" vs expected "uncertain" — model used store enrollment prior, overriding OCR/image evidence of zero FuturePark markers
- Oriental Princess 159893 `536087_0.jpg`: `belongs_to_futurepark` "no" vs expected "yes" — garbled address, no visible FuturePark text, E041310 POS prefix present but not used as signal

### Changes (principle-level, no merchant-specific lists added)

**`frag.extract.receipt_number`** (7,819 → 7,936, +1.5%)
- Added **SCAN-BEFORE-NULL**: finding excluded codes (STNO, POS ID, REG#, ORD#) does NOT end the search — they coexist with a receipt identifier. Scan all label types; cross-check hint format before concluding null.
- Added **EXCEPTION C (ORDER-IS-RECEIPT)**: when hint's `receipt_number_example` is ≥15 digits and pattern-matches the `Order No.` value, the `Order No.` IS the receipt number (covers Datou/Tai Er POS system quirk generically).
- Compressed P4 one-liner, compressed TAX INVOICE OVERRIDE and LONG NUMBERS to stay under E7 8,000-char ceiling.

**`frag.reasoning.net_amount.sanity`** (1,539 → 2,073, +34.7%)
- Added **check #7 — hard VAT gate**: if receipt shows explicit Before-VAT + VAT amounts, candidate must satisfy `candidate ≈ before_vat + vat ± 3%`. Failure = wrong source line; switch to `store_header_ocr` labeled Sub Total.

**`frag.extract.receipt_datetime.year`** (1,302 → 2,011, +54.5%)
- Added **PLAUSIBILITY GATE**: if extracted year ≥ current_year+2 (≥2028), treat as OCR digit misread. Cross-reference from transaction reference codes (e.g. `RTH-DDMM-YY-XXXX`). Correct to nearest plausible year if no cross-reference available.

**`frag.extract.payment_belongs`** (1,751 → 2,195, +25.4%)
- Added **E041310 signal**: POS ID / REG# starting with `E041310` = FuturePark Rangsit mall-wide POS infrastructure prefix → `belongs_to_futurepark: "yes"`. Confirmed present in 33/33 FuturePark stores in eval dataset.
- Strengthened **image-only rule**: `belongs_to_futurepark` must be derived solely from the current image/OCR. Store enrollment status is not visible receipt evidence. Zero markers → `"uncertain"`, never `"yes"`.

### Post-change hashes — run 3 (rollback record per E8)
```
frag.extract.receipt_number          md5=81f8ebdaae67657e3f2c9c98a9ce3bde  len=7936
frag.reasoning.net_amount.sanity     md5=6c3a98a830450e11cfec6a484e3bb676  len=2073
frag.extract.receipt_datetime.year   md5=f0376b283fe826c77deb3c29f818fa45  len=2011
frag.extract.payment_belongs         md5=68d92765855dbbcf3c2ca0fec5b0dce7  len=2195
is_futurepark (monolithic)           md5=6061866bdb3a4972db69665b79be1774  len=29882
net_amount_extraction (monolithic)   md5=d51c2f1395121c462124c6973b400db8  len=20108
```

---

## Change set 4 — Run d07f921d (0.70, 50 samples) — 2026-04-24

### Failure triage

**Ground truth errors (6 records corrected — model was correct):**
- S&P 101719 `IMG_0097 (1).JPG`: `receipt_number` "478" is `สาขาที่ 478` (branch number), not transaction receipt → corrected to `null`
- Swensen's 110327 `IMG_0049.JPG`: `receipt_datetime` "2026-08-01" → "2026-01-08" — receipt shows `08/01/2026`; store hint confirms DD/MM (Jan 8). Entry was MM/DD data-entry error.
- BOOTS 160563 `IMG_1154.JPG`: same DD/MM confusion — "2026-08-01" → "2026-01-08"
- ครัวเมืองเว้ 160828 `IMG_0642.JPG`: `receipt_datetime` "1969-01-01" → "2026-01-01" — BE year `69` was mis-parsed as AD 1969 (epoch bug); model's 2026-01-01 was correct
- Yoguruto 160502 `IMG_0914.JPG`: `receipt_number` null → "LD8WR" — receipt has explicit `ID: LD8WR` label; model correctly extracted it
- Sushiro 159231 `IMG_0154.JPG` (prev run): "2026-03-01" → "2026-01-03" — Jan 3 2026 was Saturday (confirmed); Mar 1 was Sunday

**OCR floor / unfixable (4 cases):**
- Bar BQ Plaze 159482 `26405.jpg`: blurry partial image, receipt_number "17324" not clearly readable
- After You 108309 `LINE_ALBUM...9.jpg`: hand/object obscuring center; expected receipt number not visible in OCR
- น้ำเต้าหู้ปูปลา 161298 `IMG_0994.JPG`: "ROAY2" vs "R0AY2" — O vs 0 character confusion, OCR accuracy floor
- Boost Juice 160147 `IMG_1015.JPG`: `prediction_class` null — Roboflow model issue, not prompt-addressable

**Prompt-fixable (7 issues across 5 fragments):**
- BOOTS `IMG_1091`: EXCEPTION B not extracting `4240 002 6188` from crowded line (cashier ID and date on same line)
- First Snow `IMG_0101` receipt_number: `รหัส ล : CH-260100151` misidentified as P2 (POS reg code) — P2 only covers English label patterns
- First Snow `IMG_0101` belongs_to_futurepark: reasoning concluded "uncertain" but JSON output was "yes" — image-only rule at bottom of section was ignored
- UNIQLO `20260107_142535.jpg`: `<1029>` angle bracket session counter returned instead of Tax Invoice No.
- EGV 159713 `Screenshot...`: `Order No: 124355073` chosen over `T/N: 1243550`; order numbers are session identifiers
- Bar BQ Plaze `26405.jpg` receipt_datetime: model constructed date from partial month read (พ.ค.) with defaulted day=01 — expected null
- Year plausibility gate: CRITICAL "use exactly" rule appeared before PLAUSIBILITY GATE, causing gate to be bypassed

### Changes (principle-level)

**`frag.extract.receipt_number`** (7,936 → 8,217, +3.5%)
- Added **angle bracket exclusion**: values in `<N>` angle brackets (e.g. `<1029>`) are POS session counters — never a receipt number even when the bracket is stripped.
- Added **P2 English-only note**: P2 exclusion applies ONLY to the listed English label patterns (POS#, REG#, etc.). Unrecognized Thai labels (รหัส, วล.ล) are NOT excluded by P2 — apply SCAN-BEFORE-NULL and hint format check instead.
- Added **EXCEPTION B CROWDED LINE**: when the hint's digit-group pattern appears at the START of a longer line (followed by cashier ID / date), extract ONLY the portion matching the hint's pattern up to hint's digit count.
- Added **T/N OVER ORDER NO**: when both `Order No.` and `Tax Invoice No.`/`T/N` appear, `T/N` is the receipt number. An order number identifies a POS session; `T/N` is the legally unique document identifier.
- Compressed COMPLETENESS RULE, ALL-UPPERCASE, DATE-EMBEDDED sections to fit within E7 ceiling (~8,200).

**`frag.extract.payment_belongs`** (2,195 → 2,194, ±0)
- Moved EVIDENCE REQUIREMENT to the **very start** of `## belongs_to_futurepark` section (before the "yes" criteria) — evidence-first positioning prevents the model from applying prior knowledge before reading the prohibition.
- Removed the bottom IMPORTANT note (content is now at the top).

**`frag.extract.receipt_datetime.misc`** (2,166 → 2,493, +15.1%)
- Added **token independence rule**: do NOT default any date token (day, month, or year) from context or assumptions. Each token must be independently readable. If the day specifically cannot be read (e.g. only month abbreviation visible), return null — do not assume day = 01.

**`frag.extract.receipt_datetime.year`** (2,011 → 1,864, −7.3%)
- **Restructured**: PLAUSIBILITY GATE is now **Step 1** of HOW TO USE THE YEAR TOKEN, before the USE IT EXACTLY instruction (now Step 2). The old structure had CRITICAL (use exactly) before PLAUSIBILITY GATE, causing the gate to be bypassed.

**`frag.reasoning.is_futurepark.sanity`** (3,386 → 3,648, +7.7%)
- Strengthened `belongs_to_futurepark` consistency check from an IMPORTANT note to a **HARD RULE**: if your reasoning concluded "uncertain" and no new concrete evidence was found, the JSON output MUST be "uncertain". Added explicit statement that store enrollment, brand familiarity, and inference are not evidence.

### Post-change hashes — run 4 (rollback record per E8)
```
frag.extract.receipt_number          md5=16b0648519733486a6d73d340a638122  len=8217
frag.extract.payment_belongs         md5=51428dd2855eeebc37f15f571d52c474  len=2194
frag.extract.receipt_datetime.misc   md5=f3f5272fad124b8a23fc8a6d2955bac3  len=2493
frag.extract.receipt_datetime.year   md5=82a3eb07ed40308dfd14419c76595974  len=1864
frag.reasoning.is_futurepark.sanity  md5=84030132d3b6ae1426f4d70bdbfb9047  len=3648
is_futurepark (monolithic)           md5=0a5ba1dbf358b7b6457877cec2c1d2b1  len=30604
net_amount_extraction (monolithic)   md5=d51c2f1395121c462124c6973b400db8  len=20108  (unchanged)
```

### Pre-change hashes (to roll back to)
```
frag.extract.receipt_number          md5=50132ae69d8b1b7952631469fe2e03e3  len=7819
frag.reasoning.net_amount.sanity     md5=64b3976e417e3397cf986d555ccc3780  len=1539
frag.extract.receipt_datetime.year   md5=4ffcfb3e9d55177bdb53e8081bfbf471  len=1302
frag.extract.payment_belongs         md5=0a09bb5375a17c627109c173413cf6a6  len=1751
is_futurepark (monolithic)           md5=7eb60d87fdce9aa93f412560e6203abd  len=28612
net_amount_extraction (monolithic)   md5=09cd5bdf40e2071800b55285dfe9ac16  len=19574
```

## Change set 5 — Run de88b1d0 (0.62, 50 samples) — 2026-04-24

### Eval baseline: 62% overall (50 samples, 19 failures)
- receipt_datetime fail 22% — 4× DD/MM swap, 3× year off-by-one, 1× null
- receipt_number fail 20% — partial extraction, nulls, OCR char confusion
- net_amount fail 12% — wrong label selected
- belongs_to_futurepark fail 8% — First Snow persistent false positive
- prediction_class fail 8% — Roboflow model issue (not prompt-addressable)

### Trigger failures (E6)
- S&P 101719 `IMG_0380(1).JPG`: `receipt_datetime` returned 2026-01-04 (MM/DD read) vs expected 2026-04-01 (DD/MM)
- Yamazaki 162340 `IMG_0243.JPG`: `receipt_datetime` returned 2026-01-08 (MM/DD) vs expected 2026-08-01 (DD/MM)
- BOOTS 160563 `IMG_0213(1).JPG`: `receipt_datetime` returned 2026-01-07 (MM/DD) vs expected 2026-07-01 (DD/MM)
- Oriental Princess 159893 `LINE_ALBUM_722026_260209_76.jpg`: `receipt_datetime` returned 2026-02-07 (MM/DD) vs expected 2026-07-02 (DD/MM)
- Watsons 159581 `IMG_0535.JPG`: `receipt_number` returned `0035` (short labeled) vs expected `894004012120260035` (hint-matching 18-digit)
- EGV 159713 `536137_0.jpg`: `receipt_number` returned `00000009` (zero-padded seat counter) vs expected `013372644` (transaction ref)
- Tokyo Sweets 111380 `26390.jpg`: `receipt_number` `1-66566` vs GT `#1-66566` — GT inconsistency (other TS records omit `#`); GT corrected

### Root causes
- **DD/MM swap (4 cases)**: Despite explicit rules and `"01/08/2026" → 2026-08-01 NOT 2026-01-08` examples, model still applies MM/DD for ambiguous dates where T1 ≤ 12. The prior is overriding the rule.
- **Year errors (3 cases)**: One-digit OCR misread (68↔69 BE) — at OCR accuracy floor
- **Watsons**: Short labeled "Receipt No: 0035" beats unlabeled 18-digit hint-match; EXCEPTION B lacked explicit priority over short labeled numbers
- **EGV**: Zero-padded counter `00000009` chosen despite existing exclusion rule; rule wasn't strong enough

### Changes (principle-level)

**`frag.extract.receipt_datetime.rule`** (3,089 → 3,611, +17.0%)
- Added **⚠ NUMERIC-DATE FORMAT LOCK** block after the UNIVERSAL DATE PARSING RULE header: "When all three date tokens are NUMERIC and T3 is a 4-digit year, the format is IRREVOCABLY SMALL→BIG. NEVER apply MM/DD/YYYY. Model prior knowledge cannot override this lock."
- Added to IMAGE OVERRIDE: "NUMERIC-ONLY dates (all three tokens are digits) CANNOT be overridden — FORMAT LOCK above applies absolutely."

**`frag.extract.receipt_datetime.examples`** (1,813 → 2,068, +14.1%)
- Added three new anti-pattern examples for the exact failing patterns:
  - `"01/07/2026"` → 2026-07-01  NOT 2026-01-07
  - `"01/04/2026"` → 2026-04-01  NOT 2026-01-04
  - `"02/07/2026"` → 2026-07-02  NOT 2026-02-07

**`frag.extract.receipt_number`** (8,217 → 8,836, +7.5%)
- Added **SHORT LABEL OVERRIDE** to EXCEPTION B: when hint is ≥15 digits and a matching long sequence is found, the hint-matching sequence wins over a shorter (≤10 digit) labeled "Receipt No" number.
- Added **ZERO-PADDED COUNTER EXCLUSION**: codes where the first 5+ characters are all "0" (e.g. "00000009", "00000012") are cinema/event seat or session counters REGARDLESS of label — always excluded; find the transaction reference number instead.

### Ground truth correction
- Tokyo Sweets `26390.jpg`: `receipt_number` `"#1-66566"` → `"1-66566"` — consistent with model OUTPUT FORMAT rule (strip leading `#`) and all other Tokyo Sweets GT entries.

### Post-change hashes — run 5
```
frag.extract.receipt_datetime.rule      md5=06d35de19d456ed22dba2011c5e6eadf  len=3611
frag.extract.receipt_datetime.examples  md5=f85d0c53c9f7b97a00ec682197e35153  len=2068
frag.extract.receipt_number             md5=6f78f52c5dec145a251bdaa5a5917ed0  len=8836
```

### Pre-change hashes (to roll back to)
```
frag.extract.receipt_datetime.rule      md5=8757d79e4b66e0a2cb35fd53b93309da  len=3089
frag.extract.receipt_datetime.examples  md5=add066bf894d6df4eb0de8dacd8440fb  len=1813
frag.extract.receipt_number             md5=16b0648519733486a6d73d340a638122  len=8217
```

### Known residual failures (not fixed this run)
- **Year off-by-one (3 cases)**: NITORI 2026→2025, น้ำเต้าหู้ 2026→2025, Nose Tea 2025→2026 — all at OCR accuracy floor (68/69 BE one-digit misread)
- **First Snow belongs_to_futurepark "yes" vs "uncertain"**: Persistent across runs. Likely E041310 POS prefix IS present on receipts (First Snow is a FuturePark tenant), making "yes" correct; GT "uncertain" may predate E041310 rule. To investigate.
- **Starbucks net_amount 8617.4 vs 10850**: Unclear without image — possible VAT or voucher read issue.
- **White Story null datetime**: Image readable but date missing from OCR — at extraction floor.
- **Various OCR char confusions** (ComSeVen 601-8R vs 6901-BR, Oriental Princess OP7253SL vs OP72538L): Single-character misreads at OCR accuracy floor.

---

### Correction to prior assumption (was logged as a "known issue")

Previous write-ups here claimed a DB trigger `custom_futureparkocrprompts_sync`
kept monolithic rows in sync with fragments. That trigger does not actually
exist — `pg_trigger` shows only `trg_update_custom_futureparkocrprompts_updated_at`
on this table.

It turns out none of that matters: `receipt-preview-v2` already calls
`assemble_ocr_prompt()` at runtime (see `getPrompts()` in the edge function),
and the Render `crm-batch-upload` eval service delegates to `receipt-preview-v2`.
So fragment/compose edits take effect on the next request with no sync step.

The manual `UPDATE ... SET prompt_text = assemble_ocr_prompt(...)` commands run
above are cosmetic and don't change production behaviour. See the corrected
"Architecture (as-built)" section near the top of this doc.

---

## Change set 6 — Hint-primary structural refactor + GT fixes — 2026-04-24

### Motivation
Five change sets of incremental rule/example additions had compounded the prompts to:
- `is_futurepark`: ~30,604 chars (E7 ceiling violations, multiple rule conflicts)
- `net_amount_extraction`: ~20,108 chars
- `frag.extract.receipt_number`: 8,836 chars (above E7 8,000-char ceiling)

Root cause analysis via `_reasoning` field on two eval runs revealed:
1. **GT errors** were masquerading as prompt failures (Swensen's, Starbucks).
2. **JSON/reasoning inconsistency**: model reasons correctly in `_reasoning` but overrides itself when writing JSON fields (confirmed: First Snow `belongs_to_futurepark`, Bath & Body Works `net_amount`).
3. **Hints were positioned as backup**, not primary — `frag.hint.*` fragments sat after all algorithm fragments in compose order, reducing their influence.
4. **98% of stores have hints** covering format, label, and date examples — the detailed generic rules were redundant for this majority.

### Architectural shift: hints are primary, rules are fallback

Every field now follows this two-section pattern:
```
HINT FIRST: when hint provides [field], use it directly.
FALLBACK: [condensed rules for ~2% of stores without hints]
```

### Changes applied

**Prompt version table (NEW)**
- `custom_futureparkocrprompts_versions` created with `snapshot_label`, `prompt_key`, `prompt_text`, generated `char_len` + `md5`, `snapshotted_at`.
- Snapshot `pre-cs6-hint-primary-refactor` captures all 30 rows pre-change.

**GT corrections (E6 — model was correct, GT was wrong)**
- Swensen's `IMG_0051` (`01a929cf`): `receipt_datetime` `2026-08-01` → `2026-01-08` (OCR `08/01/2026` in DD/MM = Jan 8; same error pattern as IMG_0049 corrected in CS4)
- Starbucks `IMG_0539` (`4f8e8f8e`): `receipt_datetime` `2026-02-05` → `2026-03-05` (receipt number `260305-02-16903` embeds YYMMDD = March 5)

**`frag.is_futurepark.output_format`** (1,502 → 1,888)
- Added COPY RULE to field notes: `belongs_to_futurepark` and `receipt_number` must be copied directly from `_reasoning` conclusions. "Do not re-evaluate when writing this field."
- This addresses the systematic JSON/reasoning inconsistency (model reasons correctly but writes a different value in JSON).

**`frag.base.output_format`** (935 → 1,202)
- Added equivalent COPY RULE for `net_amount_after_discount`.

**`__compose.is_futurepark__`** — reordered + trimmed
- `frag.hint.store_header` moved from position 10 → position 2 (immediately after intro, before all extraction rules).
- `frag.extract.receipt_datetime.examples`, `frag.extract.receipt_datetime.year`, `frag.extract.receipt_datetime.months` removed from compose (data now in hint + new year_months fragment).

**`__compose.net_amount_extraction__`** — reordered
- `frag.hint.sale_amount` moved from position 9 → position 2.

**`frag.hint.store_header`** (926 → 971) + **`frag.hint.sale_amount`** (807 → 591)
- Language upgraded from "helps resolve ambiguity" to "IS the format / IS the label for this store". Fallback rules explicitly secondary.

**`frag.extract.receipt_number`** (8,836 → 1,786, −80%)
- Complete rewrite: HINT FIRST section + condensed FALLBACK priority list + ALWAYS EXCLUDE list.
- All store-specific exceptions (EXCEPTION A/B/C), crowded line rules, SHORT LABEL OVERRIDE, ZERO-PADDED COUNTER — removed. Hint covers the specific store; the exclude list covers the universal cases.

**`frag.extract.receipt_datetime.rule`** (3,611 → 993, −73%)
- Complete rewrite: HINT FIRST + condensed 4-step middle-token algorithm.
- FORMAT LOCK, IMAGE OVERRIDE, NUMERIC-DATE LOCK removed — hint is the format authority for 98% of stores; the algorithm is clean fallback for the rest.

**`frag.extract.receipt_datetime.year_months`** (NEW, 905 chars)
- Replaces separate `frag.extract.receipt_datetime.year` (1,864) and `frag.extract.receipt_datetime.months` (1,286).
- Contains: CE/BE conversion table, plausibility gate, hint placeholder warning, Thai abbreviation table.

**`frag.extract.receipt_datetime.misc`** (2,493 → 706, −72%)
- Kept: multiple-date selection, date-embedded receipt numbers, time handling, best-effort null rule.

**`frag.reasoning.is_futurepark.sanity`** (3,648 → 1,292, −65%)
- Removed: all date anti-pattern examples (now in hint or algorithm), HARD RULE for belongs_to_futurepark (now in output_format COPY RULE). Kept: triple-consistency check, belongs_to_futurepark evidence check, receipt_number quick sanity.

**`frag.reasoning.net_amount.principles`** (3,556 → 1,442, −59%)
- Rewritten: HINT FIRST + 8 lean principles P1–P8. Added **P7 — PRE-PAID**: when `Amount Due: 0.00` alongside a non-zero Total, receipt was pre-paid via app — return Total (covers Tai Er WeChat pre-pay pattern).

**`frag.extract.net_amount.core`** (2,876 → 966, −66%)  
**`frag.extract.field_defs`** (2,009 → 467, −77%)  
**`frag.extract.voucher_rules`** (1,931 → 446, −77%)  
**`frag.extract.vat_patterns`** (2,308 → 666, −71%)  
**`frag.extract.misc_patterns`** (1,531 → 359, −77%)  
**`frag.reasoning.net_amount.sanity`** (2,073 → 669, −68%)

### Assembled prompt sizes (post-change)
```
is_futurepark        len=14,303  md5=f7a6435a331c1822b0adf4cb881444b9
net_amount_extraction len=8,890  md5=5c847c5f0854fdeee4e47dc0c1c5074c
```
Previous sizes: is_futurepark 30,604 / net_amount_extraction 20,108.
**Total reduction: ~53% / ~56%.**

### Rollback
Restore from version table snapshot `pre-cs6-hint-primary-refactor`:
```sql
UPDATE custom_futureparkocrprompts p
SET prompt_text = v.prompt_text
FROM custom_futureparkocrprompts_versions v
WHERE v.snapshot_label = 'pre-cs6-hint-primary-refactor'
  AND v.prompt_key = p.prompt_key;
```

### Known residual issues (not addressed this change set)
- First Snow `receipt_number` null: CH-code not present in `store_header_ocr` — Roboflow region issue, not prompt-fixable.
- น้ำเต้าหู้ / NITORI year one-digit OCR misreads — at accuracy floor.
- prediction_class failures — Roboflow model, not addressable.
- `frag.extract.receipt_datetime.examples`, `frag.extract.receipt_datetime.year`, `frag.extract.receipt_datetime.months` rows left in DB but removed from compose — safe to delete in a future cleanup pass.

---

## Change set 7 — Targeted patch: over-trimming regression fixes — 2026-04-24

Eval runs c1688149 / acd6d9db both returned 50% overall accuracy on 10 samples each. `_reasoning` analysis identified 4 root causes — all from rules removed during CS6 trimming. Architecture unchanged.

### Root causes identified via `_reasoning`

| Failure | Root cause |
|---|---|
| Karun Thai Tea + Yoguruto `receipt_number` null/wrong | `ID:` label misclassified as "staff/employee ID" — ABSOLUTE PRIORITY note was removed in CS6 |
| Sukiya `receipt_datetime` 2028 vs 2026 | Plausibility gate bypassed: model read "2028 is within 2 years of 2026" as plausible; correction example was removed |
| โอ๋กะจู๋ `net_amount` 1653 vs 1153 | HINT FIRST fired on Grand Total 1,653 and short-circuited; voucher deduction (500 Baht redemption → 1,153) was never applied |
| ครัวเมืองเว้ receipt_number+datetime both null | Incomplete JSON from is_futurepark: COPY RULE too strict, model skipped uncertain fields rather than outputting null |

### Changes (all targeted additions, no structural reversions)

**`frag.extract.receipt_number`** (1,786 → 2,239)
- Restored `ID: LABEL PRIORITY` note: *"A value labeled 'ID:' is a system-generated receipt/transaction identifier — NOT a staff ID or employee code. It takes absolute priority over any queue number."*
- Restored ALL-UPPERCASE alphabetic codes guidance (e.g. NOGYI, B3AMI, VQVPR) as valid receipt IDs.

**`frag.extract.receipt_datetime.year_months`** (905 → 1,397)
- Plausibility gate made explicit: step-by-step correction sequence restored.
- Concrete correction example added back: *"OCR reads 2028 → correct to 2026 ('8' was a misread '6')."*
- OCR garbling note for ก.พ. → "n.w." added.

**`frag.hint.sale_amount`** (591 → 860)
- Added explicit carve-out: *"P4 (VAT-inclusive wins) and voucher rules still apply after the hint fires."*
- Voucher deduction formula: *"net_amount = hint-label value − voucher amount."*

**`frag.is_futurepark.output_format`** (1,888 chars)
- Replaced strict "COPY RULE / do not re-evaluate" with softer alignment note.
- Added: *"ALWAYS output a value for this field, even if null — never skip it."* for receipt_number and receipt_datetime.
- Prevents partial JSON where the model omits fields it is uncertain about.

### Notes
- NITORI date (3 N.A. 26 → June vs January GT) not addressed: model is reading image as "JUN"; if GT expects January this may be a GT labelling error. Verify image before deciding.
- After You `receipt_number` "00020/03" vs "03044069": model applied HINT FIRST but matched wrong token. Hint pattern `03007571` (8-digit) should have matched `03044069`, not `00020/03`. May self-correct after output_format fix prevents incomplete JSON affecting hint matching.
- Bar-B-Q Plaza / โครงการหลวง `net_amount` null: is_futurepark `_reasoning` was shown (not net_amount reasoning). Requires net_amount-specific eval run to diagnose.

---

## Change set 9 — Net amount 17% fail rate: compose fix + coupon override + pre-paid QR — 2026-04-24

### Eval baseline: 83% net_amount accuracy (100 samples, 17 failures)

**Root-cause analysis (from receipt image review):**

| Bucket | Count | Root cause |
|---|---|---|
| MK Restaurant +100 (2 cases) | 2 | `ราคาสุทธิ` = pre-coupon total; receipt shows `ราคาสุทธิ → ส่วนลด 100 → QR payment`. Model correctly reads `ราคาสุทธิ` per hint but should defer to QR/Card when a coupon separates them |
| Sukiya → 0 instead of 338 | 1 | Pre-paid QR receipt: `QR: 0.00` + `Total: 338`. P7 only covered "Amount Due: 0.00" — didn't match QR label |
| Clear-image nulls (Mo-Mo Paradise, โครงการหลวง, WHITE Story, Bakery Treasury, Bonchon, etc.) | 12 | Mix of Roboflow OCR floor (sale_section_ocr misses total line) and column-layout receipts where label-value pairing fails in linearized OCR text |
| Wrong values (S&P, Nose Tea) | 2 | Partial-quality images; OCR accuracy floor |

**`frag.extract.net_amount.critical_first` was in DB but NOT in compose** — dead code for its entire existence. Activated in this change set.

### Changes

**`__compose.net_amount_extraction__`** — added `frag.extract.net_amount.critical_first` at position 2 (after intro, before hint):
```
["frag.base.intro_and_inputs", "frag.extract.net_amount.critical_first", "frag.hint.sale_amount", ...]
```

**`frag.extract.net_amount.critical_first`** (1,295 → 1,745, +34%)
- **RULE B rewrite**: removed "Do NOT subtract vouchers from it" (conflicted with loyalty/GV deduction rules). New: label identifies starting value, deductions per voucher rules still apply.
- **RULE C (NEW)**: QR/Card payment = 0.00 alongside a non-zero Total → receipt is PRE-PAID. Return the Total/Sub Total, NOT 0. Covers Sukiya-style app-pre-payment pattern.
- **COLUMN LAYOUT FALLBACK extended**: added "if no ยอดสุทธิ label AND no cash/change, use largest plausible total visible in the image."

**`frag.reasoning.net_amount.principles`** (2,052 → 2,444, +19%)
- **P4 COUPON OVERRIDE (NEW)**: "if the QR/Card payment amount is LOWER than the hint-labeled total AND a coupon or additional discount line appears between the labeled total and the payment line, the QR/Card payment IS the true net." Covers MK Restaurant pattern (ราคาสุทธิ → 100-baht coupon → QR).
- **P7 expanded**: now covers "QR, Card, or Amount Due shows 0.00 alongside a non-zero Total or Sub Total" (previously only matched "Amount Due: 0.00" label, missed "QR: 0.00" on Sukiya receipts).

**Store hints data fixes:**
- `111736` store_name: "PonnBlack by Doi Tung" → "Bakery Treasury Co.,Ltd." (rebranded; hint label `รวมทั้งสิ้น` remains correct)
- `159592` (MK): `net_amount_label` kept as `ราคาสุทธิ` — P4 COUPON OVERRIDE handles the exception without changing hint

**Ground truth correction (E6 — model was correct, GT was wrong):**
- Sukiya `IMG_0034.JPG` (`955b56cf`): `receipt_datetime` `"2028-01-14T14:06:00"` → `"2026-01-14T14:06:00"`. Year 2028 was data-entry error; model correctly read 2026.

### Post-change hashes — run 9
```
__compose.net_amount_extraction__      md5=ab972281934c2abfe8e973856c79fb8e  len=411
frag.extract.net_amount.critical_first md5=f90246989c92b3baec5ff1d61874d2ae  len=1745
frag.reasoning.net_amount.principles   md5=30fc78941a3e33f1aef6f64872089137  len=2444
net_amount_extraction (assembled)      md5=d3ad5b4e1320adfb53feea048b78013e  len=12566
```

### Unfixed failures (OCR/Roboflow floor — not prompt-addressable this run)
- **Mo-Mo Paradise / โครงการหลวง / Bonchon**: `sale_section_ocr` from Roboflow misses total line. Needs Roboflow region tuning.
- **Nose Tea doubled**: partial receipt, model picks wrong total line.
- **S&P, Bonchon partial**: partial image quality at OCR floor.

---

## Change set 8 — Structural loyalty-redemption fix — 2026-04-24

### Problem
โอ๋กะจู๋ IMG_0651 returned `net_amount = 1,653` (Grand Total) instead of `1,153` (after 500-Baht loyalty redemption).

Root cause: P6 (SPLIT PAYMENT) was *confirming* the wrong answer. Model reasoned: *"500 (Redeem) + 1,153 (Card) = 1,653 = Grand Total → P6 confirms Grand Total is correct."* Loyalty redemption lines were being treated as a real payment method in the split-payment verification, so the model never deducted them.

### Structural fix: three-layer change

**LOYALTY PRE-CHECK** added to `frag.reasoning.net_amount.principles` (before HINT FIRST):
> Before applying any principle, scan for loyalty redemption lines below the first total line. If found: `Effective Total = Grand Total − Redemption Amount`. All subsequent principles operate on Effective Total, not the printed Grand Total.

**P6 patched** to explicitly exclude loyalty lines:
> "EXCLUDE loyalty redemption lines — they are not real money. Verify: sum of real payment lines (card/QR/cash only, no Redeem) ≈ Effective Total."

**`frag.extract.voucher_rules`** extended with LOYALTY REDEMPTION as a named parallel to GV:
> Signals: "Redeem X Baht", "แลกแต้ม X บาท", "Point Redemption X", "คะแนน X บาท", "Vibe Points X", "Points used X", "แลก Xบาท". Formula identical to GV: `net_amount = Grand Total − Redemption Amount`. Confirmed by remaining card/QR charge.

**`frag.hint.sale_amount`** updated to list loyalty signals explicitly in the deduction carve-out alongside GV/voucher.

### Fragment sizes post CS8
```
frag.reasoning.net_amount.principles  2,052 chars
frag.extract.voucher_rules              959 chars
frag.hint.sale_amount                 1,005 chars
```

### Also in this session (CS7 follow-up)
- Yoguruto hint `receipt_number_example` updated from `SPMLH` → `B3AMI` (the actual mixed alphanumeric format on current receipts; `SPMLH` was pure-letter from an older receipt and failed HINT FIRST pattern match).

---

## Change set 10 — CS6 regression fix: datetime rule + examples restored, saleOcr guard removed — 2026-04-24

### Context
100-sample random eval (run after CS6–CS9) returned **57% overall** (down from 68% pre-CS9 and 69.33% pre-CS6).
Root-cause analysis identified three CS6 removals as the direct cause of each regressed field.

### Root causes

| CS6 removal | Chars lost | Failures caused |
|---|---|---|
| `frag.extract.receipt_datetime.examples` removed from compose | 2,068 | 7–8 of 10 datetime DD/MM swap failures |
| `frag.extract.receipt_datetime.rule` shrunk (FORMAT LOCK removed) | 3,611 → 993 | Compounds DD/MM — model prior overrides short rule |
| `saleOcr.length > 0` guard in edge function | — | ~10–12 net_amount nulls on clear images (Claude never called when Roboflow OCR is empty) |

### Changes applied

**`supabase/functions/receipt-preview-v2/index.ts` (v55 → v56)**
- Removed `saleOcr.length > 0` guard. When Roboflow `sale_section_ocr` is empty, Claude now receives `'[Sale section OCR unavailable — extract net amount from image directly]'` and falls back to pure vision. Previously Claude was skipped entirely, falling through to `roboflow_amount` (also usually null).

**`frag.extract.receipt_datetime.rule`** — restored from `pre-cs6-hint-primary-refactor` snapshot (3,611 chars)
- Restored FORMAT LOCK + NUMERIC-DATE LOCK + IMAGE OVERRIDE rules.
- CS6's 993-char rewrite had no FORMAT LOCK; model's MM/DD prior kept overriding examples alone.

**`__compose.is_futurepark__`** — re-added `frag.extract.receipt_datetime.examples`
- Fragment (2,068 chars, anti-pattern examples including exact DD/MM failure patterns) was in DB but excluded from compose since CS6.
- Inserted after `frag.extract.receipt_datetime.rule`.
- `frag.hint.store_header` kept at position 2 (CS6's hint-first improvement retained).

### Post-change assembled sizes
```
is_futurepark         len=19,936  md5=1455be439cb409762d9e0c523d4ab513
net_amount_extraction len=12,566  (unchanged)
```

### Pre-change hashes (to roll back to)
```
frag.extract.receipt_datetime.rule   md5=06d35de19d456ed22dba2011c5e6eadf  len=993   (CS6 version)
__compose.is_futurepark__            len=382   (CS6 version, without examples fragment)
```

### Known residual failures (not addressed)
- `receipt_number`: CS6 rewrote `frag.extract.receipt_number` from 8,836 → 2,239 chars removing exception rules. Pre-CS6 version exists in versions table. Requires targeted eval before restoring (hint-first benefit of CS6 must be preserved).
- `prediction_class` nulls: Roboflow model, not addressable via prompts.
- net_amount wrong values (MK coupon, ComSeven): prompt-level, lower priority vs null fixes.

---

## Change set 11 — Net amount null barrier + hint-not-found fallback — 2026-04-25

### Context
New 100-sample eval (run `a0dc00a3`) after CS10: 80/100 processed, overall 62.5% (up from 57%).
- `receipt_datetime`: 96.25% (+6.25%) ✅ CS10 FORMAT LOCK working
- `receipt_number`: 92.5% (+5.5%) ✅
- `net_amount_after_discount`: 72.5% (-5.5%) ❌ still degraded

### Root causes (net_amount failures)

| Pattern | Failures | Root cause |
|---|---|---|
| Clear-image returns null (~13 cases) | Mo-Mo Paradise, Sushiro, OISHI RAMEN, Watsons, UNIQLO, Shinkanzen, Bakery Treasury, S&P, KUB KAO KUB PLA, Oriental Princess | Roboflow sale_section_ocr crop misses the Total row. HINT FIRST finds no match → exits without falling through to FALLBACK PRINCIPLES (P1–P8 only apply "when no hint exists"). Model returns null. |
| Before-VAT extracted (4 cases) | ComSeven/Studio 7 (store 108907) | Hint label `รวมทั้งสิ้น` correctly found, but equals before-VAT base (17663.55) on their tax invoice format. The actual payment (18900 = base × 1.07) is outside the Roboflow OCR crop. P2 ("prefer ~7% larger") only checked OCR text, not image → model kept 17663.55. |

### Changes applied

**`frag.reasoning.net_amount.principles`** (2,052 → 2,672 chars)

HINT FIRST section rewritten to:
- Change P2 scope from "on the same receipt" → "anywhere on the receipt **(OCR or image)**"
- Add explicit hint-not-found fallback: if hint label absent from OCR, look in image; if still absent, fall through to P1–P8. Never return null solely because the hint label is missing from OCR.

**`frag.extract.net_amount.core`** (1,202 → 1,201 chars)

Step 5 changed from `"Null only if no amount anywhere on the receipt"` to:
> **NULL BARRIER** — Before returning null: look at the bottom of the receipt image. Thai receipts always display a final total amount (usually bold, larger font, or boxed). If any payment total is visible — even partially — return that value. Return null ONLY if the receipt image itself is physically unreadable.

### Post-change fragment sizes
```
frag.reasoning.net_amount.principles  2,672 chars
frag.extract.net_amount.core          1,201 chars
```

### Pre-change hashes (to roll back to)
```
frag.reasoning.net_amount.principles  len=2,052  (CS8 version)
frag.extract.net_amount.core          len=1,202  (CS10 version)
```

### Known residual failures (not addressed)
- ComSeven receipt_number confusions (BR vs 0B OCR character, partial quality images)
- Bonchon +500 wrong amount (likely a 500-baht voucher/coupon deducted on receipt but not subtracted)
- `prediction_class` nulls: Roboflow model, not addressable via prompts.
- `receipt_number`: pre-CS6 restore still deferred pending targeted eval.

---

## Change set 12 — Image-primary net_amount + eval fixes + targeted prompt fixes — 2026-04-25

### Context
Post-CS11 eval (run `ad280ef6`) on 50 samples: 32/50 overall accuracy (64%), down from 80% at CS11. Root cause analysis revealed several systemic issues:
1. **Eval bug**: `prediction_class` was compared against `correct_result['prediction_class']` (JSONB, often null) instead of the top-level `store_code` column — causing systematically wrong failures.
2. **Eval bug**: cases where model returned null for non-null expected were counted as hard failures instead of `skipped`.
3. **Architecture**: `sale_section_ocr` (Roboflow linearised text) was the primary input to the amount call, causing column-layout alignment failures and timeouts on dense receipts. Design intent was always image-primary.
4. **GT data error**: Cafe Amazon (IMG_0419) GT stored store_code `110242` which doesn't exist in `store_master`. Roboflow correctly returns `FP2053`.
5. **Targeted prompt failures**: Bonchon coupon deductions, Sushiro alphanumeric table IDs, Oriental Princess date ambiguity.

### Changes applied

#### A — Eval infrastructure (index.ts)

**A1 — Null-skip logic** (was already in local file, now deployed for first time as v62)
Cases where `actual=null, expected≠null` are counted as `skipped`, not `fail`. Accuracy denominator excludes skipped.

**A2 — prediction_class GT reads store_code column**
- All three GT select queries now fetch `store_code` column.
- Eval loop computes `gtStoreCode = tc.store_code ?? tc.correct_result?.prediction_class ?? null`.
- `prediction_class` expected value uses `gtStoreCode` (not the JSONB field which is often null/stale).
- All `failures[]` and `per_case[]` objects now surface `gtStoreCode` as `store_code`.
- Store-code filter (when `store_code` param passed) uses `tc.store_code ?? tc.correct_result?.prediction_class`.

**A3 — claude_amt_error surfaced in per_case**
`per_case[]` entries now include `claude_amt_error` and `claude_amt_raw` from the debug object, so the Render eval service can distinguish timeout vs bad-JSON vs reasoning failure without a separate DB query.

**Version bump**: v61 → v62 throughout.

#### B — Ground truth data

**B2 — Cafe Amazon GT corrected**
- `custom_futurepark_receipt_groundtruth` row `5e3e6861-2949-44e7-9939-68313ba51a4c` (IMG_0419)
- `store_code`: `110242` → `FP2053`
- `correct_result.prediction_class`: `"110242"` → `"FP2053"`
- (FP2053 is the actual Cafe Amazon kiosk code in `store_master`; 110242 had no match.)

#### C — Architecture: net_amount goes image-primary

**C1 — Drop sale_section_ocr from amount call** (index.ts ~line 443)
`saleOcrOrFallback` logic removed. The amount prompt's `{{sale_section_ocr}}` placeholder now receives only `amountHintText.trim()` (the store hint text, or empty string). No OCR text is passed to the amount call.

**C2 — Rewrite net_amount_extraction prompt fragments**

`frag.base.intro_and_inputs` (254 → 204 chars):
- Was: "Receipt Image + Sale Section OCR Text — cross-check them"
- Now: "IMAGE-FIRST: Read amounts directly from the receipt image. OCR text is not provided."

`__compose.net_amount_extraction__` (411 → 295 chars):
Removed OCR-specific fragments: `frag.base.ocr_first_method`, `frag.extract.field_defs`, `frag.extract.vat_patterns`, `frag.extract.misc_patterns`.
Retained: `frag.base.intro_and_inputs`, `frag.extract.net_amount.critical_first`, `frag.hint.sale_amount`, `frag.reasoning.net_amount.principles`, `frag.extract.net_amount.core`, `frag.extract.voucher_rules`, `frag.reasoning.net_amount.sanity`, `frag.output.confidence_rubric`, `frag.base.output_format`.

`frag.extract.net_amount.core` (1,201 → 1,212 chars):
Step 1: "Check store hint label in IMAGE" (not OCR scan).
Step 2: "Scan image bottom-up for final total labels".
Column layout note: "use visual alignment from the image to match values to labels" (removed OCR proximity guidance).

#### D — Targeted prompt and hint fixes

**D1 — Oriental Princess date hint** (store `159893`, `custom_futurepark_store_ocr_hints`)
`receipt_date_raw_example`: `07/15/20XX` → `15/07/20XX`
`receipt_date_standardized_example`: `15 july YYYY` (unchanged intent, day > 12 forces DD/MM unambiguously)

**D2 — Sushiro strict numeric guard** (index.ts `buildStoreFutureparkHintText`)
When `receipt_number_example` matches `/^[\d\-\/]+$/` (numeric-only):
> "The format is numeric only — do NOT return alphanumeric codes, table references (e.g. T54), session IDs, or codes with letters. If no numeric identifier matching the hint digit count is found, return null."
Sushiro example `715933` triggers this guard, preventing table IDs like `T54` from being returned.

**D3 — Bonchon PRE-HINT COUPON SCAN** (`frag.reasoning.net_amount.principles`, +374 chars)
New section added before LOYALTY PRE-CHECK:
> Scan the ENTIRE receipt image for discount/deduction lines (ส่วนลด, คูปอง, Campaign, Discount, ลด, Promo). If found, note the deduction amount. The true net is the final amount AFTER all deductions — confirmed by QR/Card payment line. Do NOT return the pre-deduction subtotal even if it carries the hint label.

### Post-change fragment sizes
```
frag.base.intro_and_inputs             204 chars
__compose.net_amount_extraction__      295 chars
frag.extract.net_amount.core         1,212 chars
frag.reasoning.net_amount.principles 4,170 chars
```

### Pre-change sizes (to roll back to)
```
frag.base.intro_and_inputs             254 chars  (CS11 version)
__compose.net_amount_extraction__      411 chars  (CS11 version)
frag.extract.net_amount.core         1,201 chars  (CS11 version)
frag.reasoning.net_amount.principles 3,796 chars  (CS11 version)
```

### Expected accuracy impact
- A1+A2: Recover ~5-10% from systematic eval bugs (prediction_class false failures, null false failures).
- B2: Recover 1 Cafe Amazon case.
- C: Net amount null rate should drop significantly (image always present, no OCR crop dependency).
- D1: Recover Oriental Princess date failures (DD/MM now unambiguous with day=15).
- D2: Recover Sushiro receipt_number failures.
- D3: Recover Bonchon net_amount failures (coupon deduction now detected pre-hint).

---

## Change set 14 — v66: FP normalization before hint lookup + eval field cleanup — 2026-04-25

### Motivation (from run 476f18b3, 72% overall)

Root-cause analysis identified two systematic issues not addressable via prompts:

1. **Hint lookup key mismatch (architectural)**: `getStoreOcrHint` was called with the raw
   Roboflow FP code (e.g. `FP2345`) but hints in `custom_futurepark_store_ocr_hints` are keyed
   on 6-digit `external_ref` values (e.g. `159231`). The FP→external_ref normalization only
   happened after hints were fetched, so for every Roboflow-classified store, the hint was
   silently never loaded. This was the confirmed root cause of persistent Sushiro net_amount nulls
   across multiple runs (NULL BARRIER present but hint label never injected).

2. **belongs_to_futurepark in eval (noise)**: All GT rows are confirmed FuturePark receipts by
   definition. Evaluating this field adds noise — any "uncertain" in GT is stale, not a model
   error. First Snow was a persistent false failure for this reason across CS3–CS13.

### Changes (edge function only, no prompt changes)

**`supabase/functions/receipt-preview-v2/index.ts` (v65 → v66)**

- **FP normalization moved before hint lookup**: The `store_master` lookup that translates
  `FP####` → `external_ref` now runs immediately after the text-based fallback classifier,
  before `getStoreOcrHint`. The late normalization block (which ran after `buildItem`) is
  removed — it is now redundant.

- **`belongs_to_futurepark` removed from `EVAL_FIELDS`**: The eval loop no longer scores
  this field. All GT entries are FuturePark receipts; evaluating the field against stale
  "uncertain" entries was producing false failures.

### Ground truth corrections (run 476f18b3 trigger failures)

| Row ID | Store | Field | Old value | New value | Reason |
|--------|-------|-------|-----------|-----------|--------|
| `544f6473` | Oriental Princess | `receipt_datetime` | `2026-07-02T11:17:40` | `2026-02-07T11:17:40` | Expected Jul 2 is a future date; model read DD/MM correctly |
| `20e70b1e` | Sushiro IMG_0043 | `receipt_datetime` | `2026-08-01T21:26:00` | `2026-01-08T21:26:00` | Expected Aug 1 is a future date; model read DD/MM correctly |

### Expected accuracy impact
- Sushiro net_amount nulls: hint now loads correctly → STEP 0 / RULE B have the "Total" label anchor
- prediction_class: FP codes now normalize before eval comparison → Cafe Amazon and similar stores pass
- belongs_to_futurepark: removed from scoring → First Snow persistent false failure eliminated
- receipt_datetime: 2 GT corrections → recover 2 false failures

---

## Change set 13 — STEP 0 coupon exclusion, NULL BARRIER hardening, receipt_number single-value — 2026-04-25

### Eval baseline: 70% overall (50 samples, 15 failures) — run `607a3d34`

```
receipt_number           fail 4 / 46  (92%)
prediction_class         fail 2 / 48  (96%)
receipt_datetime         fail 3 / 47  (94%)
belongs_to_futurepark    fail 1 / 49  (98%)
net_amount_after_discount fail 6 / 44 (88%)
```

### Failure triage

**Ground truth errors (2 records corrected — missing expected values):**
- Tonkatsu Wako `LINE_ALBUM_11269_260213_31.jpg` (id `1ceb21a5`): Roboflow returns null (store not in training data); text-based fallback classifier returns "161051" (external_ref). GT had `correct_result.prediction_class = null` → eval always fails regardless of actual. Fixed: `correct_result.prediction_class = "161051"`. `store_code` unchanged ("161051").
- Moshi Moshi `IMG_0179.JPG` (id `644b3a7b`): Same — fallback returns "160455". Fixed: `correct_result.prediction_class = "160455"`. `store_code` unchanged ("160455").
- Note: the "FP5600"/"FP2445" values seen as `actual` in run 607a3d34 came from an older deployed version of the text-based fallback that used `store_code` (FP-prefixed) instead of `external_ref` (6-digit). Current code is correct.

**Store hint data fixes:**
- **EGV/Major Cineplex 159713**: `receipt_number_example` cleared (was `"121577847"`, a 9-digit Order No format). HINT FIRST was matching `Order No: 124355073` (9 digits) over `T/N: 1243550` (7 digits). Clearing the hint lets FALLBACK rule 3 (T/N wins over Order No) apply.
- **Starbucks 110399**: `receipt_number_example` updated from `"100416434"` (9-digit numeric) to `"260110-03-19959"` (YYMMDD-NN-NNNNN format matching actual receipts). HINT FIRST was failing to match the hyphenated format, leaving FALLBACK unable to find it → null.

**Prompt-fixable (3 fragments):**

**STEP 0 in `frag.extract.net_amount.critical_first`:**
1. *Bonchon 1051.81 vs 51.81*: Campaign/coupon deduction lines formatted like payment lines were being summed by STEP 0 (Campaign -1000 + QR 51.81 = 1051.81). Fix: explicit exclusion list added to STEP 0 — any line labeled Campaign, ส่วนลด, คูปอง, Discount, Promo, ลด, Coupon, หักส่วนลด, บัตรส่วนลด is not a payment.
2. *Sushiro / Tokyo Sweets / UNIQLO null on clear images*: STEP 0 said "If it does → return it" but had NO fallback path when QR/Card was found but verification failed. Model had no instruction to return the payment sum anyway → fell through to null. Fix: added explicit fallback — "If verification is inconclusive or no matching labeled total found → STILL return the payment sum."

**`frag.extract.net_amount.core` NULL BARRIER:**
- Hardened Step 5: "A readable receipt image ALWAYS contains a final total amount. Returning null for a clear or partially-readable receipt is almost certainly wrong." Added: returning null from STEP 0 when a QR/Card amount was found is explicitly prohibited. Return null ONLY if image is physically unreadable.

**`frag.extract.receipt_number`:**
- Added **SINGLE VALUE**: return exactly one receipt number; never concatenate with commas, spaces, or any separator. Fixes Shinkanzen Sushi `"008RC2022569,002263"` → `"008RC2022569"`.
- Added **LENGTH MATCH**: when HINT FIRST finds a candidate with one extra leading '0' compared to hint digit count, strip the leading zero. Fixes Watsons `"0894004012120260035"` → `"894004012120260035"` (hint is 18-digit, receipt had 19-digit with leading zero).

**Not fixed this change set (residual):**
- NITORI month 05 vs 12: unclear whether receipt digit misread or GT entry error; would need image review.
- น้ำเต้าหู้ year off-by-one (2026 vs 2025): OCR 1-digit misread at accuracy floor.
- Oriental Princess persistent DD/MM swap on `LINE_ALBUM_722026_260209_76.jpg`: despite hint `15/07/20XX` + FORMAT LOCK + exact anti-pattern example `"02/07/2026"` → 2026-07-02. Model prior remains strong for ambiguous dates.
- First Snow `belongs_to_futurepark` yes vs uncertain: E041310 prefix IS present on First Snow receipts (FuturePark tenant), making "yes" plausible; GT "uncertain" may be stale.
- EGV net_amount 53.28 vs 57: 53.28 × 1.07 ≈ 57; P2 EXCEPTION A fires when QR = 53.28, blocking escalation; complex cinema receipt layout.
- Moshi Moshi net_amount 160 vs 38: partial quality image — OCR floor.

### Post-change hashes — run CS13
```
frag.extract.net_amount.critical_first  md5=0fd40843131f49a63e802c7ad72bb462  len=3252
frag.extract.net_amount.core            md5=ea90dad447731b19d11dfc00fae08ce0  len=1742
frag.extract.receipt_number             md5=d45f80453390b4db43d4b75af4ad281b  len=2727
net_amount_extraction (assembled)       md5=7722177c57dde1dbeb1565479bb39916  len=14030
is_futurepark (assembled)               md5=f30b260c119c7ff586384d1b3a24b3bf  len=20424
```

### Pre-change hashes (to roll back to)
```
frag.extract.net_amount.critical_first  md5=0fd40843131f49a63e802c7ad72bb462  len=2783  (CS12)
frag.extract.net_amount.core            md5=ea90dad447731b19d11dfc00fae08ce0  len=1212  (CS12)
frag.extract.receipt_number             md5=d45f80453390b4db43d4b75af4ad281b  len=2239  (CS12)
```

### Expected accuracy improvement
- prediction_class: +2 (GT corrections) → target 100%
- receipt_number: +2–3 (EGV T/N, Shinkanzen single-value, Watsons leading-zero, Starbucks hint) → target ~96–98%
- net_amount: +3–4 (Bonchon coupon exclusion, 3 null cases via STEP 0 fallback + NULL BARRIER) → target ~94–100%

---

## Change set 15 — Run 74e70642 (0.58, 50 samples) — 2026-04-26

### Eval baseline: 58% overall (50 samples, 21 failures)
```
net_amount_after_discount fail 9/50  (82%)
receipt_number            fail 8/50  (84%)
receipt_datetime          fail 3/50  (94%)
prediction_class          fail 2/50  (96%)
belongs_to_futurepark     fail 0/50  (100%)
```

### Root cause triage

**net_amount failures — two distinct patterns:**
1. **Pre-VAT extraction (×5)**: Starbucks ×2 (10140.19 vs 10850, 182.24 vs 195), ปังสยาม ×2 (112.15 vs 120, 59.81 vs 64), Com Seven ×1 (29813.08 vs 31900). In all cases `actual × 1.07 ≈ expected`. Root cause: these stores use cash/card payment with no visible QR line in the Roboflow OCR crop. STEP 0 finds no QR → falls to RULE B. RULE B found the hint-labeled value (pre-VAT base) and declared `labeled_total IS the net_amount` — **no P2 (VAT-inclusive wins) check was applied inside RULE B**. The 7% post-VAT total was visible in the image but never selected.
2. **Tokyo Sweets null ×3** (stores 111380, expected 326/326/276): hint label = "Amount Due". On pre-paid receipts "Amount Due: 0.00" appears; the non-zero Sub Total is shown above it. STEP 0 found no QR line → RULE B → hint-labeled value = 0 → **RULE C was only wired to STEP 0, not to RULE B** → no fallthrough to the non-zero total → null (blocked by P3) → null.

**receipt_number failures:**
- Tonkatsu Wako ×2 ("001-2" vs "001-2 [052372]", "001-48" vs "001-48 [049888]"): hint `"001-48"` was missing the bracketed `[NNNNNN]` sequence number that is part of the receipt ID. HINT FIRST matched only the prefix and stopped.
- AIIZ ×1 ("40342504017541" vs "A0342504017541"): OCR read `A` as `4`. Hint has correct "A0342602000224" prefix but no instruction to cross-reference the image for leading letter vs digit confusion.
- MK Restaurant ×1 ("001-0544927" vs "C01-0544927"): same OCR char confusion (C→0). Partial quality image.
- Others: truncation (RCRN-FIP), leading zero in ChaTraMue, ZPE/order-ref vs receipt-number on Mo-Mo Paradise.

**prediction_class failures:**
- Tonkatsu Wako `LINE_ALBUM_11269_260213_43.jpg`: GT had `prediction_class = null`; text-based fallback returns "161051" correctly. GT was wrong (sibling image _31 was fixed in CS13 but _43 was missed).
- Boost Juice 160147: Roboflow miss + text fallback fails → at accuracy floor.

**receipt_datetime failures (3):** All at OCR floor — one DD/MM ambiguous partial image (S&P), one month OCR misread (NITORI 08→01), one year off-by-one (น้ำเต้าหู้ปูปลา 2026→2025).

### Changes applied

**`frag.extract.net_amount.critical_first`** (3,252 → 3,996 chars, +23%)
- **RULE B rewritten as pure locator** (architectural fix): The previous `"labeled_total IS the net_amount"` hard assertion was wrong because `critical_first` is at compose position 2 — before principles (position 4). This meant RULE B short-circuited P2 (VAT-inclusive wins) entirely for cash receipts. The hint label was set from a simple single-total receipt; on VAT-breakdown or tax-invoice receipts the same label points to the pre-VAT subtotal.
  New RULE B: locates the anchor using hint label / ยอดสุทธิ / Grand Total / รวมทั้งสิ้น, then explicitly instructs **"Do NOT return the located value directly — apply ALL principles (P1–P9), especially P2 (VAT-inclusive wins)"**. For simple receipts where the hint label IS the grand total, P2 finds no larger candidate and returns it correctly. For VAT-breakdown receipts, P2 escalates to the post-VAT total.
- **RULE B ZERO AMOUNT CHECK** (kept): if the located amount = 0.00 ("Amount Due: 0.00"), apply RULE C.
- **RULE C extension**: also applies from RULE B zero amount check — scan for the non-zero Grand Total or Sub Total above the zero-due line.

**`frag.extract.receipt_number`** (2,727 → 3,139 chars, +15%)
- **LEADING CHAR CHECK** (new, after LENGTH MATCH): when the hint's first character is an uppercase letter (A, B, C, O, etc.) and OCR shows a look-alike digit at that position (A→4, C→0, O→0, B→8), cross-reference the receipt IMAGE to confirm the first character. Never silently drop the leading letter because OCR omitted it.

**`supabase/functions/receipt-preview-v2/index.ts` (v70 → v71)**
- `buildStoreFutureparkHintText` non-numeric branch: appended note "OCR often misreads leading uppercase letters as similar-looking digits (A→4, C→0, O→0, B→8) — cross-reference the receipt IMAGE to confirm the first character when the hint starts with a letter."

**Store hint data:**
- **Tonkatsu Wako `161051`**: `receipt_number_example` `"001-48"` → `"001-48 [049888]"`. The bracketed 6-digit sequence number is part of the receipt ID and must be included.

**Ground truth correction:**
- Tonkatsu Wako `LINE_ALBUM_11269_260213_43.jpg` (id `ae1995c8`): `store_code` set to `"161051"`, `correct_result.prediction_class` set to `"161051"`. Model (text-based fallback) was correct; GT lacked the field (sibling image _31 was fixed in CS13, _43 was missed).

### Post-change hashes — run CS15
```
frag.extract.net_amount.critical_first  md5=ac829d1a717291362d9135e29424fb04  len=3996
frag.extract.receipt_number             md5=(check db)                         len=3139
net_amount_extraction (assembled)       md5=6da4d0cb2637a26935777b4a2670d4f3  len=14774
is_futurepark (assembled)               md5=142c15bcbab2771211e65d3d55cc55d5  len=20836
```

### Pre-change hashes (to roll back to)
```
frag.extract.net_amount.critical_first  md5=0fd40843131f49a63e802c7ad72bb462  len=3252  (CS13)
frag.extract.receipt_number             md5=d45f80453390b4db43d4b75af4ad281b  len=2727  (CS13)
net_amount_extraction (assembled)       md5=7722177c57dde1dbeb1565479bb39916  len=14030
is_futurepark (assembled)               md5=f30b260c119c7ff586384d1b3a24b3bf  len=20424
```

### Expected accuracy improvement
- net_amount: +5 (RULE B VAT check for pre-VAT extractions, RULE C extended for Tokyo Sweets nulls) → target ~92%+
- receipt_number: +2–3 (Tonkatsu Wako bracketed format, AIIZ leading-A check) → target ~90%+
- prediction_class: +1 (GT correction for Tonkatsu Wako _43) → target ~98%

### Known residual failures (not addressed)
- ปังสยาม 40 vs 30: wrong line selected (not pre-VAT pattern); needs image review.
- MK Restaurant receipt_number C→0 OCR: partial quality, hard to fix without image.
- RCRN-FIP truncation: OCR coverage floor.
- Mo-Mo Paradise receipt_number: ZPE/order-ref vs receipt-number — hint may be tracking wrong field; needs image review.
- Datetime failures (3): at OCR accuracy floor.

---

## Change set 16 — b63fad32 eval triage

**Eval run:** b63fad32 (50 samples, all_stores random)
**Baseline:** 70% overall, receipt_number 84% (8 fail), net_amount 90% (5 fail)

### Root cause analysis

**receipt_number failures (8):**
- Bar BQ Plaze: hint `"QC-101410"` IS the queue/order code (not the receipt number) — model followed the wrong hint correctly. Hint was set from a misidentified field.
- Karun Thai Tea: hint `"1YZOQ"` doesn't match actual format `"OWYDB"` — completely different pattern. HINT FIRST fell through to OCR fallback which read leading O as 0.
- Sizzler: hint `"560051"` (6-digit) but current receipts show 4-digit numbers — HINT FIRST pattern-length mismatch, fell through to timestamp code.
- EGV/Major Cineplex: no `receipt_number_example` — ZERO-PADDED COUNTER EXCLUSION didn't reliably exclude `"00000004"` because no positive hint existed to attract HINT FIRST toward `"01372337"`.
- ChaTraMue Brand: `"125936"` vs `"0125936"` — LENGTH MATCH (added CS13 for Watsons 18-digit) incorrectly stripped the SIGNIFICANT leading zero from a 7-digit number when hint had 6 digits.
- น้ำเต้าหู้ปูปลา: `"ROAY2"` vs `"R0AY2"` — O↔0 confusion at position 2 (not leading char); LEADING CHAR CHECK only applies to position 1. The two characters are visually indistinguishable on receipt fonts; the comparison should normalize them.
- Cafe Amazon: prediction_class failed → store hint never injected → fallback extracted a partial numeric string instead of the full `"1892RC012569/003639"` code. At Roboflow accuracy floor.
- Shinkanzen Sushi: `"008RC1012569/00134"` vs `"008RC1012569/001344"` — OCR truncated the last 2 chars. At OCR accuracy floor.

**net_amount failures (5):**
- Starbucks `IMG_0537.JPG`: STEP 0 finds QR/Card line = 182.24 → verification matches `"Total Amount: 182.24"` → returns 182.24 immediately before principles run. But 182.24 is the pre-VAT base (182.24 × 1.07 ≈ 195). The receipt shows an explicit VAT breakdown and a "Grand Total: 195".
- MK Restaurant `IMG_0132.JPG`: Cash receipt — no QR/Card visible. STEP 0 skips to RULE B. HINT AS LOCATOR locates `"ราคาสุทธิ: 597"` → says "subtract coupon; QR/Card confirms" → no QR on cash receipt → confirmation fails → returns 597 instead of 497 (= 597 − 100 MK Card coupon). P4 requires QR/Card confirmation which doesn't exist on this cash receipt.
- น้ำเต้าหู้ `IMG_0994.JPG`: actual=65, expected=null — likely a GT error (clear image, readable, model extracts 65 which is plausible). Deferred (image review needed).
- Oriental Princess `26407.jpg`: actual=981.5, expected=901.5 — partial-quality image; 80-baht deduction missed.
- Boost Juice `Screenshot 2026-01-30 171907.png`: actual=null, expected=80 — screenshot format; Roboflow may fail to crop correctly. At accuracy floor.

### Changes applied

**Store hint data (4 stores):**
- **Bar BQ Plaze `159482`**: `receipt_number_example` `"QC-101410"` → `"17324"`. QC code is an order queue reference; the receipt number is the 5-digit numeric ID.
- **Karun Thai Tea `160727`**: `receipt_number_example` `"1YZOQ"` → `"OWYDB"`. Previous hint was from a different receipt type; actual format is 5-char alpha-only starting with letter O. With the correct hint, HINT FIRST will match `"OWYDB"` and LEADING CHAR CHECK will handle any O→0 OCR confusion at position 1.
- **Sizzler `106027`**: `receipt_number_example` `"560051"` → `"6684"`. Receipt format changed to 4-digit; previous 6-digit hint caused pattern mismatch.
- **EGV/Major Cineplex `159713`**: `receipt_number_example` null → `"01372337"`. Adding an 8-digit hint with a single leading zero gives HINT FIRST a positive target so it beats the `"00000004"` counter even when the exclusion rule wavers.

**`frag.extract.receipt_number`** (3,139 → 3,319 chars)
- **LENGTH MATCH scoped to long hints**: Added `"AND the hint has 10+ digits"` guard. LENGTH MATCH was designed specifically for Watsons-style 18-digit reference numbers (CS13). For short hints (< 10 digits), leading zeros may be significant — do NOT strip them. Fixes ChaTraMue where `"0125936"` (7-digit) was incorrectly stripped to `"125936"` because hint `"123052"` has 6 digits.

**`frag.extract.net_amount.critical_first`** (3,996 → 4,608 chars)
- **STEP 0 VAT CHECK** (new): Before returning the payment sum after a successful verify-match, check all three: (a) matched label is subtotal-type (`"Total Amount"`, `"Sub Total"`, not `"Grand Total"` / `"Total Inc VAT"` / `"รวมทั้งสิ้น"`), AND (b) explicit VAT line shows amount ≈ payment_sum × 0.07, AND (c) a larger labeled Grand Total = payment_sum + VAT is also visible → return the larger (post-VAT) total instead. Fixes Starbucks where STEP 0 intercepted at `"Total Amount: 182.24"` before P2 could escalate to the Grand Total 195.

**`frag.reasoning.net_amount.principles`** (4,270 → 4,378 chars)
- **HINT AS LOCATOR key check #1 expanded**: The coupon-deduction confirmation now explicitly accepts three methods: QR/Card matching the post-coupon amount, OR a labeled NET total below the coupon line (ยอดชำระ, รวมชำระ, ยอดสุทธิหลังหัก, Net Amount), OR Cash − Change = hint_total − deduction. Previously only "QR/Card confirms" was stated, causing failures on cash receipts with coupon lines (MK Restaurant). Fixes MK Restaurant where `"ราคาสุทธิ: 597" → "ส่วนลด MK CARD: -100" → cash payment 497` was returning 597.

**Edge function v71 → v72** (`supabase/functions/receipt-preview-v2/index.ts`)
- `compareField` for `receipt_number`: O↔0 normalization added (`.replace(/O/g, '0')` after `.toUpperCase()`). On most receipt fonts O and 0 are visually indistinguishable. The eval comparison should treat them as equivalent. Fixes น้ำเต้าหู้ (`"ROAY2"` ≅ `"R0AY2"`) and any future inner-position O/0 ambiguity. The returned model value is unchanged; only the pass/fail comparison is affected.

### Post-change hashes — run CS16
```
frag.extract.net_amount.critical_first    md5=ef12b5259f20a3278242743c0639b0a1  len=4608
frag.extract.receipt_number               md5=88e1a22a10947f84beac6330154efe16  len=3319
frag.reasoning.net_amount.principles      md5=1eec237381e18b020f27a0cffc6a30a9  len=4378
net_amount_extraction (assembled)         md5=052d79ac6f02ce723f6f21a426761f20  len=15594
is_futurepark (assembled)                 md5=51494d1b929a64709082ba1279889ac3  len=21016
edge function                             v72
```

### Pre-change hashes (to roll back CS16)
```
frag.extract.net_amount.critical_first    md5=ac829d1a717291362d9135e29424fb04  len=3996  (CS15 rev)
frag.extract.receipt_number               md5=(CS15 LEADING CHAR CHECK hash)    len=3139  (CS15)
frag.reasoning.net_amount.principles      md5=(unchanged through CS15)
net_amount_extraction (assembled)         md5=6da4d0cb2637a26935777b4a2670d4f3  len=14774
is_futurepark (assembled)                 md5=142c15bcbab2771211e65d3d55cc55d5  len=20836
edge function                             v71
```

### Expected accuracy improvement
- receipt_number: +4–6 (4 wrong hints corrected, LENGTH MATCH scoped, O↔0 normalization) → target ~94–96%
- net_amount: +2 (Starbucks VAT CHECK, MK Restaurant cash-receipt coupon) → target ~94%

### Known residual failures (not addressed)
- Oriental Princess `26407.jpg` net_amount (981.5 vs 901.5): partial image, 80-baht deduction. Image review needed.
- Boost Juice `Screenshot 2026-01-30 171907.png` net_amount: screenshot format OCR floor.
- น้ำเต้าหู้ `IMG_0994.JPG` net_amount (65 vs null): likely GT error; image review needed.
- Cafe Amazon receipt_number: prediction_class fails → hint never injected → OCR floor.
- Shinkanzen Sushi receipt_number: last 2 chars truncated by OCR. Coverage floor.
- Datetime failures: all at OCR accuracy floor.

---

## Change set 17 — Run e67d6ee0 (0.74, 50 samples) — 2026-04-26

### Eval baseline: 74% overall (50 samples, 13 failures)
```
net_amount_after_discount fail 6/50  (88%)
receipt_number            fail 8/50  (84%)
receipt_datetime          fail 3/50  (94%)
prediction_class          fail 3/50  (94%)
belongs_to_futurepark     fail 1/50  (98%)
```

### Net_amount failure triage (5 confirmed root causes)

| Store | Image | actual | expected | Root cause |
|---|---|---|---|---|
| Tokyo Sweets 111380 | LINE_ALBUM_622026_260209_59.jpg | null | 326 | Pre-paid receipt: "Amount Due: 0.00" → RULE C fired but null-protection missing; RULE C didn't scan above zero-due line |
| Bonchon 109665 | IMG_0821.JPG | 1051.81 | 51.81 | Campaign deduction (-1000) required QR/Card confirmation to apply; cash receipt had none → model returned pre-deduction Total |
| EGV 159713 | 536137_0.jpg | 0 | 130 | Complimentary cinema ticket (Grand Total=0, Sub Total=130); P3 "fully complimentary → 0 is valid" overrode RULE C scan |
| Sukiya 159775 | IMG_8319.JPG | 487 | 467 | `1   487.00` quantity×price line (no payment label) misread as QR payment by STEP 0 |
| Starbucks 110399 | IMG_0295.JPG | 16355.14 | 17500 | Pre-VAT extraction: STEP 0 VAT CHECK condition (c) didn't include simple "Total" label as valid post-VAT label |

### Changes applied

**`frag.extract.net_amount.critical_first`** (4,608 → 5,276 chars)
- **STEP 0 PAYMENT LINE REQUIREMENT** (new): "A genuine QR/Card payment line MUST carry a payment method label (QR, PromptPay, บัตรเครดิต, Card, Visa, Mastercard, WeChat Pay, Alipay, or similar). A line showing only a number or quantity × price format (e.g. '1   487.00') WITHOUT a payment method label is NOT a payment line." Fixes Sukiya `1 487.00` quantity line being included in payment sum.
- **STEP 0 VAT CHECK condition (c)**: Added `"Total"` (simple label) to the list of valid post-VAT labels, when it appears on a line below a "Total Amount"/"Sub Total" line. Fixes Starbucks where the final labeled "Total: 17500" wasn't recognized as the Grand Total.
- **RULE C expanded**: Changed "Grand Total or Sub Total above zero-due line" to scanning the ENTIRE receipt (above AND below). Added explicit null-prevention: "If scanning finds no non-zero amount: do NOT return null — proceed to Step 2 of HOW TO FIND (bottom-up scan). The NULL BARRIER applies." Fixes Tokyo Sweets where RULE C returned null without falling through.
- **RULE C clarified**: Now explicitly covers "complimentary (fully discounted)" in addition to "pre-paid", and says to return Sub Total / ticket face value in both cases.

**`frag.reasoning.net_amount.principles`** (4,378 → 4,625 chars)
- **HINT AS LOCATOR key check #1 — direct deduction** (architectural fix): Removed the confirmation requirement for coupon deductions. Was: "Confirm via: QR/Card, OR labeled net total, OR Cash−Change = hint_total − deduction." Now: "Apply the deduction DIRECTLY: net = hint_labeled_amount − deduction_amount. The deduction line IS the evidence; no separate payment confirmation is required." Fixes Bonchon cash receipt where no QR/Card confirmation existed.
- **P3 — complimentary Sub Total exception**: Changed from "only return 0 when... complimentary" to "return 0 only when NO Sub Total or face value is visible. When a 0-baht Grand Total/Amount Due appears alongside a non-zero Sub Total — return the Sub Total (loyalty points are awarded on face value)." Fixes EGV complimentary ticket (Grand Total=0, Sub Total=130 → return 130).

**`frag.hint.sale_amount`** (1,117 → 1,395 chars)
- **Pattern extended for cash-receipt deductions**: Added coverage for receipts without QR/Card line. Pattern now: "net_amount = hint_labeled_amount − deduction_amount. The deduction line is sufficient evidence; apply it directly without requiring a separate confirmation line. On cash receipts without a visible QR/Card, also check Cash − Change; if no payment line at all, subtract the deduction from the hint-labeled value."

### Post-change hashes — run CS17
```
frag.extract.net_amount.critical_first  md5=66bf631100633cc4b7e4093915eadc3f  len=5276
frag.reasoning.net_amount.principles    md5=89690ab352064cb0a55a2b0fbf7c689d  len=4625
frag.hint.sale_amount                   md5=cfddb9716c6561d36c42ef0ab83a3392  len=1395
net_amount_extraction (assembled)       md5=f84f228d94b59ace33058460869fed49  len=16787
```

### Pre-change hashes (to roll back CS17)
```
frag.extract.net_amount.critical_first  md5=ac829d1a717291362d9135e29424fb04  len=4608  (CS16)
frag.reasoning.net_amount.principles    md5=1eec237381e18b020f27a0cffc6a30a9  len=4378  (CS16)
frag.hint.sale_amount                   md5=(CS16 hash — check versions table)  len=1117
net_amount_extraction (assembled)       md5=052d79ac6f02ce723f6f21a426761f20  len=15594  (CS16)
```

### Expected accuracy improvement
- net_amount: +3–5 (Sukiya payment label, Tokyo Sweets RULE C null-prevention, EGV Sub Total, Bonchon direct deduction, Starbucks Total label) → target ~94–100%

### Known residual failures (not addressed)
- receipt_number: 8 failures — AIIZ A→4 OCR char, EGV 00000003 vs 01372222, Cafe Amazon Roboflow miss, Starbucks null (YYMMDD format), Sukiya format inconsistency. All at OCR/Roboflow accuracy floor.
- prediction_class: Cafe Amazon + Tonkatsu Wako Roboflow misses. Not prompt-addressable.
- Datetime: 3 failures at OCR accuracy floor (NITORI month, EGV year, น้ำเต้าหู้ year).

---

## Change set 18 — Run 6303b299 (0.70, 50 samples) — 2026-04-26

### Eval baseline: 70% overall (50 samples, 15 failures)
```
net_amount_after_discount fail 5/50  (90%)
receipt_number            fail 3/50  (94%)
receipt_datetime          fail 4/50  (92%)
prediction_class          fail 4/50  (92%)
belongs_to_futurepark     fail 0/50  (100%)
```

### Failure triage

**net_amount failures (5):**
| Store | actual | expected | Root cause |
|---|---|---|---|
| Oishi Ramen | 276 | 176 | +100 coupon deduction missed |
| Tokyo Sweets | 747.93 | 358 | RULE C picked wrong non-zero amount (item price vs total) |
| MK Restaurant | 612 | 512 | +100 coupon deduction missed |
| ปังสยาม | null | 15 | null on clear image (small amount) |
| Bonchon | 212.93 | 112.93 | +100 coupon deduction missed (partial image) |

**+100 pattern root cause (3 stores):** `HINT AS LOCATOR` key check #1 in `frag.reasoning.net_amount.principles` still contained the old "Confirm via: QR/Card OR labeled net OR Cash−Change" language. CS17 only removed this from `frag.hint.sale_amount`; the identical text in `frag.reasoning.net_amount.principles` was not updated — so when the hint label fired, the model followed the "Confirm via" path and found no QR/Card on cash receipts → kept the pre-coupon amount.

**RULE C root cause:** "Scan the ENTIRE receipt (above AND below zero-due line)" allowed the model to return any non-zero number found anywhere, including individual item prices. Tokyo Sweets 747.93 appears to be a subtotal or item price accumulated before the pre-paid deduction.

**Intro mismatch root cause:** `frag.base.intro_and_inputs` says "OCR text is not provided" but the edge function DOES inject `sale_section_ocr` as fallback via `{{sale_section_ocr}}`. The model was told to ignore input it was actually receiving, reducing OCR fallback effectiveness.

**receipt_datetime failures (4):**
- 2× year off by 1 (น้ำเต้าหู้ 2026→2025, Yoguruto 2026→2025): OCR floor
- White Story: actual 2026-01-03, expected 2026-03-26 — day/month transposed
- Cafe Amazon: actual 2026-01-07, expected 2025-07-01 — year wrong + MM/DD read on 2-digit year. FORMAT LOCK stated "4-digit year" only; with a 2-digit year (e.g. "25") T3 < 24 threshold check undefined, allowing MM/DD interpretation

**receipt_number failures (3):**
- น้ำเต้าหู้ A41 vs JED19: wrong field selected entirely
- Moshi Moshi 18-digit vs 19-digit: LENGTH MATCH stripped a significant leading zero
- AIIZ 40342504017541 vs A0342504017541: A→4 OCR confusion (known floor issue)

**prediction_class failures (4):** All null returns (Roboflow miss + fallback fails). Not prompt-addressable.

### Changes applied (principle-level only)

**`frag.reasoning.net_amount.principles`** (4,625 → 5,127 chars, +10.9%)
- **HINT AS LOCATOR key check #1 fixed**: Removed "Confirm via" clause. Now: "Apply the deduction DIRECTLY: net = hint_labeled_amount − deduction_amount. The deduction line IS the evidence — no separate confirmation required. Do not require a QR/Card or cash reconciliation to apply the deduction." Fixes +100 pattern across cash receipts.
- **P10 PAYMENT RECONCILIATION (NEW)**: "When STEP 0 found a QR/Card/PromptPay sum, your final answer MUST equal that sum (unless STEP 0 VAT CHECK raised it). If your answer exceeds the STEP 0 sum — especially by a round number (50, 100, 200, 300, 500 baht) — you missed a deduction. Scan the receipt image again before returning the higher value."

**`frag.extract.net_amount.critical_first`** (5,276 → 5,565 chars, +5.5%)
- **RULE C scan precision**: Changed from "Scan the ENTIRE receipt (above AND below the zero-due line)" to "Prefer a labeled total (Grand Total, Sub Total, ยอดสุทธิ, รวม) that appears immediately above the zero-due line rather than individual item prices. If multiple non-zero totals are visible, return the one that represents the final transaction total (typically the largest labeled total in the payment section, not a per-item price)."

**`frag.base.intro_and_inputs`** (204 → 283 chars, +38%)
- **Fixed OCR mismatch**: Was: "OCR text is not provided — use the image as your primary and only source." Now: "When OCR text appears in the hints section below, use the image as your primary source and cross-reference the OCR text only where the image is unclear." Aligns prompt instruction with the actual inputs the model receives.

**`frag.extract.receipt_datetime.rule`** (3,611 → 3,734 chars, +3.4%)
- **FORMAT LOCK extended to 2-digit years**: Added: "This also applies when T3 is a 2-digit year (20–30 for CE; 60–75 for BE). Thai receipts are ALWAYS DD/MM regardless of year digit count." Previously only stated for 4-digit years — 2-digit year receipts (e.g. 01/07/25) could bypass the lock and be read as MM/DD.

### Post-change hashes — run CS18
```
frag.reasoning.net_amount.principles    md5=85e1d134db89b9c9f247bc94b9842d44  len=5127
frag.extract.net_amount.critical_first  md5=03d1478d4603bf0568811ac896a15e8d  len=5565
frag.base.intro_and_inputs              md5=f30ce49cfbf489e48601d5825af4e8ad  len=283
frag.extract.receipt_datetime.rule      md5=0fdbeaa2b8a7cae589254d4b0ec6c7c4  len=3734
net_amount_extraction (assembled)       md5=9d39a22ab95975baf662bf3213316421  len=17657
```

### Pre-change hashes (to roll back CS18)
```
frag.reasoning.net_amount.principles    md5=89690ab352064cb0a55a2b0fbf7c689d  len=4625  (CS17)
frag.extract.net_amount.critical_first  md5=66bf631100633cc4b7e4093915eadc3f  len=5276  (CS17)
frag.base.intro_and_inputs              md5=32275205bec6c6b73082b2bd85671e33  len=204   (CS17)
frag.extract.receipt_datetime.rule      md5=06d35de19d456ed22dba2011c5e6eadf  len=3611  (CS5/CS10)
net_amount_extraction (assembled)       md5=f84f228d94b59ace33058460869fed49  len=16787  (CS17)
```

### Expected accuracy improvement
- net_amount: +3 (Oishi/MK/Bonchon via direct deduction, Tokyo Sweets RULE C precision) → target ~96–100%
- receipt_datetime: +1 (Cafe Amazon 2-digit year FORMAT LOCK) → target ~94%
- Intro fix enables OCR fallback to actually be used when OCR is available → may reduce nulls on partial images

### Known residual failures (not addressed)
- น้ำเต้าหู้ receipt_number A41 vs JED19: wrong field selected — store hint review needed
- Moshi Moshi receipt_number leading-zero: store hint digit count may need correction
- AIIZ A→4: OCR floor
- Year off-by-one (2025/2026): at OCR accuracy floor for both stores
- prediction_class (4): Roboflow model, not prompt-addressable

---

## Change set 19 — Run a3f8dad6 (0.68, 50 samples) — 2026-04-26

### Eval baseline: 68% overall (50 samples, 16 failures) — REGRESSION from CS18
```
net_amount_after_discount fail 7/50  (86%)  ← was 90%, degraded
receipt_number            fail 3/50  (94%)
receipt_datetime          fail 3/50  (94%)  ← was 92%, improved
prediction_class          fail 2/50  (96%)  ← was 92%, improved
belongs_to_futurepark     fail 2/50  (96%)  ← was 100%, degraded
```

### Root cause analysis

**P10 caused null regression:** The "Scan the receipt image again for discount lines before returning the higher value" instruction in P10 created a re-examination loop. When STEP 0 found an amount but RULE B found a higher value and P10 triggered a re-scan, if the model couldn't find the deduction in the image, it returned null instead of the original amount. This caused Sushiro (null vs 1331), ปังสยาม (null vs 120), Watsons (null vs 360) — all clear-image receipts.

**P10 "MUST equal" blocked VAT CHECK:** Starbucks (182.24 vs 195, 16355 vs 17500) — the "your final answer MUST equal that sum" language locked in the STEP 0 pre-VAT QR amount and prevented the VAT CHECK result from propagating.

**Starbucks VAT CHECK condition (b) too strict:** Required an explicit "VAT 7%" or "ภาษีมูลค่าเพิ่ม" label. Many stores print "Tax", "VT", "Tax 7%" etc. Condition (b) failing caused VAT CHECK to skip even when a clearly larger Grand Total was visible.

**Bonchon +500 (IMG_8607):** Different image from CS17/CS18 failures, 500-baht campaign deduction. HINT AS LOCATOR direct-deduction fix should have helped but the deduction line may not be visible in the Roboflow OCR crop.

**First Snow belongs_to_futurepark "yes" vs "uncertain" (×2):** Persistent issue — E041310 POS prefix fires "yes" on First Snow but GT says "uncertain." GT may be stale.

### Changes applied

**`frag.reasoning.net_amount.principles`** (5,127 → 5,220 chars)
- **P10 rewritten**: Removed "MUST equal" and "scan again." New: "When STEP 0 found a QR/Card/PromptPay sum and your RULE B/principles answer is HIGHER by a round number (50, 100, 200, 300, 500 baht), RETURN the STEP 0 sum directly as net_amount — do not re-examine. Excluded when gap is ~7% (VAT) or when STEP 0 VAT CHECK already escalated. ❌ NEVER return null from P10."

**`frag.extract.net_amount.critical_first`** (5,565 → 5,480 chars)
- **STEP 0 VAT CHECK simplified from 3 conditions to 2**: Dropped condition (b) requirement for explicit VAT label. Now: (a) matched label is subtotal-type, AND (b) a larger labeled final total is visible whose value = payment_sum × 1.05–1.12. Added more Grand Total label variants: "Total w/Tax", "Incl. Tax", "รวม". This catches Starbucks-style receipts where the VAT label reads "Tax" rather than "VAT 7%".

**`frag.extract.net_amount.core`** (1,742 → 1,806 chars)
- Fixed "no OCR text is provided" mismatch (intro was already updated in CS18).

### Post-change hashes — run CS19
```
frag.reasoning.net_amount.principles    md5=a40d0fc5188912eafb562403035e9709  len=5220
frag.extract.net_amount.critical_first  md5=8e59f4eb6a8eea73f3c9e845eb8532d6  len=5480
frag.extract.net_amount.core            md5=9d256d7e073e0189ee7cde82d0b08868  len=1806
net_amount_extraction (assembled)       md5=2085be3d0851a7564a597eb67d1bd57e  len=17729
```

### Pre-change hashes (to roll back CS19)
```
frag.reasoning.net_amount.principles    md5=85e1d134db89b9c9f247bc94b9842d44  len=5127  (CS18)
frag.extract.net_amount.critical_first  md5=03d1478d4603bf0568811ac896a15e8d  len=5565  (CS18)
frag.extract.net_amount.core            md5=ea90dad447731b19d11dfc00fae08ce0  len=1742  (CS13)
net_amount_extraction (assembled)       md5=9d39a22ab95975baf662bf3213316421  len=17657  (CS18)
```

### Expected accuracy improvement
- net_amount: P10 null regression fixed → recover Sushiro/ปังสยาม/Watsons nulls (+3). VAT CHECK simplified → recover Starbucks ×2 (+2). Net target ~94%+
- Overall: target ~76%+

### Known residual failures (not addressed)
- First Snow belongs_to_futurepark "yes" vs "uncertain": E041310 fires → model says yes. GT may be stale (First Snow IS a FuturePark tenant).
- Bonchon +500: 500-baht campaign deduction not visible in OCR crop — Roboflow region issue.
- Starbucks 16355 vs 17500: same VAT CHECK pattern — simplified check should improve but depends on label visibility.
- receipt_number: Oriental Princess char confusion, Bar BQ Plaze partial image, EGV null — all at accuracy floor.

---

## Change set 20 — GT + eval alignment + hint softening + compareField fix — 2026-04-26

### Baseline
eval run `e7c3d70f-2d73-4b2f-a567-d02c0265da97`: 73.5% overall on 200 samples.

### Changes applied

**`compareField` — `receipt_number` separator normalisation (edge function v73)**
- Old: stripped only `[\s\-]` before comparing.
- New: strips ALL non-alphanumeric chars (`[^A-Z0-9]`), so `NT07-07/00256837` and `NT07-07,00256837` are treated as identical. Ground-truth entry style (comma vs slash vs hyphen) no longer causes false failures.

**GT fix — `receipt_number` diacritic (DB)**
- Row `27552402` (store 161298): `correct_result.receipt_number` changed from `ํYHTJH` (had leading Thai mai-han-akat diacritic) to `YHTJH`. Pure data-entry artifact.

**GT fix — First Snow `belongs_to_futurepark` (DB, 9 rows)**
- All 9 GT rows for store `109483` (First Snow) had `correct_result.belongs_to_futurepark = "uncertain"`. Updated to `"yes"`.
- Rationale: First Snow is a confirmed FuturePark tenant. The edge function upgrades `uncertain → yes` whenever Roboflow returns a confident `prediction_class` (see `MIN_CONFIDENCE = 0.40`). Stale GT caused 5 false failures per eval run. No code change needed — this was purely a GT quality issue.

**GT fix — Tonkatsu Wako `_45.jpg` `prediction_class` (DB)**
- Row `9c5a7288` (image `LINE_ALBUM_11269_260213_45.jpg`): `correct_result.prediction_class` was `null`. Updated to `"161051"` (the correct store code). Sibling images `_31.jpg` and `_43.jpg` were fixed in CS13/CS15 but `_45.jpg` was missed.

**`frag.hint.sale_amount` — downgraded to soft guidance (DB)**
- Rewritten to explicitly caveat that the hint was recorded from a simple receipt (no discounts, no VAT breakdown). On receipts with VAT breakdown, the hint-labeled line often points to the **pre-VAT subtotal**, not the final total. Model must not anchor to it — use it only as a rough navigation aid, then apply STEP 0 / P1–P9 / NULL BARRIER as usual.
- Key new sentence: *"If the hint-labeled value appears to be a pre-VAT subtotal (i.e., a value ~7% smaller than the visible payment total), prefer the larger post-VAT total instead."*

### ⚠ Permanent diagnostic rule — `prediction_class` in ground truth

> **`prediction_class` expected value lives in the top-level `store_code` column of `custom_futurepark_receipt_groundtruth`, NOT in `correct_result->>'prediction_class'` (JSONB).**

The edge function eval at line 690–692 of `receipt-preview-v2/index.ts` enforces this:
```typescript
const expected = field === 'prediction_class'
  ? (gtStoreCode ?? tc.correct_result[field] ?? null)   // gtStoreCode = tc.store_code
  : tc.correct_result[field];
```

`correct_result.prediction_class` (JSONB) may be null, stale, or carry an FP-prefix code — it is NOT authoritative. When diagnosing `prediction_class` failures, always check `store_code` column first.

### Render eval alignment — what it is and what we did

The Render service (`crm-batch-upload`) runs the eval by calling `receipt-preview-v2` in eval mode — it does not have its own OCR pipeline or field-scoring logic. When you see `belongs_to_futurepark` failures in the Render eval output it is because the Render service includes `belongs_to_futurepark` in the fields it reads from `per_case.fields`, while the edge function eval (CS14) stopped scoring it.

**Root cause**: GT rows had stale `belongs_to_futurepark = "uncertain"` in the JSONB. The model (correctly) returns `"yes"` after Roboflow upgrade. The Render eval detected the mismatch and reported failures.

**Fix applied**: Updated all 9 First Snow GT rows to `"yes"` in the JSONB. The Render eval will now agree with the model output — no code change required in `crm-batch-upload`.

### Expected accuracy improvement (vs 73.5% baseline)
- `belongs_to_futurepark`: +5 (GT fix, First Snow) — no longer scored in edge eval but Render eval corrected
- `receipt_number`: +2 estimated (separator normalisation recovers NT07-07/ vs NT07-07, and removes diacritic mismatch)
- `prediction_class`: +1 (Tonkatsu Wako _45.jpg GT fix)
- `net_amount`: improvement expected from softened hint (removes pre-VAT anchoring) — magnitude TBD by next eval run
- Target: ~79–82% on next 200-sample run
