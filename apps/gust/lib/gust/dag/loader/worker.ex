defmodule Gust.DAG.Loader.Worker do
  @behaviour Gust.DAG.Loader
  @moduledoc false
  alias Gust.DAG.Source.Config
  alias Gust.Flows
  alias Gust.PubSub
  use GenServer
  require Logger

  @impl true
  def init(args) do
    {:ok, normalize_state(args), {:continue, :bootstrap}}
  end

  def child_spec(arg) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [arg]},
      restart: :transient,
      type: :worker
    }
  end

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  defp normalize_state(args) when is_map(args), do: Map.put_new(args, :dag_defs, %{})
  defp normalize_state(args) when is_list(args), do: args |> Map.new() |> normalize_state()
  defp normalize_state(_args), do: %{dag_defs: %{}}

  @impl true
  def get_definitions do
    GenServer.call(__MODULE__, :get_definitions)
  end

  @impl true
  def get_definition(dag_id) do
    GenServer.call(__MODULE__, {:get_definition, dag_id})
  end

  @impl true
  def handle_info(
        {dag_name, {:error, _error} = parse_result, "removed"},
        %{dag_defs: dag_defs} = state
      ) do
    dag = Flows.get_dag_by_name(dag_name)
    removed_dag = Flows.delete_dag!(dag)
    dag_defs = Map.delete(dag_defs, removed_dag.id)

    state |> apply_dag_def_update(dag.name, parse_result, dag_defs, "removed")
  end

  @impl true
  def handle_info(
        {dag_name, {:error, _error} = parse_result, "reload"},
        %{dag_defs: dag_defs} = state
      ) do
    case Flows.get_dag_by_name(dag_name) do
      %Flows.Dag{id: id, name: name} ->
        dag_defs = Map.put(dag_defs, id, parse_result)
        state |> apply_dag_def_update(name, parse_result, dag_defs, "reload")

      nil ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(
        {dag_name, {:ok, _dag_def} = parse_result, "reload"},
        %{dag_defs: dag_defs} = state
      ) do
    dag = get_or_create_dag(dag_name)
    dag_defs = Map.put(dag_defs, dag.id, parse_result)

    state |> apply_dag_def_update(dag_name, parse_result, dag_defs, "reload")
  end

  @impl true
  def handle_call(:get_definitions, _from, state) do
    {:reply, state[:dag_defs], state}
  end

  @impl true
  def handle_call({:get_definition, dag_id}, _from, state) do
    {:reply, state[:dag_defs][dag_id], state}
  end

  @impl true
  def handle_continue(:bootstrap, state) do
    dag_defs = load_dags_from_sources()
    Flows.delete_not_found_ids(Map.keys(dag_defs))

    {:noreply, state |> put_dag_defs(dag_defs)}
  end

  defp apply_dag_def_update(state, name, parse_result, dag_defs, action) do
    state = state |> put_dag_defs(dag_defs)
    PubSub.broadcast_file_update(name, parse_result, action)
    {:noreply, state}
  end

  defp put_dag_defs(state, dag_defs) do
    Map.put(state, :dag_defs, dag_defs)
  end

  defp load_dags_from_sources do
    Gust.DAG.Source.configs()
    |> Enum.reduce(%{}, &load_source_dag_defs/2)
  end

  defp load_source_dag_defs(config, dag_defs_acc) do
    source_module = Config.source_module(config)

    case source_module.load() do
      %{success: success, error: error} ->
        Map.merge(dag_defs_acc, build_source_dag_defs(success, error))

      {:error, reason} ->
        Logger.error("Failed to load DAGs from source '#{source_module}': #{inspect(reason)}")
        dag_defs_acc
    end
  end

  defp build_source_dag_defs(success, error) do
    (wrap_success(success) ++ wrap_errors(error))
    |> Enum.map(fn {name, parser_result} ->
      dag = get_or_create_dag(name)
      {dag.id, parser_result}
    end)
    |> Map.new()
  end

  defp wrap_success(entries), do: Enum.map(entries, fn {name, value} -> {name, {:ok, value}} end)

  defp wrap_errors(entries),
    do: Enum.map(entries, fn {name, reason} -> {name, {:error, reason}} end)

  def get_or_create_dag(name) do
    case Flows.get_dag_by_name(name) do
      %Flows.Dag{} = dag ->
        Logger.info("FOUND DAG: #{name}")
        dag

      nil ->
        {:ok, dag} = Flows.create_dag(%{name: name})
        Logger.info("CREATED DAG: #{name}")
        dag
    end
  end
end
