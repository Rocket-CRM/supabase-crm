# Sales Feature Copy Principles

Craft for Rocket CRM **catalog** `name` and `summary` (and Thai `name_th` / `summary_th`).

Canonical Views (pricing sheet, features summary) are a **different grain**. Write those with `CANONICAL_VIEW_COPY_PRINCIPLES.md` — do not photocopy these strings into the views.

**Read first:** `CORE_WRITING_PRINCIPLES.md` §6–8. Pair with `workflows/product-feature-catalog/REFERENCE.md` §6 / §6.0.

**Product facts:** CRM Knowledge MCP / live catalog. This file is voice and grain only.

Thai localize: `TRANSLATION_PHILOSOPHY.md` after English would pass a sales meeting.

---

## 1. Job of a catalog row

A salesperson can answer “do you have X?” from the **name**, then understand what it does from the **summary**.

| Field | Job |
|---|---|
| `name` | Short noun phrase a salesperson would say aloud — the capability the buyer is buying, not the admin screen or schema object |
| `summary` | One or two **complete** sales sentences: what you can set up / what members get, optional `such as` / `e.g.` |
| `includes` | Extra examples or “not this” clarifiers; keep the summary short |

This is fuller than a pricing-sheet bullet. It is still sales explanation, not config inventory.

Pattern:

> **[What you can set up / what members get]**[, such as / — e.g. **examples the buyer already recognizes**]

---

## 2. Sales explanation, not config inventory

| Wrong (config object) | Right (sold capability) |
|---|---|
| Store master | Store / outlet directory |
| Tier ladder | Member tiers |
| Burn rate — merchant default | Points-to-discount at checkout |
| Profile field configuration | Profile fields (ongoing). Custom signup form is a different row, under Signup & login |
| Persona-scoped tier ladders | Separate tier ladders by persona |
| Earn page setup | Member Earn page (a screen — not an earn method) |

**Test:** Would a salesperson say this name and summary aloud without then translating it?

Do not bundle two “do you have X?” answers into one name (tags with profile fields; tickets with earn rates).

**Open API** is the integration product (members, purchases, points, redemptions, assets). “Earn via Open API” is one call in that product — do not write the Open API row as if earn-from-own-system were the whole capability.

**Shopify** rows describe a loyalty plugin (orders, widget, checkout burn, member matching), not a generic “storefront integrations” leftover.

---

## 3. Same kind, same row

Keep each row inside its own boundary. Earn **methods** are not the Earn **page**. Lifecycle automations are not earn channels. Tickets are a token type, not an earn-rate dimension.

Mechanism-true examples only — see catalog REFERENCE §6.0. Name dimensions when you claim “advanced.” Cut fluff; do not cut product depth.

---

## 4. Self-check (name + summary)

1. Would a salesperson say this aloud without translating it?
2. Is this one comparable capability?
3. Are examples actions a member or admin actually performs **for this feature**?
4. Did I remove real modes/dimensions while “simplifying”?
5. Is the name a sold capability, or a config object / screen / schema label?
6. Did I glue two buyer questions into one name?

Fail any one → rewrite the catalog row. Do not wait for Canonical Views to launder it.

Canonical Views **rewrite** from these rows. They do not inherit them verbatim.
