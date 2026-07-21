---
name: Elixir DAG Creator
description: Instructions for creating an Elixir DAG to run on Gust. Use this when you need to create a new DAG.
license: Complete terms in LICENSE.txt
---

# Gust DAG Creator

Use this guide to create a DAG in Elixir for Gust.

## Create a DAG file

Create a valid Elixir module under `dags/`.

## DAG syntax

The Gust DSL turns an Elixir module into a DAG.

When you add `use Gust.DSL` to a module in the `dags/` folder, Gust detects it automatically. You can configure a schedule, define callbacks, and in development the DAG is reloaded when files change.

After enabling the DSL, define tasks with `task`.

### Example

```elixir
defmodule HelloWorld do
  use Gust.DSL, schedule: "* * * * *", on_finished_callback: :notify_something

  require Logger
  alias Gust.Flows

  def notify_something(status, run) do
    dag = Flows.get_dag!(run.dag_id)
    Logger.info("DAG: #{dag.name}; completed with status: #{status}")
  end

  def skip_first_task?(%{run_id: run_id}) do
    run = Flows.get_run!(run_id)
    Map.get(run.params, "skip_first_task", false)
  end

  task :first_task, downstream: [:second_task], save: true, skip_if: :skip_first_task? do
    greeting = "Hi from first_task"
    Logger.info(greeting)

    %{result: greeting}
  end

  task :second_task, ctx: %{run_id: run_id} do
    task = Flows.get_task_by_name_run("first_task", run_id)
    Logger.info("#{inspect(task.result)}")
  end
end
```

## DSL options

- `schedule`: a cron expression
- `on_finished_callback`: the function called when the DAG finishes

## Task options

- `:downstream` — list of downstream task names
- `:save` — persists the task return value; when enabled, the return value must be a map
- `:ctx` — pattern matched against the task context; commonly `%{run_id: run_id}`
- `:skip_if` — name of a DAG module function that receives the task context and returns a boolean. If it returns `true`, Gust does not run the task body and marks the task as skipped. Downstream tasks that depend on a skipped upstream are skipped too.
- `:map_over` — name of an upstream task whose saved list result should start one parallel task instance per item. The upstream task must use `save: true` and return a list. Each item is passed as `ctx.params`; map items are passed unchanged and scalar items are wrapped as `%{"item" => value}`. If the upstream list is empty, the mapped task is skipped.
- `:wait_for` — durable external event key. When the task is reached, Gust marks the task and run as `:waiting` and pauses that path until `Gust.DAG.TaskWaiter.resume/2` receives the matching key. Use a string or atom key that an external DAG, webhook, API call, or process can send later. If the resumed task needs payload data, read it from `ctx.params["__gust_wait_payload__"]`.

### Examples

```elixir
task :simple_task do
  IO.puts("Hello")
end

task :my_task, ctx: %{run_id: run_id} do
  IO.inspect(run_id)
end

task :first, downstream: [:second] do
  :ok
end

task :persist_result, save: true do
  %{result: :ok}
end

def skip_export?(%{run_id: run_id}) do
  run = Gust.Flows.get_run!(run_id)
  Map.get(run.params, "skip_export", false)
end

task :export, skip_if: :skip_export? do
  :ok
end

task :list_names, downstream: [:greet], save: true do
  ["Ada", "Grace"]
end

task :greet,
     map_over: :list_names,
     ctx: %{params: %{"item" => name}} do
  IO.puts("Hello #{name}")
end

task :await_payment,
     wait_for: "payment_received",
     save: true,
     ctx: %{params: %{"__gust_wait_payload__" => payload}} do
  %{payment_id: payload["payment_id"]}
end
```

Resume waiting tasks with `Gust.DAG.TaskWaiter.resume/2`:

```elixir
Gust.DAG.TaskWaiter.resume("payment_received",
  run_id: run_id,
  payload: %{"payment_id" => "pay_123"}
)
```

Omit `run_id` only when you intentionally want to resume every waiting task with the same key.

## Non-recoverable task errors

Ordinary exceptions follow Gust's retry behavior. When retrying cannot succeed—for example,
because input is permanently invalid—raise `Gust.DAG.NonRecError` from the DAG task:

```elixir
task :validate_order, ctx: %{params: params} do
  if is_nil(params["order_id"]) do
    raise Gust.DAG.NonRecError, "order_id is required"
  end

  :ok
end
```

Gust marks the task and run as failed without scheduling another attempt. The exception message
and stacktrace are persisted and displayed on the dashboard like other task errors.

## Validation

For example, if the file is `dags/hello_world.ex`, confirm that the `hello_world` DAG is valid.

Run command: `mix gust.cli dag_definition hello_world`
