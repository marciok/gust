defmodule GustShell.Runtime.AdapterTest do
  use ExUnit.Case, async: true

  alias Gust.DAG.Definition
  alias GustShell.Runtime.Adapter

  describe "setup/2" do
    test "returns the DAG definition unchanged" do
      dag_def = %Definition{
        name: "test_dag",
        adapter: :shell,
        tasks: %{"task1" => %{"run" => "echo test"}}
      }

      assert Adapter.setup(dag_def, "runtime_123") == dag_def
    end

    test "setup with nil runtime_id" do
      dag_def = %Definition{name: "test_dag", adapter: :shell}

      assert Adapter.setup(dag_def, nil) == dag_def
    end

    test "setup is idempotent" do
      dag_def = %Definition{name: "test_dag", adapter: :shell}

      result1 = Adapter.setup(dag_def, "runtime_1")
      result2 = Adapter.setup(dag_def, "runtime_1")

      assert result1 == result2
    end

    test "setup preserves all DAG definition fields" do
      dag_def = %Definition{
        name: "backup_dag",
        adapter: :shell,
        file_path: "/path/to/backup.yml",
        tasks: %{
          "task1" => %{"run" => "tar -czf backup.tar.gz /data"},
          "task2" => %{"run" => "verify.sh"}
        },
        options: [schedule: "0 2 * * *"],
        stages: [["task1"], ["task2"]]
      }

      result = Adapter.setup(dag_def, "runtime_id")

      assert result.name == dag_def.name
      assert result.adapter == dag_def.adapter
      assert result.file_path == dag_def.file_path
      assert result.tasks == dag_def.tasks
      assert result.options == dag_def.options
      assert result.stages == dag_def.stages
    end
  end

  describe "teardown/2" do
    test "returns :ok" do
      dag_def = %Definition{name: "test_dag", adapter: :shell}

      assert Adapter.teardown(dag_def, "runtime_123") == :ok
    end

    test "teardown is side-effect free" do
      dag_def = %Definition{name: "test_dag", adapter: :shell}

      # Should not raise or change anything
      assert Adapter.teardown(dag_def, "runtime_1") == :ok
      assert Adapter.teardown(dag_def, "runtime_1") == :ok
    end

    test "teardown with nil runtime_id" do
      dag_def = %Definition{name: "test_dag", adapter: :shell}

      assert Adapter.teardown(dag_def, nil) == :ok
    end

    test "teardown with different runtime ids" do
      dag_def = %Definition{name: "test_dag", adapter: :shell}

      assert Adapter.teardown(dag_def, "runtime_1") == :ok
      assert Adapter.teardown(dag_def, "runtime_2") == :ok
      assert Adapter.teardown(dag_def, "runtime_3") == :ok
    end
  end

  describe "on_finished_callback/4" do
    test "returns :ok for successful completion" do
      dag_def = %Definition{name: "test_dag", adapter: :shell}
      run = %{id: 1, status: :succeeded}

      assert Adapter.on_finished_callback(dag_def, :on_success, run, :ok) == :ok
    end

    test "returns :ok for failed completion" do
      dag_def = %Definition{name: "test_dag", adapter: :shell}
      run = %{id: 1, status: :failed}

      assert Adapter.on_finished_callback(dag_def, :on_failure, run, :error) == :ok
    end

    test "on_finished_callback is no-op" do
      dag_def = %Definition{name: "test_dag", adapter: :shell}
      run = %{id: 1}

      # Should return :ok regardless of inputs
      assert Adapter.on_finished_callback(dag_def, nil, nil, nil) == :ok
      assert Adapter.on_finished_callback(nil, nil, nil, nil) == :ok
      assert Adapter.on_finished_callback(dag_def, :callback_name, run, :any_status) == :ok
    end

    test "on_finished_callback with all possible status values" do
      dag_def = %Definition{name: "test_dag", adapter: :shell}
      run = %{id: 1}

      statuses = [:ok, :error, :upstream_failed, :skipped, :cancelled, :already_processed]

      Enum.each(statuses, fn status ->
        assert Adapter.on_finished_callback(dag_def, :callback, run, status) == :ok
      end)
    end
  end

  describe "kill/1" do
    test "sends kill cast to task process" do
      task_pid = self()

      # This will send a cast to our test process
      assert Adapter.kill(task_pid) == :ok

      # Verify the cast was sent
      assert_receive {:"$gen_cast", {:kill}}, 100
    end

    test "kill returns :ok even if process doesn't exist" do
      # Using a fake PID that doesn't exist
      fake_pid = spawn(fn -> Process.sleep(1) end)
      ref = Process.monitor(fake_pid)

      # Wait for process to exit
      assert_receive {:DOWN, ^ref, :process, ^fake_pid, _}

      # Killing a dead process should still return :ok
      # (GenServer.cast doesn't raise on non-existent processes)
      assert Adapter.kill(fake_pid) == :ok
    end

    test "kill is idempotent" do
      task_pid = self()

      # Multiple kills should all return :ok
      assert Adapter.kill(task_pid) == :ok
      assert Adapter.kill(task_pid) == :ok

      # Verify we got two casts
      assert_receive {:"$gen_cast", {:kill}}, 100
      assert_receive {:"$gen_cast", {:kill}}, 100
    end
  end

  describe "adapter callbacks" do
    test "all callbacks are implemented" do
      dag_def = %Definition{name: "test_dag", adapter: :shell}

      # Verify all callbacks work together
      assert {:ok, setup_result} = {:ok, Adapter.setup(dag_def, "runtime_1")}
      assert setup_result == dag_def

      assert :ok = Adapter.teardown(dag_def, "runtime_1")
      assert :ok = Adapter.on_finished_callback(dag_def, :callback, nil, :ok)
      assert :ok = Adapter.kill(self())
    end
  end
end
