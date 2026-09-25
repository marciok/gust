defmodule GustShell.TaskWorkerHelpers do
  @moduledoc false

  import ExUnit.Assertions

  alias GustShell.TaskWorker.Adapter

  @doc """
  Forwards shell output and exit messages to the adapter until the process finishes.
  Leaves the task result in the caller's mailbox for assertions.
  """
  def await_exit(%{os_pid: os_pid} = state) do
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
