defmodule Gust.DAG.Logger.Database do
  @moduledoc false
  alias Gust.Flows
  @behaviour Gust.DAG.Logger
  @behaviour :gen_event

  def init(__MODULE__) do
    {:ok, %{}}
  end

  def handle_event(:flush, state), do: {:ok, state}

  def handle_event({level, _gl, {Logger, msg, _ts, md}}, state) do
    if md[:task_id] do
      Task.start(fn -> handle_log(level, msg, md) end)
    end

    {:ok, state}
  end

  def handle_call({:configure, opts}, state) do
    {:ok, :ok, Map.merge(state, Map.new(opts))}
  end

  def set_task(task_id, attempt) do
    Logger.metadata(task_id: task_id, attempt: attempt)
  end

  def unset do
    Logger.reset_metadata()
  end

  defp handle_log(_level, "", md),
    do: create_log(:error, "nil or empty was logged!", md)

  defp handle_log(level, msg, md) when is_list(msg),
    do: create_log(level, Enum.join(msg, "; "), md)

  defp handle_log(level, msg, md) when is_binary(msg),
    do: create_log(level, msg, md)

  defp create_log(level, msg, md) do
    {:ok, log} =
      Flows.create_log(%{
        task_id: md[:task_id],
        content: msg,
        attempt: md[:attempt],
        level: to_string(level)
      })

    Gust.PubSub.broadcast_log(md[:task_id], log.id)
  end
end
