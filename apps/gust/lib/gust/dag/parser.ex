defmodule Gust.DAG.Parser do
  @moduledoc false

  @callback parse(term(), file_path :: String.t()) ::
              {:ok, Gust.DAG.Definition.t()} | {:error, term()}

  @callback parse_folder(folder :: String.t()) ::
              [{String.t(), {:ok, Gust.DAG.Definition.t()} | {:error, term()}}]

  def parse(adapter, file_path), do: impl().parse(adapter, file_path)
  def parse_folder(folder), do: impl().parse_folder(folder)

  defp impl, do: Application.get_env(:gust, :dag_parser, Gust.DAG.Parser.File)
end
