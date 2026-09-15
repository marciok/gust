# Gust Roles

You can run Gust with different runtime roles by setting `GUST_ROLE`:

- `core`: runs the DAG pool and execution workers without the web UI.

  ```zsh
  GUST_ROLE=core iex --sname core -S mix run --no-halt
  ```

- `web`: runs the Phoenix server and loads DAG definitions for the UI, but
  does not execute DAGs.

  ```zsh
  GUST_ROLE=web iex --sname web -S mix phx.server
  ```

- `console`: loads DAG definitions and supporting runtime pieces for CLI or
  IEx work, but does not start DAG pooling workers.

  ```zsh
  GUST_ROLE=console iex -S mix
  ```

`mix gust.cli ...` also defaults `GUST_ROLE` to `console`, and release builds
ship a `gust-cli` wrapper that exports the same role automatically.

If you do not pass anything, Gust runs as `single`, which enables both the
`core` and `web` behavior in the same node.

For choosing how `core` nodes pick up ready runs across a multi-node setup,
see [Run Dispatcher](https://hexdocs.pm/gust/configuration.html#run-dispatcher)
in the Configuration guide.
