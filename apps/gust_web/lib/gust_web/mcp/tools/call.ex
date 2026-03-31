defmodule GustWeb.MCP.Tools.Call do
  @moduledoc false

  alias Gust.DAG.{Adapter, Definition, Loader, Terminator}
  alias Gust.DAG.Run.Trigger
  alias Gust.Flows
  alias GustWeb.MCP.{Content, Tool}

  def handle(%Tool{name: :list_dags}, _args) do
    {false,
     for {id, {:ok, %Definition{name: name, file_path: fp, options: opts, error: e}}} <-
           Loader.get_definitions() do
       Content.new(
         "Name: #{name}; ID: #{id}; Error: #{inspect(e)}, Options: #{inspect(opts)} file_path: #{fp}"
       )
     end}
  end

  def handle(%Tool{name: :list_secrets}, _args) do
    {false,
     for %Flows.Secret{name: name, id: id, value_type: type} <- Flows.list_secrets() do
       Content.new("Name: #{name}; ID: #{id}; Type: #{type}")
     end}
  end

  def handle(%Tool{name: :query_dag_run}, %{
        "dag_name" => dag_name,
        "limit" => limit,
        "offset" => offset
      }) do
    dag = Flows.get_dag_by_name_with_runs!(dag_name, limit: limit, offset: offset)

    {false,
     for %Flows.Run{id: id, inserted_at: inserted_at, updated_at: updated, status: status} <-
           dag.runs do
       Content.new(
         "ID: #{id}; Inserted at: #{inserted_at}; Updated at: #{updated}; Status: #{status}"
       )
     end}
  end

  def handle(%Tool{name: :get_dag_def}, %{"dag_id" => dag_id}) do
    {_,
     %Definition{
       name: name,
       adapter: adapter,
       options: opts,
       tasks: tasks,
       stages: stages,
       error: e,
       mod: mod,
       file_path: fp
     }} = Loader.get_definition(dag_id)

    {false,
     [
       Content.new(
         "Name: #{name}; ID: #{dag_id}; Error: #{inspect(e)}, Options: #{inspect(opts)} File path: #{fp}; Stages: #{inspect(stages)}; Module: #{mod}: Adapter: #{adapter}; Tasks: #{inspect(tasks)}"
       )
     ]}
  end

  def handle(%Tool{name: :get_tasks_on_run}, %{"run_id" => run_id}) do
    run = Flows.get_run_with_tasks!(run_id)

    {false,
     for %Flows.Task{id: id, name: name, status: status, error: e, result: res} <-
           run.tasks do
       Content.new(
         "ID: #{id}; Name: #{name}, Status: #{status}; Error: #{inspect(e)}, Result: #{inspect(res)}"
       )
     end}
  end

  def handle(%Tool{name: :restart_run}, %{"run_id" => run_id}) do
    run = Flows.get_run!(run_id) |> Trigger.reset_run()

    {false, ["Run: #{run.id} was restarted"]}
  end

  def handle(%Tool{name: :restart_task}, %{"task_id" => task_id}) do
    task = Flows.get_task!(task_id)
    dag_def = get_def_by_task(task)
    tasks_graph = dag_def.tasks

    Trigger.reset_task(tasks_graph, task)

    {false, ["Task: #{task.name} was restarted"]}
  end

  def handle(%Tool{name: :cancel_task}, %{"task_id" => task_id}) do
    task = Flows.get_task!(task_id)
    dag_def = get_def_by_task(task)

    text =
      case task.status do
        :running ->
          runtime = Adapter.impl!(dag_def.adapter, :runtime)
          Terminator.kill_task(task, :cancelled, runtime)
          "Task: #{task.name} was cancelled"

        :retrying ->
          Terminator.cancel_timer(task, :cancelled)
          "Task: #{task.name} retrying cancelled"
      end

    {false, [text]}
  end

  def handle(%Tool{name: :trigger_dag_run}, %{"dag_name" => dag_name}) do
    dag = Flows.get_dag_by_name(dag_name)
    {:ok, run} = Flows.create_run(%{dag_id: dag.id})

    run = Flows.get_run_with_tasks!(run.id) |> Trigger.dispatch_run()

    {false, ["Run #{run.id} triggered"]}
  end

  defp get_def_by_task(task) do
    run = Flows.get_run!(task.run_id)
    Loader.get_definition(run.dag_id)
  end
end
