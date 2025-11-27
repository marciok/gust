defmodule Gust.DAG.Loader.Worker do
  @behaviour Gust.DAG.Loader
  @moduledoc false
  alias Gust.DAG.{Parser, RunRestarter, Scheduler}
  alias Gust.Flows
  alias Gust.PubSub
  use GenServer
  require Logger

  @impl true
  def init(args) do
    {:ok, args, {:continue, :bootstrap}}
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
  def handle_continue(:bootstrap, %{dags_folder: folder} = state) do
    dag_defs = load_folder(folder)
    Flows.delete_not_found_ids(Map.keys(dag_defs))

    Scheduler.schedule(dag_defs)
    RunRestarter.restart_dags(dag_defs)

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

  defp load_folder(folder) do
    Parser.parse_folder(folder)
    |> Enum.map(fn {name, parser_result} ->
      dag = get_or_create_dag(name)
      {dag.id, parser_result}
    end)
    |> Map.new()
  end

  def get_or_create_dag(name) do
    case Flows.get_dag_by_name(name) do
      %Flows.Dag{} = dag ->
        Logger.warning("FOUND DAG: #{name}")
        dag

      nil ->
        {:ok, dag} = Flows.create_dag(%{name: name})
        Logger.warning("CREATED DAG: #{name}")
        dag
    end
  end
end
