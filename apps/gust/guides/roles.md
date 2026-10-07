# Gust Roles

Gust supports two startup modes:

## Development setup

From the umbrella root, source the environment and choose the runtime role you want.

```zsh
cd /home/serge/projects/elixir-libs/gust
. ./.env.example
```

### Single-node development

This is the simplest local setup and uses the default `single` role:

```zsh
mix phx.server
```

Or, if you want an interactive shell:

```zsh
iex -S mix
```

### Split-role development

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

## Production / release setup

For release builds, start the generated app script instead of opening `iex`:

```zsh
mix release gust
_build/prod/rel/gust/bin/gust start
```

The generated release includes helper scripts for common service roles, such as:

```zsh
_build/prod/rel/gust/bin/start-core
_build/prod/rel/gust/bin/gust-cli
```

The production path is intentionally different from the dev path: local development uses `mix` commands, while a release is started with the compiled `gust` binary and role-specific wrappers.

## Multi-worker architecture

Gust supports running several Erlang nodes in the same cluster. The usual
pattern is to run one or more `core` nodes for execution and one `web` node for
UI access. The scheduler does not pin a DAG to a specific node permanently; the
core nodes compete to claim ready runs from the durable run queue.

The durable queue is represented by the `gust_runs` table. A row stores the
run's status plus the lease metadata used by the claimer:

- `status`
- `claimed_by`
- `claim_expires_at`
- `claim_token`

The claimer chooses a ready run, then updates the row atomically with
`FOR UPDATE SKIP LOCKED` so only one node can claim it. The node that wins the
claim becomes the owner of the run until the lease expires or the run finishes.
The run owner is then used to route run control commands back to the correct
node.

This architecture means:

- multiple `core` nodes can share a single database and process the same queue
- a `web` node is not responsible for executing DAG runs
- a `console` node is for CLI and debugging work, not for execution
- if a worker node crashes, another core node can claim the expired run and
  continue it

## Multi-worker setup

Run all nodes with the same Erlang cookie and a shared database configuration.
Use a unique node name per process, for example with `--sname`.

### Example: web + two core workers

```zsh
# terminal 1: web UI
GUST_ROLE=web iex --sname gust_web -S mix phx.server

# terminal 2: core worker 1
GUST_ROLE=core iex --sname gust_core_1 -S mix run --no-halt

# terminal 3: core worker 2
GUST_ROLE=core iex --sname gust_core_2 -S mix run --no-halt
```

The nodes must share the same cookie and be connected via Erlang distribution.
In practice, this means the cluster needs a consistent `--cookie` value and a
working Erlang distribution setup for your environment.

### Example: single-node development

```zsh
# single process, both UI and execution in one VM
iex -S mix
```

This is the default `single` role and is the simplest setup for local
development.

## Important limitations

Gust does not currently implement DAG-to-node affinity rules such as
"only execute on nodes with GPU support" or "only run on this node label set".
At the moment, selection is based on the shared run queue and the claim lease,
not on hardware or node capability constraints. If you need GPU-aware or
resource-aware scheduling, add an explicit claim policy or a custom dispatcher
layer on top of the current queue semantics.

For choosing how `core` nodes pick up ready runs across a multi-node setup,
see [Run Dispatcher](https://hexdocs.pm/gust/configuration.html#run-dispatcher)
in the Configuration guide.
