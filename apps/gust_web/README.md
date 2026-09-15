# GustWeb

The web UI for Gust.

---

GustWeb is a Phoenix web server. Run `mix phx.server` to start it.

By default, it also starts the Gust core, which means DAGs are loaded and executed.

If you are working in multi-node mode and want to run only the web server, use:

`GUST_ROLE=web mix phx.server`

---

## Guides

- [Installation](guides/installation.md) — creating a new Gust app, or adding
  `gust_web` to an existing Phoenix app.
- [HTTP API](guides/http_api.md) — triggering DAG runs and resuming waiting
  tasks over HTTP.
- [MCP Server](guides/mcp_server.md) — giving your LLM access to Gust through
  MCP.
