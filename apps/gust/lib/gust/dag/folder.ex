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

  def dag_name(path) do
    path
    |> Path.basename()
    |> Path.rootname()
  end

  def action(path) do
    if File.exists?(path), do: "reload", else: "removed"
  end
end
