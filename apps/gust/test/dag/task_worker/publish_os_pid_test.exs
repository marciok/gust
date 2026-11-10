defmodule Gust.DAG.TaskWorker.PublishOsPidTest do
  use ExUnit.Case, async: true

  alias Gust.DAG.TaskWorker

  setup do
    task = %{id: System.unique_integer([:positive]), map_index: nil}
    key = TaskWorker.registry_name(task)
    {:ok, _owner} = Registry.register(Gust.Registry, key, nil)

    %{task: task, key: key}
  end

  test "publishes a new os_pid stored by the callback", %{task: task, key: key} do
    result = {:noreply, %{task: task, os_pid: 4242}}

    assert TaskWorker.publish_os_pid(result, %{task: task}) == result
    assert [{_pid, %{os_pid: 4242}}] = Registry.lookup(Gust.Registry, key)
  end

  test "keeps the registry value when the os_pid did not change", %{task: task, key: key} do
    TaskWorker.publish_os_pid({:noreply, %{task: task, os_pid: 1}}, %{task: task})
    Registry.update_value(Gust.Registry, key, fn _value -> :untouched end)

    TaskWorker.publish_os_pid({:noreply, %{task: task, os_pid: 1}}, %{task: task, os_pid: 1})

    assert [{_pid, :untouched}] = Registry.lookup(Gust.Registry, key)
  end

  test "ignores states without an os_pid and stop results", %{task: task, key: key} do
    TaskWorker.publish_os_pid({:noreply, %{task: task}}, %{task: task})
    TaskWorker.publish_os_pid({:stop, :normal, %{task: task, os_pid: 7}}, %{task: task})

    assert [{_pid, nil}] = Registry.lookup(Gust.Registry, key)
  end

  test "keeps continue and timeout tuples intact", %{task: task, key: key} do
    result = {:noreply, %{task: task, os_pid: 9}, {:continue, :next}}

    assert TaskWorker.publish_os_pid(result, %{task: task}) == result
    assert [{_pid, %{os_pid: 9}}] = Registry.lookup(Gust.Registry, key)
  end
end
