defmodule Gust.DAG.Runner.RunGateway.DefaultTest do
  use ExUnit.Case, async: false

  import Gust.ApplicationEnvHelpers

  alias Gust.DAG.Runner.RunGateway.Default
  alias Gust.Flows.Run
  alias Gust.RunGatewayPeer

  setup_all do
    unless Node.alive?() do
      {_output, 0} = System.cmd("epmd", ["-daemon"])
      {:ok, _pid} = Node.start(:gust_run_gateway_test, :shortnames)
      on_exit(fn -> Node.stop() end)
    end

    :ok
  end

  setup do
    replace_env(:run_command_timeout, 20)
  end

  test "delivers a command to the locally registered run worker" do
    run = run()

    spawn_registered(run.id, fn
      {:"$gen_call", from, {:restart_mapped_task, 123}} ->
        GenServer.reply(from, {:ok, :restarted})
    end)

    assert {:ok, :restarted} = Default.call(run, {:restart_mapped_task, 123})
  end

  test "returns run_not_active when no worker or active lease exists" do
    assert {:error, :run_not_active} = Default.call(run(), {:restart_mapped_task, 123})
  end

  test "protects an active lease when its local worker is not registered" do
    run = run(status: :starting, claim_expires_at: future_time())

    assert {:error, :run_owner_unavailable} =
             Default.call(run, {:restart_mapped_task, 123})
  end

  test "treats a clean worker exit during the call as inactive" do
    run = run()

    spawn_registered(run.id, fn
      {:"$gen_call", _from, :stop} -> exit(:normal)
    end)

    assert {:error, :run_not_active} = Default.call(run, :stop)
  end

  test "returns a stop error without waiting for the worker to exit" do
    run = run()

    worker =
      spawn_registered(run.id, fn
        {:"$gen_call", from, :stop} ->
          GenServer.reply(from, {:error, :cannot_stop})

          receive do
            :stop -> :ok
          end
      end)

    assert {:error, :cannot_stop} = Default.call(run, :stop)
    assert Process.alive?(worker)
    send(worker, :stop)
  end

  test "times out when the worker acknowledges stop but remains alive" do
    run = run()

    worker =
      spawn_registered(run.id, fn
        {:"$gen_call", from, :stop} ->
          GenServer.reply(from, {:ok, :stopping})

          receive do
            :stop -> :ok
          end
      end)

    on_exit(fn ->
      if Process.alive?(worker), do: Process.exit(worker, :kill)
    end)

    assert {:error, :run_command_timeout} = Default.call(run, :stop)
    assert Process.alive?(worker)
    send(worker, :stop)
  end

  test "returns run_command_failed when the worker crashes during the call" do
    run = run()

    spawn_registered(run.id, fn
      {:"$gen_call", _from, :crash} -> exit(:boom)
    end)

    assert {:error, :run_command_failed} = Default.call(run, :crash)
  end

  test "treats a shutdown worker exit as inactive" do
    run = run()

    spawn_registered(run.id, fn
      {:"$gen_call", _from, :shutdown} -> exit(:shutdown)
    end)

    assert {:error, :run_not_active} = Default.call(run, :shutdown)
  end

  test "treats a shutdown tuple from the worker as inactive" do
    run = run()

    spawn_registered(run.id, fn
      {:"$gen_call", _from, :shutdown} -> exit({:shutdown, :maintenance})
    end)

    assert {:error, :run_not_active} = Default.call(run, :shutdown)
  end

  test "returns run_command_timeout when the worker does not reply" do
    run = run()

    worker =
      spawn_registered(run.id, fn
        {:"$gen_call", _from, :wait} ->
          receive do
            :stop -> :ok
          end
      end)

    on_exit(fn ->
      if Process.alive?(worker), do: Process.exit(worker, :kill)
    end)

    assert {:error, :run_command_timeout} = Default.call(run, :wait)
  end

  test "returns run_owner_unavailable for an unreachable owner with an active lease" do
    run =
      run(
        status: :running,
        claimed_by: "missing-owner@invalid",
        claim_expires_at: future_time()
      )

    assert {:error, :run_owner_unavailable} = Default.call(run, :command)
  end

  test "treats an unreachable owner with an expired lease as inactive" do
    run =
      run(
        status: :running,
        claimed_by: "expired-owner@invalid",
        claim_expires_at: DateTime.add(DateTime.utc_now(), -30)
      )

    assert {:error, :run_not_active} = Default.call(run, :command)
  end

  test "routes commands to a worker on a connected node" do
    {_peer, peer_node} = start_peer()
    run = run(claimed_by: to_string(peer_node))

    assert {:ok, _worker} =
             :erpc.call(peer_node, RunGatewayPeer, :start_worker, [run.id, self(), :reply])

    assert_receive {:remote_worker_registered, ^peer_node}

    assert {:ok, {^peer_node, :command}} = Default.call(run, :command)
  end

  test "returns run_owner_unavailable when a connected owner disappears during the call" do
    {_peer, peer_node} = start_peer()
    run = run(claimed_by: to_string(peer_node), status: :running, claim_expires_at: future_time())

    assert {:ok, _worker} =
             :erpc.call(peer_node, RunGatewayPeer, :start_worker, [run.id, self(), :halt])

    assert_receive {:remote_worker_registered, ^peer_node}
    assert {:error, :run_owner_unavailable} = Default.call(run, :command)
  end

  defp spawn_registered(run_id, callback) do
    parent = self()

    pid =
      spawn(fn ->
        {:ok, _owner} = Registry.register(Gust.Registry, "dag_run_#{run_id}", nil)
        send(parent, {:registered, self()})

        receive do
          message -> callback.(message)
        end
      end)

    assert_receive {:registered, ^pid}
    pid
  end

  defp start_peer do
    {:ok, peer, peer_node} = :peer.start_link()
    :ok = :erpc.call(peer_node, :code, :add_paths, [:code.get_path()])

    assert {:ok, _registry} =
             :erpc.call(peer_node, RunGatewayPeer, :start_registry, [])

    on_exit(fn ->
      if peer_node in Node.list() do
        :erpc.cast(peer_node, :init, :stop, [])
      end

      try do
        :peer.stop(peer)
      catch
        :exit, _reason -> :ok
      end
    end)

    {peer, peer_node}
  end

  defp run(attrs \\ []) do
    defaults = [id: System.unique_integer([:positive]), status: :created]
    struct!(Run, Keyword.merge(defaults, attrs))
  end

  defp future_time, do: DateTime.add(DateTime.utc_now(), 30)
end
