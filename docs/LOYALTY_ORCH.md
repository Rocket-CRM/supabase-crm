# Loyalty orchestration (hub-lite)

Compact coordination for core loyalty eng. Product narrative stays in Knowledge; live signatures in Supabase MCP; volatile routes/components in local FE clones.

Agents: load rocket-eng `41-orch-loyalty` first, then this file, then the owning repo `AGENTS.md`.

## Surfaces

| Surface | Local folder |
|---------|--------------|
| Admin UI (Front Line, Customer 360, Content Library, settings) | `~/Documents/rocket/loyalty-admin` |
| Member UI | `~/Documents/rocket/loyalty-user` |
| Product rules | Knowledge MCP |
| Live RPC / schema / Edge | Supabase MCP `wkevmsedchftztoolkmi` |
| Registries / domain docs | this repo (`supabase-crm`) |

## Task → read order

| Task | Order |
|------|-------|
| Content Library / resource blocks / LINE flex / card images | `loyalty-admin` `content-library` paths → call site → MCP if named RPC |
| Front Line / tier progress / manual ops | `loyalty-admin` Front Line route → Knowledge only for product rules |
| Customer 360 admin | `loyalty-admin` C360 / customer routes |
| Member rewards / missions / screens | `loyalty-user` → Knowledge for rules → MCP after named RPC |
| Tier / currency / earn (product) | Knowledge → FE call site → MCP |
| Outbound LINE/SMS/email **transport** | `messaging-service` (not admin editor UI) |

## Repo entry points

- Admin: `~/Documents/rocket/loyalty-admin/AGENTS.md`
- Member: `~/Documents/rocket/loyalty-user/AGENTS.md`

## Deferrals

| Signal | Pack / hub |
|--------|------------|
| Receipt upload / OCR / eval | `40-orch-futurepark` |
| CS inbox / procedures | `44-orch-cs` |
| AMP workflow / audience / campaign | `45-orch-amp` |
| Shopify widget / app proxy | `rewarding-shopify` hub |

## Banned shortcuts

- Do not open `messaging-service` for Content Library editor bugs.
- Do not treat AMP orchestrator workspace as AMP ownership for loyalty admin UI.
- Legacy WeWeb is historical only.
