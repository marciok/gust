defmodule Gust.Run.Pooler do
  use GenServer
  require Logger
  alias Gust.PubSub
  alias Gust.DAG.{Loader, RunnerSupervisor, Definition}
  alias Gust.Flows

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
        case Flows.claim_run() do
          {:ok, nil} ->
            {:halt, acc}

          {:ok, %Flows.Run{} = run} ->
            with {:ok, dag_def} <- Loader.get_definition(run.dag_id),
                 true <- Definition.empty_errors?(dag_def) do
              {:ok, _pid} = RunnerSupervisor.start_child(run, dag_def)
            else
              false ->
                dag = Flows.get_dag!(run.dag_id)
                Logger.error("Not starting DAG: #{dag.name} becasuse contains errors")
            end

            {:cont, acc + 1}
        end
      end)

    Logger.warning("Runs claimed: #{claimed}")

    PubSub.broadcast_runs_claimed(Node.self())
  end
end
