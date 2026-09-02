defmodule Gust.DAG.Run.ErrorReporter.ExternalReference do
  @moduledoc false

  @spec valid?(term()) :: boolean()
  def valid?(url) when is_binary(url) do
    case URI.new(url) do
      {:ok, %URI{scheme: scheme, host: host}}
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        true

      _other ->
        false
    end
  end

  def valid?(_url), do: false
end
