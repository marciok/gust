---
name: Elixir DAG Creator
description: Instructions for creating an Elixir DAG to run on Gust. Use this when you need to create a new DAG.
license: Complete terms in LICENSE.txt
---

# Gust DAG Creator

Use this guide to create a DAG in Elixir for Gust.

## Create a DAG file

Create a valid Elixir module under `/dags`.

## DAG syntax

The Gust DSL turns an Elixir module into a DAG.

When you add `use Gust.DSL` to a module in the `/dags` folder, Gust detects it automatically. You can configure a schedule, define callbacks, and in development the DAG is reloaded when files change.

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

  task :first_task, downstream: [:second_task], save: true do
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
```

## Validation

For example, if the file is `dags/hello_world.ex`, confirm that the `hello_world` DAG is valid.

Run command: `GUST_ROLE=web mix run -e "IO.inspect(Gust.Flows.get_dag_by_name(\"hello_world\").id |> Gust.DAG.Loader.get_definition())"`

