defmodule Gust.DAG.Source.Folder do
  @moduledoc """
  DAG source that loads definitions from a local folder.

  Configuration:
    - `:folder` — Path to folder containing DAG files (default: Application.get_env(:gust, :dags_folder))
  """

  @behaviour Gust.DAG.Source

  @name __MODULE__ |> Module.split() |> List.last()

  alias Gust.DAG.Folder
  alias Gust.DAG.Source.Config

  @impl true
  def load, do: load(nil)

  @impl true
  def load(_effective_time) do
    folder = get_folder()

    case Folder.verify(Gust.env(), folder) do
      :ok ->
        folder
        |> Gust.DAG.Parser.File.load_from_path()
        |> Enum.map(&parse_folder_file/1)
        |> Enum.reject(&is_nil/1)
        |> split_results()

      {:error, e} ->
        {:error, e}
    end
  end

  defp parse_folder_file(filename) do
    parser_module = Gust.DAG.Parser.File.adapter_for_extension(Path.extname(filename))
    build_folder_result(parser_module, filename)
  end

  defp build_folder_result(nil, _filename), do: nil

  defp build_folder_result(parser_module, filename) do
    dag_name = Gust.DAG.Folder.dag_name(filename)
    {dag_name, Gust.DAG.Parser.File.parse(parser_module, filename)}
  end

  defp split_results(dags) do
    {success, error} =
      Enum.reduce(dags, {[], []}, &collect_result/2)

    %{success: Enum.reverse(success), error: Enum.reverse(error)}
  end

  defp collect_result({name, {:ok, value}}, {success, error}) do
    {[{name, value} | success], error}
  end

  defp collect_result({name, {:error, reason}}, {success, error}) do
    {success, [{name, reason} | error]}
  end

  @impl true
  def monitor(loader_pid, config) do
    case folder(config) || get_folder() do
      nil ->
        {:error, "Folder DAG source requires :folder or :dags_folder to be configured"}

      folder ->
        case Folder.verify(Gust.env(), folder) do
          :ok ->
            {:ok, watcher_pid} = Gust.FileMonitor.start_link(dirs: [folder])
            Gust.FileMonitor.watch(watcher_pid)

            __MODULE__.Monitor.start_link(watcher_pid, loader_pid, folder)

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @impl true
  def name, do: @name

  @impl true
  def validate(env, config), do: Folder.verify(env, folder(config))

  @doc """
  Resolves the folder for a source config: the source `:folder` option first,
  then the legacy `:dags_folder` application env.
  """
  def folder(config) when is_list(config), do: folder(Map.new(config))

  def folder(config) when is_map(config) do
    Map.get(config, :folder) || Application.get_env(:gust, :dags_folder)
  end

  def folder(_config), do: Application.get_env(:gust, :dags_folder)

  defp get_folder do
    Gust.DAG.Source.configs()
    |> Enum.find(&(Config.source_module(&1) == __MODULE__))
    |> folder()
  end
end
