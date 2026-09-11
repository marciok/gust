defmodule Gust.DAG.TaskWorker.Adapters.ShellTest do
  use ExUnit.Case, async: false

  alias Gust.DAG.Definition
  alias Gust.DAG.TaskWorker.Adapters.Shell
  alias Gust.Flows.Task

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
      params: %{"command" => "printf 'hello'"}
    }

    dag_def = %Definition{name: "demo", adapter: :shell}

    Gust.DAGLoggerMock
    |> stub(:set_task, fn _task_id, _attempt -> nil end)
    |> stub(:unset, fn -> nil end)

    %{task: task, dag_def: dag_def, owner_pid: self()}
  end

  test "runs using the task command and captures binary output", %{task: task, dag_def: dag_def} do
    flush_mailbox()
    state = %{task: task, dag_def: dag_def, owner_pid: self(), os_pid: 42, stdout: "", stderr: ""}

    assert {:noreply, state1} = Shell.handle_info({:stdout, 42, "hello\n"}, state)
    assert {:noreply, state2} = Shell.handle_info({:stderr, 42, "warn\n"}, state1)

    assert {:stop, :normal, ^state2} =
             Shell.handle_info({:DOWN, 42, :process, self(), :normal}, state2)

    assert_receive {:task_result, %{status: :success, stdout: "hello\n", stderr: "warn\n", exit_code: 0}, 123, :ok}
  end

  test "appends list-based output chunks before finalizing", %{task: task, dag_def: dag_def} do
    flush_mailbox()
    state = %{task: task, dag_def: dag_def, owner_pid: self(), os_pid: 42, stdout: ["hello"], stderr: ["warn"]}

    assert {:noreply, state1} = Shell.handle_info({:stdout, 42, " world"}, state)
    assert {:noreply, state2} = Shell.handle_info({:stderr, 42, "!"}, state1)

    assert {:stop, :normal, ^state2} =
             Shell.handle_info({:DOWN, 42, :process, self(), :normal}, state2)

    assert_receive {:task_result,
                    %{status: :success, stdout: " worldhello", stderr: "!warn", exit_code: 0}, 123, :ok}
  end

  test "reports numeric exit statuses without signal mapping", %{task: task, dag_def: dag_def} do
    flush_mailbox()
    state = %{task: task, dag_def: dag_def, owner_pid: self(), os_pid: 42, stdout: "oops", stderr: "problem"}

    assert {:stop, :normal, ^state} =
             Shell.handle_info({:DOWN, 42, :process, self(), {:exit_status, 0}}, state)

    assert_receive {:task_result,
                    %{
                      status: :error,
                      message: "command exited with status 0",
                      exit_code: 0,
                      stdout: "oops",
                      stderr: "problem"
                    }, 123, :error}
  end

  test "reports signal termination when exit_status resolves to a signal", %{task: task, dag_def: dag_def} do
    flush_mailbox()
    state = %{task: task, dag_def: dag_def, owner_pid: self(), os_pid: 42, stdout: ["oops"], stderr: ["problem"]}

    assert {:stop, :normal, ^state} =
             Shell.handle_info({:DOWN, 42, :process, self(), {:exit_status, 7}}, state)

    assert_receive {:task_result,
                    %{
                      status: :error,
                      message: "command killed by signal sigbus",
                      exit_code: :sigbus,
                      stdout: "oops",
                      stderr: "problem",
                      coredump: false
                    }, 123, :error}
  end

  test "reports signal-based termination with atom exit codes and core dump info", %{task: task, dag_def: dag_def} do
    flush_mailbox()
    state = %{task: task, dag_def: dag_def, owner_pid: self(), os_pid: 42, stdout: "boom", stderr: "bad"}

    assert {:stop, :normal, ^state} =
             Shell.handle_info({:DOWN, 42, :process, self(), {:signal, :sigbus, true}}, state)

    assert_receive {:task_result,
                    %{
                      status: :error,
                      message: "command killed by signal sigbus (core dumped)",
                      exit_code: :sigbus,
                      stdout: "boom",
                      stderr: "bad",
                      coredump: true
                    }, 123, :error}
  end

  test "falls back to a single chunk when stdout and stderr are nil", %{task: task, dag_def: dag_def} do
    flush_mailbox()
    state = %{task: task, dag_def: dag_def, owner_pid: self(), os_pid: 42, stdout: nil, stderr: nil}

    assert {:noreply, state1} = Shell.handle_info({:stdout, 42, "hello"}, state)
    assert {:noreply, state2} = Shell.handle_info({:stderr, 42, "warn"}, state1)

    assert {:stop, :normal, ^state2} =
             Shell.handle_info({:DOWN, 42, :process, self(), :normal}, state2)

    assert_receive {:task_result,
                    %{status: :success, stdout: "hello", stderr: "warn", exit_code: 0}, 123, :ok}
  end

  test "reports signal termination without a core dump", %{task: task, dag_def: dag_def} do
    flush_mailbox()
    state = %{task: task, dag_def: dag_def, owner_pid: self(), os_pid: 42, stdout: "boom", stderr: "bad"}

    assert {:stop, :normal, ^state} =
             Shell.handle_info({:DOWN, 42, :process, self(), {:signal, :sigterm, false}}, state)

    assert_receive {:task_result,
                    %{
                      status: :error,
                      message: "command killed by signal sigterm",
                      exit_code: :sigterm,
                      stdout: "boom",
                      stderr: "bad",
                      coredump: false
                    }, 123, :error}
  end

  test "uses dag default command when task params omit command", %{owner_pid: owner_pid} do
    flush_mailbox()
    task = %Task{id: 999, run_id: 456, attempt: 2, name: "fallback_cmd", params: %{}}
    dag_def = %{command: "printf 'dag-default'"}
    state = %{task: task, dag_def: dag_def, owner_pid: owner_pid, os_pid: nil, stdout: [], stderr: []}

    assert {:noreply, %{task: ^task, os_pid: pid}} = Shell.handle_info(:run, state)
    assert is_integer(pid)
  end

  test "stringifies non-binary command values before execution", %{owner_pid: owner_pid} do
    flush_mailbox()
    task = %Task{id: 111, run_id: 456, attempt: 3, name: "coerced_cmd", params: %{command: :echo}}
    dag_def = %Definition{name: "demo", adapter: :shell}
    state = %{task: task, dag_def: dag_def, owner_pid: owner_pid, os_pid: nil, stdout: [], stderr: []}

    assert {:noreply, %{task: ^task, os_pid: pid}} = Shell.handle_info(:run, state)
    assert is_integer(pid)
  end

  test "raises when no command is configured for the task or dag", %{owner_pid: owner_pid} do
    flush_mailbox()
    task = %Task{id: 321, run_id: 456, attempt: 4, name: "missing_cmd", params: %{}}
    state = %{task: task, dag_def: %{}, owner_pid: owner_pid, os_pid: nil, stdout: [], stderr: []}

    assert_raise RuntimeError, "shell task requires a command in task.params['command']", fn ->
      Shell.handle_info(:run, state)
    end
  end

  defp flush_mailbox do
    receive do
      _ -> flush_mailbox()
    after
      0 -> :ok
    end
  end
end
