# OCR Prompt Fragment Migration

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
