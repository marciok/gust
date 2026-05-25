defmodule ParamsExample do
  @moduledoc """
  Example DAG demonstrating two ways to access run params.

  Trigger with:

      {:ok, run} = Gust.Flows.create_run(%{
        dag_id: dag.id,
        params: %{"greeting" => "Hello", "name" => "World"}
      })

  """
  use Gust.DSL
  require Logger
  alias Gust.Flows

  # Option 1: access params directly via ctx pattern matching
  task :via_ctx, downstream: [:greet], save: true, ctx: %{params: params} do
    greeting = Map.get(params, "greeting", "Hi")
    Logger.info("[via_ctx] greeting=#{greeting}")
    %{greeting: greeting}
  end

  # Option 2: access params by fetching the run manually
  task :via_run, downstream: [:greet], save: true, ctx: %{run_id: run_id} do
    run = Flows.get_run!(run_id)
    name = Map.get(run.params, "name", "Gust")
    Logger.info("[via_run] name=#{name}")
    %{name: name}
  end

  # Combine results from both upstream tasks
  task :greet, ctx: %{run_id: run_id} do
    %{"greeting" => greeting} = Flows.get_task_by_name_run("via_ctx", run_id).result
    %{"name" => name} = Flows.get_task_by_name_run("via_run", run_id).result

    message = "#{greeting}, #{name}!"
    Logger.info("[greet] #{message}")
  end
end
