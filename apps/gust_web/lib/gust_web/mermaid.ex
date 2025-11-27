defmodule GustWeb.Mermaid do
  @moduledoc false
  def chart(tasks) do
    tasks
    |> Enum.reduce("flowchart LR\n ", fn {name, %{upstream: upstream}}, flow_description ->
      upstream = upstream |> MapSet.to_list()
      lines = name |> build_lines(upstream)

      "#{flow_description}#{lines}"
    end)
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
end
