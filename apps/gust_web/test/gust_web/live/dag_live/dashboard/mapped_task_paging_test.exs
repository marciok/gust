defmodule GustWeb.DagLive.Dashboard.MappedTaskPagingTest do
  use ExUnit.Case, async: false

  alias Gust.Flows.Task
  alias GustWeb.DagLive.Dashboard.MappedTasks

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

  test "is nil at or below the limit" do
    assert MappedTasks.paging(tasks([:running, :created]), "", nil) == nil
  end

  test "is nil when no limit is configured" do
    Application.delete_env(:gust, :mapped_tasks)

    assert MappedTasks.paging(tasks([:running, :created, :created]), "", nil) == nil
  end

  test "rounds the page total up" do
    assert %{size: 2, total: 3} = MappedTasks.paging(tasks(List.duplicate(:created, 5)), "", nil)
  end

  test "opens the page of the furthest active instance" do
    statuses = [:running, :succeeded, :succeeded, :succeeded, :retrying, :created]

    assert %{page: 3, running: 3, total: 3} = MappedTasks.paging(tasks(statuses), "", nil)
  end

  test "opens the first pending page when nothing is active" do
    statuses = [:succeeded, :failed, :succeeded, :created, :created]

    assert %{page: 2, running: nil} = MappedTasks.paging(tasks(statuses), "", nil)
  end

  test "opens the last page when every instance has finished" do
    statuses = [:succeeded, :failed, :succeeded, :skipped, :succeeded]

    assert %{page: 3, running: nil, total: 3} = MappedTasks.paging(tasks(statuses), "", nil)
  end

  test "keeps a requested page while another one runs" do
    statuses = [:running, :created, :created, :created, :created]

    assert %{page: 3, running: 1} = MappedTasks.paging(tasks(statuses), "", 3)
  end

  test "clamps a requested page to the last one" do
    assert %{page: 2} = MappedTasks.paging(tasks(List.duplicate(:created, 3)), "", 9)
  end

  test "pages the matching instances when filtering" do
    statuses = [:running, :failed, :created, :failed, :failed]

    assert %{page: 1, running: nil, total: 2} = MappedTasks.paging(tasks(statuses), "failed", nil)
  end

  test "keeps one page when no instance matches the filter" do
    assert %{page: 1, total: 1} =
             MappedTasks.paging(tasks(List.duplicate(:created, 3)), "failed", nil)
  end

  test "only exposes the instances of the displayed page" do
    tasks = tasks(List.duplicate(:created, 5))

    assert [%{map_index: 2}, %{map_index: 3}] =
             MappedTasks.visible(tasks, "", %{size: 2, page: 2})

    assert [%{map_index: 4}] = MappedTasks.visible(tasks, "", %{size: 2, page: 3})
  end

  test "exposes every instance when not paged" do
    tasks = tasks([:running, :created])

    assert MappedTasks.visible(tasks, "", nil) == tasks
  end

  defp tasks(statuses) do
    statuses
    |> Enum.with_index()
    |> Enum.map(fn {status, index} -> %Task{id: index, map_index: index, status: status} end)
  end
end
