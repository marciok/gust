defmodule FileMonitor.WorkerTest do
  use Gust.DataCase, async: false

  import Gust.FSHelpers
  import Mox

  setup do
    dir = make_rand_dir!("dags")
    replace_env(:dag_adapter, [])

    on_exit(fn -> File.rm_rf!(dir) end)

    {:ok, tmp_dir: dir}
  end

  setup :verify_on_exit!
  setup :set_mox_from_context

  setup %{tmp_dir: tmp_dir} do
    # Set short debounce delay for tests
    Application.put_env(:gust, :file_reload_delay, 50)

    Application.put_env(
      :gust,
      :dag_source_monitor_status_path,
      Path.join(tmp_dir, ".dag_source_monitor_status")
    )

    Application.put_env(:gust, :dag_adapter,
      elixir: %{
        parser: Gust.DAGParserAdapterMock,
        runtime: Gust.DAG.Runtime.Adapters.Elixir,
        task_worker: Gust.DAG.TaskWorker.Adapters.Elixir
      }
    )

    Gust.DAGParserAdapterMock
    |> stub(:extensions, fn -> [".ex"] end)

    Gust.FileMonitorMock
    |> expect(:start_link, fn keywords ->
      assert [dirs: [tmp_dir], latency: 0] == keywords
      {:ok, spawn(fn -> :ok end)}
    end)

    Gust.FileMonitorMock
    |> expect(:watch, fn _pid ->
      :ok
    end)

    pid =
      start_link_supervised!({Gust.FileMonitor.Worker, %{dags_folder: tmp_dir, loader: self()}})

    Gust.PubSub.subscribe_all_files("update")
    Process.monitor(pid)

    on_exit(fn ->
      Application.put_env(:gust, :file_reload_delay, 1_000)
    end)

    %{dag_watcher_pid: pid}
  end

  test "persists monitor status to disk and restores it after restart", %{
    tmp_dir: tmp_dir,
    dag_watcher_pid: pid
  } do
    status_path = Path.join(tmp_dir, ".dag_source_monitor_status")

    assert Gust.FileMonitor.Worker.status() == :running
    assert status_from_disk(status_path) == "running"

    assert :ok == Gust.FileMonitor.Worker.pause()
    assert status_from_disk(status_path) == "paused"

    Process.unlink(pid)
    GenServer.stop(pid)

    Gust.FileMonitorMock
    |> stub(:start_link, fn keywords ->
      assert [dirs: [tmp_dir], latency: 0] == keywords
      {:ok, spawn_link(fn -> :ok end)}
    end)

    Gust.FileMonitorMock
    |> stub(:watch, fn _pid -> :ok end)

    {:ok, restarted_pid} =
      GenServer.start_link(Gust.FileMonitor.Worker, %{dags_folder: tmp_dir, loader: self()})

    assert GenServer.call(restarted_pid, :status) == :paused
  end

  defp status_from_disk(path) do
    path
    |> File.read!()
    |> String.trim()
    |> String.split(~r/\s+/, trim: true)
    |> List.last()
  end

  test "ignore debounce events", %{tmp_dir: tmp_dir, dag_watcher_pid: pid} do
    name = "my_dag_file"
    event_file_path = "#{tmp_dir}/#{name}.ex"
    File.write!(event_file_path, "")

    delay = 200
    replace_env(:file_reload_delay, delay)
    dag_def = %Gust.DAG.Definition{name: name}

    Gust.DAGParserMock
    |> expect(:parse, fn adapter, path ->
      assert adapter == Gust.DAGParserAdapterMock
      assert path == event_file_path
      {:ok, dag_def}
    end)

    Enum.each(1..5, fn _ ->
      send(pid, {:file_event, "watcher_pid", {event_file_path, [:removed]}})
    end)

    assert_receive {^name, {:ok, ^dag_def}, "reload"}, delay + 100
    refute_receive {^name, {:ok, ^dag_def}, "reload"}, delay + 150
  end

  test "ignore broadcast reload for non ex files", %{tmp_dir: tmp_dir, dag_watcher_pid: pid} do
    event_file_path = "#{tmp_dir}/dag_name.txt"

    send(pid, {:file_event, "watcher_pid", {event_file_path, [:created]}})

    refute_receive {"dag_name", _, _}, 150
  end

  test "broadcast specific file", %{tmp_dir: tmp_dir, dag_watcher_pid: pid} do
    Phoenix.PubSub.unsubscribe(Gust.PubSub, "update")
    name = "my_dag_file"

    dag_def = %Gust.DAG.Definition{name: name}
    Gust.PubSub.subscribe_file(name)
    event_file_path = "#{tmp_dir}/#{name}.ex"
    File.write!(event_file_path, "")

    Gust.DAGParserMock
    |> expect(:parse, fn adapter, path ->
      assert adapter == Gust.DAGParserAdapterMock
      assert path == event_file_path
      {:ok, dag_def}
    end)

    send(pid, {:file_event, "watcher_pid", {event_file_path, [:removed]}})

    assert_receive {^name, {:ok, ^dag_def}, "reload"}
  end

  test "broadcast nil for removed file", %{tmp_dir: tmp_dir, dag_watcher_pid: pid} do
    name = "my_dag_file"
    event_file_path = "#{tmp_dir}/#{name}.ex"

    Gust.DAGParserMock
    |> expect(:parse, fn adapter, path ->
      assert adapter == Gust.DAGParserAdapterMock
      assert path == event_file_path
      {:error, :enoent}
    end)

    File.write!(event_file_path, "")

    send(pid, {:file_event, "watcher_pid", {event_file_path, [:removed]}})

    assert_receive {^name, {:error, :enoent}, "reload"}, 300
  end

  test "broadcast nil for file without dsl", %{tmp_dir: tmp_dir, dag_watcher_pid: pid} do
    name = "my_dag_file"
    event_file_path = "#{tmp_dir}/#{name}.ex"

    Gust.DAGParserMock
    |> expect(:parse, fn adapter, path ->
      assert adapter == Gust.DAGParserAdapterMock
      assert path == event_file_path
      {:error, {:dsl_not_found}}
    end)

    File.write!(event_file_path, "")

    send(pid, {:file_event, "watcher_pid", {event_file_path, [:removed]}})

    assert_receive {^name, {:error, {:dsl_not_found}}, "reload"}, 300
  end

  test "broadcast for valid files", %{tmp_dir: tmp_dir, dag_watcher_pid: pid} do
    name = "my_dag_file"
    event_file_path = "#{tmp_dir}/#{name}.ex"
    dag_def = %Gust.DAG.Definition{name: name}

    Gust.DAGParserMock
    |> expect(:parse, fn adapter, path ->
      assert adapter == Gust.DAGParserAdapterMock
      assert path == event_file_path
      {:ok, dag_def}
    end)

    dag_def = %Gust.DAG.Definition{name: name}
    File.write!(event_file_path, "")

    send(pid, {:file_event, "watcher_pid", {event_file_path, [:removed]}})

    assert_receive {^name, {:ok, ^dag_def}, "reload"}
  end
end
