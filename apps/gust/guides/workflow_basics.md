# Workflow basics

This guide introduces workflows in Gust using its native Elixir API. You will
define a DAG, pass input to a run, save task results, and handle failures.
For Python, see [Writing Python DAGs](https://hexdocs.pm/gust_py/writing_python_dags.html).

## Develop a basic workflow

A workflow in Gust is a directed acyclic graph (DAG). A DAG definition describes
tasks and their dependencies; a run is one execution of that definition.

Define a DAG as an Elixir module with `use Gust.DSL`. Each `task` block defines
one step. The `downstream:` option declares which tasks follow that step.
Gust derives execution order from these dependencies, rather than the order of
the blocks in the file. Tasks without dependencies can run in parallel.

In an application with Gust configured, save this module as `greeting.ex` in
your configured DAG folder:

```elixir
defmodule Greeting do
  use Gust.DSL

  alias Gust.Flows
  require Logger

  task :build_greeting, downstream: [:log_greeting], save: true, ctx: %{run_id: run_id} do
    run = Flows.get_run!(run_id)
    name = Map.get(run.params, "name", "World")

    if not is_binary(name) or name == "" do
      raise Gust.DAG.NonRecError, "name must be a non-empty string"
    end

    %{"message" => "Hello, #{name}!"}
  end

  task :log_greeting, ctx: %{run_id: run_id} do
    result = Flows.get_task_result_by_name_run!("build_greeting", run_id)
    Logger.info(result["message"])
  end
end
```

Gust loads the file as a DAG named `greeting`. The `build_greeting` task saves
its result before `log_greeting` reads it. Each task executes in its own worker
process, so use persisted results to pass data between tasks.

### Start a run

With the DAG loaded and a Gust execution node running, trigger it from the
dashboard or use the CLI from your application directory:

```sh
mix gust.cli trigger_run greeting --run_params '{"name":"Ada"}'
```

The CLI queues a run; an execution node picks it up. The CLI defaults to the
`console` role and does not start execution workers itself. Use a running
`single` or `core` node connected to the same database; see [Gust Roles](roles.md).

The run saves `%{"message" => "Hello, Ada!"}` on `build_greeting` and logs
`Hello, Ada!` from `log_greeting`. Inspect the run's status, tasks, results, and
logs in the dashboard.

## Define workflow parameters

Pass run input as a JSON object. Use named fields and defaults for optional
values so callers can add fields without changing a function signature.
Run parameters are persisted on `Gust.Flows.Run` and are available through
`Gust.Flows.get_run!/1`:

```elixir
task :read_input, ctx: %{run_id: run_id} do
  run = Gust.Flows.get_run!(run_id)
  Map.fetch!(run.params, "name")
end
```

The `ctx:` option pattern-matches a task's context, which contains `:run_id`
and `:params`. These represent different sources of input:

| Value | Meaning |
| --- | --- |
| `run_id` | Identifies the current run; use it to read run parameters and task results. |
| `Flows.get_run!(run_id).params` | The input supplied when the run was created. |
| `ctx.params` | Task-specific parameters, such as the item supplied by `map_over` or data supplied when resuming a waiting task. |

Ordinary tasks start with empty task parameters. Read run input from the run
record, rather than assuming it is copied into `ctx.params`.

## Define workflow results

Gust stores results per task. Set `save: true` on every task whose output must
be available to downstream tasks or visible as a saved result in the dashboard.
The last expression in the task block is its return value.

Saved results must be JSON-serializable maps or lists. Wrap scalar values in a
map, for example `%{"message" => "Hello!"}`. Lists are stored inside a map
under the `"gust_task_items"` key and can drive `map_over` tasks. Functions,
process IDs, and other values that cannot be JSON-encoded cannot be saved.

Read a saved result with the task's string name and the run ID:

```elixir
result = Gust.Flows.get_task_result_by_name_run!("build_greeting", run_id)
message = result["message"]
```

Persisted JSON map keys are strings. Without `save: true`, a task's return
value is discarded and its stored result remains an empty map. Returning a
value does not automatically pass it as an argument to the next task.

For a workflow-level output, designate a final task with `save: true` and read
its result after the run succeeds. For mapped tasks, use
`Gust.Flows.get_tasks_by_name/2` to retrieve all instances instead of a helper
that expects a single task.

## Name your workflow and tasks

The DAG name comes from the filename without its extension: `greeting.ex`
becomes `greeting`. The Elixir module name identifies the code to execute;
changing it alone does not change the DAG name. Keep one DAG module per file
and use distinct module names across files.

Task names are atoms in the definition, such as `:build_greeting`, and strings
in persisted records and lookup calls, such as `"build_greeting"`. Use unique
task names within a DAG and refer to those atoms in `downstream:`.

## Configure the workflow

Pass definition options to `use Gust.DSL`. For example, replace the example's
`use Gust.DSL` line with:

```elixir
use Gust.DSL,
  schedule: "0 9 * * *",
  on_finished_callback: :notify_finished,
  runs: [concurrency: :sequential]
```

Then define the callback in the same module:

```elixir
def notify_finished(status, run) do
  Logger.info("Run #{run.id} finished with status #{status}")
end
```

The schedule is optional. Without one, trigger runs manually or through the
API. Runs can overlap by default; `concurrency: :sequential` queues them so
only one run of this DAG is active at a time.

Definition options describe the DAG. Put work that depends on a particular
run inside task blocks, where its input and run ID are available.

## Develop workflow logic

Gust executes task code and persists task state and results. It does not
reconstruct workflow state by replaying a deterministic workflow function.
Tasks can make HTTP requests, query databases, read files, generate random
values, and use `DateTime.utc_now/0` directly.

### Handle failures and retries

Ordinary exceptions follow Gust's task retry behavior. Raise an exception
when an operation fails; an `{:error, reason}` return value alone does not
signal a task failure. If `save: true` is set, that tuple also fails result
validation because it is neither a map nor a list.

For invalid input or another permanent failure, raise
`Gust.DAG.NonRecError`. Gust marks the task and run as failed without
scheduling another attempt. The greeting example uses this for an invalid name.

Tasks can execute again after a retry or a manual reset. Make external effects
safe to repeat: use an upsert for a database write or a stable idempotency key
for a payment request. A saved result does not make the external operation and
Gust's result persistence one atomic transaction.

### Log from a task

Use Elixir's `Logger` inside task blocks:

```elixir
task :log_start, ctx: %{run_id: run_id} do
  Logger.info("Processing run #{run_id}")
end
```

Add `require Logger` to the DAG module. Gust associates task logs with the
task and attempt and displays them in the dashboard. A retried task can log
again. Keep credentials and secret values out of log messages.

### Keep dependencies explicit

Declare `downstream:` when one task needs another task's output. Saving a
result or querying it does not create a dependency. Use `map_over` to process
saved list items, `skip_if` for conditional skipping, and `wait_for` for a
durable pause until an external event arrives. See [Writing DAGs](writing_dags.md)
and `Gust.DSL` for these options and reusable actions.

DAGs execute as trusted application code. See
[Trusted code](writing_dags.md#trusted-code) for the execution boundary.

## Next steps

- [Writing DAGs](writing_dags.md) — mapping, skipping, callbacks, and reusable actions.
- [Configuration](configuration.md) — dispatchers, retention, and language adapters.
- [HTTP API](https://hexdocs.pm/gust_web/http_api.html) — trigger and inspect runs from another application.
- [Error Tracking](error_tracking.md) — report terminal task failures.
