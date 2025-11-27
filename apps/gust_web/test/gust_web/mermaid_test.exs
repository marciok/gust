defmodule GustWeb.MermaidTest do
  use ExUnit.Case, async: true

  alias GustWeb.Mermaid

  defp edges_from_chart(chart) do
    chart
    |> String.split("\n", parts: 2)
    |> List.last()
    |> String.trim()
    |> String.split(~r/\R+/, trim: true)
    |> Enum.reject(&(&1 == ""))
    |> MapSet.new()
  end

  test "chart/1 with a single task and no upstream deps" do
    tasks = [
      {"A", %{downstream: MapSet.new(), upstream: MapSet.new()}}
    ]

    assert Mermaid.chart(tasks) == "flowchart LR\n \nA"
  end

  test "chart/1 with a single upstream dependency" do
    tasks = [
      {"A", %{downstream: MapSet.new(), upstream: MapSet.new(["X"])}}
    ]

    assert Mermaid.chart(tasks) == "flowchart LR\n \nX --> A"
  end

  test "chart/1 with multiple tasks and multiple upstreams (order-agnostic)" do
    tasks = [
      {"B", %{downstream: MapSet.new(), upstream: MapSet.new(["A", "C"])}},
      {"D", %{downstream: MapSet.new(), upstream: MapSet.new(["B"])}}
    ]

    chart = Mermaid.chart(tasks)

    assert String.starts_with?(chart, "flowchart LR\n")

    expected_edges =
      MapSet.new([
        "A --> B",
        "C --> B",
        "B --> D"
      ])

    assert edges_from_chart(chart) == expected_edges
  end

  test "chart/1 accepts a map of tasks as well (order-agnostic)" do
    tasks =
      %{
        "B" => %{downstream: MapSet.new(), upstream: MapSet.new(["A"])},
        "C" => %{downstream: MapSet.new(), upstream: MapSet.new(["A"])},
        "D" => %{downstream: MapSet.new(), upstream: MapSet.new(["B", "C"])}
      }

    chart = Mermaid.chart(tasks)

    expected_edges =
      MapSet.new([
        "A --> B",
        "A --> C",
        "B --> D",
        "C --> D"
      ])

    assert edges_from_chart(chart) == expected_edges
  end
end
