defmodule Gust.DAG.TaskWaiter do
  @moduledoc """
  Behaviour for resuming tasks that are parked on external wait events.

  This module delegates to the configured implementation module:

      config :gust, :dag_task_waiter, Gust.DAG.TaskWaiter.Repo

  The configured module must implement this behaviour.
  """

  @type task :: term()
  @type resume_opts :: keyword()

  @callback resume(term(), resume_opts()) :: {:ok, [task()]} | {:error, term()}
  @callback clear_wait(task()) :: task()

  def resume(waiting_for, opts) when is_list(opts), do: impl().resume(waiting_for, opts)
  def clear_wait(task), do: impl().clear_wait(task)

  def impl, do: Application.get_env(:gust, :dag_task_waiter, Gust.DAG.TaskWaiter.Repo)
end
