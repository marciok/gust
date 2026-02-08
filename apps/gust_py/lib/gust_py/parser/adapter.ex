defmodule GustPy.Parser.Adapter do
  @behaviour Gust.DAG.Parser.Adapter
  alias Gust.DAG.Definition
  alias Gust.DAG.Graph
  alias GustPy.Executor

  @impl true
  def extension, do: ".py"

  @impl true
  def parse_file(file_path) do
    name = Path.basename(file_path, extension())

    with {out, 0} <- Executor.parse_dag(file_path),
         [dag_json | _] <- Jason.decode!(out),
         {:ok, dag_def} <- parse_dag_def(dag_json, name) do
      {:ok, dag_def}
    else
      {:error, error} ->
        {:error, error}

      {_out, exit} ->
        {:error, {[line: ""], "Parse file command failed, exit: #{exit}", ""}}
    end
  end

  defp put_store_result(tasks, all_tasks) do
    for {t_name, opts} <- tasks, into: %{} do
      {t_name, Map.put(opts, :store_result, all_tasks[t_name]["save"])}
    end
  end

  defp parse_dag_def(%{"error" => error}, _name) when map_size(error) > 0 do
    {:error, {[line: error["line"]], "parsing error", error["description"]}}
  end

  defp parse_dag_def(
         %{"mod" => mod, "tasks" => tasks, "options" => opts, "file_path" => file_path},
         name
       ) do
    list = parse_deps(tasks)

    tasks = Graph.link_tasks(list) |> put_store_result(tasks)

    stages = tasks |> Graph.to_stages() |> then(fn {:ok, stages} -> stages end)

    options = for {k, v} <- opts, into: [], do: {String.to_atom(k), v}

    {:ok,
     %Definition{
       name: name,
       mod: mod,
       adapter: :python,
       task_list: List.flatten(stages),
       stages: stages,
       file_path: file_path,
       options: options,
       tasks: tasks
     }}
  end

  defp parse_deps(tasks) do
    for {task_name, %{"deps" => deps}} <- tasks do
      options = [downstream: Enum.map(deps, &String.to_atom/1)]
      {String.to_atom(task_name), options}
    end
  end
end
