defmodule GustWeb.DagLive.Dashboard.SelectedItemTest do
  use ExUnit.Case, async: true

  alias Gust.Flows.Task
  alias GustWeb.DagLive.Dashboard.SelectedItem

  defp group(statuses), do: Enum.map(statuses, &%Task{status: &1})

  describe "status/1 for a group of mapped instances" do
    test "is running between pages of instances" do
      assert :running == SelectedItem.status(group([:succeeded, :created]))
      assert :running == SelectedItem.status(group([:skipped, :enqueued]))
    end

    test "keeps failures and retries ahead of running" do
      assert :failed == SelectedItem.status(group([:succeeded, :created, :failed]))
      assert :retrying == SelectedItem.status(group([:succeeded, :created, :retrying]))
    end

    test "is created before any instance starts" do
      assert :created == SelectedItem.status(group([:created, :created]))
    end

    test "is succeeded once every instance succeeded" do
      assert :succeeded == SelectedItem.status(group([:succeeded, :succeeded]))
    end
  end
end
