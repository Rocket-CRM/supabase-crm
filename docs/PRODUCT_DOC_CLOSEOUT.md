# Product documentation closeout

This contract applies after an approved, behavior-affecting change ships in a thread.
It defines the shared product-documentation obligation; each workspace decides how to invoke it.

## Canonical sink

- Product behavior belongs in the canonical CRM requirements repository.
- Write to the relevant `requirements/<Domain>.md`, required registries, and `requirements/CHANGELOG.md`.
- Do not create a parallel product wiki in an implementation or orchestration workspace.
- Never write legacy feature-doc collections or hand-edit the deprecated function index.

## Once per thread

- Run one closeout pass for the approved change set before the thread ends.
- Append at most one changelog bullet for that change set.
- If closeout already ran in the thread, skip it rather than duplicating documentation.

## Required routing

- Follow `.cursor/rules/06-update-docs.mdc` for affected documents, registries, and changelog routing.
- Put product nouns or shipped status in **Concept**.
- Put guarantees, limits, states, and edge cases in **Rules**.
- Put admin or member-visible behavior in **Journeys**.
- Put tables, functions, services, queues, triggers, caches, and flows in **System**.
- Use `### <Surface>` only when behavior differs on that surface.

## Domain resolution

- Resolve the domain through the canonical domain index and CRM Knowledge search.
- If no existing domain clearly owns the change, do not create a domain document or index row.
- Stop closeout and report `DOMAIN GAP` with:
  - the suggested domain document name;
  - routing keywords;
  - the behavior that changed.
- Resume only after the product owner approves the new domain.

## Shopify split

- Shopify platform plumbing belongs in the Shopify domain: OAuth, webhooks, billing, proxy shell, entitlements, and app packaging.
- Feature-specific storefront or embedded-admin behavior belongs in that feature's domain as delta-only `### Shopify` content.
- Marketplace or order-to-points behavior belongs in the ecommerce integration domain when that domain owns the flow.

## Out of scope

- Execute closeout does not update the product catalog, Product Narrative, or commercial sales views.
- Those artifacts follow their own reconcile and review cadence.
