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

## What landed (DB only, no service code change yet)

All of these are idempotent `INSERT ... ON CONFLICT UPDATE` rows.

| prompt_key                                | role                          | len (chars) |
|-------------------------------------------|-------------------------------|-------------|
| `__editing_principles__`                  | meta, read before every edit  | 3,800       |
| `__compose.net_amount_extraction__`       | JSON array of fragment keys   | 223         |
| `frag.base.intro_and_inputs`              | role + INPUTS                 | 254         |
| `frag.reasoning.net_amount.principles`    | P1-P7                         | 2,155       |
| `frag.base.ocr_first_method`              | OCR-first method              | 1,107       |
| `frag.extract.net_amount.core`            | net amount selection rules    | 2,343       |
| `frag.extract.sale_fields`                | field defs + vouchers + patterns | 7,785    |
| `frag.reasoning.net_amount.sanity`        | sanity checklist              | 1,539       |
| `frag.base.output_format`                 | closing + return JSON         | 610         |

Bitwise equivalence was verified in-DB:

```
assembled_len = legacy_len = 15805
assembled_hash = legacy_hash = d4ee6f34d6801e2951daa2a01e34c08a
bitwise_equal = true
```

The legacy `net_amount_extraction` row is **unchanged** by this migration.
The OCR service continues to read from it and sees byte-identical content.

`is_futurepark` (21.7k chars) is NOT yet fragmented. That is a follow-up.

## What the service needs to do (Render deployment, not in this repo)

Replace the direct read with a `loadPrompt(key)` helper that prefers the
compose row:

```ts
async function loadPrompt(key: string): Promise<string> {
  const composeKey = `__compose.${key}__`;
  const composeRow = await db.selectOne(
    "SELECT prompt_text FROM custom_futureparkocrprompts WHERE prompt_key = $1",
    [composeKey]
  );

  if (!composeRow) {
    // backward-compat: monolithic prompt still the source
    const legacy = await db.selectOne(
      "SELECT prompt_text FROM custom_futureparkocrprompts WHERE prompt_key = $1",
      [key]
    );
    if (!legacy) throw new Error(`Prompt not found: ${key}`);
    return legacy.prompt_text;
  }

  const fragmentKeys: string[] = JSON.parse(composeRow.prompt_text);
  const fragments = await db.selectMany(
    "SELECT prompt_key, prompt_text FROM custom_futureparkocrprompts WHERE prompt_key = ANY($1)",
    [fragmentKeys]
  );
  const byKey = new Map(fragments.map(f => [f.prompt_key, f.prompt_text]));
  const missing = fragmentKeys.filter(k => !byKey.has(k));
  if (missing.length > 0) {
    throw new Error(`Missing fragments for ${key}: ${missing.join(", ")}`);
  }
  return fragmentKeys.map(k => byKey.get(k)!).join("\n\n");
}
```

Verification checklist for the deploy:

1. Before rollout, assert `loadPrompt("net_amount_extraction")` returns a
   string of length `15805`.
2. After rollout, run the eval harness on the baseline set and confirm
   accuracy metrics are unchanged (must be, since content is byte-identical).
3. Only then start landing content-level edits to individual `frag.*` rows.

## Editing workflow going forward

**Phase A (current, until service is updated):**

1. Read `__editing_principles__` from the DB. Apply E1-E8.
2. Edit the relevant `frag.*` row(s).
3. Re-assemble fragments into `net_amount_extraction`:

   ```sql
   WITH compose AS (
     SELECT prompt_text::jsonb AS keys
     FROM custom_futureparkocrprompts
     WHERE prompt_key = '__compose.net_amount_extraction__'
   ),
   assembled AS (
     SELECT string_agg(f.prompt_text, E'\n\n' ORDER BY ord) AS text
     FROM compose c
     CROSS JOIN LATERAL generate_series(0, jsonb_array_length(c.keys)-1) AS ord
     JOIN custom_futureparkocrprompts f ON f.prompt_key = (c.keys->>ord)::text
   )
   UPDATE custom_futureparkocrprompts
   SET prompt_text = (SELECT text FROM assembled), updated_at = NOW()
   WHERE prompt_key = 'net_amount_extraction';
   ```
4. Re-run eval. Record hash before + after for rollback.

**Phase B (after service update):**

Steps 1-2 and 4 only. The legacy-row sync is no longer needed; the service
assembles on read.

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

## Follow-ups queued (not done in this migration)

1. Deploy the `loadPrompt()` change on the Render OCR service.
2. Decompose `is_futurepark` into fragments.
3. `frag.extract.sale_fields` is 7,785 chars — close to the E7 8k ceiling.
   Split it into `frag.extract.voucher_rules`, `frag.extract.vat_patterns`,
   and `frag.extract.misc_patterns` on the next touch.
4. Apply the three diagnosed content fixes (queued; do not apply until
   phase 1 is validated on eval):
   - **P3 softening** — allow 0 when receipt explicitly shows zero total.
   - **Multi-receipt rule** — ignore secondary overlapping receipts in one
     image.
   - **Voucher section consolidation** — E4 says the voucher rules are
     stated in three places (`frag.extract.net_amount.core` step 2,
     `frag.extract.sale_fields`, and `frag.reasoning.net_amount.sanity` #2).
     Pick one canonical location.
