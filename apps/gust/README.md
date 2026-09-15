# Gust

Gust is a DAG-based workflow orchestration engine for Elixir.

## Runtime roles

Set `GUST_ROLE` to control which parts of the runtime start:

- `single`: default mode; runs the web-facing and execution-oriented parts together.
- `core`: runs DAG scheduling and execution workers without the web UI.
- `web`: loads DAG definitions for the UI, but does not run DAG execution workers.
- `console`: loads DAG definitions and supporting runtime services for CLI or IEx usage, but skips DAG pooling workers.

## Console usage

Use `console` when you want to inspect DAGs, run CLI commands, or open IEx without starting execution workers:

```zsh
GUST_ROLE=console iex -S mix
mix gust.cli your_command_here
```

The `mix gust.cli` task defaults `GUST_ROLE` to `console` automatically, and release builds provide a `gust-cli` wrapper with the same behavior.

## Guides

- [Writing DAGs](guides/writing_dags.md) — the `Gust.DSL` in practice.
- [Configuration](guides/configuration.md) — run dispatcher config and DAG
  adapters.
- [Gust Roles](guides/roles.md) — `GUST_ROLE` and multi-node setup.
- [Error Tracking](guides/error_tracking.md) — reporting terminal task
  failures.
