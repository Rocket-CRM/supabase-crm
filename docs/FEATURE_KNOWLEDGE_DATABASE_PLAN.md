# Feature Knowledge Database Plan

## Goal

Create a shared feature knowledge database that helps downstream agents and projects understand CRM features accurately before creating their own outputs: decks, proposals, marketing copy, frontend journey context, help docs, test cases, or technical briefs.

This is not a database of final marketing copy. It is a structured source of truth for what each feature is, how it works, how users experience it, what rules govern it, what it connects to, and what implementation objects should be checked.

## Implementation Status

Implemented in Supabase with `internal_knowledge`-prefixed database objects.

### Tables

```text
internal_knowledge_feature_items
internal_knowledge_blocks
internal_knowledge_type_templates
```

### Enum Types

```text
internal_knowledge_item_type
internal_knowledge_type
internal_knowledge_perspective
internal_knowledge_output_use
internal_knowledge_scope
```

### Functions

Read functions:

```text
internal_knowledge_get_feature_tree
internal_knowledge_get_feature_context
internal_knowledge_search_feature_knowledge
internal_knowledge_get_related_features
internal_knowledge_list_knowledge_type_templates
```

Edit and authoring functions:

```text
internal_knowledge_create_feature_item
internal_knowledge_update_feature_item
internal_knowledge_create_knowledge_block
internal_knowledge_update_knowledge_block
internal_knowledge_suggest_block_metadata
internal_knowledge_validate_knowledge_block
```

Read functions are granted to `authenticated` and `service_role`. Edit functions are granted to `service_role`.

## Source Inputs

The structure should align with the existing feature guide format in `requirements/feature-docs/`:

- Overview
- Key Concepts
- Configuration Reference
- Admin Journey
- Member/User Experience
- Perspectives for CS, Marketing, and Testers
- Business Rules
- Related Features

The feature knowledge DB should break those guide sections into reusable blocks that can be searched and retrieved by agents.

## Core Concepts

Use two core entities:

1. `internal_knowledge_feature_items`
2. `internal_knowledge_blocks`

`internal_knowledge_feature_items` describe the product hierarchy. `internal_knowledge_blocks` attach reusable explanations to those items.

Example hierarchy:

```text
Loyalty
  Reward
    Reward Redemption
    Reward Groups
    Dynamic Reward Points
  Currency
    Earn Rules
    Wallet Ledger
```

Broad items can have their own blocks, but they should not aggregate every child detail.

Example:

`Reward` can have a high-level overview and value proposition.

`Reward Redemption` should own redemption flow, validation, ledger behavior, and redemption-specific constraints.

Rule:

```text
Put a block on the highest item where it remains accurate, but do not use broad items as summaries of all child details.
```

## Top-Level Module Coverage

Top-level domain records must have their own reusable positioning blocks. These records are not just hierarchy/category nodes; they are the source of truth for section-level outputs such as "Why Loyalty CRM", "Marketing Automation", "Customer Service", and other module-opening slides.

Required v1 top-level records:

```text
loyalty
amp
customer-service
```

Each top-level record should have at least one block for each of these knowledge types:

```text
overview
value_proposition
key_concepts
related_features
limitations
```

These blocks should support the broad retrieval filters used by deck, proposal, and enablement agents:

```text
perspectives: ["marketing", "sales", "product"]
output_uses: ["slide_generation", "proposal_content", "training_material"]
scope: general
```

The purpose is module-level positioning, not child-feature aggregation. For example, the `loyalty` record can explain why loyalty CRM matters, what business outcomes it supports, and how rewards, tiers, missions, currency, referrals, forms, tags/personas, check-in, and purchase transactions relate at a high level. Detailed mechanics still belong on the narrower feature or sub-feature records.

Coverage rule:

```text
If a top-level domain can appear as a section title in a deck, proposal, or training outline, it needs at least overview, value proposition, key concepts, related features, and limitations blocks tagged for slide/proposal/training retrieval.
```

## Table: `internal_knowledge_feature_items`

One table stores domains, features, and sub-features.

### Columns

```text
id
parent_id
slug
name
item_type
description
sort_order
metadata
is_active
created_at
updated_at
```

### `item_type` Values

```text
domain
feature
sub_feature
```

Definitions:

```text
domain
Large product area, e.g. Loyalty, Customer Service, AMP.

feature
Major feature, e.g. Reward, Currency, Purchase Transaction.

sub_feature
Smaller part of a feature, e.g. Reward Redemption, Reward Groups, Dynamic Reward Points.
```

Do not use item types such as `screen`, `configuration`, `integration`, `report`, `data_object`, or `technical_flow` in v1. Those are better represented as knowledge block types or metadata inside the content.

## Table: `internal_knowledge_blocks`

Each block explains one reusable piece of knowledge about a feature item.

### Columns

```text
id
feature_item_id
title
content
content_format
knowledge_type
perspectives
output_uses
scope
source_ref
metadata
is_active
search_vector
created_at
updated_at
```

### Column Notes

```text
feature_item_id
The domain, feature, or sub-feature this block belongs to.

title
Short human-readable title.

content
The actual explanation. V1 stores this as Markdown or plain text, not as one large flat document. Retrieval quality comes from small typed blocks plus metadata filters.

content_format
`markdown` or `plain_text`. Default is `markdown`.

knowledge_type
What kind of knowledge this block contains.

perspectives
Array of lenses this block serves, e.g. marketing, frontend, technical.

output_uses
Array of downstream uses this block supports.

scope
Which system area the block mainly applies to.

source_ref
Optional source pointer, e.g. requirement doc, feature guide section, repo file, or MCP lookup note.

metadata
JSON escape hatch for optional values. Do not overuse in v1.

search_vector
Generated full-text search vector over title and content.
```

No `language` field in v1. All content is English.

No `content_status` field in v1. Keep publishing/review workflow outside the first schema unless it becomes necessary.

## Table: `internal_knowledge_type_templates`

Stores expected content guidance per `knowledge_type`.

### Columns

```text
knowledge_type
expected_content
recommended_scopes
quality_rules
created_at
updated_at
```

## `knowledge_type` Values

Use this final v1 set:

```text
overview
key_concepts
value_proposition
configuration_reference
admin_journey
user_experience
business_rules
related_features
limitations
testing_guidance
technical_overview
implementation_objects
technical_flow
implementation_constraints
```

### Definitions

```text
overview
What the feature is. Short orientation.

key_concepts
Important terms, definitions, and examples.

value_proposition
Problem solved, business value, marketing/sales angle, and outcomes.

configuration_reference
Settings, admin options, required fields, and configurable behavior.

admin_journey
What admin users do in the admin frontend.

user_experience
What members, customers, or end users experience in the user frontend.

business_rules
Rules that govern behavior.

related_features
Other product features this feature connects to.

limitations
What is not supported, risky to promise, constrained, delayed, or conditional.

testing_guidance
Config/input to expected behavior, assertions, status transitions, edge cases, and test notes.

technical_overview
High-level backend or architecture explanation.

implementation_objects
Concrete technical objects: tables, RPCs, database functions, edge functions, triggers, queues, consumers, source files, services, or external systems.

technical_flow
Cross-system, data, event, or async flow. Example: purchase completion to CDC/Kafka to currency processing.

implementation_constraints
Technical gotchas, race conditions, idempotency rules, permission rules, async behavior, and assumptions agents must not make.
```

## `perspectives` Values

```text
general
product
marketing
sales
customer_success
frontend
technical
testing
implementation
```

Use an array because one block can serve more than one perspective.

Example:

```text
perspectives = ["marketing", "sales"]
```

If a block needs too many perspectives, split it into clearer blocks.

## `output_uses` Values

```text
agent_context
slide_generation
proposal_content
marketing_content
frontend_context
product_docs
help_center
training_material
implementation_brief
technical_docs
qa_testing
```

Use an array because one block can support multiple downstream uses.

Example:

```text
output_uses = ["agent_context", "frontend_context", "product_docs"]
```

## `scope` Values

Use one simple scope field instead of separate actor, surface, and test-layer dimensions.

```text
general
admin_fe
user_fe
be
integration
```

Definitions:

```text
general
Not specific to frontend, backend, or integration.

admin_fe
Admin panel behavior, admin journey, admin testing, admin UI context.

user_fe
Member/customer/user-facing frontend behavior and testing.

be
Backend behavior, database functions, RPCs, tables, triggers, edge functions, and service logic.

integration
Cross-system flows, external integrations, Kafka/CDC, queues, consumers, webhooks, and multi-service behavior.
```

Do not separate `database` from `be` in v1. Tables, functions, triggers, and RPCs are backend scope.

Do not separate `customer_fe`, `member_fe`, and `cs_agent_fe` in v1. Use `user_fe` unless a later use case proves a separate scope is needed.

## Examples

### Broad Feature Block

```text
feature_item: Reward
item_type: feature
knowledge_type: overview
perspectives: ["general", "product", "marketing"]
output_uses: ["agent_context", "slide_generation", "product_docs"]
scope: general

Reward lets merchants define benefits that members can redeem using points, eligibility, vouchers, or fulfillment rules.
```

### Narrow Sub-Feature Block

```text
feature_item: Reward Redemption
item_type: sub_feature
knowledge_type: business_rules
perspectives: ["product", "technical", "testing"]
output_uses: ["agent_context", "technical_docs", "qa_testing"]
scope: be

Redemption must validate reward status, schedule, customer eligibility, point balance, redemption limits, inventory, and reward group limits before issuing the benefit.
```

### Testing Block

```text
feature_item: Purchase Transaction
knowledge_type: testing_guidance
perspectives: ["testing"]
output_uses: ["qa_testing", "agent_context"]
scope: be

If status is completed, earn_currency is true, and processing_method is queue, currency should be awarded asynchronously. If status is cancelled, no currency, tier evaluation, or mission progress should occur. Refunds should create debit records instead of mutating the original purchase.
```

### Implementation Objects Block

```text
feature_item: Reward Redemption
knowledge_type: implementation_objects
perspectives: ["technical", "implementation"]
output_uses: ["agent_context", "technical_docs", "implementation_brief"]
scope: be

Relevant objects include reward definition tables, redemption ledger tables, eligibility functions, point calculation functions, redemption RPCs, and redemption detail edge functions. Agents should verify exact table names, function signatures, and return shapes from Supabase MCP before generating implementation-level output.
```

### Technical Flow Block

```text
feature_item: Purchase Transaction
knowledge_type: technical_flow
perspectives: ["technical", "implementation"]
output_uses: ["agent_context", "technical_docs", "implementation_brief"]
scope: integration

Completed purchases write to the purchase ledger. CDC can publish ledger changes through Debezium and Kafka. Downstream consumers or materialized views may process purchase and wallet events for currency, AMP state, and user history. Agents should verify exact topics, consumers, and current architecture from service docs, code, and live MCP tools.
```

## MCP Requirements

The MCP should support both read and edit workflows.

### Read Functions

```text
internal_knowledge_get_feature_tree
internal_knowledge_get_feature_context
internal_knowledge_search_feature_knowledge
internal_knowledge_get_related_features
internal_knowledge_list_knowledge_type_templates
```

### Edit Functions

```text
internal_knowledge_create_feature_item
internal_knowledge_update_feature_item
internal_knowledge_create_knowledge_block
internal_knowledge_update_knowledge_block
internal_knowledge_suggest_block_metadata
internal_knowledge_validate_knowledge_block
```

### Why Edit Mode Matters

Different projects own different context:

- Backend project enriches `technical_overview`, `implementation_objects`, `technical_flow`, `implementation_constraints`, and backend testing guidance.
- Admin FE project enriches `admin_journey`, `configuration_reference`, admin FE testing guidance, and frontend context.
- User FE project enriches `user_experience`, user FE testing guidance, and member journey details.
- Marketing/deck/proposal projects consume the knowledge and may add improved `value_proposition` blocks.

MCP edit mode should guide contributors with templates so blocks stay consistent.

## Knowledge Type Templates

Each `knowledge_type` should have a template that explains expected content.

Example template:

```json
{
  "knowledge_type": "implementation_objects",
  "expected_content": "List concrete technical objects that implement or support the feature: tables, RPCs, database functions, edge functions, triggers, queues, consumers, source files, services, or external systems. Do not include full schemas or payloads unless needed for orientation. Agents should verify exact details from Supabase MCP or code before implementation.",
  "recommended_scopes": ["be", "integration"],
  "quality_rules": [
    "Use concrete object names when known",
    "State when names/signatures must be verified",
    "Do not duplicate full technical documentation"
  ]
}
```

Example template:

```json
{
  "knowledge_type": "testing_guidance",
  "expected_content": "Describe concrete inputs, configuration, expected behavior, edge cases, assertions, and relevant status transitions. Keep it testable. Avoid marketing or broad product explanation.",
  "recommended_scopes": ["admin_fe", "user_fe", "be", "integration"],
  "quality_rules": [
    "Use config/input to expected result format when useful",
    "Include negative cases if behavior is easy to over-assume",
    "Mention status transitions when relevant"
  ]
}
```

## Retrieval Examples

Marketing deck:

```text
feature = Reward
knowledge_type = overview, value_proposition, related_features
perspectives = marketing, sales
output_uses = slide_generation
```

Frontend journey context:

```text
feature = Reward Redemption
knowledge_type = user_experience, business_rules, limitations, testing_guidance
perspectives = frontend, testing
scope = user_fe
output_uses = frontend_context
```

Backend implementation context:

```text
feature = Purchase Transaction
knowledge_type = technical_overview, implementation_objects, technical_flow, implementation_constraints, testing_guidance
perspectives = technical, implementation, testing
scope = be, integration
output_uses = implementation_brief, technical_docs, agent_context
```

## V1 Design Principles

- Keep the schema small.
- Use `metadata` only as an escape hatch.
- Do not model every possible audience, surface, business outcome, or industry in v1.
- Prefer precise blocks over broad blocks with too many tags.
- Do not duplicate live implementation details that Supabase MCP or code MCP can verify.
- Store intent, rules, journeys, relationships, constraints, and pointers to implementation objects.
- Let downstream agents retrieve context, then verify exact technical details from live tools before producing implementation-level output.

