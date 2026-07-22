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

  test "chart/3 assigns task status and selection classes" do
    tasks = %{
      "A" => %{downstream: MapSet.new(["B"]), upstream: MapSet.new()},
      "B" => %{downstream: MapSet.new(), upstream: MapSet.new(["A"])}
    }

    chart =
      Mermaid.chart(
        tasks,
        %{
          "A" => :running,
          "B" => :none,
          "removed_task" => :failed
        },
        ["A", "removed_task"]
      )

    assert chart =~ "class A status-running"
    assert chart =~ "class B status-none"
    assert chart =~ "class A selected-task"
    refute chart =~ "removed_task"
  end

  test "chart/2 ignores unsupported statuses" do
    tasks = %{"A" => %{downstream: MapSet.new(), upstream: MapSet.new()}}

    refute Mermaid.chart(tasks, %{"A" => :unknown}) =~ "class A"
  end
end
