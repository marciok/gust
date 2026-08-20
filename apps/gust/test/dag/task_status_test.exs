defmodule Gust.DAG.TaskStatusTest do
  use ExUnit.Case, async: true

  alias Gust.DAG.TaskStatus

  test "classifies cancellable statuses" do
    assert TaskStatus.cancellable_statuses() == [:running, :retrying, :waiting]

    assert Enum.all?(TaskStatus.cancellable_statuses(), &TaskStatus.cancellable?/1)
    refute TaskStatus.cancellable?(:failed)
  end

  test "classifies restartable statuses" do
    assert TaskStatus.restartable_statuses() == [:failed, :succeeded]

    assert Enum.all?(TaskStatus.restartable_statuses(), &TaskStatus.restartable?/1)
    refute TaskStatus.restartable?(:running)
  end
end
