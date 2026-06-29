defmodule Gust.DAG.TaskWaiter.Repo do
  @moduledoc false

  @behaviour Gust.DAG.TaskWaiter

  import Ecto.Query, warn: false

  alias Gust.DAG.Run.Trigger
  alias Gust.Flows
  alias Gust.Flows.Task
  alias Gust.PubSub
  alias Gust.Repo

  @wait_payload_param "__gust_wait_payload__"

  @impl true
  def resume(waiting_for, opts) when is_list(opts) do
    wait_for = to_string(waiting_for)
    run_id = Keyword.get(opts, :run_id)
    payload = resume_payload(opts)

    Repo.transaction(fn ->
      run_id
      |> waiting_tasks_query(wait_for)
      |> Repo.all()
      |> Enum.map(&resume_task(&1, payload))
    end)
    |> case do
      {:ok, tasks} ->
        tasks
        |> Enum.map(& &1.run_id)
        |> Enum.uniq()
        |> Enum.each(&trigger_run/1)

        {:ok, tasks}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def clear_wait(%Flows.Task{waiting_for: nil, wait_satisfied_at: nil} = task), do: task

  def clear_wait(task) do
    {:ok, task} = Flows.update_task_wait_state(task, %{waiting_for: nil, wait_satisfied_at: nil})

    task
  end

  defp resume_payload(opts) do
    opts
    |> Keyword.get(:payload, %{})
    |> Map.merge(
      opts
      |> Keyword.drop([:run_id, :payload])
      |> Map.new(fn {key, value} -> {to_string(key), value} end)
    )
  end

  defp waiting_tasks_query(nil, wait_for) do
    from(task in waiting_tasks_query(wait_for))
  end

  defp waiting_tasks_query(run_id, wait_for) do
    from task in waiting_tasks_query(wait_for),
      where: task.run_id == ^run_id
  end

  defp waiting_tasks_query(wait_for) do
    from task in Task,
      where: task.status == :waiting,
      where: task.waiting_for == ^wait_for
  end

  defp resume_task(task, payload) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    params =
      task.params
      |> Map.put(@wait_payload_param, payload)

    {:ok, task} = Flows.resume_waiting_task(task, params, now)

    PubSub.broadcast_run_status(task.run_id, :created, task.id)

    task
  end

  defp trigger_run(run_id) do
    run = Flows.get_run!(run_id)
    Trigger.dispatch_run(run)
  end
end
