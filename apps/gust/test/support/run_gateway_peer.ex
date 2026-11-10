defmodule Gust.RunGatewayPeer do
  @moduledoc false

  def start_registry do
    {:ok, registry} = Registry.start_link(keys: :unique, name: Gust.Registry)
    Process.unlink(registry)
    {:ok, registry}
  end

  def start_worker(run_id, parent, mode) do
    worker =
      spawn(fn ->
        {:ok, _owner} = Registry.register(Gust.Registry, "dag_run_#{run_id}", nil)
        send(parent, {:remote_worker_registered, node()})

        receive do
          {:"$gen_call", from, command} -> handle_command(mode, from, command)
        end
      end)

    {:ok, worker}
  end

  def register_idle(key, parent) do
    pid =
      spawn(fn ->
        {:ok, _owner} = Registry.register(Gust.Registry, key, nil)
        send(parent, {:remote_registered, key, node()})

        receive do
          :stop -> :ok
        end
      end)

    {:ok, pid}
  end

  defp handle_command(:reply, from, command) do
    GenServer.reply(from, {:ok, {node(), command}})
  end

  defp handle_command(:halt, _from, _command), do: :erlang.halt()
end
