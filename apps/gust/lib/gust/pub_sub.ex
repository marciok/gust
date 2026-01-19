defmodule Gust.PubSub do
  @moduledoc false

  # Topic bases
  @topic_run "dag:run"
  @topic_task "dag:task"
  @topic_file "dag:file"
  @runs_pool "runs_pool"
  @runs_claimed "runs_claimed"

  # Event atoms
  @event_run_started :run_started
  @event_run_status :run_status
  @event_file_update :file_updated
  @dispatch_run :dispatch_run

  ## Broadcasts
  #

  def broadcast_runs_claimed(node) do
    Phoenix.PubSub.broadcast(
      __MODULE__,
      @runs_claimed,
      {:runs_claimed, %{node: node}}
    )
  end

  def broadcast_run_dispatch(run_id) do
    Phoenix.PubSub.broadcast(
      __MODULE__,
      @runs_pool,
      {:run_pool, @dispatch_run, %{run_id: run_id}}
    )
  end

  def broadcast_log(task_id, log_id) do
    Phoenix.PubSub.broadcast(
      __MODULE__,
      "#{@topic_task}:#{task_id}",
      {:task, :log, %{task_id: task_id, log_id: log_id}}
    )
  end

  def broadcast_run_status(run_id, status) do
    Phoenix.PubSub.broadcast(
      __MODULE__,
      "#{@topic_run}:#{run_id}",
      {:dag, @event_run_status, %{run_id: run_id, status: status}}
    )
  end

  def broadcast_run_started(dag_id, run_id) do
    Phoenix.PubSub.broadcast(
      __MODULE__,
      "#{@topic_run}:#{dag_id}",
      {:dag, @event_run_started, %{dag_id: dag_id, run_id: run_id}}
    )
  end

  def broadcast_file_update(name, parse_result, action) do
    payload =
      {:dag, @event_file_update, %{dag_name: name, parse_result: parse_result, action: action}}

    # Broadcast to all-file topic
    Phoenix.PubSub.broadcast(__MODULE__, "#{@topic_file}:update", payload)

    # Broadcast to specific-file topic
    Phoenix.PubSub.broadcast(__MODULE__, "#{@topic_file}:#{name}", payload)
  end

  ## Subscriptions
  #
  def subscribe_runs_claimed do
    Phoenix.PubSub.subscribe(__MODULE__, @runs_claimed)
  end

  def subscribe_runs_pool do
    Phoenix.PubSub.subscribe(__MODULE__, @runs_pool)
  end

  # Subscribe to updates for *all* files
  def subscribe_all_files(action) do
    Phoenix.PubSub.subscribe(__MODULE__, "#{@topic_file}:#{action}")
  end

  # Subscribe to updates for a *specific* file
  def subscribe_file(name) do
    Phoenix.PubSub.subscribe(__MODULE__, "#{@topic_file}:#{name}")
  end

  # Subscribe to a single run’s status
  def subscribe_run(run_id) do
    Phoenix.PubSub.subscribe(__MODULE__, "#{@topic_run}:#{run_id}")
  end

  def subscribe_task(task_id) do
    Phoenix.PubSub.subscribe(__MODULE__, "#{@topic_task}:#{task_id}")
  end

  # Subscribe to all runs under a given DAG
  def subscribe_runs_for_dag(dag_id) do
    Phoenix.PubSub.subscribe(__MODULE__, "#{@topic_run}:#{dag_id}")
  end
end
