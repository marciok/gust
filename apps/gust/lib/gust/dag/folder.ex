defmodule Gust.DAG.Folder do
  @moduledoc false

  def verify!("test", _folder), do: :ok

  def verify!(_env, folder) do
    File.dir?(folder) || raise "DAG folder does not exist!: #{folder}"
    :ok
  end

  def list_files(folder, extension) do
    folder
    |> File.ls!()
    |> Enum.filter(&(Path.extname(&1) == extension))
    |> Enum.sort()
  end

  def absolute_path(folder, filename) do
    folder
    |> Path.absname()
    |> Path.join(filename)
  end

  def dag_name(path) do
    path
    |> Path.basename()
    |> Path.rootname()
  end

  def action(path) do
    if File.exists?(path), do: "reload", else: "removed"
  end
end
