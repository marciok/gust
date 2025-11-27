defmodule FileMonitor.WorkerTest do
  use Gust.DataCase, async: false
  import Mox
  import Gust.FSHelpers

  setup do
    dir = make_rand_dir!("dags")

    on_exit(fn ->
      File.rm_rf!(dir)
    end)

    {:ok, tmp_dir: dir}
  end

  setup :verify_on_exit!
  setup :set_mox_from_context

  setup %{tmp_dir: tmp_dir} do
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

    %{dag_watcher_pid: pid}
  end

  test "ignore debounce events", %{tmp_dir: tmp_dir, dag_watcher_pid: pid} do
    name = "my_dag_file"
    event_file_path = "#{tmp_dir}/#{name}.ex"
    File.write!(event_file_path, "")

    Gust.DAGParserMock
    |> expect(:maybe_ex_file, fn path ->
      assert path == event_file_path
      path
    end)

    delay = 200
    original_delay = Application.get_env(:gust, :file_reload_delay)
    Application.put_env(:gust, :file_reload_delay, delay)
    on_exit(fn -> Application.put_env(:gust, :file_reload_delay, original_delay) end)
    dag_def = %Gust.DAG.Definition{name: name}

    Gust.DAGParserMock
    |> expect(:parse, fn path ->
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
    event_file_path = "#{tmp_dir}/dag_name.ex"

    Gust.DAGParserMock
    |> expect(:maybe_ex_file, fn ^event_file_path -> nil end)

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
    |> expect(:parse, fn path ->
      assert path == event_file_path
      {:ok, dag_def}
    end)

    Gust.DAGParserMock
    |> expect(:maybe_ex_file, fn path ->
      assert path == event_file_path
      path
    end)

    send(pid, {:file_event, "watcher_pid", {event_file_path, [:removed]}})

    assert_receive {^name, {:ok, ^dag_def}, "reload"}
  end

  test "broadcast nil for removed file", %{tmp_dir: tmp_dir, dag_watcher_pid: pid} do
    name = "my_dag_file"
    event_file_path = "#{tmp_dir}/#{name}.ex"

    Gust.DAGParserMock
    |> expect(:parse, fn path ->
      assert path == event_file_path
      {:error, :enoent}
    end)

    File.write!(event_file_path, "")

    Gust.DAGParserMock
    |> expect(:maybe_ex_file, fn path ->
      assert path == event_file_path
      path
    end)

    send(pid, {:file_event, "watcher_pid", {event_file_path, [:removed]}})

    assert_receive {^name, {:error, :enoent}, "reload"}, 300
  end

  test "broadcast nil for file without dsl", %{tmp_dir: tmp_dir, dag_watcher_pid: pid} do
    name = "my_dag_file"
    event_file_path = "#{tmp_dir}/#{name}.ex"

    Gust.DAGParserMock
    |> expect(:parse, fn path ->
      assert path == event_file_path
      {:error, {:dsl_not_found}}
    end)

    File.write!(event_file_path, "")

    Gust.DAGParserMock
    |> expect(:maybe_ex_file, fn path ->
      assert path == event_file_path
      path
    end)

    send(pid, {:file_event, "watcher_pid", {event_file_path, [:removed]}})

    assert_receive {^name, {:error, {:dsl_not_found}}, "reload"}, 300
  end

  test "broadcast for valid files", %{tmp_dir: tmp_dir, dag_watcher_pid: pid} do
    name = "my_dag_file"
    event_file_path = "#{tmp_dir}/#{name}.ex"
    dag_def = %Gust.DAG.Definition{name: name}

    Gust.DAGParserMock
    |> expect(:parse, fn path ->
      assert path == event_file_path
      {:ok, dag_def}
    end)

    dag_def = %Gust.DAG.Definition{name: name}
    File.write!(event_file_path, "")

    Gust.DAGParserMock
    |> expect(:maybe_ex_file, fn path ->
      assert path == event_file_path
      path
    end)

    send(pid, {:file_event, "watcher_pid", {event_file_path, [:removed]}})

    assert_receive {^name, {:ok, ^dag_def}, "reload"}
  end
end
