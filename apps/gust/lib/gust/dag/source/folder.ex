defmodule Gust.DAG.Source.Folder do
  @moduledoc """
  DAG source that loads definitions from a local folder.

  Configuration:
    - `:folder` — Path to folder containing DAG files (default: Application.get_env(:gust, :dags_folder))
  """

  @behaviour Gust.DAG.Source

  alias Gust.DAG.Adapter
  alias Gust.DAG.Folder
  alias Gust.DAG.Parser

  @env Application.compile_env(:gust, :env)

  @impl true
  def load(_effective_time \\ nil) do
    folder = get_folder()

    case Folder.verify(@env, folder) do
      :ok ->
        dags =
          Adapter.parser_modules()
          |> Enum.flat_map(&load_extension(&1, folder))

        # Partition DAGs into success and error lists, unwrapping the tuples
        {success, error} =
          Enum.reduce(dags, {[], []}, fn
            {name, {:ok, value}}, {success, error} -> {[{name, value} | success], error}
            {name, {:error, reason}}, {success, error} -> {success, [{name, reason} | error]}
          end)

        %{success: success |> Enum.reverse(), error: error |> Enum.reverse()}

      {:error, e} ->
        {:error, e}
    end
  end

  @impl true
  def monitor(loader_pid, config \\ %{}) do
    folder = get_folder_from_config(config)

    {:ok, watcher_pid} = Gust.FileMonitor.start_link(dirs: [folder], latency: 0)
    Gust.FileMonitor.watch(watcher_pid)

    __MODULE__.Monitor.start_link(watcher_pid, loader_pid, folder)
  end

  @impl true
  def name, do: "Folder"

  defp load_extension(parser_module, folder) do
    parser_module.extensions()
    |> Enum.map(&Folder.list_files(folder, &1))
    |> Enum.concat()
    |> Enum.map(fn filename ->
      path = Folder.absolute_path(folder, filename)
      dag_name = Folder.dag_name(path)
      result = Parser.parse(parser_module, path)
      {dag_name, result}
    end)
  end

  defp get_folder do
    Gust.DAG.Source.config()
    |> Keyword.get(:folder, Application.get_env(:gust, :dags_folder))
  end

  defp get_folder_from_config(config) when is_list(config) do
    Keyword.get(config, :folder, Keyword.get(config, :dags_folder, get_folder()))
  end

  defp get_folder_from_config(config) when is_map(config) do
    config
    |> Map.get(:folder, Map.get(config, :dags_folder, get_folder()))
  end

  defp get_folder_from_config(_config), do: get_folder()
end
