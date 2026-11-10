defmodule Gust.DAG.Runner.TaskPagerTest do
  use ExUnit.Case, async: false

  alias Gust.DAG.Runner.TaskPager

  setup do
    previous = Application.fetch_env(:gust, :mapped_tasks)
    Application.put_env(:gust, :mapped_tasks, max_parallel: 2)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:gust, :mapped_tasks, value)
        :error -> Application.delete_env(:gust, :mapped_tasks)
      end
    end)
  end

  test "leaves ordinary tasks and expansions within the limit alone" do
    stage = [
      {:ok, task(1, "plain", nil)},
      {:ok, task(2, "mapped", 0)},
      {:ok, task(3, "mapped", 1)}
    ]

    assert {%TaskPager{} = pager, ^stage} = TaskPager.new(stage)
    assert TaskPager.settle(pager, 2) == {pager, []}
  end

  test "starts the first page and queues the rest in map_index order" do
    stage = Enum.map([3, 0, 2, 1, 4], &{:ok, task(&1 + 10, "mapped", &1)})

    {pager, startable} = TaskPager.new(stage)

    assert startable |> Enum.map(fn {:ok, task} -> task.id end) |> Enum.sort() == [10, 11]
    refute TaskPager.queued?(pager, 10)
    assert TaskPager.queued?(pager, 12)
    assert TaskPager.queued?(pager, 13)
    assert TaskPager.queued?(pager, 14)
  end

  test "starts the next page only after the whole current page settles" do
    {pager, _startable} = TaskPager.new(mapped_stage(5))

    assert {pager, []} = TaskPager.settle(pager, 0)
    assert {pager, [2, 3]} = TaskPager.settle(pager, 1)
    refute TaskPager.queued?(pager, 2)
    assert TaskPager.queued?(pager, 4)

    assert {pager, []} = TaskPager.settle(pager, 2)
    assert {pager, [4]} = TaskPager.settle(pager, 3)
    assert {_pager, []} = TaskPager.settle(pager, 4)
  end

  test "ignores tasks outside the active page" do
    {pager, _startable} = TaskPager.new(mapped_stage(3))

    assert {^pager, []} = TaskPager.settle(pager, 2)
    assert {^pager, []} = TaskPager.settle(pager, 999)
  end

  test "does not start dropped tasks" do
    {pager, _startable} = TaskPager.new(mapped_stage(5))

    pager = TaskPager.drop(pager, 2)
    refute TaskPager.queued?(pager, 2)

    {pager, []} = TaskPager.settle(pager, 0)
    assert {_pager, [3, 4]} = TaskPager.settle(pager, 1)
  end

  describe "admit/2" do
    test "starts tasks that are not paged" do
      {pager, _startable} = TaskPager.new([{:ok, task(1, "mapped", 0)}])

      assert TaskPager.admit(pager, task(1, "mapped", 0)) == {:start, pager}
    end

    test "starts a restart while the page has capacity and holds the page for it" do
      {pager, _startable} = TaskPager.new(mapped_stage(3))
      {pager, []} = TaskPager.settle(pager, 0)

      assert {:start, pager} = TaskPager.admit(pager, task(0, "mapped", 0))
      refute TaskPager.queued?(pager, 0)

      assert {pager, []} = TaskPager.settle(pager, 1)
      assert {_pager, [2]} = TaskPager.settle(pager, 0)
    end

    test "queues a restart ahead of the next page when the page is full" do
      {pager, _startable} = TaskPager.new(mapped_stage(5))
      {pager, []} = TaskPager.settle(pager, 0)
      {pager, [2, 3]} = TaskPager.settle(pager, 1)

      assert {:queued, pager} = TaskPager.admit(pager, task(1, "mapped", 1))
      assert TaskPager.queued?(pager, 1)

      {pager, []} = TaskPager.settle(pager, 2)
      assert {pager, [1, 4]} = TaskPager.settle(pager, 3)
      refute TaskPager.queued?(pager, 1)

      {pager, []} = TaskPager.settle(pager, 1)
      assert {_pager, []} = TaskPager.settle(pager, 4)
    end

    test "applies the limit to instances finished before a reclaim" do
      stage = [{:already_processed, task(0, "mapped", 0)} | Enum.drop(mapped_stage(3), 1)]
      {pager, _startable} = TaskPager.new(stage)

      assert {:queued, pager} = TaskPager.admit(pager, task(0, "mapped", 0))
      assert TaskPager.queued?(pager, 0)
    end

    test "starts a cancelled queued instance only once when restarted" do
      {pager, _startable} = TaskPager.new(mapped_stage(3))
      pager = TaskPager.drop(pager, 2)

      {:queued, pager} = TaskPager.admit(pager, task(2, "mapped", 2))

      {pager, []} = TaskPager.settle(pager, 0)
      assert {_pager, [2]} = TaskPager.settle(pager, 1)
    end
  end

  test "counts finished instances but never pages them" do
    stage = [
      {:already_processed, task(0, "mapped", 0)},
      {:ok, task(1, "mapped", 1)},
      {:ok, task(2, "mapped", 2)},
      {:ok, task(3, "mapped", 3)}
    ]

    {pager, startable} = TaskPager.new(stage)

    assert Enum.map(startable, fn {_status, task} -> task.id end) == [0, 1, 2]
    assert TaskPager.queued?(pager, 3)
  end

  test "pages each mapped task independently" do
    stage = mapped_stage(3) ++ Enum.map(0..2, &{:ok, task(&1 + 10, "other", &1)})

    {pager, startable} = TaskPager.new(stage)

    assert length(startable) == 4
    assert TaskPager.queued?(pager, 2)
    assert TaskPager.queued?(pager, 12)

    {pager, []} = TaskPager.settle(pager, 0)
    assert {_pager, [2]} = TaskPager.settle(pager, 1)
  end

  defp mapped_stage(count), do: Enum.map(0..(count - 1), &{:ok, task(&1, "mapped", &1)})

  defp task(id, name, map_index), do: %{id: id, name: name, map_index: map_index}
end
