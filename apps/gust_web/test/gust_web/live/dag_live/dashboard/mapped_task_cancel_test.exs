defmodule GustWeb.DagLive.Dashboard.MappedTaskCancelTest do
  use ExUnit.Case, async: true

  import Mox

  alias Gust.Flows.Task
  alias GustWeb.DagLive.Dashboard.{MappedTasks, TaskActions}

  setup :verify_on_exit!

  test "a selected queued instance can be cancelled" do
    tasks = [%Task{id: 1, status: :created}, %Task{id: 2, status: :succeeded}]

    assert MappedTasks.cancelable?(tasks, [1])
    refute MappedTasks.cancelable?(tasks, [2])
  end

  test "bulk cancel sends queued instances to the run owner" do
    task = %Task{id: 1, name: "mapped", status: :created}

    expect(GustWeb.DAGTerminatorMock, :cancel, fn ^task -> {:ok, task} end)

    assert TaskActions.cancel_many([task]) == {:info, "1 tasks canceled"}
  end

  test "cancelling a single created task is still a no-op" do
    task = %Task{id: 1, name: "plain", status: :created}

    assert TaskActions.cancel(task) == {:info, "Task: plain is not running"}
  end
end
