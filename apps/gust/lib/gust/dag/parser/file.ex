defmodule Gust.DAG.Parser.File do
  @moduledoc false

  @behaviour Gust.DAG.Parser
  alias Gust.DAG.Adapter

  @impl true
  def parse_folder(folder) do
    Enum.map(Adapter.parser_modules(), fn adapter ->
      ext = adapter.extension()

      list_files(folder, ext)
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

  defp list_files(folder, ext) do
    folder
    |> File.ls!()
    |> Enum.filter(&maybe_dag_file(&1, ext))
  end

  def maybe_dag_file(path, ext) do
    if Path.extname(path) == ext, do: path, else: nil
  end
end
