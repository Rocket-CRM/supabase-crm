# Database Context

- Always use the **Supabase MCP connection** to inspect schema, tables, functions, and indexes.  
- When analyzing, explain:  
  - What each table/function is for.  
  - How they connect to business requirements.  
- Prefer ERD-style or textual relationship diagrams when summarizing.  

### SQL Execution Rules
- Default to **read-only queries** (SELECT).  
- Never modify schema or run migrations automatically.  
- Schema changes must be **presented in chat with descriptive explanation**.
- Show raw SQL only if needed for implementation.
- Create `.sql` migration files only if useful for implementation workflow.






























