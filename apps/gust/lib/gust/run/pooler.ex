defmodule Gust.Run.Pooler do
  @moduledoc """
  Claims runnable DAG runs and starts their execution.

  The pooler subscribes to run dispatch events and also polls on a configurable
  interval to claim work in batches. Each claimed run is validated against its
  DAG definition and then started under the runner supervisor when valid.
  """

  use GenServer
  require Logger
  alias Gust.DAG.Definition
  alias Gust.DAG.Loader
  alias Gust.DAG.RunnerSupervisor
  alias Gust.Flows
  alias Gust.PubSub
  alias Gust.Run.Claim

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init(init_arg) do
    PubSub.subscribe_runs_pool()
    send(self(), :loop_runs_pool)
    {:ok, init_arg}
  end

  @impl true
  def handle_info(:loop_runs_pool, state) do
    tick = Application.get_env(:gust, :claim_runs_tick, 2_000)
    claim_runs()
    Process.send_after(self(), :loop_runs_pool, tick)

    {:noreply, state}
  end

  def handle_info({:run_pool, :dispatch_run, %{run_id: _run_id}}, state) do
    claim_runs()
    {:noreply, state}
  end

  defp claim_runs do
    batch_size = Application.get_env(:gust, :claim_runs_batch_size, 50)

    Logger.info("Claiming runs at #{Node.self()}")

    claimed =
      Enum.reduce_while(1..batch_size, 0, fn _batch_num, acc ->
        run = Claim.next_run()

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
