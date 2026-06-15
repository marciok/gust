defmodule Gust.DAG.Parser.File do
  @moduledoc false

  @behaviour Gust.DAG.Parser
  alias Gust.DAG.{Adapter, Folder}

  @impl true
  def parse_folder(folder) do
    Enum.map(Adapter.parser_modules(), fn adapter ->
      ext = adapter.extension()

      Folder.list_files(folder, ext)
      |> Enum.map(&Folder.absolute_path(folder, &1))
      |> Enum.map(fn path ->
        name = Folder.dag_name(path)
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
