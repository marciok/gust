defmodule Gust.DAG.Folder do
  @moduledoc false

  def verify!(env, folder) do
    case verify(env, folder) do
      :ok -> :ok
      {:error, reason} -> raise reason
    end
  end

  def verify(env, _folder) when env in [:test, "test"], do: :ok

  def verify(_env, folder) do
    if File.dir?(folder), do: :ok, else: {:error, "DAG folder does not exist!: #{folder}"}
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
