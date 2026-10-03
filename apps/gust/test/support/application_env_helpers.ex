defmodule Gust.ApplicationEnvHelpers do
  @moduledoc false

  def replace_env(key, value) do
    previous = Application.fetch_env(:gust, key)
    Application.put_env(:gust, key, value)

    ExUnit.Callbacks.on_exit(fn ->
      case previous do
        {:ok, previous_value} -> Application.put_env(:gust, key, previous_value)
        :error -> Application.delete_env(:gust, key)
      end
    end)
  end

  def restore_dag_source(value \\ nil) do
    case value do
      nil -> Application.delete_env(:gust, :dag_source)
      previous -> Application.put_env(:gust, :dag_source, previous)
    end
  end

  def init_dag_source(_context) do
    previous = Application.get_env(:gust, :dag_source)

    ExUnit.Callbacks.on_exit(fn ->
      restore_dag_source(previous)
    end)

    :ok
  end

  def init_idempotent_test(context) do
    init_dag_source(context)
  end
end
