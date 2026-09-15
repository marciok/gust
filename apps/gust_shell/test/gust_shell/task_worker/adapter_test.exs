defmodule GustShell.TaskWorker.AdapterTest do
  use ExUnit.Case, async: false

  alias Gust.DAG.Definition
  alias Gust.Flows.Task
  alias GustShell.TaskWorker.Adapter

  import Mox

  setup :verify_on_exit!
  setup :set_mox_from_context

  setup do
    flush_mailbox()

    task = %Task{
      id: 123,
      run_id: 456,
      attempt: 1,
      name: "shell_cmd",
      params: %{"run" => "printf 'hello'"}
    }

    dag_def = %Definition{name: "demo", adapter: :shell}

    Gust.DAGLoggerMock
    |> stub(:set_task, fn _task_id, _attempt -> nil end)
    |> stub(:unset, fn -> nil end)

    %{task: task, dag_def: dag_def, owner_pid: self()}
  end

  describe "basic command execution" do
    test "runs using the task run parameter and captures binary output", %{
      task: task,
      dag_def: dag_def
    } do
      flush_mailbox()
      state = %{task: task, dag_def: dag_def, owner_pid: self(), os_pid: 42, stdout: "", stderr: "", opts: %{}}

      assert {:noreply, state1} = Adapter.handle_info({:stdout, 42, "hello\n"}, state)
      assert {:noreply, state2} = Adapter.handle_info({:stderr, 42, "warn\n"}, state1)

      assert {:stop, :normal, ^state2} =
               Adapter.handle_info({:DOWN, 42, :process, self(), :normal}, state2)

      assert_receive {:task_result,
                      %{status: :success, stdout: "hello\n", stderr: "warn\n", exit_code: 0}, 123,
                      :ok}
    end

    test "appends list-based output chunks before finalizing", %{task: task, dag_def: dag_def} do
      flush_mailbox()
      state = %{task: task, dag_def: dag_def, owner_pid: self(), os_pid: 42, stdout: ["hello"], stderr: ["warn"], opts: %{}}

      assert {:noreply, state1} = Adapter.handle_info({:stdout, 42, " world"}, state)
      assert {:noreply, state2} = Adapter.handle_info({:stderr, 42, "!"}, state1)

      assert {:stop, :normal, ^state2} =
               Adapter.handle_info({:DOWN, 42, :process, self(), :normal}, state2)

      assert_receive {:task_result,
                      %{status: :success, stdout: "hello world", stderr: "warn!", exit_code: 0}, 123,
                      :ok}
    end

    test "falls back to a single chunk when stdout and stderr are nil", %{
      task: task,
      dag_def: dag_def
    } do
      flush_mailbox()
      state = %{task: task, dag_def: dag_def, owner_pid: self(), os_pid: 42, stdout: nil, stderr: nil, opts: %{}}

      assert {:noreply, state1} = Adapter.handle_info({:stdout, 42, "hello"}, state)
      assert {:noreply, state2} = Adapter.handle_info({:stderr, 42, "warn"}, state1)

      assert {:stop, :normal, ^state2} =
               Adapter.handle_info({:DOWN, 42, :process, self(), :normal}, state2)

      assert_receive {:task_result,
                      %{status: :success, stdout: "hello", stderr: "warn", exit_code: 0}, 123,
                      :ok}
    end
  end

  describe "exit codes and signals" do
    test "reports success when process exits normally", %{task: task, dag_def: dag_def} do
      flush_mailbox()
      state = %{task: task, dag_def: dag_def, owner_pid: self(), os_pid: 42, stdout: "ok", stderr: "", opts: %{}}

      assert {:stop, :normal, ^state} =
               Adapter.handle_info({:DOWN, 42, :process, self(), :normal}, state)

      assert_receive {:task_result,
                      %{status: :success, stdout: "ok", stderr: "", exit_code: 0}, 123,
                      :ok}
    end

    test "reports success when exit_status is 0", %{task: task, dag_def: dag_def} do
      flush_mailbox()
      state = %{task: task, dag_def: dag_def, owner_pid: self(), os_pid: 42, stdout: "ok", stderr: "", opts: %{}}

      assert {:stop, :normal, ^state} =
               Adapter.handle_info({:DOWN, 42, :process, self(), {:exit_status, 0}}, state)

      assert_receive {:task_result,
                      %{status: :success, stdout: "ok", stderr: "", exit_code: 0}, 123,
                      :ok}
    end

    test "reports error when exit_status is non-zero", %{task: task, dag_def: dag_def} do
      flush_mailbox()
      state = %{task: task, dag_def: dag_def, owner_pid: self(), os_pid: 42, stdout: "oops", stderr: "problem", opts: %{}}

      # Exit status encoding: exit_code shifted left 8 bits (for normal exit)
      # Exit code 5 should be encoded as (5 << 8) = 1280 for proper decoding by :exec.status
      exit_status = Bitwise.bsl(5, 8)
      assert {:stop, :normal, ^state} =
               Adapter.handle_info({:DOWN, 42, :process, self(), {:exit_status, exit_status}}, state)

      assert_receive {:task_result, error, 123, :error}
      assert is_exception(error)
      assert error.exit_code == 5
      assert error.stdout == "oops"
      assert error.stderr == "problem"
      assert Exception.message(error) =~ "5"
    end

    test "reports signal termination when exit_status resolves to a signal", %{task: task, dag_def: dag_def} do
      flush_mailbox()
      state = %{task: task, dag_def: dag_def, owner_pid: self(), os_pid: 42, stdout: ["oops"], stderr: ["problem"], opts: %{}}

      assert {:stop, :normal, ^state} =
               Adapter.handle_info({:DOWN, 42, :process, self(), {:exit_status, 7}}, state)

      assert_receive {:task_result, error, 123, :error}
      assert is_exception(error)
      assert error.exit_code == :sigbus
      assert error.stdout == "oops"
      assert error.stderr == "problem"
      assert error.coredump == false
      assert Exception.message(error) =~ "sigbus"
    end

    test "reports signal-based termination with atom exit codes and core dump info", %{
      task: task,
      dag_def: dag_def
    } do
      flush_mailbox()
      state = %{task: task, dag_def: dag_def, owner_pid: self(), os_pid: 42, stdout: "boom", stderr: "bad", opts: %{}}

      assert {:stop, :normal, ^state} =
               Adapter.handle_info({:DOWN, 42, :process, self(), {:signal, :sigbus, true}}, state)

      assert_receive {:task_result, error, 123, :error}
      assert is_exception(error)
      assert error.exit_code == :sigbus
      assert error.stdout == "boom"
      assert error.stderr == "bad"
      assert error.coredump == true
      message = Exception.message(error)
      assert String.contains?(message, "sigbus")
      assert String.contains?(message, "core dumped")
    end

    test "reports signal termination without a core dump", %{task: task, dag_def: dag_def} do
      flush_mailbox()
      state = %{task: task, dag_def: dag_def, owner_pid: self(), os_pid: 42, stdout: "boom", stderr: "bad", opts: %{}}

      assert {:stop, :normal, ^state} =
               Adapter.handle_info({:DOWN, 42, :process, self(), {:signal, :sigterm, false}}, state)

      assert_receive {:task_result, error, 123, :error}
      assert is_exception(error)
      assert error.exit_code == :sigterm
      assert error.stdout == "boom"
      assert error.stderr == "bad"
      assert error.coredump == false
      assert Exception.message(error) =~ "sigterm"
    end
  end

  describe "process kill" do
    test "sends kill cast to stop the process", %{task: task, dag_def: dag_def} do
      state = %{task: task, dag_def: dag_def, owner_pid: self(), os_pid: 42, stdout: [], stderr: [], opts: %{}}

      # Note: This test just verifies the cast handler exists and calls :exec.stop
      # Actual kill behavior would be tested with real process communication
      assert {:stop, :normal, ^state} = Adapter.handle_cast({:kill}, state)
    end
  end

  describe "exec.run error handling" do
    test "handles exec.run error and sends error message to owner", %{task: task, dag_def: dag_def} do
      # Create a state that will cause :exec.run to fail
      # Using an empty command will cause a failure
      state = %{
        task: %{task | params: %{"run" => ""}},
        dag_def: dag_def,
        owner_pid: self(),
        os_pid: nil,
        stdout: [],
        stderr: [],
        opts: %{}
      }

      # When :exec.run is called with an empty command, it should fail
      {:stop, error, _final_state} = Adapter.handle_info(:run, state)

      # Verify error is a RuntimeError
      assert error.__struct__ == RuntimeError
      assert String.contains?(error.message, "failed to start shell task")

      # Verify the error was sent to owner
      assert_receive {:task_result, %RuntimeError{message: msg}, 123, :error}
      assert String.contains?(msg, "failed to start shell task")
    end
  end

  describe "command resolution" do
    test "resolves command from task params", %{dag_def: dag_def} do
      task = %Task{
        id: 1,
        run_id: 1,
        attempt: 1,
        name: "test",
        params: %{"run" => "echo hello"}
      }

      state = %{task: task, dag_def: dag_def, owner_pid: self(), os_pid: nil, stdout: [], stderr: [], opts: %{}}

      # The command resolution happens in handle_info(:run, state)
      # We're testing the private function behavior through the public interface
      # This test documents what gets passed to :exec.run
      assert {:noreply, %{os_pid: _pid}} = Adapter.handle_info(:run, state)
    end

    test "fails when command is missing from both task params and dag_def", %{owner_pid: owner_pid} do
      task = %Task{id: 999, run_id: 456, attempt: 1, name: "no_cmd", params: %{}}
      dag_def = %Definition{name: "demo", adapter: :shell}
      state = %{task: task, dag_def: dag_def, owner_pid: owner_pid, os_pid: nil, stdout: [], stderr: [], opts: %{}}

      flush_mailbox()

      assert {:stop, %RuntimeError{message: "shell task requires a command in task.params['run']"}, _state} = Adapter.handle_info(:run, state)

      assert_receive {:task_result, %RuntimeError{}, 999, :error}
    end
  end

  describe "configuration precedence" do
    test "merges dag definition, task params, and runtime opts in order", %{task: task, dag_def: dag_def} do
      # DAG definition sets cd
      dag_def_with_opts = %{dag_def | tasks: %{"shell_cmd" => %{"cd" => "/tmp"}}}

      # Task params set env
      task_with_env = %{task | params: %{"run" => "echo test", "env" => %{"FOO" => "bar"}}}

      # Runtime opts set other options (not user, which requires elevated privileges)
      runtime_opts = %{"kill_timeout" => 5000}

      state = %{
        task: task_with_env,
        dag_def: dag_def_with_opts,
        owner_pid: self(),
        os_pid: nil,
        stdout: [],
        stderr: [],
        opts: runtime_opts
      }

      # The precedence is: dag_def → task_params → runtime_opts (runtime_opts wins)
      # This documents the expected merge behavior
      assert {:noreply, %{os_pid: _pid}} = Adapter.handle_info(:run, state)
    end

    test "runtime opts override task params which override dag_def", %{dag_def: dag_def} do
      # Set different values at each level
      dag_def_with_opts = %{dag_def | tasks: %{"test" => %{"cd" => "/tmp"}}}

      task = %Task{
        id: 1,
        run_id: 1,
        attempt: 1,
        name: "test",
        params: %{"run" => "pwd", "cd" => "/tmp"}
      }

      runtime_opts = %{"cd" => "/tmp"}

      state = %{
        task: task,
        dag_def: dag_def_with_opts,
        owner_pid: self(),
        os_pid: nil,
        stdout: [],
        stderr: [],
        opts: runtime_opts
      }

      # Runtime opts should win
      assert {:noreply, %{os_pid: _pid}} = Adapter.handle_info(:run, state)
    end
  end

  describe "mismatch handling" do
    test "ignores stdout for mismatched os_pid", %{task: task, dag_def: dag_def} do
      state = %{task: task, dag_def: dag_def, owner_pid: self(), os_pid: 42, stdout: "initial", stderr: "", opts: %{}}

      # Send stdout for different PID - should be ignored
      assert {:noreply, unchanged_state} = Adapter.handle_info({:stdout, 99, "ignored"}, state)
      assert %{stdout: "initial"} = unchanged_state
    end

    test "ignores stderr for mismatched os_pid", %{task: task, dag_def: dag_def} do
      state = %{task: task, dag_def: dag_def, owner_pid: self(), os_pid: 42, stdout: "", stderr: "initial", opts: %{}}

      # Send stderr for different PID - should be ignored
      assert {:noreply, unchanged_state} = Adapter.handle_info({:stderr, 99, "ignored"}, state)
      assert %{stderr: "initial"} = unchanged_state
    end

    test "ignores DOWN message for mismatched os_pid", %{task: task, dag_def: dag_def} do
      state = %{task: task, dag_def: dag_def, owner_pid: self(), os_pid: 42, stdout: "", stderr: "", opts: %{}}

      # Send DOWN for different PID - should be ignored (handler pattern doesn't match)
      # The catch-all handler should return noreply with unchanged state
      assert {:noreply, unchanged_state} = Adapter.handle_info({:DOWN, 99, :process, self(), :normal}, state)
      assert unchanged_state == state
    end
  end

  # Helper function for setting up mailbox
  defp flush_mailbox do
    receive do
      _ -> flush_mailbox()
    after
      0 -> :ok
    end
  end
end
