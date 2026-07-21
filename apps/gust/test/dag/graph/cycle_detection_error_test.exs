defmodule DAG.Graph.CycleDetectionErrorTest do
  alias Gust.DAG.Graph.CycleDetectionError
  use Gust.DataCase

  test "error message" do
    assert_raise(CycleDetectionError, "Possible cycle detected", fn ->
      raise CycleDetectionError
    end)
  end
end
