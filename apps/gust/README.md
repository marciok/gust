# Gust

Gust is a DAG-based workflow orchestration engine for Elixir.

## Runtime roles

Set `GUST_ROLE` to control which parts of the runtime start:

- `single`: default mode; runs the web-facing and execution-oriented parts together.
- `core`: runs DAG scheduling and execution workers without the web UI.
- `web`: loads DAG definitions for the UI, but does not run DAG execution workers.
- `console`: loads DAG definitions and supporting runtime services for CLI or IEx usage, but skips DAG pooling workers.

## Development setup

From the umbrella root, load the project environment and start Gust in the mode you need.

```zsh
cd /home/serge/projects/elixir-libs/gust
. ./.env.example
```

### Single-node dev (simplest option)

This is the default `single` role and runs both the web UI and execution workers in one VM.

```zsh
mix phx.server
```

If you want an interactive shell instead of the Phoenix server:

```zsh
iex -S mix
```

### Split-role dev

```zsh
# UI node
GUST_ROLE=web mix phx.server

# worker node
GUST_ROLE=core mix run --no-halt

# CLI/IEx node
GUST_ROLE=console iex -S mix
```

### Console usage

Use `console` when you want to inspect DAGs, run CLI commands, or open IEx without starting execution workers:

```zsh
GUST_ROLE=console iex -S mix
mix gust.cli your_command_here
```

The `mix gust.cli` task defaults `GUST_ROLE` to `console` automatically, and release builds provide a `gust-cli` wrapper with the same behavior.

## Production / release setup

Release startup should use the generated app entrypoint instead of dropping into `iex`.

```zsh
mix release gust
_build/prod/rel/gust/bin/gust start
```

This starts the release in the configured role. In practice, the release layout includes role-specific wrappers such as:

```zsh
_build/prod/rel/gust/bin/start-core
_build/prod/rel/gust/bin/gust-cli
```

The `start-core` wrapper executes the release binary with the `start` command, while `gust-cli` exports `GUST_ROLE=console` and runs the CLI through the release app. That is the production-compatible startup path.

## Shell tasks

- [Writing DAGs](guides/writing_dags.md) — the `Gust.DSL` in practice.
- [Configuration](guides/configuration.md) — run dispatcher config and DAG
  adapters.
- [DAG Sources](guides/dag_sources.md) — Load DAGs from folder, Git, or database.
- [Gust Roles](guides/roles.md) — `GUST_ROLE` and multi-node setup.
- [Error Tracking](guides/error_tracking.md) — reporting terminal task
  failures.
