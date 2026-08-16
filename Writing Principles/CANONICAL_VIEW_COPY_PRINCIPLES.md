# Canonical View Copy Principles

Craft for the **jump** from Product Feature Catalog (+ optional Product Narrative) into Rocket CRM’s commercial Canonical Views: the pricing sheet and the features summary.

This is **not** catalog writing and **not** proposal writing.

**Read first:** `CORE_WRITING_PRINCIPLES.md` §6–8. Catalog name/summary craft stays in `workflows/product-feature-catalog/REFERENCE.md` §6 and `SALES_FEATURE_COPY_PRINCIPLES.md`.

**Do not load:** `PROPOSAL_WRITING_PRINCIPLES.md` or proposal scaffolds. Those produce long-form walkthroughs. These views are shorthand.

**Product facts:** live catalog is required fuel. `docs/PRODUCT_NARRATIVE.md` is optional color — never paste a narrative section into a view.

**Workflow:** `workflows/canonical-views/REFERENCE.md` must load this file before writing or refreshing either baseline.

Thai is a later localize pass (`TRANSLATION_PHILOSOPHY.md`). Write English until a salesperson would say it in one breath.

---

## 1. What this jump is for

The catalog is the inventory. These views are **written from** it. They must not reprint it.

| Surface | Job | Grain | How it is written |
|---|---|---|---|
| Catalog `name` / `summary` | Comparable capability | 1–2 complete sales sentences | Catalog workflow — not this file |
| **Features summary** | RFP / competitor coverage | **Every** active feature, one scannable sales line | Non-deterministic rewrite |
| **Pricing sheet** | Quote-shaped SKU highlights | One sales line per **program area** inside a billable unit | Non-deterministic cluster + rewrite |
| HTML / PDF | Layout | Same MD structure | Deterministic script — no LLM |

Pattern for a **pricing-sheet** line:

> **Keyword** rest of the sales sentence

Keyword first, **bold** (normal capitalization — not all caps), then the description on the same line. Example:

> **Member tiers** with configurable conditions for upgrade and maintenance

Features summary keeps name on one line and the sentence under it (checklist grain). Pricing sheet is one line: keyword then description.

Shorter than the catalog summary. Same sales intent. One breath.

---

## 2. Fuel and agency

| Input | Role |
|---|---|
| Live catalog (keys, `commercial_nature`, name, summary, group) | Required inventory. Feature identity comes from here. Pricing-sheet **sections** = modules; **rows** = plan grouping and/or fee model (`workflows/canonical-views/REFERENCE.md` §3.1 / §4). |
| Product Narrative | Optional. Use only when a catalog summary is thin and the view line needs a concrete example. Do not copy narrative blocks. |
| Current view markdown | Diff target. Rewrite affected sections; leave unrelated SKUs/groups. |

**Human-quality sentences. Deterministic structure.**

- **Deterministic:** which rows exist, which `billable_unit_key` / `feature_group_key`, blank prices, HTML export.
- **Non-deterministic:** the words. Cluster by buyer question, then write shorthand. Never concatenate catalog `name` fields.

HTML export stays a script. Copy is not a script.

---

## 3. Features summary (coverage, still shorthand)

- One bullet per active catalog feature, **except** the omit/fold list. Do not drop a feature to look tidy.
- **Name** may be a light sales label (still the same feature). **Line under it** is one shorthand sentence — not the catalog paragraph reprinted, not `includes` dumped as sub-bullets.
- Put one proof example in the sentence when the buyer needs it (`such as birthday points`, `e.g. double points on skincare`). Extra catalog `includes` stay in the catalog.
- Group headings keep `feature_group_key`. Display titles may be slightly more sales-facing than the catalog group name (`Multi-step workflows` not `Deterministic multi-step workflows`).
- **Admin portal and reports** sits after the member-journey groups (and Member app UI CMS). Fold PDPA, languages, and Customer 360 into that row: PDPA and languages in the admin **config** list; Member 360 as a **key area** next to Members, Redemptions, Transactions, Campaigns. Do not give PDPA or languages their own features-summary bullets. **Front Line** is its own group (store-staff lookup and assisted actions) — not paired with Customer 360.
- If a catalog **name** is still a config object, write a sales label in the view **and** flag the catalog row. Do not launder jargon only here forever.

Wrong (photocopy):

> **Tickets (non-fungible tokens)**  
> Tickets are non-fungible token balances: each ticket type is separate and cannot be mixed with another type or with points.

Right (shorthand):

> **Tickets**  
> Separate token types such as raffle tickets or parking passes — not mixed with points.

---

## 4. Pricing sheet (cluster, then one line)

Sparse = fewer complete sales lines, not a denser dump of labels.

### Order (Loyalty Core)

Member **journey** first, then operator surfaces, then backend. Do not follow catalog group sort order.

1. Sign up  
2. Points  
3. Earn channels (including receipt upload)  
4. Rewards  
5. Burn (points-to-discount)  
6. Member tiers  
7. Personas and tags  
8. Admin portal  
9. Front Line (immediately under admin)  
10. Reports  

Lifecycle automations sit in the journey (after personas) and are **Core** (including anniversary and tier-change). **Member app UI CMS** sits with operator surfaces, just before admin. Customer import folds into **Admin portal**. Tickets and event promo are omitted from views.

### Format

```markdown
- **Keyword** description that a salesperson would say
```

The exporter prints the keyword bold. Do not write a comma-joined catalog-name list.

**Notes / PS** are a different kind. Do not write them as `- **Keyword** …`. After the feature bullets, add a whole-line italic:

```markdown
*One campaign unit = one campaign type enabled for the month — Mission, Referral, Check-in, Spin wheel, or Lucky draw*
```

Use notes for definitions, included quotas, and packaging (“this price covers 10 workflows”). The exporter renders italics without the `·` feature marker.

### Altitude — what is allowed to share a line

**Right altitude beats “one catalog row per line.”** The pricing sheet is program-area grain. Catalog rows that are platform plumbing fold into the parent area.

| Fold into | Do not give its own Core line |
|---|---|
| **Admin portal** | Privacy consent (PDPA), multiple languages, admin users & permissions |
| **Sign up** | Custom signup form, profile completion, own-site signup |
| **Member app UI CMS** | Homepage blocks, menus, banners — say **CMS / UI**, not only “layout” |

This is **not** the same as gluing unrelated program areas (rewards + burn, store directory + Customer 360, earn rates + tickets). Those stay split.

The 2026-08-13 sheet split PDPA and languages out of admin because “one buyer-recognizable capability per line” was applied at **catalog** grain. At **pricing-sheet** grain that over-promotes supporting details. The principle that wins here is **right altitude** (this section) plus **journey-first order** (horizontal logic: one dimension = member journey, then operator, then backend).

### Clustering steps

1. List catalog features in this billable unit (inventory — not copy).
2. Cluster by **buyer question** at program-area altitude, not group sort order.
3. Drop the wrong kind for that cluster (Earn page is not an earn method; store directory is not Front Line).
4. Write **one** `**Keyword** description` line per cluster.
5. Sort Core by the journey list above. Front Line is Core, one line below admin.
6. Respect commercial grain: Core **earn methods** on the Core row (purchase sync, marketplace, QR/code, **receipt upload**, manual adjust). Receipt **AI / OCR** and **Open API** are Loyalty **rows** (fee model), not extra modules. **Shopify** is its own module. Do not give stored value a row until it is GA.
7. **Section = module.** Split **rows** by plan grouping (Core / Advanced) and/or fee model. Marketing Automation: Workflows + AI rows. Customer Service: Software + AI Customer Service Agent. Phone numbers omitted from the sheet. Never title a CS row “Advanced.”
8. Run §7.

Typed lists stay one kind:

| Kind | In the list | Not in the list |
|---|---|---|
| Earn methods | Purchase sync, marketplace, QR/code, receipt upload, manual adjust | Earn page, missions, birthday, Open API (own product), Receipt AI (own meter) |
| Program areas | Tiers, rewards, campaigns, reports | `maintain mode`, `tier windows` |
| Staff surfaces | Admin portal, Front Line | Store / outlet directory. Member 360 is an admin area, not a Front Line title. |

`&` / `;` is a smell unless the two words are one capability (“Reward catalog and redemption”).

---

## 5. Worked pricing-sheet clusters (Loyalty) — regression set

| Shipped (wrong) | Intended |
|---|---|
| Member app layout and admin / PDPA / languages | **Member app UI CMS** configure the member-facing UI. **Admin portal** including PDPA, languages, reward codes, tier earn rates, space settings, and customer import — not their own lines. |
| Earn channels: … earn page | Core methods on Core including receipt upload. Earn page out. Open API is its own product (not an earn-method line). |
| Reward catalog & redeem; default burn rate | Reward catalog and redemption. Points-to-discount at checkout. |
| Tier ladder, upgrade conditions, maintain mode | **Member tiers** with configurable conditions for upgrade and maintenance |
| Profile fields & custom fields; tags & personas | Custom signup form (with signup). Tags and personas (own line). |
| Signup & birthday lifecycle automations | Lifecycle automations — birthday, signup, anniversary, and tier-change — all on Core. Not a separate Advanced SKU. |
| Store master; Customer 360 / Front Line | **Admin portal** … Member 360 is a key admin area. **Front Line** store-staff lookup and assisted actions — Core, immediately under admin. Not the store directory. |
| Loyalty analytics reports | 30+ reports in the standard admin portal. Key areas: Members, Member 360, Redemptions, Transactions, Campaigns |
| Advanced earn rates, multipliers, tickets | Advanced earn: different rate per channel / store group / category and/or multipliers (e.g. 2× category or member type). Tickets: omit from views. |
| Per-tier burn; tier windows, per-tier earn benefits, persona-scoped ladders | Advanced tier rules — different earn and burn by tier, evaluation windows, and separate ladders by persona |
| Open API including earning points from your own systems | **Open API** members, purchases, points, redemptions, and assets — earn-from-own-system is one of those calls, not the product. Loyalty **row**, not a section. |
| Shopify widget + Shopify burn | **Shopify** module: order earn, storefront widget, checkout burn, member matching |
| Stored value as its own section | Omit until GA — it is a Loyalty capability, not a module |
| MA Workflows section + MA AI section | One **Marketing Automation** module; Workflows and AI are **rows** |
| CS Core / CS Advanced / Phone numbers as sections | One **Customer Service** module; Software and AI Customer Service Agent are **rows**. Phone omitted from the sheet. |

---

## 6. Automation write step

When catalog identity changed (`commercial_nature`, groups, active set, names/summaries that fuel a view):

1. Load this file + CORE §6–8 + `workflows/canonical-views/REFERENCE.md`.
2. Read affected catalog rows (and narrative sections only if needed).
3. Rewrite affected **pricing** bullets and **features-summary** lines in the EN baselines. Do not run the JSON flatten as the published voice.
4. Keep Price as `—`. Do not touch `runs/`.
5. Coverage check: every **GA** active feature still has a features-summary line **except** the omit list in `workflows/canonical-views/REFERENCE.md` (tickets, event promo; store attributes folded into earn rates). Every §4 billable unit still exists. Omit `planned` / not-launched rows from the pricing sheet.
6. Self-check §7. Report clusters rewritten and any catalog names that should be fixed upstream.

The JSON dump script may be used as a **coverage inventory** (keys present/missing). It must not overwrite view copy.

---

## 7. Self-check (every view line)

1. Would a salesperson say this in one breath without then translating it?
2. Shorter than the catalog summary — not a reprint, not a proposal paragraph?
3. Pricing: one program area (or one typed list)? Features summary: one feature?
4. Same kind as its peers? Earn page not inside earn methods?
5. No config object (`store master`, `maintain mode`, `tier windows`, bare `burn rate`)?
6. No two “do you have X?” answers glued with `&` / `;`?
7. Coverage claims proven with examples the buyer already knows?
8. Catalog `name` fields concatenated? If yes, it is not written yet.
9. Pricing: keyword first (`**Keyword**` bold, not all caps) then description on the same line?
10. Core bullets in journey order (signup → points → earn → rewards → burn → tiers → personas → admin → front line → reports), backend last?

Fail any one → rewrite.
