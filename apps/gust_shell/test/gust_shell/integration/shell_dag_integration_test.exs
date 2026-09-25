defmodule GustShell.Integration.ShellDAGIntegrationTest do
  @moduledoc """
  Integration tests for shell DAG loading and execution.

  These tests verify the complete flow of:
  1. Loading YAML DAG definitions
  2. Parsing into DAG structures
  3. Executing tasks through the shell adapter
  4. Capturing results and outputs
  """

  use ExUnit.Case, async: false

  import Mox
  import GustShell.TestFixtures
  import GustShell.TaskWorkerHelpers, only: [await_exit: 1]

  alias Gust.DAG.Definition
  alias GustShell.Parser.Adapter, as: ParserAdapter

  setup :verify_on_exit!

  setup do
    Gust.DAGLoggerMock
    |> stub(:set_task, fn _, _ -> :ok end)
    |> stub(:unset, fn -> :ok end)

    :ok
  end

  test "executes parsed options and keeps task params separate" do
    assert {:ok, definition} =
             parse_shell_dag("""
             tasks:
               - name: configured
                 run: printf '%s' "$GREETING"; printf warning >&2
                 cwd: #{System.tmp_dir!()}
                 env:
                   GREETING: hello
             """)

    state = %{
      task: %{
        id: 123,
        attempt: 1,
        name: "configured",
        params: %{"run" => "exit 99", "env" => %{"GREETING" => "wrong"}, "unknown" => true}
      },
      dag_def: definition,
      owner_pid: self(),
      opts: Map.fetch!(definition.tasks, "configured")
    }

    assert {:noreply, running} = GustShell.TaskWorker.Adapter.handle_info(:run, state)
    on_exit(fn -> :exec.stop(running.os_pid) end)
    await_exit(running)
    assert_receive {:task_result, %{stdout: "hello", stderr: "warning", exit_code: 0}, 123, :ok}
  end

  test "reports a real command failure with captured output" do
    assert {:ok, definition} =
             parse_shell_dag("""
             tasks:
               - name: fail
                 run: printf output; printf problem >&2; exit 7
             """)

    state = %{
      task: %{id: 124, attempt: 1, name: "fail", params: %{}},
      owner_pid: self(),
      opts: Map.fetch!(definition.tasks, "fail")
    }

    assert {:noreply, running} = GustShell.TaskWorker.Adapter.handle_info(:run, state)
    on_exit(fn -> :exec.stop(running.os_pid) end)
    await_exit(running)

    assert_receive {:task_result,
                    %GustShell.ShellExitError{exit_code: 7, stdout: "output", stderr: "problem"},
                    124, :error}
  end

  describe "YAML DAG parsing" do
    test "parses a simple sequential YAML DAG" do
      yaml = sequential_dag_yaml()
      assert {:ok, %Definition{} = dag_def} = parse_shell_dag(yaml)

      assert dag_def.name =~ ~r/shell_dag_test_/
      assert dag_def.adapter == :shell
      assert Map.has_key?(dag_def.tasks, "task1")
      assert Map.has_key?(dag_def.tasks, "task2")
      assert dag_def.tasks["task1"][:downstream] == MapSet.new(["task2"])
      assert dag_def.tasks["task2"][:downstream] == MapSet.new([])
    end

    test "parses a parallel YAML DAG with multiple downstream tasks" do
      yaml = parallel_dag_yaml()
      assert {:ok, %Definition{} = dag_def} = parse_shell_dag(yaml)

      assert dag_def.adapter == :shell
      assert dag_def.tasks["task1"][:downstream] == MapSet.new(["task2", "task3"])
      assert dag_def.tasks["task2"][:downstream] == MapSet.new([])
      assert dag_def.tasks["task3"][:downstream] == MapSet.new([])
    end

    test "parses YAML DAG with environment variables" do
      yaml = configured_dag_yaml(env_var: "test_value")
      assert {:ok, %Definition{} = dag_def} = parse_shell_dag(yaml)

      assert {:env, [{"MY_VAR", "test_value"}]} in dag_def.tasks["configured_task"].exec_opts
    end

    test "parses YAML DAG with schedule option" do
      yaml = """
      schedule: "0 2 * * *"
      tasks:
        - name: scheduled_task
          run: echo "scheduled"
      """

      assert {:ok, %Definition{} = dag_def} = parse_shell_dag(yaml)
      assert dag_def.options == [schedule: "0 2 * * *"]
    end

    test "creates proper task graph structure" do
      yaml = parallel_dag_yaml()
      assert {:ok, %Definition{} = dag_def} = parse_shell_dag(yaml)

      # Verify task list is flattened stages (one per stage for parallel tasks)
      assert is_list(dag_def.task_list)
      assert length(dag_def.task_list) >= 3

      # Verify stages are properly structured
      assert is_list(dag_def.stages)
      assert length(dag_def.stages) >= 2
    end

    test "fails gracefully on invalid YAML" do
      invalid_yaml = """
      invalid: yaml: syntax: error
        - malformed
      """

      assert {:error, {[], "invalid shell DAG", _reason}} = parse_shell_dag(invalid_yaml)
    end

    test "rejects a task without a command before execution" do
      assert {:error, {[], "invalid shell DAG", reason}} =
               parse_shell_dag("tasks: [{name: task_without_run}]")

      assert reason =~ "run must be a string"
    end
  end

  describe "shell command task structure" do
    test "task contains run command" do
      yaml = sequential_dag_yaml(cmd1: "echo hello world")
      assert {:ok, %Definition{} = dag_def} = parse_shell_dag(yaml)

      assert dag_def.tasks["task1"].run == "echo hello world"
    end

    test "task prepares execution options" do
      yaml = """
      tasks:
        - name: full_config_task
          run: echo test
          cwd: /tmp
          kill_timeout: 5000
          nice: 10
      """

      assert {:ok, %Definition{} = dag_def} = parse_shell_dag(yaml)
      task = dag_def.tasks["full_config_task"]

      assert task.run == "echo test"
      assert {:cd, "/tmp"} in task.exec_opts
      assert {:kill_timeout, 5000} in task.exec_opts
      assert {:nice, 10} in task.exec_opts
    end

    test "task normalizes environment variables to string keys" do
      yaml = """
      tasks:
        - name: env_task
          run: echo $VAR
          env:
            KEY1: value1
            KEY2: value2
      """

      assert {:ok, %Definition{} = dag_def} = parse_shell_dag(yaml)
      task = dag_def.tasks["env_task"]

      assert {:env, env} = List.keyfind(task.exec_opts, :env, 0)
      assert Map.new(env) == %{"KEY1" => "value1", "KEY2" => "value2"}
    end
  end

  describe "error handling" do
    test "handles YAML with no tasks" do
      yaml = "schedule: '0 0 * * *'\ntasks: []"
      assert {:ok, %Definition{} = dag_def} = parse_shell_dag(yaml)
      assert dag_def.tasks == %{}
    end

    test "handles multiple tasks with same downstream (not allowed in YAML but parser should handle gracefully)" do
      yaml = """
      tasks:
        - name: task1
          run: echo 1
          downstream: [task2, task2]
        - name: task2
          run: echo 2
      """

      # Should parse successfully (deduplication happens in graph linking)
      assert {:ok, %Definition{}} = parse_shell_dag(yaml)
    end
  end

  describe "file-based YAML DAG loading" do
    test "loads and parses YAML file with complete example" do
      yaml_content = """
      schedule: "0 2 * * *"
      tasks:
        - name: backup
          run: tar -czf backup.tar.gz /data
          cwd: /tmp
          downstream: [verify]
        - name: verify
          run: tar -tzf backup.tar.gz
          cwd: /tmp
          downstream: [cleanup]
        - name: cleanup
          run: rm -f backup.tar.gz
          cwd: /tmp
      """

      file_path = yaml_dag_fixture(yaml_content)

      on_exit(fn -> File.rm(file_path) end)

      assert {:ok, %Definition{} = dag_def} = ParserAdapter.parse_file(file_path)

      # Verify sequential chain
      assert dag_def.tasks["backup"][:downstream] == MapSet.new(["verify"])
      assert dag_def.tasks["verify"][:downstream] == MapSet.new(["cleanup"])
      assert dag_def.tasks["cleanup"][:downstream] == MapSet.new([])

      # Verify all tasks have the command
      assert dag_def.tasks["backup"].run == "tar -czf backup.tar.gz /data"
      assert dag_def.tasks["verify"].run == "tar -tzf backup.tar.gz"
      assert dag_def.tasks["cleanup"].run == "rm -f backup.tar.gz"

      # Verify schedule is preserved
      assert dag_def.options == [schedule: "0 2 * * *"]
    end

    test "creates DAG with complex multi-stage pipeline" do
      yaml_content = """
      tasks:
        - name: extract
          run: tar -xzf source.tar.gz
          downstream: [validate, process]
        - name: validate
          run: ./validate.sh
          downstream: [merge]
        - name: process
          run: ./process.sh
          downstream: [merge]
        - name: merge
          run: ./merge.sh
          downstream: [publish]
        - name: publish
          run: ./publish.sh
      """

      file_path = yaml_dag_fixture(yaml_content)

      on_exit(fn -> File.rm(file_path) end)

      assert {:ok, %Definition{} = dag_def} = ParserAdapter.parse_file(file_path)

      # Verify diamond-shaped DAG structure (order of downstream may vary)
      assert Enum.sort(dag_def.tasks["extract"][:downstream]) == ["process", "validate"]
      assert dag_def.tasks["validate"][:downstream] == MapSet.new(["merge"])
      assert dag_def.tasks["process"][:downstream] == MapSet.new(["merge"])
      assert dag_def.tasks["merge"][:downstream] == MapSet.new(["publish"])

      # Verify stages are properly layered
      # Due to graph merging, extract is stage 1, [validate, process] is stage 2, merge is stage 3, publish is stage 4
      assert is_list(dag_def.stages)
      assert length(dag_def.stages) == 4
    end
  end

  describe "edge cases" do
    test "handles tasks with special characters in run command" do
      yaml = """
      tasks:
        - name: special_chars_task
          run: echo "hello \\"world\\"" | grep hello
      """

      assert {:ok, %Definition{} = dag_def} = parse_shell_dag(yaml)
      assert String.contains?(dag_def.tasks["special_chars_task"].run, "hello")
    end

    test "handles multiline shell commands" do
      yaml = """
      tasks:
        - name: multiline_task
          run: |
            echo start
            sleep 1
            echo end
          downstream: []
      """

      assert {:ok, %Definition{} = dag_def} = parse_shell_dag(yaml)
      # Verify multiline command is preserved
      assert String.contains?(dag_def.tasks["multiline_task"].run, "echo start")
    end

    test "task names with underscores and hyphens" do
      yaml = """
      tasks:
        - name: task_with_underscore
          run: echo 1
          downstream: [task-with-hyphen]
        - name: task-with-hyphen
          run: echo 2
      """

      assert {:ok, %Definition{} = dag_def} = parse_shell_dag(yaml)
      assert Map.has_key?(dag_def.tasks, "task_with_underscore")
      assert Map.has_key?(dag_def.tasks, "task-with-hyphen")
    end
  end
end
