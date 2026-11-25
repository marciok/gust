defmodule GustPy.Parser.Adapter do
  @moduledoc false

  @behaviour Gust.DAG.Parser.Adapter
  alias Gust.DAG.Definition
  alias Gust.DAG.Graph
  alias Gust.DAG.Options
  alias GustPy.Executor

  @impl true
  def extension, do: ".py"

  @impl true
  def parse_file(file_path) do
    name = Path.basename(file_path, extension())

    with {out, 0} <- Executor.run(["parse", "--file", file_path]),
         [dag_json | _] <- Jason.decode!(out),
         {:ok, dag_def} <- parse_dag_def(dag_json, name) do
      {:ok, dag_def}
    else
      {:error, :uv_not_found} ->
        error =
          {[], "`uv` executable not found on your PATH", ""}

        {:error, error}

      [] ->
        error = {[], "Not a GustPy file", ""}
        {:error, error}

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
    list = parse_downstream(tasks)

    tasks = Graph.link_tasks(list) |> put_store_result(tasks)

    stages = tasks |> Graph.to_stages() |> then(fn {:ok, stages} -> stages end)

    case Options.from_json(opts) do
      {:ok, options} ->
        {:ok,
         %Definition{
           name: name,
           mod: mod,
           adapter: :python,
           task_list: List.flatten(stages),
           stages: stages,
           file_path: file_path,
           options: options,
           messages: Options.warnings(options, file_path),
           tasks: tasks
         }}

      {:error, message} ->
        {error, messages} = Options.definition_error(file_path, message)

        {:ok,
         %Definition{
           name: name,
           mod: mod,
           adapter: :python,
           file_path: file_path,
           error: error,
           messages: messages
         }}
    end
  end

  defp parse_downstream(tasks) do
    for {task_name, %{"downstream" => deps}} <- tasks do
      {task_name, [downstream: deps]}
    end
  end
end
