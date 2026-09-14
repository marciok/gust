# MCP Server

GustWeb includes a built-in MCP server that gives your LLM access to Gust's
core features, including listing DAGs, triggering runs, exploring DAG
definitions, and debugging executions.

To mount it in your Phoenix router:

```elixir
import GustWeb.MCPRouter

scope "/mcp", MyAppWeb do
  pipe_through :api
  gust_mcp_server()
end
```

The prefix comes from your `MyAppWeb` router scope, so you can also mount it
under a project-specific path to avoid clashes:

```elixir
scope "/gust/mcp", MyAppWeb do
  pipe_through :api
  gust_mcp_server()
end
```

That would expose `POST /gust/mcp/server`. Keep auth and any app-specific
policy outside the macro, at the router scope or pipeline level.

## Connect to an MCP client

- claude: `claude mcp add --transport http gust-mcp http://localhost:4000/gust/mcp/server`
- codex: `codex mcp add gust-mcp --url http://localhost:4000/gust/mcp/server`

## Skills

- [Available Skills](https://github.com/marciok/gust/tree/main/skills)

Install:

```
gh skill install marciok/gust elixir-dag-creator
```
