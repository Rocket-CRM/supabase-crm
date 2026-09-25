# CRM Knowledge MCP — Downstream Agent Setup

Use when connecting any agent to hosted `crm-knowledge` (v1.1.0+).

## New tool

**`get_product_feature_catalog`** — full `proposal-knowledge/features.md` from Storage (~40K tokens). Same artefact as Rocket Deck proposal generation.

## Copy-paste for Agent MD / Rules

See `.cursor/rules/15-crm-knowledge-mcp.mdc` in Supabase CRM repo for the canonical routing table.

**Default:** `search_semantic` + `get_feature_context` (one slug) or `get_feature_answer_context`.

**Full catalog:** `get_product_feature_catalog` only for entire-catalog / proposal / RFP / cross-domain scope — not per-feature debugging.

## Deploy

1. Deploy `Rocket-CRM/crm-knowledge` v1.1.0+
2. Reload Cursor MCP
3. Smoke `get_product_feature_catalog`

Canon upload: `rocket-internal` → `npx tsx scripts/upload-proposal-guidance.ts`
