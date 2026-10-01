# <Feature name>

<One-line scope: what this feature is for, in this product.>

Owner surfaces: <e.g. loyalty-admin, loyalty-user, Shopify storefront>

## Concept

<!-- Depth: A new PM understands it in two minutes. Purpose (2–4 sentences). The 5–10 nouns with one-line definitions and how they relate. Shipped-status inline as (beta) / (planned) on the capability it qualifies. No identifiers (no table/function names). -->

## Rules

<!-- Depth: Every rule is testable: condition → outcome. State models fully enumerated: all values, valid transitions, dependence between tracks, member-facing label per state. Limits, precedence, edge cases. One example only where the rule is non-obvious. -->

## Journeys

### Admin journey

<!-- Depth: Open with a settings table (knob → effect on behaviour), then numbered steps by page name. Head with a small map: page → owning repo → BFF/RPC (route optional). Steps never restate a rule — they reference its effect. -->

### Member journey

<!-- Depth: Numbered steps with every human-visible state including errors. Head with a small map: page → owning repo → BFF/RPC (route optional). -->

<!-- ### Shopify
     Surface delta only: what differs / is absent / is added vs the journeys above. Omit this subsection if nothing differs. Typical: checkout, storefront, embedded-admin steps.
-->

## System

### Data model

<!-- Depth: Every table a change would touch — named with its role. Roles and flows, not signatures or bodies. -->

### Functions

<!-- Depth: Every function / trigger a change would touch — named with its role. -->

### Flows

<!-- Depth: Sync path, async path, external calls, caches. -->

### External services

<!-- Depth: Render / Inngest / edge fns a change would touch — named with its role. -->

### Known gaps

<!-- Depth: Unshipped or incomplete behaviour. Prefer (planned) / (beta) on the capability in Concept; list residual gaps here. -->

<!-- ### Shopify
     Surface delta only: webhook path, rewarding-shopify calls, credential lookup. Omit if nothing differs.
-->

## Related

<!-- Depth: 3–6 lines. Domain → one-sentence coupling. Routing only. -->
