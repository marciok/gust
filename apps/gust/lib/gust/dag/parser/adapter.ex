defmodule Gust.DAG.Parser.Adapter do
  @moduledoc false

  @callback parse_file(String.t()) :: {:ok, Gust.DAG.Definition.t()} | {:error, term()}
  @callback extension() :: String.t()
end
