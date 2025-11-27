defmodule Dag.GraphTest do
  alias Gust.DAG.Graph
  use Gust.DataCase

  @graph %{
    "bye" => %{
      downstream: MapSet.new([]),
      upstream: MapSet.new(["for_me", "wait"])
    },
    "hi" => %{
      downstream: MapSet.new(["for_me", "wait"]),
      upstream: MapSet.new([])
    },
    "for_me" => %{
      downstream: MapSet.new(["bye"]),
      upstream: MapSet.new(["hi"])
    },
    "wait" => %{
      downstream: MapSet.new(["bye"]),
      upstream: MapSet.new(["hi"])
    }
  }

  describe "build_branch/3" do
    test "when direction is upstream" do
      direction = :upstream

      assert [
               "bye",
               ["for_me", ["hi"]],
               ["wait", ["hi"]]
             ] =
               Graph.build_branch(@graph, direction, "bye")
    end

    test "when direction is downstream" do
      direction = :downstream

      assert [
               "hi",
               ["for_me", ["bye"]],
               ["wait", ["bye"]]
             ] =
               Graph.build_branch(@graph, direction, "hi")
    end
  end

  describe "to_stage/1" do
    test "no cycle detected" do
      stages = [
        ["hi"],
        ["for_me", "wait"],
        ["bye"]
      ]

      assert Graph.to_stages(@graph) == {:ok, stages}
    end

    test "cycle is detected" do
      graph =
        %{
          "bye" => %{
            downstream: MapSet.new(["hi"]),
            upstream: MapSet.new(["hi"])
          },
          "hi" => %{
            downstream: MapSet.new(["bye"]),
            upstream: MapSet.new(["bye"])
          }
        }

      assert {:error, %Graph.CycleDection{message: "Possible cycle detected"}} ==
               Graph.to_stages(graph)
    end
  end

  describe "link_tasks/1" do
    test "linked tasks map" do
      tasks_list = [
        {:bye, []},
        {:wait, [downstream: [:bye]]},
        {:for_me, [downstream: [:bye]]},
        {:hi, [downstream: [:wait, :for_me]]}
      ]

      assert @graph == Graph.link_tasks(tasks_list)
    end
  end
end
