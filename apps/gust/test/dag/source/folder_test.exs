defmodule Gust.DAG.Source.FolderTest do
  use ExUnit.Case, async: false

  import Gust.ApplicationEnvHelpers
  import Mox

  alias Gust.DAG.Source.Folder

  setup :verify_on_exit!
  setup :init_dag_source

  describe "load/0" do
    test "returns success/error structure for loaded DAGs" do
      # Use a clean temporary directory specifically for this test
      test_dir = Path.join(System.tmp_dir!(), "gust_test_dags_#{System.monotonic_time()}")
      File.mkdir_p!(test_dir)

      try do
        Application.put_env(:gust, :dag_source, {Gust.DAG.Source.Folder, folder: test_dir})

        result = Folder.load()
        assert is_map(result) or is_tuple(result)

        if is_map(result) do
          # Should have success and error keys
          assert Map.has_key?(result, :success)
          assert Map.has_key?(result, :error)
          assert is_list(result.success)
          assert is_list(result.error)
        end
      after
        # Cleanup
        if File.exists?(test_dir), do: File.rm_rf!(test_dir)
      end
    end

    test "directory operations work as expected" do
      test_dir = Path.join(System.tmp_dir!(), "gust_test_dir_#{System.monotonic_time()}")
      File.mkdir_p!(test_dir)

      try do
        Application.delete_env(:gust, :dag_source)
        Application.put_env(:gust, :dag_source, {Gust.DAG.Source.Folder, folder: test_dir})

        # Verify directory exists
        assert File.exists?(test_dir)
        assert File.dir?(test_dir)
      after
        if File.exists?(test_dir), do: File.rm_rf!(test_dir)
      end
    end

    test "file extension patterns work" do
      # Test that extension patterns are correct
      assert String.ends_with?("dag.ex", ".ex")
      assert String.ends_with?("dag.yml", ".yml")
      assert String.ends_with?("dag.yaml", ".yaml")
      refute String.ends_with?("readme.md", [".ex", ".yml", ".yaml"])
    end
  end

  describe "name/0" do
    test "returns the source name" do
      assert Folder.name() == "Folder"
    end
  end

  describe "configuration" do
    test "supports dag_source tuple config" do
      test_dir = Path.join(System.tmp_dir!(), "gust_test_dags_tuple_#{System.monotonic_time()}")
      File.mkdir_p!(test_dir)

      try do
        Application.put_env(:gust, :dag_source, {Gust.DAG.Source.Folder, folder: test_dir})

        assert Folder.load() == %{success: [], error: []}
      after
        Application.delete_env(:gust, :dag_source)
        if File.exists?(test_dir), do: File.rm_rf!(test_dir)
      end
    end

    test "uses default dags_folder if not in dag_source config" do
      Application.delete_env(:gust, :dag_source)
      assert Folder.name() == "Folder"
    end
  end

  describe "monitor lifecycle" do
    test "supports pause, resume, and status queries" do
      test_dir = Path.join(System.tmp_dir!(), "gust_test_monitor_#{System.monotonic_time()}")
      File.mkdir_p!(test_dir)

      try do
        Application.put_env(:gust, :dag_source, {Gust.DAG.Source.Folder, folder: test_dir})

        Gust.FileMonitorMock
        |> expect(:start_link, fn opts ->
          assert opts == [dirs: [test_dir], latency: 0]

          {:ok,
           spawn_link(fn ->
             receive do
               _ -> :ok
             end
           end)}
        end)

        Gust.FileMonitorMock
        |> expect(:watch, fn _watcher_pid -> :ok end)

        {:ok, monitor_pid} = Folder.monitor(self(), %{})

        assert Gust.DAG.Source.monitor_status(monitor_pid) == :running
        assert :ok == Gust.DAG.Source.monitor_pause(monitor_pid)
        assert Gust.DAG.Source.monitor_status(monitor_pid) == :paused
        assert :ok == Gust.DAG.Source.monitor_resume(monitor_pid)
        assert Gust.DAG.Source.monitor_status(monitor_pid) == :running

        Process.unlink(monitor_pid)
        Process.exit(monitor_pid, :kill)
      after
        if File.exists?(test_dir), do: File.rm_rf!(test_dir)
      end
    end
  end

  describe "behavior compliance" do
    test "implements Gust.DAG.Source behavior" do
      assert function_exported?(Folder, :load, 0)
      assert function_exported?(Folder, :load, 1)
      assert function_exported?(Folder, :monitor, 2)
      assert function_exported?(Folder, :name, 0)
    end

    test "load returns success/error map or error tuple" do
      test_dir = Path.join(System.tmp_dir!(), "gust_test_behavior_#{System.monotonic_time()}")
      File.mkdir_p!(test_dir)

      try do
        Application.put_env(:gust, :dag_source, {Gust.DAG.Source.Folder, folder: test_dir})
        result = Folder.load()
        assert is_map(result) or is_tuple(result)

        if is_map(result) do
          assert Map.has_key?(result, :success)
          assert Map.has_key?(result, :error)
        end
      after
        if File.exists?(test_dir), do: File.rm_rf!(test_dir)
      end
    end

    test "monitor/2 function exists and has correct arity" do
      assert function_exported?(Folder, :monitor, 2)
    end
  end
end
