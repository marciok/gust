defmodule Gust.DAG.Runner.RunGateway.Default do
  @moduledoc false

  @behaviour Gust.DAG.Runner.RunGateway

  alias Gust.Flows.Run

  @impl true
  def call(%Run{id: run_id} = run, command) do
    with {:ok, target_node} <- target_node(run) do
      target_node
      |> route(run_id, command)
      |> protect_active_lease(run)
    end
  catch
    kind, _reason when kind in [:exit, :error] -> {:error, :run_owner_unavailable}
  end

  @doc false
  def local_call(run_id, command) do
    case Registry.lookup(Gust.Registry, registry_key(run_id)) do
      [{pid, _value}] when command == :stop -> safe_stop(pid)
      [{pid, _value}] -> safe_call(pid, command)
      [] -> {:error, :run_not_active}
    end
  end

  defp route(target_node, run_id, command) when target_node == node() do
    local_call(run_id, command)
  end

  defp route(target_node, run_id, command) do
    :erpc.call(target_node, __MODULE__, :local_call, [run_id, command])
  end

  defp target_node(%Run{claimed_by: nil}), do: {:ok, Node.self()}

  defp target_node(%Run{claimed_by: claimed_by} = run) do
    case Enum.find([Node.self() | Node.list()], &(to_string(&1) == claimed_by)) do
      nil ->
        if active_lease?(run),
          do: {:error, :run_owner_unavailable},
          else: {:error, :run_not_active}

      target_node ->
        {:ok, target_node}
    end
  end

  defp safe_call(pid, command) do
    call_safely(fn -> GenServer.call(pid, command, call_timeout()) end)
  end

  defp safe_stop(pid) do
    monitor = Process.monitor(pid)

    try do
      call_safely(fn -> stop_and_wait(pid, monitor) end)
    after
      Process.demonitor(monitor, [:flush])
    end
  end

  defp stop_and_wait(pid, monitor) do
    case GenServer.call(pid, :stop, call_timeout()) do
      {:ok, _value} = result ->
        receive do
          {:DOWN, ^monitor, :process, ^pid, _reason} -> result
        after
          call_timeout() -> {:error, :run_command_timeout}
        end

      {:error, _reason} = error ->
        error
    end
  end

  defp call_safely(callback) do
    callback.()
  catch
    :exit, {:normal, _call} -> {:error, :run_not_active}
    :exit, {:shutdown, _call} -> {:error, :run_not_active}
    :exit, {{:shutdown, _reason}, _call} -> {:error, :run_not_active}
    :exit, {:timeout, _call} -> {:error, :run_command_timeout}
    :exit, _reason -> {:error, :run_command_failed}
  end

  defp protect_active_lease({:error, :run_not_active}, %Run{} = run) do
    if active_lease?(run) do
      {:error, :run_owner_unavailable}
    else
      {:error, :run_not_active}
    end
  end

  defp protect_active_lease(result, _run), do: result

  defp active_lease?(%Run{status: status, claim_expires_at: expires_at})
       when status in [:starting, :running] and not is_nil(expires_at) do
    DateTime.after?(expires_at, DateTime.utc_now())
  end

  defp active_lease?(_run), do: false

  defp call_timeout, do: Application.get_env(:gust, :run_command_timeout, 5_000)

  defp registry_key(run_id), do: "dag_run_#{run_id}"
end
