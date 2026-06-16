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
```

## Validation

For example, if the file is `dags/hello_world.ex`, confirm that the `hello_world` DAG is valid.

Run command: `mix gust.cli dag_definition hello_world`
