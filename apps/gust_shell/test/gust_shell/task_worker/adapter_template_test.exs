defmodule GustShell.TaskWorker.AdapterTemplateTest do
  use ExUnit.Case, async: false

  alias GustShell.TaskWorker.Adapter

  import Mox
  import GustShell.TestFixtures

  setup :verify_on_exit!

  setup do
    Gust.DAGLoggerMock
    |> stub(:set_task, fn _, _ -> :ok end)
    |> stub(:unset, fn -> :ok end)

    :ok
  end

  test "renders the command and env with the task context" do
    state =
      state("""
      tasks:
        - name: templated
          run: 'printf "%s %s $TARGET" <%= run_id %> <%= params["name"] %>'
          env:
            TARGET: '<%= params["target"] %>'
      """)

    assert {:noreply, running} = Adapter.handle_info(:run, state)
    on_exit(fn -> :exec.stop(running.os_pid) end)
    await_exit(running)

    assert_receive {:task_result, %{stdout: "42 build x86_64", exit_code: 0}, 128, :ok}
  end

  test "fails the task without running the command when rendering raises" do
    state =
      state("""
      tasks:
        - name: templated
          run: 'touch /tmp/should_not_exist_<%= raise "boom" %>'
      """)

    assert {:stop, %RuntimeError{message: message}, _} = Adapter.handle_info(:run, state)
    assert message =~ "failed to render shell task template: boom"
    assert_receive {:task_result, %RuntimeError{}, 128, :error}
    refute Map.has_key?(state, :os_pid)
  end

  defp state(yaml) do
    assert {:ok, definition} = parse_shell_dag(yaml)

    %{
      task: %{
        id: 128,
        attempt: 1,
        name: "templated",
        run_id: 42,
        params: %{"name" => "build", "target" => "x86_64"}
      },
      owner_pid: self(),
      opts: Map.fetch!(definition.tasks, "templated")
    }
  end

  defp await_exit(%{os_pid: os_pid} = state) do
    receive do
      {stream, ^os_pid, _data} = message when stream in [:stdout, :stderr] ->
        {:noreply, state} = Adapter.handle_info(message, state)
        await_exit(state)

      {:DOWN, ^os_pid, :process, _pid, _reason} = message ->
        assert {:stop, :normal, _} = Adapter.handle_info(message, state)
    after
      5_000 -> flunk("shell process did not finish")
    end
  end
end
