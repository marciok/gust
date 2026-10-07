defmodule Gust.DAG.Source.Database do
  @moduledoc """
  DAG source that loads definitions from the database.

  Stores DAG definitions in a `gust_dag_sources` table, enabling UI-driven
  DAG creation and management. Changes are detected via polling.

  DAGs are only loaded if they are:
    - `enabled = true`
    - `start_time` is NULL or in the past (or current time >= start_time)
    - `end_time` is NULL or in the future (or current time <= end_time)

  Configuration:
    - `:notify` — `:poll` (default) or `:listen`
    - `:poll_seconds` — Polling interval in seconds (default: 30)

  When `:notify` is set to `:listen`, the source listens on the PostgreSQL
  channel `gust-dag-source-changes` and reloads when a change notification is
  received. Use `:poll` for the simpler polling-based monitor.
  """

  @behaviour Gust.DAG.Source

  import Ecto.Query

  alias Gust.DAG.Adapter
  alias Gust.DAG.Parser
  alias Gust.DAG.Source.Database.Notify
  alias Gust.DAG.Source.Polling
  alias Gust.DagSource
  alias Gust.Repo

  @name __MODULE__ |> Module.split() |> List.last()

  @impl true
  # This avoids compiler warnings about non-exported load/0
  def load, do: load(DateTime.utc_now())

  @impl true
  def load(effective_time) do
    load_from_database(effective_time)
  end

  @impl true
  def monitor(loader_pid, config \\ nil) do
    config =
      Gust.DAG.Source.config()
      |> Map.new()
      |> Map.merge(if(is_list(config), do: Map.new(config), else: config || %{}))

    case notify_mode(config) do
      :poll ->
        poll_interval_ms = poll_seconds(config) * 1_000
        Polling.start_link(loader_pid, &load/0, poll_interval_ms)

      :listen ->
        # FUTURE IMPROVEMENT: Calculate the interval until the next DAG time-
        # window boundary (`start_time`/`end_time`) and schedule reconciliation
        # for that exact moment instead of using a frequent fixed poll interval.
        poll_interval_ms = max(poll_seconds(config), 1) * 1_000
        Notify.start_link(loader_pid, &load/0, poll_interval_ms)
    end
  end

  @impl true
  def name, do: @name

  @doc false
  def notify_mode(config \\ nil) do
    config = config || Gust.DAG.Source.config()
    mode = get_config_value(config, :notify, :poll)

    case mode do
      :poll ->
        :poll

      :listen ->
        :listen

      other ->
        raise ArgumentError,
              "Invalid database DAG source notify mode: #{inspect(other)}. Expected :poll or :listen."
    end
  end

  defp load_from_database(effective_time) do
    effective_time = effective_time || DateTime.utc_now()

    query =
      from(dag in DagSource,
        where: dag.enabled == true,
        where: is_nil(dag.start_time) or dag.start_time <= ^effective_time,
        where: is_nil(dag.end_time) or dag.end_time >= ^effective_time,
        select: %{
          id: dag.id,
          name: dag.name,
          content: dag.content,
          format: dag.format,
          version: dag.version,
          enabled: dag.enabled,
          description: dag.description,
          inserted_at: dag.inserted_at,
          updated_at: dag.updated_at
        },
        order_by: dag.name
      )

    try do
      dag_sources = Repo.all(query)

      {success, error} =
        dag_sources
        |> Enum.map(&parse_dag_source/1)
        |> Enum.reduce({[], []}, fn
          {name, {:ok, value}}, {success, error} -> {[{name, value} | success], error}
          {name, {:error, reason}}, {success, error} -> {success, [{name, reason} | error]}
        end)

      %{success: success |> Enum.reverse(), error: error |> Enum.reverse()}
    rescue
      e -> {:error, inspect(e)}
    end
  end

  defp parse_dag_source(%{} = dag_source) do
    name = dag_source[:name] || dag_source["name"]
    content = dag_source[:content] || dag_source["content"]
    format = dag_source[:format] || dag_source["format"]

    case parse_dag_content(content, format) do
      {:ok, definition} -> {name, {:ok, %{definition | name: name, source: content}}}
      error -> {name, error}
    end
  end

  defp parse_dag_content(content, format) do
    format = to_string(format)

    # Create a temporary file for the DAG content
    temp_dir = System.tmp_dir!()
    timestamp = System.monotonic_time(:microsecond)
    temp_file = Path.join(temp_dir, "gust_dag_#{timestamp}.tmp")

    try do
      File.write!(temp_file, content)

      parser_module =
        case format do
          "elixir" -> find_parser_for_extension(".ex")
          "yaml" -> find_parser_for_extension(".yaml")
          ext -> find_parser_for_extension(".#{ext}")
        end

      if parser_module do
        result = Parser.parse(parser_module, temp_file)
        result
      else
        {:error, "No parser found for format: #{format}"}
      end
    rescue
      e ->
        {:error, e}
    after
      File.rm(temp_file)
    end
  end

  defp find_parser_for_extension(extension) do
    Adapter.parser_for_extension(extension)
  end

  defp poll_seconds(config) do
    get_config_value(config, :poll_seconds, 30)
  end

  defp get_config_value(config, key, default) when is_map(config) do
    Map.get(config, key, default)
  end

  defp get_config_value(config, key, default) when is_list(config) do
    Keyword.get(config, key, default)
  end

  defp get_config_value(_config, _key, default), do: default
end
