defmodule GustWeb.Mermaid do
  @moduledoc false

  @task_statuses [:none | Ecto.Enum.values(Gust.Flows.Task, :status)]

  def chart(tasks, task_statuses \\ %{}, selected_tasks \\ []) do
    task_names = tasks |> Enum.map(fn {name, _task} -> name end) |> MapSet.new()

    flowchart =
      Enum.reduce(tasks, "flowchart LR\n ", fn {name, %{upstream: upstream}}, flow_description ->
        lines = build_lines(name, MapSet.to_list(upstream))

        "#{flow_description}#{lines}"
      end)

    flowchart <>
      build_status_classes(task_statuses, task_names) <>
      build_selected_classes(selected_tasks, task_names)
  end

  defp build_lines(name, []) do
    "\n#{name}"
  end

  defp build_lines(name, upstream) do
    upstream
    |> Enum.reduce("", fn upstream_name, line ->
      "#{line}\n#{upstream_name} --> #{name}"
    end)
  end

  defp build_status_classes(task_statuses, task_names) do
    task_statuses
    |> Enum.filter(fn {name, status} ->
      MapSet.member?(task_names, name) and status in @task_statuses
    end)
    |> Enum.sort_by(fn {name, _status} -> name end)
    |> Enum.map_join(fn {name, status} -> "\nclass #{name} status-#{status}" end)
  end

  defp build_selected_classes(selected_tasks, task_names) do
    selected_tasks
    |> Enum.filter(&MapSet.member?(task_names, &1))
    |> Enum.sort()
    |> Enum.map_join(&"\nclass #{&1} selected-task")
  end
end
