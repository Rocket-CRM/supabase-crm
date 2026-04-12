# MCP Server — Best Practices

## What is MCP

Model Context Protocol (MCP) is a standard for LLM applications to interact with external tools and data. It decouples the AI's reasoning from the systems it needs to access — the AI decides what to do, MCP servers provide the capabilities.

An MCP server is a process with an HTTP endpoint that exposes three types of capabilities:
- **Resources** — read-only data the AI needs for context
- **Tools** — actions the AI can invoke to cause effects in the world
- **Prompts** — reusable prompt templates (not used in our implementation)

---

## Resources vs Tools — The Core Distinction

This is the most important design decision. Getting this wrong breaks the MCP contract.

**Resources = data for context (read-only)**

Resources provide information the AI needs to reason. The host application (not the AI) discovers and fetches resources, then puts the data into the prompt. Resources are:
- Discovered via `resources/list` or `resources/templates/list`
- Fetched via `resources/read` with a URI
- Read-only — they never cause side effects
- Identified by URI templates (e.g. `user://{user_id}/context`)

**Tools = actions that cause effects (write)**

Tools are functions the AI can invoke during reasoning. The AI decides when to call them and with what parameters. The host executes the call and returns the result. Tools are:
- Discovered via `tools/list`
- Invoked via `tools/call` with name + arguments
- Cause side effects — they change state in the world
- Defined with JSON Schema for parameters

**The workflow:**
```
1. Host discovers resources → asks LLM which ones are relevant
2. Host fetches relevant resources → puts data in the prompt
3. LLM reasons with the data → decides to call a tool
4. Host executes the tool → returns result to LLM
5. LLM may call more tools or return final answer
```

---

## Text Descriptions

Every resource and tool needs a rich, clear text description. The LLM uses these descriptions to decide whether a resource is relevant and how to use a tool correctly.

**Bad description:**
```
"Award points to a user"
```

**Good description:**
```
"Award loyalty points to a user's wallet. Points are immediately available
for redemption or earning tier progress. Use this when you want to financially
incentivize a user — it's the most direct reward. The cost is 1 unit per point
awarded, so a 300-point award costs 300 units of budget."
```

Good descriptions should explain:
- What the capability does
- When to use it (and when not to)
- Cost or impact implications
- Where to get required parameters (e.g. "get tag_id from the merchant's available actions resource")
- Any constraints or limitations

---

## Transport: Streamable HTTP

The current MCP standard transport for remote servers is **Streamable HTTP** (replaced the older HTTP+SSE approach). It uses:
- HTTP POST for sending JSON-RPC requests
- HTTP GET or Server-Sent Events (SSE) for server-to-client streaming
- JSON-RPC 2.0 message format

Standard endpoints:
```
POST /                → JSON-RPC request (initialize, tools/list, tools/call, resources/read, etc.)
Accept header         → "application/json, text/event-stream"
Response              → SSE format: "event: message\ndata: {json}\n\n"
```

---

## JSON-RPC Methods

| Method | Purpose | Direction |
|--------|---------|-----------|
| `initialize` | Handshake — client announces itself, server returns capabilities | Client → Server |
| `resources/list` | List static resources | Client → Server |
| `resources/templates/list` | List parameterized resource templates | Client → Server |
| `resources/read` | Fetch a specific resource by URI | Client → Server |
| `tools/list` | List available tools with JSON schemas | Client → Server |
| `tools/call` | Execute a tool with arguments | Client → Server |
| `notifications/*` | Async server notifications | Server → Client |

---

## Security Best Practices

- **Authentication on every request** — validate Authorization header (API key, JWT, or OAuth)
- **Scope by identity** — extract merchant/user from the auth token and scope all queries to that identity
- **Validate all inputs** — check parameters before executing any tool
- **Rate limiting** — prevent abuse by limiting calls per key per time window
- **Audit logging** — log every tool call with who called it, what parameters, and the result
- **Principle of least privilege** — API keys should have granular permissions (read-only vs full access)

---

## Design Principles

**Single responsibility** — each MCP server should have one clear domain. Don't mix unrelated capabilities (e.g. loyalty actions and email marketing in the same server).

**Stateless by default** — don't store session state between requests. Each request should be self-contained with all context in the parameters.

**Descriptive over clever** — tool names and descriptions should be self-explanatory. The LLM reads them literally.

**Fail safely** — return structured error messages the LLM can understand and react to. Don't crash — return `{ error: "budget_exceeded", remaining: 300 }` so the LLM can adjust.

**Composability** — an MCP server can also be a client. If your server needs data from another system (e.g. Kafka, Snowflake), connect to that system's MCP server instead of building custom integrations.

---

## Implementation Pattern (Supabase Edge Function)

Supabase provides first-class support for MCP servers on Edge Functions. The pattern:

```
Framework:    Official MCP TypeScript SDK (@modelcontextprotocol/sdk)
HTTP Router:  Hono
Validation:   Zod (v4)
Transport:    WebStandardStreamableHTTPServerTransport
Deployment:   supabase functions deploy --no-verify-jwt
```

```
crm-loyalty-actions/
├── index.ts     ← McpServer + resource registrations + tool registrations + Hono handler
└── deno.json    ← Deno compiler options
```

The server is created once at module level. Each request creates a new transport and connects it:
```
const server = new McpServer({ name: "...", version: "..." });
// register resources and tools...

const app = new Hono();
app.all("*", async (c) => {
  const transport = new WebStandardStreamableHTTPServerTransport();
  await server.connect(transport);
  return transport.handleRequest(c.req.raw);
});
```

---

## Resource Template Pattern

For parameterized resources, use `ResourceTemplate` with URI templates:

```
server.resource(
  "user_context",
  new ResourceTemplate("user://{user_id}/context", { list: undefined }),
  async (uri, { user_id }) => ({
    contents: [{ uri: uri.href, text: JSON.stringify(data), mimeType: "application/json" }]
  })
);
```

URI templates follow RFC 6570. Parameters are extracted automatically and passed to the handler.

---

## Tool Registration Pattern

```
server.registerTool(
  "award_points",
  {
    title: "Award Points",
    description: "Rich description for LLM...",
    inputSchema: {
      user_id: z.string().describe("The user UUID"),
      amount: z.number().describe("Points to award — must be > 0"),
    },
  },
  async ({ user_id, amount }) => ({
    content: [{ type: "text", text: JSON.stringify({ success: true }) }]
  })
);
```

Tool responses use `content` array with typed entries. For structured data, return `type: "text"` with JSON string.

---

## Client Configuration

MCP clients connect using a server URL:

```json
{
  "mcpServers": {
    "crm-loyalty": {
      "url": "https://your-project.supabase.co/functions/v1/crm-loyalty-actions",
      "headers": {
        "Authorization": "Bearer <api-key>"
      }
    }
  }
}
```

Compatible with: Cursor, Claude Desktop, n8n, OpenAI Agents SDK, Inngest AgentKit, and any MCP client.

---

## Testing

**curl:**
```bash
curl -X POST 'https://your-endpoint/functions/v1/mcp-server' \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc": "2.0", "id": 1, "method": "tools/list"}'
```

**MCP Inspector:**
```bash
npx @modelcontextprotocol/inspector
```
Enter the server URL in the inspector UI to browse resources and test tools interactively.

---

## References

- [MCP Specification](https://modelcontextprotocol.io/specification/2025-06-18/basic/transports)
- [MCP TypeScript SDK](https://github.com/modelcontextprotocol/typescript-sdk)
- [Supabase MCP Server Guide](https://supabase.com/docs/guides/getting-started/byo-mcp)
- [Supabase mcp-lite Guide](https://supabase.com/docs/guides/functions/examples/mcp-server-mcp-lite)
- [Inngest AgentKit MCP Integration](https://agentkit.inngest.com/advanced-patterns/mcp)
