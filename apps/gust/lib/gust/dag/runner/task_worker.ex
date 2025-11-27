defmodule Gust.DAG.Runner.TaskWorker do
  @moduledoc false
  use GenServer
  alias Gust.DAG

  @impl true
  def init(init_arg) do
    {:ok, init_arg, {:continue, :init_run}}
  end

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: via_tuple("task_#{args[:task].id}"))
  end

  defp via_tuple(name) do
    {:via, Registry, {Gust.Registry, name}}
  end

  def child_spec(args) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [args]},
      restart: :temporary,
      type: :worker
    }
  end

  @impl true
  def handle_continue(:init_run, state) do
    send(self(), :run)

    {:noreply, state}
  end

  @impl true
  def handle_info(
        :run,
        %{task: task, mod: mod, stage_pid: stage_pid} = state
      ) do
    fun_name = String.to_atom(task.name)
    args = [%{run_id: task.run_id}]

    DAG.Logger.set_task(task.id, task.attempt)

    {status, result} =
      case try_run(mod, fun_name, args) do
        {:ok, result} ->
          {:ok, result}

        {:error, error} ->
          {:error, error}
      end

    DAG.Logger.unset()

    send(stage_pid, {:task_result, result, task.id, status})

    {:stop, :normal, state}
  end

  defp try_run(mod, fun_name, args) do
    {:ok, apply(mod, fun_name, args)}
  rescue
    e -> {:error, e}
  end
end
