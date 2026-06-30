defmodule ParentWaitsForChild do
  use Gust.DSL

  require Logger

  alias Gust.DAG.Run.Trigger
  alias Gust.Flows

  @child_dag_name "child_resumes_parent"
  @wait_key "child_dag_finished"

  task :trigger_child, downstream: [:wait_for_child], save: true, ctx: %{run_id: run_id} do
    child_dag = Flows.get_dag_by_name(@child_dag_name)

    {:ok, child_run} =
      Flows.create_run(%{
        dag_id: child_dag.id,
        params: %{
          "parent_run_id" => run_id,
          "wait_key" => @wait_key,
          "message" => "hello from parent run #{run_id}"
        }
      })

    child_run =
      child_run.id
      |> Flows.get_run_with_tasks!()
      |> Trigger.dispatch_run()

    Logger.info("Triggered child run #{child_run.id} for parent run #{run_id}")

    %{child_run_id: child_run.id}
  end

  task :wait_for_child,
    wait_for: @wait_key,
    save: true,
    ctx: %{params: %{"__gust_wait_payload__" => payload}} do
    if payload["child_status"] != "ok" do
      raise "Child DAG finished with status #{inspect(payload["child_status"])}"
    end

    result = payload["child_result"]
    Logger.info("Child DAG completed with result: #{inspect(result)}")

    %{child_result: result}
  end
end
