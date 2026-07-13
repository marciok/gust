defmodule Gust.Run.DispatcherSupervisorTest do
  use ExUnit.Case, async: false

  alias Gust.Run.DispatcherSupervisor

  setup do
    previous_dispatcher = Application.get_env(:gust, :run_dispatcher)
    on_exit(fn -> restore_env(:run_dispatcher, previous_dispatcher) end)
  end

  test "starts the polling workers with rest-for-one supervision" do
    Application.put_env(:gust, :run_dispatcher, Gust.Run.Pooler)

    assert {:ok, {flags, children}} = DispatcherSupervisor.init([])
    assert flags.strategy == :rest_for_one

    assert Enum.map(children, & &1.id) == [
             Gust.Run.Pooler,
             Gust.Run.Claimer,
             Gust.DAG.Terminator.Worker
           ]
  end

  test "starts the notifier before the dispatcher in notification mode" do
    Application.put_env(:gust, :run_dispatcher, Gust.PGNotifier.Worker)

    assert {:ok, {flags, children}} = DispatcherSupervisor.init([])
    assert flags.strategy == :rest_for_one

    assert Enum.map(children, & &1.id) == [
             Gust.PGNotifier.Worker,
             Gust.Run.Claimer,
             Gust.DAG.Terminator.Worker
           ]
  end

  defp restore_env(key, nil), do: Application.delete_env(:gust, key)
  defp restore_env(key, value), do: Application.put_env(:gust, key, value)
end
