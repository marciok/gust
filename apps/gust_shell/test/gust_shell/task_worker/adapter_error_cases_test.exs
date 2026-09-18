defmodule GustShell.TaskWorker.AdapterErrorCasesTest do
  @moduledoc """
  Tests for error cases in the TaskWorker Adapter.

  Focuses on error handling paths that may not be covered in other test files,
  particularly error cases when handling tasks.
  """

  use ExUnit.Case, async: false

  alias Gust.DAG.Definition
  alias Gust.Flows.Task
  alias GustShell.TaskWorker.Adapter

  import Mox

  setup :verify_on_exit!
  setup :set_mox_from_context

  setup do
    Gust.DAGLoggerMock
    |> stub(:set_task, fn _task_id, _attempt -> nil end)
    |> stub(:unset, fn -> nil end)

    :ok
  end

  describe "error handling - send_task_error path" do
    test "sends error message to owner when command resolution fails" do
      task = %Task{
        id: 500,
        run_id: 1,
        attempt: 1,
        name: "no_command_task",
        params: %{}
      }

      dag_def = %Definition{name: "test", adapter: :shell}

      state = %{
        task: task,
        dag_def: dag_def,
        owner_pid: self(),
        os_pid: nil,
        stdout: [],
        stderr: [],
        opts: %{}
      }

      # When run command is missing, should send error to owner
      {:stop, error, _final_state} = Adapter.handle_info(:run, state)

      assert error.__struct__ == RuntimeError
      assert error.message =~ "shell task requires a command"

      # Verify the task_result message was sent
      assert_receive {:task_result, ^error, 500, :error}
    end

    test "handles task with missing command in params and dag_def" do
      task = %Task{
        id: 501,
        run_id: 1,
        attempt: 1,
        name: "missing_task",
        params: %{"other_key" => "value"}
      }

      # DAG definition doesn't have this task
      dag_def = %Definition{
        name: "test",
        adapter: :shell,
        tasks: %{"different_task" => %{"run" => "echo test"}}
      }

      state = %{
        task: task,
        dag_def: dag_def,
        owner_pid: self(),
        os_pid: nil,
        stdout: [],
        stderr: [],
        opts: %{}
      }

      {:stop, error, _final_state} = Adapter.handle_info(:run, state)

      assert error.__struct__ == RuntimeError
      assert_receive {:task_result, %RuntimeError{}, 501, :error}
    end

    test "handles task config with nil task params" do
      task = %Task{
        id: 503,
        run_id: 1,
        attempt: 1,
        name: "test_task",
        params: nil
      }

      dag_def = %Definition{
        name: "test",
        adapter: :shell,
        tasks: %{"test_task" => %{"run" => "echo from dag"}}
      }

      state = %{
        task: task,
        dag_def: dag_def,
        owner_pid: self(),
        os_pid: nil,
        stdout: [],
        stderr: [],
        opts: %{}
      }

      # Should resolve from dag_def even if task.params is nil
      assert {:noreply, %{os_pid: _pid}} = Adapter.handle_info(:run, state)
    end

    test "handles task config with nil opts" do
      task = %Task{
        id: 504,
        run_id: 1,
        attempt: 1,
        name: "test",
        params: %{"run" => "echo test"}
      }

      dag_def = %Definition{name: "test", adapter: :shell}

      state = %{
        task: task,
        dag_def: dag_def,
        owner_pid: self(),
        os_pid: nil,
        stdout: [],
        stderr: [],
        opts: nil
      }

      # Should handle nil opts gracefully
      assert {:noreply, %{os_pid: _pid}} = Adapter.handle_info(:run, state)
    end
  end

  describe "stdio option normalization edge cases" do
    test "handles numeric options like nice" do
      task = %Task{
        id: 600,
        run_id: 1,
        attempt: 1,
        name: "nice_test",
        params: %{
          "run" => "echo test",
          "nice" => 10
        }
      }

      dag_def = %Definition{name: "test", adapter: :shell}

      state = %{
        task: task,
        dag_def: dag_def,
        owner_pid: self(),
        os_pid: nil,
        stdout: [],
        stderr: [],
        opts: %{}
      }

      assert {:noreply, %{os_pid: _pid}} = Adapter.handle_info(:run, state)
    end

    test "handles success_exit_code option" do
      task = %Task{
        id: 601,
        run_id: 1,
        attempt: 1,
        name: "success_exit_code_test",
        params: %{
          "run" => "echo test",
          "success_exit_code" => 0
        }
      }

      dag_def = %Definition{name: "test", adapter: :shell}

      state = %{
        task: task,
        dag_def: dag_def,
        owner_pid: self(),
        os_pid: nil,
        stdout: [],
        stderr: [],
        opts: %{}
      }

      assert {:noreply, %{os_pid: _pid}} = Adapter.handle_info(:run, state)
    end

  end

  describe "option key normalization edge cases" do
    test "handles cwd as alias for cd" do
      task = %Task{
        id: 700,
        run_id: 1,
        attempt: 1,
        name: "cwd_test",
        params: %{
          "run" => "pwd",
          "cwd" => "/tmp"
        }
      }

      dag_def = %Definition{name: "test", adapter: :shell}

      state = %{
        task: task,
        dag_def: dag_def,
        owner_pid: self(),
        os_pid: nil,
        stdout: [],
        stderr: [],
        opts: %{}
      }

      assert {:noreply, %{os_pid: _pid}} = Adapter.handle_info(:run, state)
    end

    test "handles working_dir as alias for cd" do
      task = %Task{
        id: 701,
        run_id: 1,
        attempt: 1,
        name: "working_dir_test",
        params: %{
          "run" => "pwd",
          "working_dir" => "/tmp"
        }
      }

      dag_def = %Definition{name: "test", adapter: :shell}

      state = %{
        task: task,
        dag_def: dag_def,
        owner_pid: self(),
        os_pid: nil,
        stdout: [],
        stderr: [],
        opts: %{}
      }

      assert {:noreply, %{os_pid: _pid}} = Adapter.handle_info(:run, state)
    end

    test "handles key with whitespace" do
      task = %Task{
        id: 702,
        run_id: 1,
        attempt: 1,
        name: "whitespace_test",
        params: %{
          "run" => "echo test",
          "  cd  " => "/tmp"
        }
      }

      dag_def = %Definition{name: "test", adapter: :shell}

      state = %{
        task: task,
        dag_def: dag_def,
        owner_pid: self(),
        os_pid: nil,
        stdout: [],
        stderr: [],
        opts: %{}
      }

      # Keys with whitespace should be trimmed
      assert {:noreply, %{os_pid: _pid}} = Adapter.handle_info(:run, state)
    end

    test "handles atom keys" do
      task = %Task{
        id: 703,
        run_id: 1,
        attempt: 1,
        name: "atom_key_test",
        params: %{
          run: "echo test",
          cd: "/tmp",
          monitor: true
        }
      }

      dag_def = %Definition{name: "test", adapter: :shell}

      state = %{
        task: task,
        dag_def: dag_def,
        owner_pid: self(),
        os_pid: nil,
        stdout: [],
        stderr: [],
        opts: %{}
      }

      # Should handle atom keys
      assert {:noreply, %{os_pid: _pid}} = Adapter.handle_info(:run, state)
    end

    test "ignores unknown option keys" do
      task = %Task{
        id: 704,
        run_id: 1,
        attempt: 1,
        name: "unknown_opts_test",
        params: %{
          "run" => "echo test",
          "unknown_option" => "value",
          "another_unknown" => "ignored"
        }
      }

      dag_def = %Definition{name: "test", adapter: :shell}

      state = %{
        task: task,
        dag_def: dag_def,
        owner_pid: self(),
        os_pid: nil,
        stdout: [],
        stderr: [],
        opts: %{}
      }

      # Unknown options should be silently ignored
      assert {:noreply, %{os_pid: _pid}} = Adapter.handle_info(:run, state)
    end
  end
end
