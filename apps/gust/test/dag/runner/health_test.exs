defmodule Gust.DAG.Runner.HealthTest do
  use Gust.DataCase, async: false

  import Gust.ApplicationEnvHelpers
  import Gust.FlowsFixtures

  alias Gust.DAG.Runner.Health
  alias Gust.DAG.TaskWorker
  alias Gust.Flows
  alias Gust.RunGatewayPeer

  setup_all do
    unless Node.alive?() do
      {_output, 0} = System.cmd("epmd", ["-daemon"])
      {:ok, _pid} = Node.start(:gust_health_test, :shortnames)
      on_exit(fn -> Node.stop() end)
    end

    :ok
  end

  setup do
    dag = dag_fixture()
    run = run_fixture(%{dag_id: dag.id, status: :running})
    %{run: run}
  end

  describe "inspect_task/1 on the local node" do
    test "reports a running task with a live worker as healthy", %{run: run} do
      task = task_fixture(%{run_id: run.id, name: "task", status: :running})
      pid = register(TaskWorker.registry_name(task))

      assert %{error: nil, run: run_report, tasks: [report]} = Health.inspect_task(task)

      assert run_report.node_connected
      assert run_report.owner_node == to_string(node())
      assert report.verdict == :healthy
      assert report.registry_key == "task_#{task.id}"
      assert report.process.pid == inspect(pid)
      assert report.process.alive

      assert %{status: _status, message_queue_len: 0, current_function: function} =
               report.process.info

      assert is_binary(function)
      assert report.process.os_process == nil
    end

    test "flags a running task without a worker as a zombie", %{run: run} do
      task = task_fixture(%{run_id: run.id, name: "task", status: :running})

      assert %{error: nil, tasks: [%{verdict: :zombie, process: nil}]} =
               Health.inspect_task(task)
    end

    test "marks tasks that are not running in the database", %{run: run} do
      task = task_fixture(%{run_id: run.id, name: "task", status: :succeeded})

      assert %{tasks: [%{verdict: :not_running}]} = Health.inspect_task(task)
    end

    test "reports each map index of a mapped task", %{run: run} do
      alive = task_fixture(%{run_id: run.id, name: "mapped", status: :running, map_index: 0})
      dead = task_fixture(%{run_id: run.id, name: "mapped", status: :running, map_index: 1})
      register(TaskWorker.registry_name(alive))

      assert %{tasks: [first, second]} = Health.inspect_tasks([alive, dead])

      assert %{map_index: 0, verdict: :healthy, registry_key: key0} = first
      assert %{map_index: 1, verdict: :zombie, registry_key: key1} = second
      assert key0 == "task_#{alive.id}_0"
      assert key1 == "task_#{dead.id}_1"
    end

    test "reports the DAG worker of the run", %{run: run} do
      task = task_fixture(%{run_id: run.id, name: "task", status: :running})
      pid = register("dag_run_#{run.id}")

      assert %{run: %{dag_worker: %{pid: pid_string, alive: true}}} = Health.inspect_task(task)
      assert pid_string == inspect(pid)
    end

    test "reports the external OS process recorded by the worker", %{run: run} do
      task = task_fixture(%{run_id: run.id, name: "task", status: :running})
      os_pid = String.to_integer(System.pid())

      register(TaskWorker.registry_name(task), fn ->
        TaskWorker.publish_os_pid({:noreply, %{task: task, os_pid: os_pid}}, %{})
      end)

      assert %{tasks: [%{process: %{os_process: %{os_pid: ^os_pid, alive: true}}}]} =
               Health.inspect_task(task)
    end

    test "reports an external OS process that has exited as dead", %{run: run} do
      task = task_fixture(%{run_id: run.id, name: "task", status: :running})
      port = Port.open({:spawn, "sh -c 'echo $$'"}, [:binary, :exit_status])
      assert_receive {^port, {:data, output}}
      os_pid = output |> String.trim() |> String.to_integer()
      assert_receive {^port, {:exit_status, 0}}

      register(TaskWorker.registry_name(task), fn ->
        TaskWorker.publish_os_pid({:noreply, %{task: task, os_pid: os_pid}}, %{})
      end)

      assert %{tasks: [%{process: %{os_process: %{os_pid: ^os_pid, alive: false}}}]} =
               Health.inspect_task(task)
    end

    test "inspect_run/1 checks the DAG worker and only running tasks", %{run: run} do
      running = task_fixture(%{run_id: run.id, name: "running", status: :running})
      _done = task_fixture(%{run_id: run.id, name: "done", status: :succeeded})
      register(TaskWorker.registry_name(running))
      register("dag_run_#{run.id}")

      assert %{error: nil, run: %{dag_worker: %{alive: true}}, tasks: [report]} =
               Health.inspect_run(run)

      assert %{id: id, verdict: :healthy} = report
      assert id == running.id
    end

    test "inspect_run/1 reports no tasks when nothing is running", %{run: run} do
      _done = task_fixture(%{run_id: run.id, name: "done", status: :succeeded})

      assert %{error: nil, run: %{dag_worker: nil}, tasks: []} = Health.inspect_run(run)
    end

    test "does not change run or task state", %{run: run} do
      task = task_fixture(%{run_id: run.id, name: "task", status: :running})

      before = {Flows.get_run!(run.id), Flows.get_task!(task.id)}
      Health.inspect_task(task)

      assert before == {Flows.get_run!(run.id), Flows.get_task!(task.id)}
    end
  end

  describe "inspect_task/1 for runs owned elsewhere" do
    test "reports unknown when the owner node is unreachable" do
      dag = dag_fixture(%{name: "unreachable"})

      run =
        run_fixture(%{
          dag_id: dag.id,
          status: :running,
          claimed_by: "missing-owner@invalid",
          claim_expires_at: DateTime.add(DateTime.utc_now(), 30)
        })

      task = task_fixture(%{run_id: run.id, name: "task", status: :running})

      assert %{
               error: :run_owner_unavailable,
               run: %{node_connected: false, owner_node: nil, dag_worker: nil},
               tasks: [%{verdict: :unknown}]
             } = Health.inspect_task(task)
    end

    test "inspects processes on the node that owns the run" do
      peer_node = start_peer()
      dag = dag_fixture(%{name: "remote"})
      run = run_fixture(%{dag_id: dag.id, status: :running, claimed_by: to_string(peer_node)})
      alive = task_fixture(%{run_id: run.id, name: "task", status: :running})
      dead = task_fixture(%{run_id: run.id, name: "other", status: :running})
      key = TaskWorker.registry_name(alive)

      assert {:ok, _pid} = :erpc.call(peer_node, RunGatewayPeer, :register_idle, [key, self()])
      assert_receive {:remote_registered, ^key, ^peer_node}

      register(TaskWorker.registry_name(dead))

      assert %{error: nil, run: run_report, tasks: [first, second]} =
               Health.inspect_tasks([alive, dead])

      assert run_report.owner_node == to_string(peer_node)
      assert %{verdict: :healthy, process: %{pid: pid}} = first
      assert pid =~ "#PID<"
      assert %{verdict: :zombie} = second
    end

    test "reports unknown when the owner node times out" do
      peer_node = start_peer()
      replace_env(:health_check_timeout, 0)
      dag = dag_fixture(%{name: "slow"})
      run = run_fixture(%{dag_id: dag.id, status: :running, claimed_by: to_string(peer_node)})
      task = task_fixture(%{run_id: run.id, name: "task", status: :running})

      assert %{error: :timeout, tasks: [%{verdict: :unknown}]} = Health.inspect_task(task)
    end

    test "reports unknown when the lookup fails on the owner node" do
      peer_node = start_peer(registry: false)
      dag = dag_fixture(%{name: "broken"})
      run = run_fixture(%{dag_id: dag.id, status: :running, claimed_by: to_string(peer_node)})
      task = task_fixture(%{run_id: run.id, name: "task", status: :running})

      assert %{error: :lookup_failed, tasks: [%{verdict: :unknown}]} = Health.inspect_task(task)
    end
  end

  defp register(key, callback \\ fn -> :ok end) do
    parent = self()

    pid =
      spawn(fn ->
        {:ok, _owner} = Registry.register(Gust.Registry, key, nil)
        callback.()
        send(parent, {:registered, self()})

        receive do
          :stop -> :ok
        end
      end)

    assert_receive {:registered, ^pid}
    on_exit(fn -> Process.exit(pid, :kill) end)
    pid
  end

  defp start_peer(opts \\ []) do
    {:ok, peer, peer_node} = :peer.start_link()
    :ok = :erpc.call(peer_node, :code, :add_paths, [:code.get_path()])

    if Keyword.get(opts, :registry, true) do
      assert {:ok, _registry} = :erpc.call(peer_node, RunGatewayPeer, :start_registry, [])
    end

    on_exit(fn ->
      try do
        :peer.stop(peer)
      catch
        :exit, _reason -> :ok
      end
    end)

    peer_node
  end
end
