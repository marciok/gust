defmodule Gust.PGNotifierTest do
  use Gust.DataCase, async: false

  import ExUnit.CaptureLog
  import Gust.FlowsFixtures
  import Mox

  alias Gust.Flows
  alias Gust.PGNotifier.Postgrex
  alias Gust.PGNotifier.Worker
  alias Gust.PubSub
  alias Gust.Repo

  setup :verify_on_exit!
  setup :set_mox_global

  setup do
    previous_impl = Application.get_env(:gust, :pg_notifier)
    previous_options = Application.get_env(:gust, :pg_notifications)

    Application.put_env(:gust, :pg_notifier, Gust.PGNotifierMock)

    on_exit(fn ->
      restore_env(:pg_notifier, previous_impl)
      restore_env(:pg_notifications, previous_options)
    end)

    :ok
  end

  test "worker delegates enqueue to the configured notifier" do
    run = %{id: 42}
    expect(Gust.PGNotifierMock, :enqueue, fn ^run -> :enqueued end)

    assert :enqueued = Worker.enqueue(run)
  end

  test "Postgrex implementation enqueues and notifies in one transaction" do
    dag = dag_fixture(%{name: "pg_notifier_enqueue"})
    run = run_fixture(%{dag_id: dag.id})

    PubSub.subscribe_run(run.id)

    assert %{id: run_id, status: :enqueued} = Postgrex.enqueue(run)
    assert run_id == run.id
    assert %{status: :enqueued} = Flows.get_run!(run.id)

    assert_receive {:dag, :run_status, %{run_id: ^run_id, status: :enqueued, task_id: nil}}
  end

  test "worker sets up the listener and forwards notifications" do
    expect_connection_start()

    expect(Gust.PGNotifierMock, :listen, fn Gust.PGNotifier.Connection, "run_dispatch" ->
      {:ok, make_ref()}
    end)

    start_supervised!(Worker)
    assert :ok = Worker.setup()

    send(Worker, {:notification, self(), make_ref(), "run_dispatch", "42"})
    assert_receive :claim_runs
  end

  test "Postgrex implementation starts and listens to a real connection" do
    connection_opts =
      Repo.config()
      |> Keyword.take([:hostname, :port, :username, :password, :database])

    assert {:ok, pid} = Postgrex.start_link(connection_opts)

    assert {:ok, listen_ref} = Postgrex.listen(pid, "pg_notifier_postgrex_test")
    assert is_reference(listen_ref)
  end

  test "worker merges repo, notification, and child options" do
    Application.put_env(:gust, :pg_notifications,
      username: "notification-user",
      reconnect_backoff: 25,
      sync_connect: false,
      auto_reconnect: true
    )

    expect(Gust.PGNotifierMock, :start_link, fn opts ->
      assert opts[:username] == "notification-user"
      assert opts[:database] == "override"
      assert opts[:reconnect_backoff] == 25
      assert opts[:name] == Gust.PGNotifier.Connection
      assert opts[:sync_connect] == true
      assert opts[:auto_reconnect] == false
      {:ok, spawn_link(fn -> Process.sleep(:infinity) end)}
    end)

    pid = start_supervised!({Worker, database: "override"})
    assert Process.whereis(Worker) == pid
  end

  test "worker rejects invalid reconnect backoff values" do
    for invalid <- [-1, "soon"] do
      Application.put_env(:gust, :pg_notifications, reconnect_backoff: invalid)

      assert_raise ArgumentError, ~r/must be a non-negative integer/, fn ->
        Worker.start_link([])
      end
    end
  end

  test "worker waits and retries a failed notification connection" do
    Application.put_env(:gust, :pg_notifications, reconnect_backoff: 0)
    Process.delete(:pg_notifier_attempt)

    expect(Gust.PGNotifierMock, :start_link, 2, fn _opts ->
      case Process.get(:pg_notifier_attempt, 0) do
        0 ->
          Process.put(:pg_notifier_attempt, 1)
          {:error, :database_unavailable}

        1 ->
          {:ok, spawn_link(fn -> Process.sleep(:infinity) end)}
      end
    end)

    log =
      capture_log(fn ->
        pid = start_supervised!(Worker)
        assert Process.whereis(Worker) == pid
      end)

    assert log =~ "PostgreSQL notification connection failed"
    assert log =~ "retrying in 0ms"
  end

  defp restore_env(key, nil), do: Application.delete_env(:gust, key)
  defp restore_env(key, value), do: Application.put_env(:gust, key, value)

  defp expect_connection_start do
    expect(Gust.PGNotifierMock, :start_link, fn _opts ->
      {:ok, spawn_link(fn -> Process.sleep(:infinity) end)}
    end)
  end
end
