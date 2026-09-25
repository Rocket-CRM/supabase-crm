# Knowledge MCP Project Setup Guide

## What The Knowledge MCP Does

The CRM Knowledge MCP gives downstream agents structured product knowledge about the CRM platform. It exposes the internal feature knowledge database through tools such as `search_feature_knowledge`, `get_feature_context`, `get_related_features`, and `get_feature_tree`.

Instead of asking an agent to infer product behavior from scattered docs, the MCP returns typed knowledge blocks for each feature. Those blocks can cover feature purpose, key concepts, configuration references, admin journeys, user experiences, business rules, related features, limitations, testing guidance, and technical implementation pointers.

The important detail is that the same feature can be retrieved from different perspectives. A frontend project should get UI journeys and configuration behavior. A proposal project should get value propositions and scope language. A backend project should get technical flows and implementation constraints. The MCP supports this through filters like `knowledge_types`, `perspectives`, `output_uses`, and `scopes`.

## What Downstream Projects Use It For

Downstream projects use the Knowledge MCP to start work from the correct product context before creating an output. Typical uses include:

- Frontend projects retrieving admin journeys, member experiences, UI rules, and testing guidance before building screens.
- Marketing projects retrieving value propositions, key concepts, and related features before writing public-facing copy.
- Feature research projects retrieving broad product, customer success, and technical context before producing analysis or discovery notes.
- Proposal projects retrieving sales-ready capability descriptions, assumptions, exclusions, and business rules before drafting customer-facing scope.
- Slide generation projects retrieving concise positioning and feature summaries before building decks or talk tracks.
- QA projects retrieving testing guidance, rules, limitations, and journey coverage before writing test plans.
- Backend or implementation projects retrieving technical overviews, implementation objects, flows, constraints, and business rules before coding.
- Customer success projects retrieving setup flows, common scenarios, limitations, and training material before writing enablement docs.

The MCP should be treated as the feature-context layer. It is authoritative for product meaning, rules, journeys, and positioning. It is not the final authority for current local code, API signatures, database columns, or deployed schemas; implementation projects must still verify those details from the target repo or live backend tools.

## How The Knowledge Base Is Structured

The Knowledge MCP organizes CRM product context as a feature hierarchy with typed blocks attached to each feature.

```text
Domain
  Feature
    Sub-feature
      Knowledge blocks
```

Examples:

```text
Loyalty
  Rewards
    Reward Redemption
    Promo Code Management
    Reward Fulfillment

Customer Service
  CS Knowledge Base
    Knowledge Articles
    Custom Answers
    Semantic Search
```

A `feature_slug` identifies the product area to retrieve. A feature can be broad, like `loyalty` or `customer-service`, or specific, like `rewards`, `promo-code-management`, `cs-knowledge-base`, or `semantic-search`.

When `include_children` is `true`, the MCP can return context from the selected feature and its sub-features. This is useful when a task needs the full product area instead of one narrow capability.

### Knowledge Types

Knowledge types describe what kind of information a block contains.

Common values:

- `overview`: what the feature is and why it exists.
- `key_concepts`: important terms, objects, and mental models.
- `value_proposition`: customer-facing benefits and positioning.
- `configuration_reference`: settings, options, and admin configuration concepts.
- `admin_journey`: what admins configure or operate.
- `user_experience`: what members, customers, agents, or end users experience.
- `business_rules`: rules, constraints, eligibility, calculations, and state behavior.
- `related_features`: connected modules, dependencies, or neighboring capabilities.
- `limitations`: known caveats, unsupported cases, or boundaries.
- `testing_guidance`: QA scenarios, edge cases, and validation notes.
- `technical_overview`: high-level technical architecture.
- `implementation_objects`: tables, functions, RPCs, APIs, jobs, or queues to inspect.
- `technical_flow`: backend, integration, or event flow.
- `implementation_constraints`: technical guardrails or constraints.

Frontend example:

```json
{
  "feature_slug": "rewards",
  "knowledge_types": ["configuration_reference", "admin_journey", "user_experience", "business_rules", "testing_guidance"]
}
```

Backend example:

```json
{
  "feature_slug": "rewards",
  "knowledge_types": ["technical_overview", "implementation_objects", "technical_flow", "implementation_constraints", "business_rules"]
}
```

### Perspectives

Perspectives describe the lens the agent should use when reading the feature.

Common values:

- `general`: broad context useful to most tasks.
- `product`: product-management explanation and behavior.
- `marketing`: benefit-led messaging and positioning.
- `sales`: proposal, pitch, and customer-facing scope language.
- `customer_success`: support, onboarding, enablement, and operational usage.
- `frontend`: UI behavior, journeys, configuration surfaces, and user-facing states.
- `technical`: architecture and technical system context.
- `implementation`: build-oriented technical guidance.
- `testing`: QA and acceptance coverage.

The same feature can return different context depending on perspective.

```json
{
  "feature_slug": "cs-knowledge-base",
  "perspectives": ["frontend", "testing", "customer_success"]
}
```

```json
{
  "feature_slug": "cs-knowledge-base",
  "perspectives": ["marketing", "sales", "product"]
}
```

```json
{
  "feature_slug": "cs-knowledge-base",
  "perspectives": ["technical", "implementation", "testing"]
}
```

### Output Uses

Output uses describe what the downstream project is trying to produce.

Common values:

- `agent_context`: general context for an agent before work.
- `frontend_context`: UI and frontend implementation context.
- `qa_testing`: QA, UAT, and regression planning.
- `proposal_content`: proposal-ready content.
- `slide_generation`: deck and presentation content.
- `marketing_content`: website, campaign, or launch copy.
- `product_docs`: product documentation.
- `help_center`: customer-facing help content.
- `training_material`: onboarding or enablement content.
- `implementation_brief`: technical implementation planning.
- `technical_docs`: technical documentation.

### Scopes

Scopes describe which product surface the context belongs to.

Common values:

- `general`: applies across the feature.
- `admin_fe`: admin frontend surfaces.
- `user_fe`: member, customer, agent, or user-facing surfaces.
- `be`: backend logic, database, functions, and services.
- `integration`: external systems, events, sync jobs, and connectors.

In short: `feature_slug` selects the product area, `knowledge_types` select the kind of knowledge, `perspectives` select the lens, `output_uses` select the deliverable, and `scopes` select the product surface.

## Why Project Setup Matters

Every downstream project should make three things explicit:

1. Project identity: what kind of output this project creates.
2. Retrieval contract: which Knowledge MCP filters to use for that output.
3. Feature mapping: how local files, routes, pages, decks, or deliverables map to CRM feature slugs.

Without those three pieces, agents tend to retrieve broad generic context and miss the perspective-specific blocks that were created for frontend, marketing, sales, testing, or implementation work.

## Recommended Project Files

Use this structure in each downstream project:

```text
.cursor/
  rules/
    00-project-identity.mdc
    10-knowledge-mcp-retrieval.mdc
    20-output-quality.mdc

docs/
  ai/
    feature-map.md
    knowledge-mcp-tool-contract.md
    project-boundaries.md
```

### `.cursor/rules/00-project-identity.mdc`

Purpose: define the agent's default perspective.

This rule should answer:

- What type of project is this?
- Who is the audience?
- What outputs are normally created?
- What should the agent optimize for?
- Which Knowledge MCP perspective should be preferred?

Example:

```md
---
description: Defines this project's default AI working identity
alwaysApply: true
---

# Project Identity

This project is a downstream CRM frontend project.

Default agent perspective:
- Build admin and member-facing CRM UI.
- Prioritize feature behavior, configuration flows, user journeys, labels, validation, empty states, and testable UI states.
- Use CRM Knowledge MCP frontend context before feature-specific implementation.
- Treat backend implementation details as pointers only; verify exact API contracts and types in the local codebase before coding.
```

### `.cursor/rules/10-knowledge-mcp-retrieval.mdc`

Purpose: define when and how to call the Knowledge MCP.

```md
---
description: Required CRM Knowledge MCP retrieval workflow
alwaysApply: true
---

# CRM Knowledge MCP Retrieval

Before creating feature-specific output, query the CRM Knowledge MCP.

Workflow:
1. If the feature slug is unknown, call `search_feature_knowledge` with the user's topic and this project's default filters.
2. Pick the best matching `feature_slug`.
3. Call `get_feature_context` with the selected slug and this project's default filters.
4. Use returned blocks as product orientation, constraints, and acceptance guidance.
5. For implementation work, verify exact routes, schemas, RPC signatures, APIs, and source files from live project tools before coding.
```

### `.cursor/rules/20-output-quality.mdc`

Purpose: define how retrieved context should affect the final deliverable.

```md
---
description: Output quality rules for Knowledge MCP informed work
alwaysApply: true
---

# Knowledge-Grounded Output

When Knowledge MCP context is retrieved:
- Preserve business rules and feature limitations.
- Use the vocabulary from the returned feature blocks.
- Do not invent unsupported capabilities.
- Mention assumptions when context is incomplete.
- For code, turn context into behavior and tests, not copied documentation.
- For business deliverables, turn context into audience-specific messaging, not raw technical notes.
```

## Supporting Markdown Docs

### `docs/ai/feature-map.md`

Purpose: map local project concepts to Knowledge MCP feature slugs.

Frontend example:

```md
# Feature Map

| Local Area | Files / Routes | Knowledge MCP Feature Slug |
|---|---|---|
| Rewards admin | `/admin/rewards/**` | `rewards` |
| Promo codes | `/admin/rewards/promo-codes/**` | `promo-code-management` |
| CS knowledge base | `/cs/knowledge/**` | `cs-knowledge-base` |
| AMP workflow builder | `/amp/workflows/**` | `amp-workflows` |
```

Proposal or slide example:

```md
# Feature Map

| Deliverable Section | CRM Feature Slug |
|---|---|
| Loyalty engine | `loyalty` |
| Rewards and redemption | `rewards` |
| Marketing automation | `amp-workflows` |
| Customer service AI | `customer-service` |
| Knowledge base and procedures | `cs-knowledge-base` |
```

### `docs/ai/knowledge-mcp-tool-contract.md`

Purpose: store exact tool argument presets by project type.

```md
# Knowledge MCP Tool Contract

Use `search_feature_knowledge` first when the feature slug is unknown.
Use `get_feature_context` after selecting a feature slug.

All presets should set `include_children: true` unless the task explicitly asks for a narrow sub-feature.
```

### `docs/ai/project-boundaries.md`

Purpose: define what the Knowledge MCP is authoritative for.

```md
# Project Boundaries

Knowledge MCP is authoritative for:
- Feature purpose
- Business rules
- Configuration concepts
- Admin and user journeys
- Testing guidance
- Proposal and marketing positioning

Knowledge MCP is not the final authority for:
- Current API signatures
- Local route names
- Generated TypeScript types
- Current database schema
- Component implementation details

Verify implementation details in the target repo or live backend tools before coding.
```

## Project Type Presets

### Frontend Product Project

Use when building CRM admin UI, member UI, WeWeb pages, React apps, component specs, or UI tests.

```json
{
  "knowledge_types": ["configuration_reference", "admin_journey", "user_experience", "business_rules", "testing_guidance"],
  "perspectives": ["frontend", "testing", "customer_success"],
  "output_uses": ["frontend_context", "qa_testing"],
  "scopes": ["admin_fe", "user_fe", "general"],
  "include_children": true
}
```

Best for page behavior, form fields, validation, admin configuration flows, member experience, empty states, and UI acceptance criteria.

### Marketing Content Project

Use when creating website copy, launch messaging, campaign content, product pages, email copy, or social content.

```json
{
  "knowledge_types": ["overview", "value_proposition", "key_concepts", "related_features", "limitations"],
  "perspectives": ["marketing", "sales", "product"],
  "output_uses": ["marketing_content", "slide_generation", "proposal_content"],
  "scopes": ["general"],
  "include_children": true
}
```

Best for benefit-led messaging, audience positioning, campaign angles, website sections, and competitive framing.

### Feature Research Project

Use when exploring what a feature does, comparing modules, writing product briefs, or preparing discovery notes.

```json
{
  "knowledge_types": ["overview", "key_concepts", "business_rules", "related_features", "limitations", "technical_overview"],
  "perspectives": ["product", "customer_success", "technical"],
  "output_uses": ["agent_context", "product_docs", "training_material"],
  "scopes": ["general", "admin_fe", "user_fe", "be", "integration"],
  "include_children": true
}
```

Best for product discovery, feature comparisons, internal enablement, gap analysis, roadmap input, and support readiness.

### Proposal Project

Use when creating customer proposals, statements of work, solution outlines, or commercial narratives.

```json
{
  "knowledge_types": ["overview", "value_proposition", "key_concepts", "business_rules", "related_features", "limitations"],
  "perspectives": ["sales", "marketing", "product", "customer_success"],
  "output_uses": ["proposal_content", "marketing_content", "product_docs"],
  "scopes": ["general"],
  "include_children": true
}
```

Best for proposal sections, solution scope, customer-facing capability descriptions, assumptions, exclusions, and non-code implementation narratives.

### Slide Generation Project

Use when producing decks, executive summaries, sales slides, training decks, or workshop materials.

```json
{
  "knowledge_types": ["overview", "value_proposition", "key_concepts", "related_features", "limitations"],
  "perspectives": ["marketing", "sales", "product"],
  "output_uses": ["slide_generation", "proposal_content", "training_material"],
  "scopes": ["general"],
  "include_children": true
}
```

Best for slide titles, speaker notes, feature explainers, executive summaries, capability matrices, and training decks.

### QA And Test Planning Project

Use when creating manual test cases, automated test plans, UAT scripts, or regression matrices.

```json
{
  "knowledge_types": ["testing_guidance", "business_rules", "configuration_reference", "admin_journey", "user_experience", "limitations"],
  "perspectives": ["testing", "frontend", "customer_success"],
  "output_uses": ["qa_testing", "frontend_context", "training_material"],
  "scopes": ["general", "admin_fe", "user_fe"],
  "include_children": true
}
```

Best for UAT scenarios, regression cases, edge cases, configuration matrices, and admin/customer journey coverage.

### Backend Or Implementation Project

Use when implementing APIs, database functions, jobs, integrations, or backend services.

```json
{
  "knowledge_types": ["technical_overview", "implementation_objects", "technical_flow", "implementation_constraints", "business_rules", "limitations"],
  "perspectives": ["technical", "implementation", "testing"],
  "output_uses": ["implementation_brief", "technical_docs", "agent_context", "qa_testing"],
  "scopes": ["be", "integration", "general"],
  "include_children": true
}
```

Best for backend implementation briefs, API design, database function planning, integration workflows, constraints, and testable backend behavior.

### Customer Success Or Training Project

Use when creating enablement docs, support playbooks, onboarding content, or help center drafts.

```json
{
  "knowledge_types": ["overview", "key_concepts", "configuration_reference", "admin_journey", "user_experience", "business_rules", "limitations"],
  "perspectives": ["customer_success", "product", "frontend"],
  "output_uses": ["training_material", "help_center", "product_docs"],
  "scopes": ["general", "admin_fe", "user_fe"],
  "include_children": true
}
```

Best for help center articles, admin training, support macros, onboarding guides, and operational playbooks.

## Search Then Context Pattern

When the feature slug is unknown:

```json
{
  "query": "reward promo codes and redemption limits",
  "knowledge_types": ["overview", "business_rules", "configuration_reference"],
  "perspectives": ["frontend", "testing", "customer_success"],
  "output_uses": ["frontend_context", "qa_testing"],
  "scopes": ["admin_fe", "general"],
  "limit": 10
}
```

After selecting a slug:

```json
{
  "feature_slug": "rewards",
  "knowledge_types": ["configuration_reference", "admin_journey", "user_experience", "business_rules", "testing_guidance"],
  "perspectives": ["frontend", "testing", "customer_success"],
  "output_uses": ["frontend_context", "qa_testing"],
  "scopes": ["admin_fe", "user_fe", "general"],
  "include_children": true
}
```

## Retrieval Decision Matrix


| Project Type     | Preferred Perspectives                              | Preferred Knowledge Types                                                                                                       | Preferred Output Uses                                                   | Preferred Scopes                 |
| ---------------- | --------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------- | -------------------------------- |
| Frontend         | `frontend`, `testing`, `customer_success`           | `configuration_reference`, `admin_journey`, `user_experience`, `business_rules`, `testing_guidance`                             | `frontend_context`, `qa_testing`                                        | `admin_fe`, `user_fe`, `general` |
| Marketing        | `marketing`, `sales`, `product`                     | `overview`, `value_proposition`, `key_concepts`, `related_features`, `limitations`                                              | `marketing_content`, `slide_generation`, `proposal_content`             | `general`                        |
| Feature research | `product`, `customer_success`, `technical`          | `overview`, `key_concepts`, `business_rules`, `related_features`, `limitations`, `technical_overview`                           | `agent_context`, `product_docs`, `training_material`                    | all relevant scopes              |
| Proposal         | `sales`, `marketing`, `product`, `customer_success` | `overview`, `value_proposition`, `key_concepts`, `business_rules`, `related_features`, `limitations`                            | `proposal_content`, `marketing_content`, `product_docs`                 | `general`                        |
| Slides           | `marketing`, `sales`, `product`                     | `overview`, `value_proposition`, `key_concepts`, `related_features`, `limitations`                                              | `slide_generation`, `proposal_content`, `training_material`             | `general`                        |
| QA               | `testing`, `frontend`, `customer_success`           | `testing_guidance`, `business_rules`, `configuration_reference`, `admin_journey`, `user_experience`, `limitations`              | `qa_testing`, `frontend_context`, `training_material`                   | `general`, `admin_fe`, `user_fe` |
| Backend          | `technical`, `implementation`, `testing`            | `technical_overview`, `implementation_objects`, `technical_flow`, `implementation_constraints`, `business_rules`, `limitations` | `implementation_brief`, `technical_docs`, `agent_context`, `qa_testing` | `be`, `integration`, `general`   |


## Minimal Setup Checklist

For any new downstream project:

- Add `.cursor/rules/00-project-identity.mdc`.
- Add `.cursor/rules/10-knowledge-mcp-retrieval.mdc`.
- Add `docs/ai/feature-map.md`.
- Add `docs/ai/knowledge-mcp-tool-contract.md`.
- Add `docs/ai/project-boundaries.md`.
- Define default `knowledge_types`, `perspectives`, `output_uses`, and `scopes`.
- Add examples for the project's most common tasks.
- State when local/live verification is required.

## Practical Guidance

Keep Cursor rules short and operational. Put long examples and mapping tables in `docs/ai/*.md`.

Rules should teach the agent how to behave every time. Markdown docs should hold project-specific details that may grow over time.

For example:

- Put "always query Knowledge MCP before feature work" in a rule.
- Put the route-to-feature map in `docs/ai/feature-map.md`.
- Put customer-specific proposal sections in a proposal project's docs.
- Put slide tone, audience, and deck structure in a slide project's docs.

This keeps the agent's behavior stable while letting each downstream project maintain its own mappings and examples.