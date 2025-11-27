defmodule Gust.DAG.Parser do
  @moduledoc false

  @callback parse(file_path :: String.t()) ::
              {:ok, module()} | {:error, term()}

  @callback parse_folder(folder :: String.t()) ::
              [{String.t(), {:ok, module()} | {:error, term()}}]

  @callback maybe_ex_file(path :: String.t()) :: String.t() | nil

  def parse(file_path), do: impl().parse(file_path)
  def parse_folder(folder), do: impl().parse_folder(folder)
  def maybe_ex_file(path), do: impl().maybe_ex_file(path)

  defp impl, do: Application.get_env(:gust, :dag_parser, Gust.DAG.Parser.File)
end
