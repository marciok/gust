defmodule Gust.DAG.Parser.Adapter do
  @moduledoc false

  @callback parse_file(term()) :: {:ok | :error, term()}
  @callback extension() :: term()
end
