defmodule Gust.DAG.MappedTasksTest do
  use ExUnit.Case, async: true

  alias Gust.DAG.MappedTasks

  describe "validate!/1" do
    test "accepts an empty config and a positive limit" do
      assert :ok = MappedTasks.validate!([])
      assert :ok = MappedTasks.validate!(max_parallel: 20)
    end

    test "rejects non-positive or non-integer values" do
      assert_raise ArgumentError, ~r/:max_parallel/, fn ->
        MappedTasks.validate!(max_parallel: 0)
      end

      assert_raise ArgumentError, ~r/:max_parallel/, fn ->
        MappedTasks.validate!(max_parallel: "2")
      end
    end

    test "rejects unknown options" do
      assert_raise ArgumentError, fn -> MappedTasks.validate!(max_parallel: 2, page: 1) end
    end
  end

  describe "page_size/2" do
    test "is nil when no limit is configured" do
      assert MappedTasks.page_size(1_000, []) == nil
    end

    test "is nil at or below the limit" do
      assert MappedTasks.page_size(20, max_parallel: 20) == nil
    end

    test "is the limit above it" do
      assert MappedTasks.page_size(21, max_parallel: 20) == 20
    end
  end
end
