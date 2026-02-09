# Functions, Queues, Triggers, and Crons Context

## Comprehensive Study Requirements

When initializing, the assistant must **thoroughly study and understand** all Supabase components:

### 1. Database Functions (RPC Functions)
- Load and analyze **all database functions** via MCP
- Understand function signatures, parameters, and return types
- Map function purposes to business logic
- Document dependencies between functions
- Identify which functions are called by triggers vs. application code
- Note any functions that modify state vs. read-only functions

### 2. Database Triggers
- Catalog all database triggers and their associated tables
- Understand trigger timing (BEFORE/AFTER) and operations (INSERT/UPDATE/DELETE)
- Map trigger cascades and their business implications
- Document which functions are invoked by triggers
- Analyze trigger conditions and when they fire
- Understand the data flow through trigger chains

### 3. Edge Functions
- List all deployed edge functions via MCP
- Understand their endpoints, authentication requirements, and purposes
- Map edge functions to business features (webhooks, integrations, etc.)
- Document any scheduled or event-driven edge function invocations
- Identify external API dependencies

### 4. Queues (pg_net or Supabase Queues)
- Identify all queue configurations
- Understand queue consumers and producers
- Map queue message types to business processes
- Document retry policies and error handling
- Understand queue-to-function relationships

### 5. Cron Jobs
- List all scheduled cron jobs (via pg_cron or edge function schedules)
- Document cron schedules and their business purposes
- Map crons to the functions/processes they trigger
- Understand dependencies and execution order
- Note any maintenance or cleanup crons

## Integration Context

### Cross-Component Relationships
- Map how functions, triggers, queues, and crons work together
- Document data flow patterns through the system
- Identify critical paths and dependencies
- Understand error propagation and handling across components

### Business Logic Mapping
- Connect each component to specific business requirements
- Document which loyalty features depend on which components
- Map currency award mechanisms to their implementing functions
- Trace reward redemption flows through the system
- Understand tier calculation and progression triggers

## Critical Safety Rules

### Read-Only Analysis
- **NEVER modify any functions, triggers, queues, or crons** without explicit approval
- Treat all components as production-critical
- Only perform read operations for analysis

### Modification Protocol
- If modifications are needed:
  1. **Present in chat** - describe what changes, why, and business impact
  2. Show raw code only if needed for implementation steps
  3. Create files only if useful for implementation workflow
  4. Document risks and rollback strategies in chat
- Wait for explicit human approval before any execution

### Analysis Before Action
- Always start with comprehensive analysis
- Map the full impact of any proposed change
- Consider downstream effects on dependent components
- Document current state before proposing modifications

## Response Guidelines

When discussing functions, queues, triggers, or crons:

1. **Explain the current implementation** - what exists and how it works
2. **Connect to business logic** - why it exists and what it accomplishes
3. **Identify dependencies** - what relies on this component
4. **Assess criticality** - production impact if modified or fails
5. **Propose carefully** - any changes must be presented with full context

## Initialization Checklist

On startup, systematically:
- [ ] Query all database functions via MCP
- [ ] List all triggers and their configurations
- [ ] Retrieve all edge functions
- [ ] Identify queue configurations
- [ ] Document all cron schedules
- [ ] Map relationships between components
- [ ] Connect to business requirements in `/requirements/`
- [ ] Build comprehensive system understanding

## Production Environment Emphasis

- This is a **live production system**
- All functions, triggers, queues, and crons are **business-critical**
- Default stance: **observe and analyze only**
- Modifications require **explicit thread approval**
- Always consider **system-wide impact** before proposing changes






























