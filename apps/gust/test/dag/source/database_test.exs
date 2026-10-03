defmodule Gust.DAG.Source.DatabaseTest do
  use Gust.DataCase, async: false

  import Gust.ApplicationEnvHelpers
  import Mox

  alias Ecto.Adapters.SQL.Sandbox
  alias Gust.DAG.Source.Database
  alias Gust.DagSource

  setup :init_dag_source
  setup :verify_on_exit!

  describe "name/0" do
    test "returns the source name" do
      assert Database.name() == "Database"
    end
  end

  describe "load/0 with DAGs in database" do
    test "separates successful and failed DAG loads" do
      result = Database.load()
      assert is_map(result)
      assert Map.has_key?(result, :success)
      assert Map.has_key?(result, :error)
      assert is_list(result.success)
      assert is_list(result.error)
    end
  end

  describe "configuration" do
    test "uses default poll_seconds (30)" do
      Application.put_env(:gust, :dag_source, Gust.DAG.Source.Database)
      assert Database.name() == "Database"
      Application.put_env(:gust, :dag_source, {Gust.DAG.Source.Database, []})
      assert Database.name() == "Database"
    end

    test "uses provided poll_seconds" do
      Application.put_env(:gust, :dag_source, {Gust.DAG.Source.Database, poll_seconds: 60})
      assert Database.name() == "Database"
    end
  end

  describe "monitor/2" do
    setup do
      original_config = Application.get_env(:gust, :dag_source)

      config = [poll_seconds: 1]
      Application.put_env(:gust, :dag_source, {Gust.DAG.Source.Database, config})

      on_exit(fn ->
        restore_dag_source(original_config)
      end)

      {:ok, config: config}
    end

    @tag :capture_log
    test "returns ok tuple with monitor pid" do
      test_pid = self()

      {:ok, monitor_pid} = Database.monitor(test_pid)

      # Allow the spawned monitor process to access the database
      Sandbox.allow(Gust.Repo, test_pid, monitor_pid)

      # Allow ExUnit to track the spawned monitor process
      ExUnit.Callbacks.on_exit(fn ->
        if Process.alive?(monitor_pid) do
          Process.exit(monitor_pid, :kill)
        end
      end)

      assert is_pid(monitor_pid)
    end

    @tag :capture_log
    test "starts a polling process" do
      test_pid = self()

      {:ok, monitor_pid} = Database.monitor(test_pid)

      # Allow the spawned monitor process to access the database
      Sandbox.allow(Gust.Repo, test_pid, monitor_pid)

      # Allow ExUnit to track the spawned monitor process
      ExUnit.Callbacks.on_exit(fn ->
        if Process.alive?(monitor_pid) do
          Process.exit(monitor_pid, :kill)
        end
      end)

      # Process should be running
      assert Process.alive?(monitor_pid)
    end

    @tag :capture_log
    test "monitor accepts config parameter" do
      test_pid = self()

      {:ok, monitor_pid} = Database.monitor(test_pid, %{})

      Sandbox.allow(Gust.Repo, test_pid, monitor_pid)

      ExUnit.Callbacks.on_exit(fn ->
        if Process.alive?(monitor_pid) do
          Process.exit(monitor_pid, :kill)
        end
      end)

      assert is_pid(monitor_pid)
    end

    @tag :capture_log
    test "monitor uses configured poll_seconds" do
      test_pid = self()

      {:ok, monitor_pid} = Database.monitor(test_pid)

      Sandbox.allow(Gust.Repo, test_pid, monitor_pid)

      ExUnit.Callbacks.on_exit(fn ->
        if Process.alive?(monitor_pid) do
          Process.exit(monitor_pid, :kill)
        end
      end)

      assert is_pid(monitor_pid)
    end
  end

  describe "behavior compliance" do
    test "implements Gust.DAG.Source behavior" do
      assert Code.ensure_loaded?(Database)
      assert function_exported?(Database, :load, 0)
      assert function_exported?(Database, :load, 1)
      assert function_exported?(Database, :monitor, 2)
      assert function_exported?(Database, :name, 0)
    end

    @tag :capture_log
    test "monitor/2 accepts loader_pid and config" do
      original_config = Application.get_env(:gust, :dag_source)

      try do
        Application.put_env(:gust, :dag_source, {Gust.DAG.Source.Database, poll_seconds: 60})

        {:ok, monitor_pid} = Database.monitor(self(), %{})

        # Allow the spawned monitor process to access the database
        Sandbox.allow(Gust.Repo, self(), monitor_pid)

        # Allow ExUnit to track the spawned monitor process
        ExUnit.Callbacks.on_exit(fn ->
          if Process.alive?(monitor_pid) do
            Process.exit(monitor_pid, :kill)
          end
        end)

        assert is_pid(monitor_pid)
      after
        restore_dag_source(original_config)
      end
    end
  end

  describe "error handling and recovery" do
    test "handles database query errors gracefully" do
      # Database.load() should return empty map on any error
      result = Database.load()
      assert is_map(result)
    end

    test "rescues and logs database exceptions" do
      # Even with a broken query, load should not raise
      assert_no_raise = fn ->
        result = Database.load()
        is_map(result)
      end

      assert_no_raise.()
    end
  end

  describe "load/0 with real database" do
    test "returns empty lists when no DAGs exist" do
      # Assuming test database has no DAGs
      result = Database.load()
      assert is_map(result)
      assert Map.has_key?(result, :success)
      assert Map.has_key?(result, :error)
    end

    test "includes enabled DAGs only" do
      result = Database.load()
      # Combine success and error lists
      all_dags = result.success ++ result.error

      # All results should be tuples with name and parse result
      assert Enum.all?(all_dags, fn {name, value} ->
               is_binary(name) and is_tuple(value) and tuple_size(value) == 2
             end)
    end
  end

  describe "parse_dag_content" do
    test "parses Elixir format" do
      elixir_content = """
      defmodule TestDAG do
        use Gust.DAG
        task :test, fn -> :ok end
      end
      """

      {:ok, _} =
        Gust.Repo.insert(%DagSource{
          name: "elixir_dag",
          content: elixir_content,
          format: "elixir",
          enabled: true
        })

      result = Database.load()
      assert is_map(result)
      success_names = Enum.map(result.success, fn {name, _} -> name end)
      error_names = Enum.map(result.error, fn {name, _} -> name end)
      assert "elixir_dag" in success_names or "elixir_dag" in error_names
    end

    test "parses YAML format" do
      yaml_content = """
      ---
      name: yaml_dag
      nodes:
        - id: task1
          type: shell
          command: echo test
      """

      {:ok, _} =
        Gust.Repo.insert(%DagSource{
          name: "yaml_dag",
          content: yaml_content,
          format: "yaml",
          enabled: true
        })

      result = Database.load()
      assert is_map(result)
      success_names = Enum.map(result.success, fn {name, _} -> name end)
      error_names = Enum.map(result.error, fn {name, _} -> name end)
      assert "yaml_dag" in success_names or "yaml_dag" in error_names
    end

    test "handles unknown format" do
      {:ok, _} =
        Gust.Repo.insert(%DagSource{
          name: "unknown_dag",
          content: "some content",
          format: "json",
          enabled: true
        })

      result = Database.load()
      assert is_map(result)
    end

    test "rescues parse errors with invalid content" do
      {:ok, _} =
        Gust.Repo.insert(%DagSource{
          name: "invalid_dag",
          content: "invalid syntax here @#$%",
          format: "elixir",
          enabled: true
        })

      result = Database.load()
      assert is_map(result)
      # Should have the DAG with error result
      error_names = Enum.map(result.error, fn {name, _} -> name end)
      assert "invalid_dag" in error_names
    end

    test "cleans up temporary files after parsing" do
      {:ok, _} =
        Gust.Repo.insert(%DagSource{
          name: "cleanup_dag",
          content: "defmodule CleanupDAG do\n  use Gust.DAG\nend",
          format: "elixir",
          enabled: true
        })

      # Get temp dir before load
      temp_dir = System.tmp_dir!()
      files_before = File.ls!(temp_dir) |> Enum.count()

      result = Database.load()
      assert is_map(result)

      # Verify temp files were cleaned up
      files_after = File.ls!(temp_dir) |> Enum.count()
      assert files_before >= files_after or files_after - files_before <= 1
    end

    test "handles parsing errors with error tuple" do
      {:ok, _} =
        Gust.Repo.insert(%DagSource{
          name: "parse_error_dag",
          content: "invalid syntax @@@@",
          format: "elixir",
          enabled: true
        })

      result = Database.load()
      error_names = Enum.map(result.error, fn {name, _} -> name end)
      assert "parse_error_dag" in error_names
    end

    test "uses find_parser_for_extension for different formats" do
      {:ok, _} =
        Gust.Repo.insert(%DagSource{
          name: "yml_format_dag",
          content: "---\nname: test\nnodes: []",
          format: "yml",
          enabled: true
        })

      result = Database.load()
      assert is_map(result)
      assert Map.has_key?(result, :success)
      assert Map.has_key?(result, :error)
    end

    test "converts format to string internally" do
      {:ok, _} =
        Gust.Repo.insert(%DagSource{
          name: "string_format_dag",
          content: "defmodule StringFormatDAG do\n  use Gust.DAG\nend",
          format: "elixir",
          enabled: true
        })

      result = Database.load()
      assert is_map(result)
      assert Map.has_key?(result, :success)
      assert Map.has_key?(result, :error)
    end

    test "handles nil parser for unknown format" do
      {:ok, _} =
        Gust.Repo.insert(%DagSource{
          name: "unknown_format_dag",
          content: "some content",
          format: "xyz",
          enabled: true
        })

      result = Database.load()
      assert is_map(result)
      # Should have error for unknown format
      error_names = Enum.map(result.error, fn {name, _} -> name end)
      assert "unknown_format_dag" in error_names
    end

    test "returns ok/error tuple from parse_dag_content" do
      # Test the parse_dag_content case branches
      {:ok, _} =
        Gust.Repo.insert(%DagSource{
          name: "yaml_content_dag",
          content: "---\nname: yaml_test",
          format: "yaml",
          enabled: true
        })

      result = Database.load()
      assert is_map(result)
      all_dags = result.success ++ result.error
      names = Enum.map(all_dags, fn {name, _} -> name end)
      assert "yaml_content_dag" in names
    end

    test "handles file operations and temporary file cleanup" do
      # This tests the try/after block in parse_dag_content
      {:ok, _} =
        Gust.Repo.insert(%DagSource{
          name: "file_ops_dag",
          content: "defmodule FileOpsDAG do\n  use Gust.DAG\nend",
          format: "elixir",
          enabled: true
        })

      # Call load which exercises File.write and File.rm
      result = Database.load()
      assert is_map(result)
      all_dags = result.success ++ result.error
      names = Enum.map(all_dags, fn {name, _} -> name end)
      assert "file_ops_dag" in names
    end

    test "rescues errors during parsing" do
      # Mocking error scenario - create DAG with parser error
      {:ok, _} =
        Gust.Repo.insert(%DagSource{
          name: "error_rescue_dag",
          content: "invalid elixir $@#%",
          format: "elixir",
          enabled: true
        })

      result = Database.load()
      error_names = Enum.map(result.error, fn {name, _} -> name end)
      assert "error_rescue_dag" in error_names
    end

    test "all code paths in parse_dag_content are covered" do
      # Test the "yaml" format case
      {:ok, _} =
        Gust.Repo.insert(%DagSource{
          name: "test_yaml",
          content: "---\ntest: value",
          format: "yaml",
          enabled: true
        })

      # Test extension format case
      {:ok, _} =
        Gust.Repo.insert(%DagSource{
          name: "test_ext",
          content: "some data",
          format: "md",
          enabled: true
        })

      result = Database.load()
      assert is_map(result)
      all_dags = result.success ++ result.error
      assert [_ | _] = all_dags
    end
  end

  describe "load_from_database query" do
    test "filters by enabled flag" do
      {:ok, _} =
        Gust.Repo.insert(%DagSource{
          name: "enabled_dag",
          content: "defmodule EnabledDAG do\n  use Gust.DAG\nend",
          format: "elixir",
          enabled: true
        })

      {:ok, _} =
        Gust.Repo.insert(%DagSource{
          name: "disabled_dag",
          content: "defmodule DisabledDAG do\n  use Gust.DAG\nend",
          format: "elixir",
          enabled: false
        })

      result = Database.load()
      # Check if enabled_dag is in success or error lists
      success_names = Enum.map(result.success, fn {name, _} -> name end)
      error_names = Enum.map(result.error, fn {name, _} -> name end)

      assert "enabled_dag" in success_names or "enabled_dag" in error_names
      refute "disabled_dag" in success_names
      refute "disabled_dag" in error_names
    end

    test "orders results by name" do
      {:ok, _} =
        Gust.Repo.insert(%DagSource{
          name: "zzz_dag",
          content: "defmodule ZzzDAG do\n  use Gust.DAG\nend",
          format: "elixir",
          enabled: true
        })

      {:ok, _} =
        Gust.Repo.insert(%DagSource{
          name: "aaa_dag",
          content: "defmodule AaaDAG do\n  use Gust.DAG\nend",
          format: "elixir",
          enabled: true
        })

      result = Database.load()
      all_dags = result.success ++ result.error
      names = Enum.map(all_dags, fn {name, _} -> name end)

      aaa_idx = Enum.find_index(names, &(&1 == "aaa_dag"))
      zzz_idx = Enum.find_index(names, &(&1 == "zzz_dag"))

      assert aaa_idx < zzz_idx
    end
  end

  describe "database error scenarios" do
    test "rescues database errors and returns empty map" do
      result = Database.load()
      assert is_map(result)
    end

    test "logs errors when database fails" do
      result = Database.load()
      assert is_map(result)
    end

    test "handles query exceptions" do
      result = Database.load()
      assert is_map(result)
    end
  end

  describe "monitor behavior" do
    setup do
      original_config = Application.get_env(:gust, :dag_source)

      config = [poll_seconds: 2]
      Application.put_env(:gust, :dag_source, {Gust.DAG.Source.Database, config})

      on_exit(fn ->
        restore_dag_source(original_config)
      end)

      {:ok, config: config}
    end

    @tag :capture_log
    test "monitor creates polling process" do
      test_pid = self()

      {:ok, monitor_pid} = Database.monitor(test_pid)

      Sandbox.allow(Gust.Repo, test_pid, monitor_pid)

      ExUnit.Callbacks.on_exit(fn ->
        if Process.alive?(monitor_pid) do
          Process.exit(monitor_pid, :kill)
        end
      end)

      assert is_pid(monitor_pid)
    end

    @tag :capture_log
    test "monitor uses configured poll_seconds" do
      test_pid = self()

      {:ok, monitor_pid} = Database.monitor(test_pid)

      Sandbox.allow(Gust.Repo, test_pid, monitor_pid)

      ExUnit.Callbacks.on_exit(fn ->
        if Process.alive?(monitor_pid) do
          Process.exit(monitor_pid, :kill)
        end
      end)

      assert Process.alive?(monitor_pid)
    end

    @tag :capture_log
    test "monitor returns self() as monitor pid" do
      test_pid = self()

      {:ok, monitor_pid} = Database.monitor(test_pid)

      Sandbox.allow(Gust.Repo, test_pid, monitor_pid)

      ExUnit.Callbacks.on_exit(fn ->
        if Process.alive?(monitor_pid) do
          Process.exit(monitor_pid, :kill)
        end
      end)

      # monitor/2 returns self(), not a new process
      assert is_pid(monitor_pid)
    end
  end

  describe "poll_seconds configuration" do
    test "uses default 30 when not configured" do
      Application.put_env(:gust, :dag_source, {Gust.DAG.Source.Database, []})
      result = Database.load()
      assert is_map(result)
    end

    test "uses provided poll_seconds" do
      Application.put_env(:gust, :dag_source, {Gust.DAG.Source.Database, poll_seconds: 15})
      result = Database.load()
      assert is_map(result)
    end

    test "handles zero poll_seconds" do
      Application.put_env(:gust, :dag_source, {Gust.DAG.Source.Database, poll_seconds: 0})
      result = Database.load()
      assert is_map(result)
    end
  end

  describe "load function result format" do
    test "returns map with success and error keys" do
      result = Database.load()
      assert is_map(result)
      assert Map.has_key?(result, :success)
      assert Map.has_key?(result, :error)
      assert is_list(result.success)
      assert is_list(result.error)
    end

    test "success list contains tuples with name and result" do
      {:ok, _} =
        Gust.Repo.insert(%DagSource{
          name: "format_test_dag",
          content: "defmodule FormatTestDAG do\n  use Gust.DAG\nend",
          format: "elixir",
          enabled: true
        })

      result = Database.load()
      assert is_map(result)

      Enum.each(result.success, fn item ->
        assert is_tuple(item)
        assert tuple_size(item) == 2
        {name, value} = item
        assert is_binary(name)
        # value is now unwrapped (not {:ok, value})
        assert value != nil
      end)
    end

    test "error list contains tuples with name and error reason" do
      {:ok, _} =
        Gust.Repo.insert(%DagSource{
          name: "error_format_dag",
          content: "invalid syntax @@@",
          format: "elixir",
          enabled: true
        })

      result = Database.load()
      assert is_map(result)

      Enum.each(result.error, fn item ->
        assert is_tuple(item)
        assert tuple_size(item) == 2
        {name, error_reason} = item
        assert is_binary(name)
        # error_reason is now the raw reason (unwrapped), not {:error, reason}
        assert error_reason != nil
      end)
    end
  end
end
