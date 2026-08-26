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
end
