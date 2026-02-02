defmodule Gust.DAG.Parser.File do
  @moduledoc false

  @behaviour Gust.DAG.Parser

  @impl true
  def parse_folder(folder) do
    Enum.map(Gust.DAG.Adapter.parser_modules(), fn adapter ->
      adapter.list_files(folder)
      |> Enum.map(&"#{Path.absname(folder)}/#{&1}")
      |> Enum.map(fn path ->
        name = Path.basename(path, adapter.extension())
        {name, parse(adapter, path)}
      end)
    end)
    |> List.flatten()
  end

  @impl true
  def parse(adapter, file_path) do
    if File.exists?(file_path) do
      adapter.parse_file(file_path)
    else
      {:error, :enoent}
    end
  end
end
