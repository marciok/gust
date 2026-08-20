defmodule Gust.DAG.Runner.RunGatewayTest do
  use ExUnit.Case, async: false

  import Gust.ApplicationEnvHelpers
  import Mox

  alias Gust.DAG.Runner.RunGateway
  alias Gust.Flows.Run

  setup :verify_on_exit!

  setup do
    replace_env(:dag_run_gateway, Gust.RunGatewayMock)
  end

  test "delegates commands to the configured gateway" do
    run = %Run{id: 123}

    Gust.RunGatewayMock
    |> expect(:call, fn ^run, {:restart_task, 456} -> {:ok, :restarted} end)

    assert {:ok, :restarted} = RunGateway.call(run, {:restart_task, 456})
    assert RunGateway.impl() == Gust.RunGatewayMock
  end
end
