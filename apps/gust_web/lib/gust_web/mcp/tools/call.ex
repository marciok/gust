defmodule GustWeb.MCP.Tools.Call do
  @moduledoc false

  alias Gust.DAG.{Adapter, Definition, Loader, Terminator}
  alias Gust.DAG.Run.Trigger
  alias Gust.Flows
  alias GustWeb.MCP.{Content, Tool, Tools}

  def handle(%Tool{name: :list_dags}, _args) do
    {false,
     for {id, {:ok, %Definition{} = dag_def}} <-
           Loader.get_definitions() do
       dag_def_text(id, dag_def) |> content()
     end}
  end

  def handle(%Tool{name: :list_secrets}, _args) do
    {false,
     for %Flows.Secret{name: name, id: id, value_type: type} <- Flows.list_secrets() do
       content("Name: #{name}; ID: #{id}; Type: #{type}")
     end}
  end

  def handle(%Tool{name: :query_dag_run}, %{
        "dag_name" => dag_name,
        "limit" => limit,
        "offset" => offset
      }) do
    dag = Flows.get_dag_by_name(dag_name)

    if dag do
      dag = Flows.get_dag_by_name_with_runs!(dag_name, limit: limit, offset: offset)

      {false,
       for %Flows.Run{id: id, inserted_at: inserted_at, updated_at: updated, status: status} <-
             dag.runs do
         content(
           "ID: #{id}; Inserted at: #{inserted_at}; Updated at: #{updated}; Status: #{status}"
         )
       end}
    else
      dag_not_found(dag_name)
    end
  end

  def handle(%Tool{name: :get_dag_def}, %{"dag_name" => dag_name}) do
    dag = Flows.get_dag_by_name(dag_name)

    if dag do
      dag.id |> dag_definition_reply()
    else
      dag_not_found(dag_name)
    end
  end

  def handle(%Tool{name: :get_dag_def}, %{"dag_id" => dag_id}) do
    dag_id |> dag_definition_reply()
  end

  def handle(%Tool{name: :get_tasks_on_run}, %{"run_id" => run_id}) do
    run = Flows.get_run_with_tasks!(run_id)

    {false,
     for %Flows.Task{id: id, name: name, status: status, error: e, result: res} <-
           run.tasks do
       content(
         "ID: #{id}; Name: #{name}, Status: #{status}; Error: #{inspect(e)}, Result: #{inspect(res)}"
       )
     end}
  end

  def handle(%Tool{name: :get_logs_on_task}, %{"task_id" => task_id}) do
    task = Flows.get_task_with_logs!(task_id)

    {false,
     for %Flows.Log{id: id, level: lvl, inserted_at: inserted_at, content: content} <-
           task.logs do
       content(
         "ID: #{id}; level: #{lvl}, inserted_at: #{inspect(inserted_at)}; Content: #{content}"
       )
     end}
  end

  def handle(%Tool{name: :restart_run}, %{"run_id" => run_id}) do
    run = Flows.get_run!(run_id) |> Trigger.reset_run()

    {false, [content("Run: #{run.id} was restarted")]}
  end

  def handle(%Tool{name: :restart_task}, %{"task_id" => task_id}) do
    task = Flows.get_task!(task_id)
    {:ok, dag_def} = get_def_by_task(task)
    tasks_graph = dag_def.tasks

    Trigger.reset_task(tasks_graph, task)

    {false, [content("Task: #{task.name} was restarted")]}
  end

  def handle(%Tool{name: :cancel_task}, %{"task_id" => task_id}) do
    task = Flows.get_task!(task_id)
    {:ok, dag_def} = get_def_by_task(task)

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

    {false, [content(text)]}
  end

  def handle(%Tool{name: :trigger_dag_run}, %{"dag_id" => dag_id}) do
    dag_id |> trigger_dag_run_reply()
  end

  def handle(%Tool{name: :trigger_dag_run}, %{"dag_name" => dag_name}) do
    dag = Flows.get_dag_by_name(dag_name)

    if dag do
      dag.id |> trigger_dag_run_reply()
    else
      dag_not_found(dag_name)
    end
  end

  def handle(%Tool{name: name} = tool, _args) do
    tool = Tools.find(to_string(name)) || tool

    {true, [content(invalid_properties_text(tool))]}
  end

  defp get_def_by_task(task) do
    run = Flows.get_run!(task.run_id)
    Loader.get_definition(run.dag_id)
  end

  defp dag_definition_reply(id) do
    {:ok, dag_def} = Loader.get_definition(id)
    {false, [dag_def_text(id, dag_def) |> content()]}
  end

  defp dag_def_text(
         dag_id,
         %Definition{
           name: name,
           adapter: adapter,
           options: opts,
           tasks: tasks,
           stages: stages,
           messages: warnings,
           error: e,
           mod: mod,
           file_path: fp
         }
       ) do
    """
    Name: #{name}
    ID: #{dag_id}
    File Path: #{fp}
    Options: #{inspect(opts)}
    Stages: #{inspect(stages)}
    Module: #{mod}
    Adapter: #{adapter}
    Tasks: #{inspect(tasks)}
    Error: #{inspect(e)}
    Warnings: #{inspect(warnings)}
    """
  end

  defp trigger_dag_run_reply(dag_id) do
    {:ok, run} = Flows.create_run(%{dag_id: dag_id})

    run = Flows.get_run_with_tasks!(run.id) |> Trigger.dispatch_run()

    {false, [content("Run #{run.id} triggered")]}
  end

  defp invalid_properties_text(%Tool{name: name, props: []}) do
    "Tool #{name} supports no properties."
  end

  defp invalid_properties_text(%Tool{name: name, props: props}) do
    properties =
      Enum.map_join(props, ", ", fn {prop_name, _required, %{"description" => description}} ->
        "#{prop_name}: #{description}"
      end)

    "Tool #{name} supports the following properties: #{properties}"
  end

  defp content(txt), do: Content.new(txt)

  defp dag_not_found(name) do
    {true,
     [
       content("DAG with name #{name} does not exists. Use list_dags to find available DAG names")
     ]}
  end
end
