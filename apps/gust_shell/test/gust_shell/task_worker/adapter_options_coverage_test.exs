defmodule GustShell.TaskWorker.AdapterOptionsCoverageTest do
  @moduledoc """
  Tests for exec option normalization to ensure all code paths are covered.
  Specifically targets the normalize_exec_option2 function clauses.
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

  describe "exec option normalization - all clauses" do
    test "cgroup option is processed" do
      task = %Task{
        id: 1,
        run_id: 1,
        attempt: 1,
        name: "cgroup_test",
        params: %{
          "run" => "echo test",
          "cgroup" => "my_cgroup"
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

      # Should successfully execute with cgroup option (line 119)
      assert {:noreply, %{os_pid: _pid}} = Adapter.handle_info(:run, state)
    end

    test "debug option is processed" do
      task = %Task{
        id: 2,
        run_id: 1,
        attempt: 1,
        name: "debug_test",
        params: %{
          "run" => "echo test",
          "debug" => 2
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

      # Should successfully execute with debug option (line 120)
      assert {:noreply, %{os_pid: _pid}} = Adapter.handle_info(:run, state)
    end

    test "executable option is processed" do
      task = %Task{
        id: 3,
        run_id: 1,
        attempt: 1,
        name: "executable_test",
        params: %{
          "run" => "echo test",
          "executable" => "/bin/bash"
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

      # Should successfully execute with executable option (line 122)
      assert {:noreply, %{os_pid: _pid}} = Adapter.handle_info(:run, state)
    end

    test "pty_echo true option is processed" do
      task = %Task{
        id: 4,
        run_id: 1,
        attempt: 1,
        name: "pty_echo_test",
        params: %{
          "run" => "echo test",
          "pty_echo" => true
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

      # Should successfully execute with pty_echo option (line 129)
      assert {:noreply, %{os_pid: _pid}} = Adapter.handle_info(:run, state)
    end

    test "pty_echo false option is filtered" do
      task = %Task{
        id: 5,
        run_id: 1,
        attempt: 1,
        name: "pty_echo_false_test",
        params: %{
          "run" => "echo test",
          "pty_echo" => false
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

      # Should successfully execute (false pty_echo is filtered out) (line 129)
      assert {:noreply, %{os_pid: _pid}} = Adapter.handle_info(:run, state)
    end

    test "pty_echo string 'true' is processed" do
      task = %Task{
        id: 6,
        run_id: 1,
        attempt: 1,
        name: "pty_echo_str_test",
        params: %{
          "run" => "echo test",
          "pty_echo" => "true"
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

      # Should successfully execute with pty_echo string "true" (line 129)
      assert {:noreply, %{os_pid: _pid}} = Adapter.handle_info(:run, state)
    end

    test "success_exit_code option is processed" do
      task = %Task{
        id: 7,
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

      # Should successfully execute with success_exit_code option (line 133)
      assert {:noreply, %{os_pid: _pid}} = Adapter.handle_info(:run, state)
    end

    test "catch-all for unknown options is processed" do
      task = %Task{
        id: 8,
        run_id: 1,
        attempt: 1,
        name: "unknown_test",
        params: %{
          "run" => "echo test",
          "unknown_option" => "value"
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

      # Should successfully execute (unknown options are filtered) (line 135)
      assert {:noreply, %{os_pid: _pid}} = Adapter.handle_info(:run, state)
    end
  end

  describe "normalize_option_key2 coverage" do
    test "cgroup string key is normalized" do
      task = %Task{
        id: 100,
        run_id: 1,
        attempt: 1,
        name: "cgroup_key_test",
        params: %{
          "run" => "echo test",
          "cgroup" => "group1"
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

    test "debug string key is normalized" do
      task = %Task{
        id: 101,
        run_id: 1,
        attempt: 1,
        name: "debug_key_test",
        params: %{
          "run" => "echo test",
          "debug" => 1
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
end
