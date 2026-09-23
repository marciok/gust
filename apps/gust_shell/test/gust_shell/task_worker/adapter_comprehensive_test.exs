defmodule GustShell.TaskWorker.AdapterComprehensiveTest do
  @moduledoc """
  Comprehensive tests for TaskWorker Adapter covering edge cases and private function behavior.
  """

  use ExUnit.Case, async: true

  alias Gust.DAG.Definition
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

  describe "finalize_task - exit status handling" do
    test "handles normal process exit" do
      # Test via DOWN message with :normal reason - os_pid must match 42
      state = %{
        stdout: "output",
        stderr: "",
        task: %{id: 1},
        owner_pid: self(),
        os_pid: 42
      }

      assert {:stop, :normal, _} =
               Adapter.handle_info({:DOWN, 42, :process, self(), :normal}, state)

      assert_receive {:task_result, %{status: :success, exit_code: 0}, 1, :ok}
    end

    test "handles exit with status 0" do
      state = %{
        stdout: "done",
        stderr: "",
        task: %{id: 2},
        owner_pid: self(),
        os_pid: 42
      }

      assert {:stop, :normal, _} =
               Adapter.handle_info({:DOWN, 42, :process, self(), {:exit_status, 0}}, state)

      assert_receive {:task_result, result, 2, :ok}
      assert is_map(result)
      assert result.status == :success
      assert result.exit_code == 0
    end

    test "handles process killed by signal" do
      state = %{
        stdout: "",
        stderr: "",
        task: %{id: 3},
        owner_pid: self(),
        os_pid: 42
      }

      assert {:stop, :normal, _} =
               Adapter.handle_info(
                 {:DOWN, 42, :process, self(), {:signal, :sigterm, false}},
                 state
               )

      assert_receive {:task_result, error, 3, :error}
      assert is_exception(error)
      assert error.exit_code == :sigterm
      assert error.coredump == false
      assert Exception.message(error) =~ "sigterm"
    end

    test "handles process killed by signal with core dump" do
      state = %{
        stdout: "",
        stderr: "",
        task: %{id: 4},
        owner_pid: self(),
        os_pid: 42
      }

      assert {:stop, :normal, _} =
               Adapter.handle_info(
                 {:DOWN, 42, :process, self(), {:signal, :sigsegv, true}},
                 state
               )

      assert_receive {:task_result, error, 4, :error}
      assert is_exception(error)
      assert error.exit_code == :sigsegv
      assert error.coredump == true

      message = Exception.message(error)
      assert String.contains?(message, "core dumped")
    end
  end

  describe "output accumulation" do
    test "accumulates stdout in list form" do
      state = %{
        task: %{id: 1, run_id: 1, attempt: 1, name: "test", params: %{"run" => "test"}},
        dag_def: %Definition{name: "test", adapter: :shell},
        owner_pid: self(),
        os_pid: 42,
        stdout: [],
        stderr: "",
        opts: %{}
      }

      state1 = elem(Adapter.handle_info({:stdout, 42, "line 1\n"}, state), 1)
      state2 = elem(Adapter.handle_info({:stdout, 42, "line 2\n"}, state1), 1)
      state3 = elem(Adapter.handle_info({:stdout, 42, "line 3"}, state2), 1)

      assert {:stop, :normal, _final_state} =
               Adapter.handle_info({:DOWN, 42, :process, self(), :normal}, state3)

      assert_receive {:task_result,
                      %{status: :success, stdout: "line 1\nline 2\nline 3", stderr: ""}, 1, :ok}
    end

    test "accumulates stderr in list form" do
      state = %{
        task: %{id: 2, run_id: 1, attempt: 1, name: "test", params: %{"run" => "test"}},
        dag_def: %Definition{name: "test", adapter: :shell},
        owner_pid: self(),
        os_pid: 42,
        stdout: "",
        stderr: [],
        opts: %{}
      }

      state1 = elem(Adapter.handle_info({:stderr, 42, "warning: "}, state), 1)
      state2 = elem(Adapter.handle_info({:stderr, 42, "something"}, state1), 1)

      assert {:stop, :normal, _final_state} =
               Adapter.handle_info({:DOWN, 42, :process, self(), :normal}, state2)

      assert_receive {:task_result, %{status: :success, stdout: "", stderr: "warning: something"},
                      2, :ok}
    end

    test "handles nil stdout and stderr" do
      state = %{
        task: %{id: 3, run_id: 1, attempt: 1, name: "test", params: %{"run" => "test"}},
        dag_def: %Definition{name: "test", adapter: :shell},
        owner_pid: self(),
        os_pid: 42,
        stdout: nil,
        stderr: nil,
        opts: %{}
      }

      assert {:stop, :normal, _final_state} =
               Adapter.handle_info({:DOWN, 42, :process, self(), :normal}, state)

      assert_receive {:task_result, %{status: :success, stdout: "", stderr: ""}, 3, :ok}
    end

    test "handles binary stdout and stderr" do
      state = %{
        task: %{id: 4, run_id: 1, attempt: 1, name: "test", params: %{"run" => "test"}},
        dag_def: %Definition{name: "test", adapter: :shell},
        owner_pid: self(),
        os_pid: 42,
        stdout: "existing output",
        stderr: "existing error",
        opts: %{}
      }

      state1 = elem(Adapter.handle_info({:stdout, 42, " more"}, state), 1)
      state2 = elem(Adapter.handle_info({:stderr, 42, " details"}, state1), 1)

      assert {:stop, :normal, _final_state} =
               Adapter.handle_info({:DOWN, 42, :process, self(), :normal}, state2)

      assert_receive {:task_result,
                      %{
                        status: :success,
                        stdout: "existing output more",
                        stderr: "existing error details"
                      }, 4, :ok}
    end
  end

  describe "process termination" do
    test "kill cast stops the process" do
      state = %{
        task: %{id: 300},
        dag_def: %Definition{},
        owner_pid: self(),
        os_pid: 42,
        stdout: [],
        stderr: [],
        opts: %{}
      }

      assert {:stop, :normal, ^state} = Adapter.handle_cast({:kill}, state)
    end
  end

  describe "mismatched PID handling" do
    test "stdout from wrong PID is ignored and state unchanged" do
      original_state = %{
        task: %{id: 1},
        dag_def: %Definition{},
        owner_pid: self(),
        os_pid: 42,
        stdout: "keep this",
        stderr: "",
        opts: %{}
      }

      {:noreply, new_state} = Adapter.handle_info({:stdout, 999, "ignore this"}, original_state)

      assert new_state.stdout == "keep this"
      assert new_state == original_state
    end

    test "stderr from wrong PID is ignored" do
      original_state = %{
        task: %{id: 2},
        dag_def: %Definition{},
        owner_pid: self(),
        os_pid: 42,
        stdout: "",
        stderr: "keep this",
        opts: %{}
      }

      {:noreply, new_state} = Adapter.handle_info({:stderr, 999, "ignore this"}, original_state)

      assert new_state.stderr == "keep this"
    end

    test "DOWN from wrong PID is ignored" do
      original_state = %{
        task: %{id: 3},
        dag_def: %Definition{},
        owner_pid: self(),
        os_pid: 42,
        stdout: "",
        stderr: "",
        opts: %{}
      }

      {:noreply, new_state} =
        Adapter.handle_info({:DOWN, 999, :process, self(), :normal}, original_state)

      assert new_state == original_state
      refute_receive {:task_result, _, _, _}, 50
    end
  end
end
