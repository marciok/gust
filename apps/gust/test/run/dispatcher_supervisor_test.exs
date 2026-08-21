defmodule Gust.Run.DispatcherSupervisorTest do
  use ExUnit.Case, async: false

  import Gust.ApplicationEnvHelpers

  alias Gust.Run.DispatcherSupervisor

  test "starts the polling workers with rest-for-one supervision" do
    replace_env(:run_dispatcher, Gust.Run.Pooler)

    assert {:ok, {flags, children}} = DispatcherSupervisor.init([])
    assert flags.strategy == :rest_for_one

    assert Enum.map(children, & &1.id) == [
             Gust.Run.Pooler,
             Gust.Run.Claimer
           ]
  end

  test "starts the notifier before the dispatcher in notification mode" do
    replace_env(:run_dispatcher, Gust.PGNotifier.Worker)

    assert {:ok, {flags, children}} = DispatcherSupervisor.init([])
    assert flags.strategy == :rest_for_one

    assert Enum.map(children, & &1.id) == [
             Gust.PGNotifier.Worker,
             Gust.Run.Claimer
           ]
  end
end
