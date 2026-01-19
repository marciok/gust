defmodule Gust.Run.Terminator do
  use GenServer
  # import Ecto.Query, warn: false
  alias Gust.Registry, as: GustReg

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init(init_arg) do
    # PubSub.subscribe_runs_pool()
    {:ok, init_arg}
  end

  @impl true
  def handle_cast({:terminate, task, status}, state) do
    stage_pid = lookup("stage_run_#{task.run_id}")
    task_pid = lookup("task_#{task.id}")

    IO.inspect("KILLING TASK!!")
    true = Process.exit(task_pid, :kill)

    send(stage_pid, {:task_result, nil, task.id, status})

    {:noreply, state}
  end

  defp lookup(key) do
    [{pid, _val}] = Registry.lookup(GustReg, key)
    pid
  end

  # @impl true
  # def handle_info(:loop_runs_pool, state) do
  #   tick = 5_000
  #
  #   now = DateTime.utc_now()
  #   node_str = to_string(node())
  #
  #   tasks =
  #     Gust.Repo.all(
  #       from t in Gust.Flows.Task,
  #         join: r in Gust.Flows.Run,
  #         on: r.id == t.run_id,
  #         where:
  #           r.claimed_by == ^node_str and
  #           r.claim_expires_at > ^now and
  #           r.status == :running and
  #           t.status == :running # OR Retrying (cancel timer)
  #     )
  #
  #   IO.inspect("Runss that are running and can be cacelled")
  #   IO.inspect(tasks)
  #
  #   Process.send_after(self(), :loop_runs_pool, tick)
  #
  #   {:noreply, state}
  # end
end
