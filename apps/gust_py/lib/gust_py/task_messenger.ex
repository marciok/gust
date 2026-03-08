defmodule GustPy.TaskMessenger do
  @type done_message :: {:result, term()} | {:error, term()}

  @callback decode(binary()) :: {:ok, map()} | {:error, term()}
  @callback handle_next(map()) :: :noreply | {:reply, map()} | {:done, done_message()}
  @callback reply(term(), map()) :: :ok

  def decode(data), do: impl().decode(data)
  def handle_next(msg), do: impl().handle_next(msg)
  def reply(target, payload), do: impl().reply(target, payload)

  defp impl, do: Application.get_env(:gust_py, :task_messenger, GustPy.TaskMessenger.JSON)
end
