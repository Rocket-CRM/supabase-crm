# Principles for AI-Optimized Project Rules, Indexes, and Self-Maintaining Knowledge

A practical guide for structuring `.cursor/rules/`, project documentation, indexes, and self-maintenance loops so that AI agents can orient themselves on any project with minimal user prompting — without burning excessive tokens.

Derived from real-world optimization across 4 production repos (backend/Supabase, Next.js admin, Next.js user app, UI component library) totaling 50+ rules, 11 skills, and 200+ project docs.

---

## Part 1: The Architecture

### 1.1 The Three Layers

Every project needs three layers of agent context. Each layer is progressively more detailed and more expensive to load.

| Layer | What it is | When it loads | Token cost |
|---|---|---|---|
| **Always-on** | Project identity, domain router, guardrails | Every turn of every thread | High — multiplied by turn count |
| **On-demand rules** | Conventions, patterns, templates, workflows | When agent reads them (triggered by description match or glob) | Medium — loaded once or twice per thread |
| **Deep docs** | Full requirement specs, component docs, business rules | When agent reads specific sections | Low — loaded only when truly needed |

The key insight: **Layer 1 is a tax on every turn. Layer 2 is a tax per read. Layer 3 is a tax only when you need it.** Most rule systems fail by putting too much in Layer 1.

### 1.2 Layer 1 — The Always-On Rules

These files have `alwaysApply: true`. Their full content is injected into every turn's system prompt. They are the most expensive text in your project.

**What belongs in Layer 1:**
- Project identity (what this is, tech stack, key IDs/URLs — 5-10 lines)
- Domain router (keyword → domain mapping so the agent knows WHERE to look — compact table)
- Lookup procedure (HOW to find context — steps, not content)
- Guardrails (what NOT to do without approval — list format)
- One-line pointers to Layer 2 rules ("after changes, read `update-docs.mdc`")

**What does NOT belong in Layer 1:**
- SQL templates, code patterns, code examples (put in Layer 2)
- Detailed conventions (naming, auth, DB patterns — Layer 2)
- Procedure re-explanations (say it once, not twice)
- Post-action rules (doc updates, deployment checklists — Layer 2, triggered by pointer)
- Tables with >5 rows of examples (illustrate the principle briefly, put the full reference in Layer 2)

**Budget:** Total always-on text should be under **6KB** (~1,500 tokens). If you're over 10KB, you're almost certainly duplicating content or inlining reference material.

### 1.3 Layer 2 — On-Demand Rules

These files have `alwaysApply: false` with a clear `description` field. The description appears in the system prompt (lightweight), and the agent reads the full file only when relevant.

**Descriptions are critical.** The description is the agent's only clue about whether to read this file. Write descriptions that answer: "When would an agent need this?"

| Good description | Bad description |
|---|---|
| "Function conventions for writing DB functions. Covers: naming, BFF skeleton, upsert/get patterns." | "Function conventions" |
| "After making approved changes, update corresponding docs. Read before closing any task that made changes." | "Documentation rules" |
| "SQL templates and workflow examples for the Context Lookup Procedure." | "Context lookup" |

**Use `globs` when a rule is file-type specific.** A rule about React component conventions should trigger on `src/**/*.tsx`, not on every turn. A rule about writing feature guides should trigger on `requirements/feature-docs/*.md`.

### 1.4 Layer 3 — Deep Project Docs

These are markdown files in your repo (e.g., `requirements/`, `ProjectDocs/`, `docs/`). They are never loaded automatically — the agent reads them via tool calls, using offset + limit for large files.

**The critical pattern: indexes.**

Never expect the agent to discover docs by browsing the filesystem. Create index files that map domains → doc paths → line ranges → summaries:

```
## Currency & Wallet
- **Source doc:** `Currency.md` (lines 1-480)
- **Tables:** wallet_ledger, user_wallet, wallet_transaction
- **Key functions:** chokepoint_post_wallet_transaction (Backend), bff_get_wallet_balance (BFF)
- **Key rules:** Points are always integers. Negative balance not allowed.
```

The index serves as Layer 1's routing table: the always-on rule says "read the relevant section of INDEX_DOMAIN.md," and the index gives just enough context to proceed — or tells the agent exactly which lines of which doc to read for more detail.

**Index file hygiene:**
- Index files can get large. Always read by section (offset + limit), never in full.
- Include line ranges for the source docs so the agent can read only relevant sections.
- Keep index entries factual: table names, function names, one-line business rules. No prose.
- One index per dimension: domain index (what tables/functions exist), function index (all functions by type), feature index (user-facing behavior docs).

---

## Part 2: The Self-Maintenance Loop

### 2.1 Agent Writes → Future Agent Reads

When an agent creates a function, adds a table, or changes behavior, it should update the indexes and docs. This creates a virtuous cycle: the next thread starts with accurate context.

But this loop has a cost: every word the agent writes to a doc becomes input tokens in future threads. So the rules governing agent writing must enforce conciseness.

### 2.2 Rules for Agent-Written Documentation

The rule that governs doc updates should include:

1. **What triggers an update:** New function → update function index. New table → update domain index. Changed behavior → update feature guide. Be explicit about the mapping.

2. **What format to use:** Index entries = `| name | type | one-line purpose |`. Domain docs = schema + rules, not narrative. Feature docs = have a line budget.

3. **Conciseness enforcement:** State explicitly that these docs become input tokens. "Write the minimum that carries full meaning. No prose in index entries. No adjectives that don't add information."

4. **Don't defer, but also don't over-trigger.** The update-docs rule should be on-demand (Layer 2), not always-on. The always-on rule should have one line: "After approved changes, read `update-docs.mdc` before closing."

### 2.3 Prevention-as-Documentation

When an agent fixes a bug or discovers a pattern, the fix should leave behind a rule or convention entry that prevents recurrence. This is the "fix → audit → abstract → prevent" loop:

1. Fix the immediate issue
2. Search for other instances of the same pattern
3. If it's systemic, extract a shared fix
4. Create or update a rule/convention to prevent recurrence

The key token-efficiency point: prevention rules should be **on-demand** (Layer 2 with a good description), not always-on. A rule about hydration safety in React only needs to load when someone is working on SSR-related code.

---

## Part 3: Token Economy

### 3.1 The Compounding Cost of Conversation History

This is the least obvious and most expensive cost. In a Cursor thread:

- Every turn, the full conversation history is sent as input
- A tool call result on turn 1 (e.g., 2,000 tokens from an MCP query) is re-sent on turns 2, 3, 4... through turn N
- A 2,000-token result over a 20-turn thread costs 2,000 × 19 = 38,000 tokens just from history

This means: **rules that trigger tool calls have a multiplicative cost.** A rule that says "run 3 SQL queries before every response" costs not just the 3 queries but the accumulated results across the entire thread.

### 3.2 "Per Task" vs "Per Turn" — The Most Important Distinction

The most common and expensive mistake in rule writing:

| Rule says | Agent interprets as | Cost impact |
|---|---|---|
| "Before ANY response to a task..." | Run this on every turn | MCP queries × turns × history accumulation |
| "MANDATORY on every user task" | Run this on every turn | Same |
| "At the start of a new task or thread" | Run this once, reuse context | MCP queries × 1 |

Always scope mandatory procedures explicitly:

> "Run Steps 1-3 at the START of a new task or thread. On follow-up turns within the same task, only re-run if: (a) a new domain enters scope, (b) you need data you haven't checked yet, or (c) user explicitly asks to re-check."

### 3.3 The Double-Mandate Problem

If two always-on rules both say "you MUST do X before anything else," the agent is doubly reinforced. It's less likely to exercise judgment about when X is redundant. 

**Rule: One authoritative source per procedure.** Other rules can reference it with a one-liner, but should not re-explain it.

### 3.4 Token Budget Guidelines

| Category | Budget | Notes |
|---|---|---|
| Total always-on rule text | < 6KB | ~1,500 tokens/turn. Over a 20-turn thread, that's 30K tokens just for rules |
| Single always-on rule | < 3KB | If a rule is bigger, it probably contains reference material that should be Layer 2 |
| On-demand rule description | 1-2 sentences | This is what the agent sees every turn to decide if it should read the full file |
| On-demand rule file | < 10KB | If bigger, consider splitting or moving detail into Layer 3 docs |
| Index file section | < 2KB per domain | Agent reads one section at a time via offset/limit |

### 3.5 Live Data Over Static Docs

When you have a live data source (database via MCP, API, running dev server), prefer querying it over reading docs:

- Docs can be stale. Live schema/function signatures are always current.
- A single MCP query is cheaper than reading a 10KB doc section and parsing it.
- Rules should say: "Verify via MCP. Docs can be stale; live data is truth."

But don't over-query either. Query once at the start of a task, cache the mental model, don't re-query every turn (see 3.2).

---

## Part 4: Common Pitfalls (What Makes Tokens Balloon)

### Pitfall 1: Duplicate Files

Git conflicts, file sync, or copy-paste creates `file.mdc` and `file 2.mdc`. Both get their descriptions injected into the system prompt. If the agent reads both, it pays double.

**Prevention:** Periodically audit `.cursor/rules/` for duplicate files. Add `.cursor/rules/*\ 2.mdc` to `.gitignore` or a cleanup hook.

### Pitfall 2: Same Content as Both Rule and Skill

Having `verify-data-before-coding.mdc` (rule) AND `.cursor/skills/verify-data-before-coding/SKILL.md` (skill) means the same concept exists twice. The rule's description loads every turn, and if both get read, it's double tokens.

**Rule of thumb:** If content is needed proactively (agent should always know about it), it's a rule. If it's a procedure the agent runs on specific tasks, it's a skill. Never both.

### Pitfall 3: Always-Apply Rules That Overlap

Across your repos, you might have `study-before-building.mdc` (alwaysApply: true) AND `verify-data-before-coding.mdc` (alwaysApply: true) AND `requirement-docs.mdc` (alwaysApply: true) all telling the agent some version of "look things up before coding." That's 3 always-on rules teaching one concept.

**Consolidate.** One always-on rule says "follow the lookup procedure." The lookup procedure is defined in one place. Verification, study, and doc reading are all part of that one procedure.

### Pitfall 4: Post-Action Rules as Always-On

"Update docs after changes," "run tests after implementation," "verify visual changes after edits" — these only matter AFTER the agent has done something. Making them always-on means the agent carries that weight during analysis, planning, and discussion turns.

**Demote to Layer 2.** Add a one-line pointer in the workflow section of your always-on rule.

### Pitfall 5: Negative Instruction Lists

"DO NOT do X. DO NOT do Y. DO NOT shortcut by doing Z. NEVER assume W." These feel necessary but are expensive. Each negative instruction takes tokens. Positive instructions usually subsume the negatives.

**Before writing "DO NOT,"** ask: does the positive instruction already cover this? "Always verify via MCP" already implies "don't guess column names." You don't need both.

### Pitfall 6: Verbose Examples in Always-On Rules

A 7-row example table in an always-on rule costs tokens on every turn. 2-3 distinct examples teach the same principle.

### Pitfall 7: Rule-Triggered Cascading Reads

The most expensive pitfall. An always-on rule says: "Before creating cross-module structures, check `abstraction-principles.mdc`." The agent dutifully reads a 3KB file every time it creates anything. Another rule says "after any change, check if feature guide needs updating" which causes the agent to read an INDEX, then potentially a feature guide, then potentially a writing-guide rule.

**Each pointer in an always-on rule is a potential cascade.** Be intentional about which pointers are always-on vs. which are reminders in the workflow step.

### Pitfall 8: Agent-Written Docs That Grow Unbounded

If the rule says "write a page doc for every new page" without a size constraint, the agent may generate 5KB docs that become input tokens every time someone works on that page. 

**Set line budgets.** "Index entries: one line per function. Page docs: under 100 lines. Feature guides: 250-400 lines."

---

## Part 5: The Scaffolding Checklist

When setting up rules for a new project, follow this order:

### Step 1: Create the always-on identity rule (< 3KB)

Contents:
- What this project is (2-3 lines)
- Tech stack, key IDs/URLs (3-5 lines)
- Domain router table (keyword → where to look)
- Lookup procedure (numbered steps — what to do, not how)
- One-line pointers to key Layer 2 rules
- Workflow (lookup → present → approve → implement → update docs)

### Step 2: Create the always-on guardrails rule (< 2KB)

Contents:
- What's prohibited without approval (dense list)
- One-line reference to the lookup procedure
- Output style preferences
- "When in doubt, stop and ask"

### Step 3: Create on-demand convention rules

One file per concern, with good descriptions and optional glob triggers:
- DB/schema conventions (triggered when writing migrations)
- Function/code conventions (triggered when writing functions)
- Auth patterns (triggered when writing auth-related code)
- Component standards (triggered when editing components)
- Testing patterns (triggered when writing tests)

### Step 4: Create index files in the repo

- Domain index: domains → tables → functions → key rules → doc paths
- Function index: all functions by domain with type and purpose
- Feature index: user-facing behavior docs with status

### Step 5: Create the doc-update rule (on-demand)

- What change triggers what doc update
- Format constraints for index entries
- Conciseness enforcement
- Line budgets

### Step 6: Add prevention rules as they emerge

Don't pre-create rules for problems you haven't hit. When a bug pattern or mistake recurs, create an on-demand rule that prevents it. This keeps the rule set lean and earned.

---

## Part 6: Review & Maintenance Cadence

### Monthly: Token Audit

1. Check total byte count of `alwaysApply: true` rules. Target: under 6KB total.
2. Check for duplicate files (`*.mdc` with spaces or copies).
3. Check for retired rules that should be deleted.
4. Check for overlapping always-on rules teaching the same concept.

### Per-Feature: Doc Quality Check

1. Are index entries concise? (Name, type, one-line purpose — no prose)
2. Are requirement docs within line budget?
3. Are any docs growing unbounded?

### Quarterly: Rule Relevance Audit

1. Are any on-demand rules never being triggered? (Stale descriptions, wrong globs)
2. Are any conventions outdated? (Framework upgrade, pattern change)
3. Are there new recurring mistakes that need a prevention rule?

---

## Part 7: Key Principles Summary

1. **Three layers:** Always-on (routing + guardrails) → On-demand (conventions + patterns) → Deep docs (full specs). Most content belongs in Layer 2 or 3.

2. **Always-on is a per-turn tax.** Every byte is multiplied by turn count. Budget < 6KB total.

3. **Scope procedures to "once per task."** Ambiguous language like "before any response" causes redundant tool calls across every turn.

4. **One source of truth per concept.** Other rules reference it, don't re-explain it.

5. **Descriptions are how agents discover on-demand rules.** Write them like search result snippets — when + what + why.

6. **Indexes are the bridge.** Compact routing tables that tell the agent WHERE to look, not WHAT the answer is.

7. **Live data beats docs.** Query the database/API when possible. Docs are for business rules and conventions that don't live in code.

8. **Agent-written docs are future input tokens.** Enforce conciseness in the rules that govern writing.

9. **Post-action rules are on-demand.** Triggered by a one-line pointer in the always-on workflow, not always-on themselves.

10. **Earn your rules.** Don't pre-create rules for hypothetical problems. Add prevention rules when patterns actually recur.

11. **Conversation history compounds costs.** Every tool result on turn 1 is re-sent as input on all subsequent turns. Minimize redundant lookups.

12. **Negative instructions are usually redundant.** If the positive instruction is clear, the negative is implied. Cut it.

13. **Self-maintenance is a loop, not a sprint.** Fix → Audit → Abstract → Prevent → Update docs. The agent improves the project context for the next agent.

14. **Review monthly.** Token costs, duplicate files, stale rules, unbounded docs. Prevention is cheaper than cure.

---

## Part 8: Token Audit Prompt (Portable)

Copy-paste this prompt into any Cursor project to run a token audit. It works standalone — no project-specific knowledge needed.

---

### Prompt: Token Usage Audit

```
Audit this project's token efficiency. Do NOT make changes — present findings and wait for approval.

**Step 1: Measure always-on rules**
List all .cursor/rules/*.mdc files with alwaysApply: true. Show byte count + line count for each. Total should be under 6KB.

**Step 2: Check for duplicate/stale files**
- Duplicate rules: files with " 2", "copy", or near-identical content in .cursor/rules/
- Duplicate plans: files in .cursor/plans/ with identical sizes
- Stale rules: any rule referencing tables, functions, or patterns that no longer exist

**Step 3: Measure on-demand rules**
List all alwaysApply: false rules. Flag any over 5KB — these are candidates for compression.
Check: do multiple rules teach the same concept? (e.g., two rules both saying "look things up before coding")

**Step 4: Check for cascading reads**
For each pointer in always-on rules (e.g., "read X.mdc before Y"), trace the chain:
- Does reading rule A trigger reading rule B?
- Does any rule instruct reading large files (>10KB) on every task?
- Are there index files over 50KB that get partially read on most tasks?

**Step 5: Check skills**
List enabled skills from the system prompt. For each:
- Does it instruct reading additional files (SDK docs, type definitions, etc.)?
- How many total lines would the agent read when this skill fires?
- Is the skill actually used in this project?

**Step 6: Check MCP servers**
List all enabled MCP servers. For each:
- Tool count and approximate descriptor size
- Is this server actually used for this project?
- Flag servers with >50 tools or >30KB of descriptors that aren't core to the project

**Step 7: Check large docs**
- List any file in the repo over 50KB that might be read by the agent
- Check if index files have precise section boundaries (line ranges) so agent reads minimal sections

**Present findings as a prioritized list: what to fix, estimated token savings, effort level.**
```

---

### Principles Checklist (for any project)

When optimizing a project's Cursor setup, verify each item:

**Always-on layer (per-turn cost)**
- [ ] Total always-on rules under 6KB
- [ ] No SQL templates, code examples, or verbose tables in always-on rules
- [ ] No duplicate concepts across always-on rules
- [ ] Lookup procedures scoped to "once per task," not "every turn"
- [ ] Post-action rules (update docs, run tests) are on-demand with one-line pointers

**On-demand layer (per-read cost)**
- [ ] Each rule under 5KB (ideally under 3KB)
- [ ] Descriptions are specific ("when writing DB functions" not "function conventions")
- [ ] Glob triggers used where applicable (`.tsx` files, `docs/*.md`)
- [ ] No rule duplicates what the agent can discover via MCP/live data
- [ ] Code examples are minimal (3-5 lines max, or "read an existing X via MCP for the pattern")

**Deep docs layer (per-task cost)**
- [ ] Index files have section boundaries so agent can offset+limit
- [ ] Large indexes (>50KB) are split by domain or have explicit read conditions
- [ ] Agent-written docs have line budgets
- [ ] No doc is read in full — always offset+limit

**Skills and tools**
- [ ] Skills don't instruct reading large SDK/type definition files
- [ ] Unused MCP servers disabled for the project
- [ ] No duplicate MCP servers (same tool set, different name)

**Hygiene**
- [ ] No duplicate files in .cursor/rules/ or .cursor/plans/
- [ ] .cursorignore excludes files the agent should never read
- [ ] No plan files over 100KB sitting in .cursor/plans/
