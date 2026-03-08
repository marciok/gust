defmodule GustPy.TaskMessenger.JSON do
  @behaviour GustPy.TaskMessenger

  @enforce_keys [:type]
  defstruct [:type, :msg, :op, :name, :run_id, :data, :ok, :trace]

  require Logger

  alias GustPy.TaskWorker.Error
  alias __MODULE__, as: Msg

  @impl true
  def decode(data) do
    with {:ok, payload} <- Jason.decode(data) do
      {:ok, new(payload)}
    end
  end

  @impl true
  def handle_next(%Msg{type: :log, msg: msg}) do
    Logger.info(msg)
    :noreply
  end

  def handle_next(%Msg{type: :call, op: :get_secret_by_name, name: name}) do
    {:reply, reply_with_secret(name)}
  end

  def handle_next(%Msg{
        type: :call,
        op: :get_task_by_name_run,
        name: task_name,
        run_id: run_id
      }) do
    {:reply, reply_with_task(task_name, run_id)}
  end

  def handle_next(%Msg{type: :result, ok: true, data: result}) do
    {:done, {:result, result_value(result)}}
  end

  def handle_next(%Msg{type: :error, ok: false, trace: trace}) do
    {:done, {:error, Error.new(:task_failed, trace)}}
  end

  def handle_next(%Msg{} = msg) do
    Logger.warning("Received unknown port message", msg: inspect(msg))
    :noreply
  end

  @impl true
  def reply(target, %{ok: ok} = payload) when is_boolean(ok) do
    response = payload |> Map.put_new(:type, "reply") |> Jason.encode!()
    Port.command(target, response)
    :ok
  end

  defp reply_with_secret(name) do
    case Gust.Flows.get_secret_by_name(name) do
      nil ->
        %{ok: false, error: "secret_not_found"}

      secret ->
        %{ok: true, data: serialize_secret(secret)}
    end
  end

  defp reply_with_task(task_name, run_id) do
    run = Gust.Flows.get_task_by_name_run(task_name, run_id)
    %{ok: true, data: serialize_task(run)}
  end

  defp new(%{"type" => "log", "msg" => msg}) do
    %Msg{type: :log, msg: msg}
  end

  # TODO: to_atom op
  defp new(%{"type" => "call", "op" => "get_secret_by_name", "name" => name}) do
    %Msg{type: :call, op: :get_secret_by_name, name: name}
  end

  defp new(%{
         "type" => "call",
         "op" => "get_task_by_name_run",
         "name" => name,
         "run_id" => run_id
       }) do
    %Msg{type: :call, op: :get_task_by_name_run, name: name, run_id: run_id}
  end

  defp new(%{"type" => "result"} = payload) do
    %Msg{type: :result, ok: payload["ok"], data: payload["data"]}
  end

  defp new(%{"type" => "error"} = payload) do
    %Msg{type: :error, ok: payload["ok"], trace: payload["trace"]}
  end

  defp new(payload) do
    %Msg{type: :unknown, data: payload}
  end

  defp result_value(result) when is_map(result) do
    Map.get(result, :value) || Map.get(result, "value")
  end

  defp result_value(result), do: result

  defp serialize_secret(secret) do
    %{
      id: secret.id,
      name: secret.name,
      value_type: secret.value_type,
      value: secret.value
    }
  end

  defp serialize_task(task) do
    %{id: task.id, result: task.result}
  end
end
