defmodule Gust.DAG.Parser.Adapter do
  @moduledoc false

  @callback list_files(term()) :: [term()]
  @callback parse_file(term()) :: {:ok | :error, term()}
  @callback extension() :: term()
end
