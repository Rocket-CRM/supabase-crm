# Pricing breakdown scaffold

Use when document group **G2 Pricing breakdown / summary** is included for the run. This is **not** the same as e-GP / portal price entry (`manual`).

## Purpose

A customer-facing (or pack-facing) explanation of **how price is structured** — phases, line items, assumptions, validity — using only commercial facts from Clarify / human Inputs.

## Class

`hybrid` — workflow drafts structure and wording; humans supply numbers, discounts, tax treatment, and validity rules.

## Suggested shape (adapt to buyer forms)

1. **Price summary** — total (state VAT inclusive/exclusive as TOR requires); validity period.
2. **Structure** — how the bid is broken down (phases, modules, licenses, services, warranty).
3. **Line items** — table only with approved figures; `[GAP]` if missing.
4. **Assumptions** — what is in/out of scope commercially (hosting procurement, third-party licenses, travel).
5. **Payment** — only if the **pack** requires commercial terms in this document. Prefer keeping payment % out of the **technical** proposal narrative (see `standard-delivery-timeline-migration.md`).

## Rules

- Do not invent unit prices, totals, or discounts.
- Align totals with whatever will be typed into e-GP / portal when both exist.
- If the bid has no separate pricing narrative (quote only in portal), **omit G2** in `submission-plan.md`.
- Dossier may hold internal margin notes; customer doc must not.

## Outline hooks

- `section_type`: `pricing_breakdown`
- `reads`: Clarify answers / commercial source files in `sources/`
- `late_ai`: yes when numbers arrive after first Produce pass
