defmodule GustShell.Parser.Adapter do
  @moduledoc false

  @behaviour Gust.DAG.Parser.Adapter

  alias Gust.DAG.{Definition, Graph}

  @impl true
  def extension, do: ".yml"

  @impl true
  def parse_file(file_path) do
    with {:ok, yaml} <- read_yaml(file_path),
         {:ok, dag_def} <- build_definition(yaml, file_path) do
      {:ok, dag_def}
    else
      {:error, reason} ->
        {:error, {[], "invalid shell DAG", inspect(reason)}}
    end
  end

  defp read_yaml(file_path) do
    try do
      {:ok, :glazer_yaml.read_file(file_path)}
    rescue
      e -> {:error, e}
    end
  end

  defp build_definition(yaml, file_path) do
    name = Path.basename(file_path, extension())
    task_entries = tasks_from_yaml(yaml)
    task_list = Enum.map(task_entries, &task_graph_entry/1)
    graph = Graph.link_tasks(task_list)
    tasks = merge_task_options(graph, task_entries)
    stages = Graph.to_stages(graph) |> then(fn {:ok, stages} -> stages end)

    {:ok,
     %Definition{
       name: name,
       adapter: :shell,
       file_path: file_path,
       options: parse_options(yaml),
       task_list: List.flatten(stages),
       stages: stages,
       tasks: tasks
     }}
  end

  defp tasks_from_yaml(yaml) do
    case Map.get(yaml, "tasks") || Map.get(yaml, :tasks) || [] do
      tasks when is_list(tasks) -> tasks
      task when is_map(task) -> [task]
      _ -> []
    end
  end

  defp task_graph_entry(task) do
    task_name = fetch_task_name(task)
    downstream = fetch_downstream(task)
    {to_string(task_name), [downstream: downstream]}
  end

  defp fetch_task_name(task) do
    task["name"] || task[:name] ||
      raise ArgumentError, "shell task is missing a name"
  end

  defp fetch_downstream(task) do
    case task["downstream"] || task[:downstream] || [] do
      list when is_list(list) -> Enum.map(list, &to_string/1)
      value -> [to_string(value)]
    end
  end

  defp merge_task_options(graph, task_entries) do
    task_params =
      Enum.reduce(task_entries, %{}, fn task, acc ->
        name = to_string(fetch_task_name(task))
        Map.put(acc, name, normalize_task(task))
      end)

    Enum.reduce(graph, %{}, fn {name, node}, acc ->
      downstream = node[:downstream] |> MapSet.to_list() |> Enum.map(&to_string/1)
      task = Map.get(task_params, name, %{})
      Map.put(acc, name, Map.put(task, "downstream", downstream))
    end)
  end

  defp normalize_task(task) do
    task
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      Map.put(acc, normalize_key(key), normalize_value(value))
    end)
    |> Map.delete("name")
  end

  defp normalize_key(key) do
    key |> to_string() |> String.trim_leading("$")
  end

  defp normalize_value(value) when is_map(value) do
    Map.new(value, fn {key, item} -> {normalize_key(key), normalize_value(item)} end)
  end

  defp normalize_value(value) when is_list(value) do
    Enum.map(value, &normalize_value/1)
  end

  defp normalize_value(value), do: value

  defp parse_options(yaml) do
    Enum.reduce([:schedule, :on_finished_callback], [], fn key, acc ->
      value = yaml[to_string(key)] || yaml[key]

      if value == nil do
        acc
      else
        Keyword.put(acc, key, value)
      end
    end)
  end
end
