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

## Shell tasks

Gust includes a shell task adapter for running OS commands inside a task. The adapter reads the command from `task.params["command"]` and raises a clear error when no command is provided.

```elixir
# task params passed to the runtime
%{"command" => "echo hello && ls -1"}
```

The shell adapter captures stdout and stderr, and returns either a successful result or an error result like:

```elixir
%{
  status: :success,
  stdout: "hello\n",
  stderr: "",
  exit_code: 0
}
```

or

```elixir
%{
  status: :error,
  message: "command exited with status 2",
  stdout: "...",
  stderr: "...",
  exit_code: 2
}
```

This is useful for lightweight operational tasks such as invoking a backup script, a system CLI, or a packaged utility without writing a dedicated Elixir task implementation. When the process is terminated by a signal, `exit_code` is set to the signal atom name such as `:sigterm` or `:sigkill` instead of a numeric code.
