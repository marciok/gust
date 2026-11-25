defmodule Gust.Run.Claimer do
  @moduledoc """
  Claims runnable DAG runs and starts their execution.

  Dispatch transports notify this process when work may be available. The
  claimer then drains a bounded batch from the durable run queue.

  DAGs with `runs: [concurrency: :sequential]` are read from the loaded
  definitions on every claim cycle and passed to `Gust.Run.Claim.next_run/1`,
  which then claims their runs one at a time, oldest first. Nothing about the
  setting is stored in the database.
  """

  use GenServer
  require Logger
  alias Gust.DAG.Definition
  alias Gust.DAG.Loader
  alias Gust.DAG.Options
  alias Gust.DAG.RunnerSupervisor
  alias Gust.Flows
  alias Gust.PubSub
  alias Gust.Run.Claim
  alias Gust.Run.Dispatcher

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init(init_arg) do
    :ok = Dispatcher.setup()
    send(self(), :claim_runs)
    {:ok, init_arg}
  end

  @impl true
  def handle_info(:claim_runs, state) do
    batch_size = batch_size()
    claimed = claim_runs(batch_size)

    if claimed == batch_size do
      send(self(), :claim_runs)
    end

    {:noreply, state}
  end

  defp claim_runs(batch_size) do
    Logger.info("Claiming runs at #{Node.self()}")
    sequential_dag_ids = sequential_dag_ids()

    claimed =
      Enum.reduce_while(1..batch_size, 0, fn _batch_num, acc ->
        run = Claim.next_run(sequential_dag_ids)

        if run do
          maybe_start(run)
          {:cont, acc + 1}
        else
          {:halt, acc}
        end
      end)

    Logger.warning("Runs claimed: #{claimed}")
    Logger.warning("Node list: #{inspect(Node.list())}")

    PubSub.broadcast_runs_claimed(Node.self())
    claimed
  end

  defp batch_size, do: Application.get_env(:gust, :claim_runs_batch_size, 50)

  defp sequential_dag_ids do
    for {dag_id, {:ok, dag_def}} <- Loader.get_definitions(),
        Options.concurrency(dag_def) == :sequential do
      dag_id
    end
  end

  defp maybe_start(run) do
    with {:ok, dag_def} <- Loader.get_definition(run.dag_id),
         true <- Definition.empty_errors?(dag_def) do
      {:ok, _pid} = RunnerSupervisor.start_child(run, dag_def)
    else
      false ->
        dag = Flows.get_dag!(run.dag_id)
        Logger.error("Not starting DAG: #{dag.name} because contains errors")
    end
  end
end
