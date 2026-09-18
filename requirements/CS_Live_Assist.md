# CS Live Assist

**Human agent augmentation** in **CS Inbox**: knowledge search, resource send, and AI drafts — full copilot sidebar `(mostly planned)`.

Owner surfaces: loyalty-admin **CS Inbox** (thread + content panel)

## Concept

**Suggested reply** — AI draft agent edits before send `(pipeline can propose; dedicated multi-draft UI planned)`.

**Conversation summary** — Escalation bundle on case log / events `(partial via events + AI metadata)`.

**Knowledge assist** — Search articles from content panel with insert-into-reply `(shipped search BFF)`.

**Action suggestion** — One-click tool execution with policy context `(planned)`.

**Translation** — Real-time bilingual compose `(planned)`.

## Rules

- **No auto-send to customer** from copilot without explicit agent action unless merchant enables autonomous AI mode on conversation.
- **Shipped today** — `cs_bff_search_conversation_knowledge`, `cs_bff_search_conversation_resources`, `cs_bff_send_resource`; general reply via `cs_bff_send_message`.
- **Planned RPCs** — Dedicated copilot/stream endpoints on `cs-ai-service` not in registry — do not document as live.
- Translation must not alter policy meaning `(future QA requirement)`.

## Journeys

### Admin journey

| Knob | Effect |
| --- | --- |
| Knowledge quality | Better search hits in panel |
| Autonomous AI vs human mode | Whether drafts auto-send |

| Page | Owning repo | BFF |
| --- | --- | --- |
| **CS Inbox** thread | loyalty-admin | `cs_bff_send_message` |
| Content panel | loyalty-admin | `cs_bff_search_conversation_knowledge`, `cs_bff_search_conversation_resources`, `cs_bff_send_resource` |

1. Open conversation → optional AI draft in composer `(when pipeline/human assist wired)`.
2. Search knowledge or resources → insert or send card.
3. Edit and send final reply.

### Member journey

Receives only agent-approved (or policy-allowed AI) outbound messages.

## System

### Shipped

Inbox `use-content-panel.ts` calls search/send resource BFFs; thread uses standard message BFF. Autonomous AI replies originate from pipeline, not Live Assist namespace.

### Planned (product spec folded — not deployed)

- Multi-suggestion drafts with accept/modify telemetry.
- Sidebar copilot Q&A with citations across articles + past conversations.
- Action suggestion chips tied to `CS_Actions.md` registry.
- Inline translation layer on composer.

Track implementation in `cs-ai-service` + loyalty-admin before moving items to Rules.

### Known gaps

Entire §6 Live Assist from legacy plan remains **roadmap** except knowledge/resource search panel.

## Related

- **CS_Knowledge_Base.md** — Corpus for search.
- **CS_Actions.md** — Future action suggestions.
- **CS_AI_Pipeline.md** — Autonomous draft generation.
- **CS_AI_System.md** — Copilot product framing.
