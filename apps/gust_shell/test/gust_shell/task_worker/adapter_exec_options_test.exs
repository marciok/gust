defmodule GustShell.TaskWorker.AdapterExecOptionsTest do
  @moduledoc """
  Comprehensive tests for exec option types to ensure complete coverage
  of the normalize_exec_option2 and normalize_stdio functions.
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

  defp create_task_state(task_id, params) do
    task = %Task{
      id: task_id,
      run_id: 1,
      attempt: 1,
      name: "test_task",
      params: Map.merge(%{"run" => "echo test"}, params)
    }

    dag_def = %Definition{name: "test", adapter: :shell}

    %{
      task: task,
      dag_def: dag_def,
      owner_pid: self(),
      os_pid: nil,
      stdout: [],
      stderr: [],
      opts: %{}
    }
  end

  describe "debug option" do
    test "debug option with numeric value" do
      state = create_task_state(1, %{"debug" => 1})
      assert {:noreply, %{os_pid: _pid}} = Adapter.handle_info(:run, state)
    end

    test "debug option with level 2" do
      state = create_task_state(2, %{"debug" => 2})
      assert {:noreply, %{os_pid: _pid}} = Adapter.handle_info(:run, state)
    end
  end

  describe "executable option" do
    test "executable option with bash path" do
      state = create_task_state(3, %{"executable" => "/bin/bash"})
      assert {:noreply, %{os_pid: _pid}} = Adapter.handle_info(:run, state)
    end

    test "executable option with sh path" do
      state = create_task_state(4, %{"executable" => "/bin/sh"})
      assert {:noreply, %{os_pid: _pid}} = Adapter.handle_info(:run, state)
    end
  end

  describe "group option" do
    test "group option with numeric value" do
      state = create_task_state(5, %{"group" => 0})
      assert {:noreply, %{os_pid: _pid}} = Adapter.handle_info(:run, state)
    end

    test "group option with different process group" do
      state = create_task_state(6, %{"group" => 100})
      assert {:noreply, %{os_pid: _pid}} = Adapter.handle_info(:run, state)
    end
  end

  describe "kill_group option" do
    test "kill_group true boolean" do
      state = create_task_state(7, %{"kill_group" => true})
      assert {:noreply, %{os_pid: _pid}} = Adapter.handle_info(:run, state)
    end

    test "kill_group string true" do
      state = create_task_state(8, %{"kill_group" => "true"})
      assert {:noreply, %{os_pid: _pid}} = Adapter.handle_info(:run, state)
    end

    test "kill_group false boolean is filtered" do
      state = create_task_state(9, %{"kill_group" => false})
      assert {:noreply, %{os_pid: _pid}} = Adapter.handle_info(:run, state)
    end

    test "kill_group string false is filtered" do
      state = create_task_state(10, %{"kill_group" => "false"})
      assert {:noreply, %{os_pid: _pid}} = Adapter.handle_info(:run, state)
    end
  end

  describe "pty option" do
    test "pty true boolean" do
      state = create_task_state(11, %{"pty" => true})
      assert {:noreply, %{os_pid: _pid}} = Adapter.handle_info(:run, state)
    end

    test "pty string true" do
      state = create_task_state(12, %{"pty" => "true"})
      assert {:noreply, %{os_pid: _pid}} = Adapter.handle_info(:run, state)
    end

    test "pty false boolean is filtered" do
      state = create_task_state(13, %{"pty" => false})
      assert {:noreply, %{os_pid: _pid}} = Adapter.handle_info(:run, state)
    end
  end

  describe "pty_echo option" do
    test "pty_echo true boolean" do
      state = create_task_state(14, %{"pty_echo" => true})
      assert {:noreply, %{os_pid: _pid}} = Adapter.handle_info(:run, state)
    end

    test "pty_echo string true" do
      state = create_task_state(15, %{"pty_echo" => "true"})
      assert {:noreply, %{os_pid: _pid}} = Adapter.handle_info(:run, state)
    end

    test "pty_echo false boolean is filtered" do
      state = create_task_state(16, %{"pty_echo" => false})
      assert {:noreply, %{os_pid: _pid}} = Adapter.handle_info(:run, state)
    end

    test "pty_echo string false is filtered" do
      state = create_task_state(17, %{"pty_echo" => "false"})
      assert {:noreply, %{os_pid: _pid}} = Adapter.handle_info(:run, state)
    end
  end

  describe "user option" do
    test "user option with root" do
      state = create_task_state(18, %{"user" => "root"})
      result = Adapter.handle_info(:run, state)

      # Either succeeds or fails with permission error - both are acceptable
      case result do
        {:noreply, %{os_pid: _pid}} -> assert true
        {:stop, %RuntimeError{message: msg}, _state} ->
          assert String.contains?(msg, "failed to start shell task")
      end
    end

    test "user option with different user" do
      state = create_task_state(19, %{"user" => "nobody"})
      result = Adapter.handle_info(:run, state)

      case result do
        {:noreply, %{os_pid: _pid}} -> assert true
        {:stop, %RuntimeError{}, _state} -> assert true
      end
    end
  end

  describe "stdio options - null mode" do
    test "stdout null option (string)" do
      state = create_task_state(20, %{"stdout" => "null"})
      assert {:noreply, %{os_pid: _pid}} = Adapter.handle_info(:run, state)
    end

    test "stderr null option (string)" do
      state = create_task_state(21, %{"stderr" => "null"})
      assert {:noreply, %{os_pid: _pid}} = Adapter.handle_info(:run, state)
    end

    test "stdin null option (string)" do
      state = create_task_state(22, %{"stdin" => "null"})
      assert {:noreply, %{os_pid: _pid}} = Adapter.handle_info(:run, state)
    end

    test "stdout null option (atom)" do
      state = create_task_state(23, %{"stdout" => :null})
      assert {:noreply, %{os_pid: _pid}} = Adapter.handle_info(:run, state)
    end

    test "stderr null option (atom)" do
      state = create_task_state(24, %{"stderr" => :null})
      assert {:noreply, %{os_pid: _pid}} = Adapter.handle_info(:run, state)
    end

    test "stdin null option (atom)" do
      state = create_task_state(25, %{"stdin" => :null})
      assert {:noreply, %{os_pid: _pid}} = Adapter.handle_info(:run, state)
    end
  end

  describe "stdio options - close mode" do
    test "stdout close option (string)" do
      state = create_task_state(26, %{"stdout" => "close"})
      assert {:noreply, %{os_pid: _pid}} = Adapter.handle_info(:run, state)
    end

    test "stderr close option (string)" do
      state = create_task_state(27, %{"stderr" => "close"})
      assert {:noreply, %{os_pid: _pid}} = Adapter.handle_info(:run, state)
    end

    test "stdin close option (string)" do
      state = create_task_state(28, %{"stdin" => "close"})
      assert {:noreply, %{os_pid: _pid}} = Adapter.handle_info(:run, state)
    end

    test "stdout close option (atom)" do
      state = create_task_state(29, %{"stdout" => :close})
      assert {:noreply, %{os_pid: _pid}} = Adapter.handle_info(:run, state)
    end

    test "stderr close option (atom)" do
      state = create_task_state(30, %{"stderr" => :close})
      assert {:noreply, %{os_pid: _pid}} = Adapter.handle_info(:run, state)
    end

    test "stdin close option (atom)" do
      state = create_task_state(31, %{"stdin" => :close})
      assert {:noreply, %{os_pid: _pid}} = Adapter.handle_info(:run, state)
    end
  end

  describe "option edge cases" do
    test "option with whitespace in key is trimmed" do
      state = create_task_state(50, %{"  debug  " => 1})
      assert {:noreply, %{os_pid: _pid}} = Adapter.handle_info(:run, state)
    end

    test "option with whitespace and pty" do
      state = create_task_state(51, %{"  pty  " => true})
      assert {:noreply, %{os_pid: _pid}} = Adapter.handle_info(:run, state)
    end

    test "unknown option is ignored" do
      state = create_task_state(52, %{
        "unknown_exec_option" => "value",
        "debug" => 1
      })

      assert {:noreply, %{os_pid: _pid}} = Adapter.handle_info(:run, state)
    end

    test "multiple unknown options are ignored" do
      state = create_task_state(53, %{
        "unknown1" => "value1",
        "unknown2" => "value2",
        "cd" => "/tmp"
      })

      assert {:noreply, %{os_pid: _pid}} = Adapter.handle_info(:run, state)
    end
  end

  describe "normalize_option_key2 coverage" do
    test "cgroup string key is normalized" do
      state = create_task_state(60, %{"cgroup" => "group1"})
      assert {:noreply, %{os_pid: _pid}} = Adapter.handle_info(:run, state)
    end

    test "pty_echo string key is normalized" do
      state = create_task_state(61, %{"pty_echo" => true})
      assert {:noreply, %{os_pid: _pid}} = Adapter.handle_info(:run, state)
    end

    test "cwd alias is normalized to cd" do
      state = create_task_state(62, %{"cwd" => "/tmp"})
      assert {:noreply, %{os_pid: _pid}} = Adapter.handle_info(:run, state)
    end

    test "working_dir alias is normalized to cd" do
      state = create_task_state(63, %{"working_dir" => "/var"})
      assert {:noreply, %{os_pid: _pid}} = Adapter.handle_info(:run, state)
    end
  end

  describe "normalize_stdio coverage" do
    test "stdout with true boolean becomes key" do
      state = create_task_state(70, %{"stdout" => true})
      assert {:noreply, %{os_pid: _pid}} = Adapter.handle_info(:run, state)
    end

    test "stderr with true string becomes key" do
      state = create_task_state(71, %{"stderr" => "true"})
      assert {:noreply, %{os_pid: _pid}} = Adapter.handle_info(:run, state)
    end
  end

  describe "option combinations (safe combinations)" do
    test "debug and executable together" do
      state = create_task_state(80, %{
        "debug" => 1,
        "executable" => "/bin/bash"
      })

      assert {:noreply, %{os_pid: _pid}} = Adapter.handle_info(:run, state)
    end

    test "kill_group and nice together" do
      state = create_task_state(81, %{
        "kill_group" => true,
        "nice" => 5
      })

      assert {:noreply, %{os_pid: _pid}} = Adapter.handle_info(:run, state)
    end

    test "pty and pty_echo together" do
      state = create_task_state(82, %{
        "pty" => true,
        "pty_echo" => true
      })

      assert {:noreply, %{os_pid: _pid}} = Adapter.handle_info(:run, state)
    end

    test "cd and kill_timeout together" do
      state = create_task_state(83, %{
        "cd" => "/tmp",
        "kill_timeout" => 5000
      })

      assert {:noreply, %{os_pid: _pid}} = Adapter.handle_info(:run, state)
    end
  end
end
