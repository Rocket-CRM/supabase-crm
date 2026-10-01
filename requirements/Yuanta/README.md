# Yuanta Securities — proposal & demo assets

| Asset | Purpose |
|---|---|
| `YUANTA_CS_DEMO_CONFIGURATION.md` | Realistic CS platform configuration for demos, UAT scripts, and implementation seeding (AI, AOPs, KB, channels, rules, mock logs). |
| `yuanta-cs-demo-seed.json` | Machine-readable mirror of key config blocks for import tooling / fixtures. |

**Source brief:** `Yuanta-securities-OPTIONAL-MCA-CS-AI--dossier.md` (sales dossier, internal).

**Scope alignment (Phase 1 POC):** LINE OA + web chat; knowledge base TH/EN; AI on FAQ / loyalty / reward ops / non-trade queries; explicit exclusions for trade instructions and regulated complaint scripts until compliance sign-off.

**Active AOPs (brokerage demo, 2026-05-19):** 9 multi-step procedures — loyalty AOPs deactivated. See `YUANTA_CS_DEMO_CONFIGURATION.md` §4 or Procedures admin on `yuanta-demo`. Flagship demo: `account_opening_kyc_status` (11 steps, ~3.9k chars).

**Live merchant (seeded 2026-05-19):** `fe754adc-766b-4553-abda-7bc80dcc9724` — `merchant_master.name` = **Yuanta Demo**, `merchant_code` = `yuanta-demo`.
