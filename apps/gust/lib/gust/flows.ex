defmodule Gust.Flows do
  @moduledoc """
  The Flows context.

  This module serves as the boundary for accessing and manipulating
  Flow-related data, such as DAGs, Runs, Tasks, and Secrets.
  """

  alias Gust.Flows.{Dag, Log, Run, Secret, Task}
  import Ecto.Query, warn: false
  alias Gust.Repo

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking secret changes.

  ## Examples

      iex> change_secret(secret)
      %Ecto.Changeset{data: %Secret{}}

  """
  def change_secret(%Secret{} = secret, attrs \\ %{}) do
    Secret.changeset(secret, attrs)
  end

  @doc """
  Creates a secret.

  ## Examples

      iex> create_secret(%{field: value})
      {:ok, %Secret{}}

      iex> create_secret(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_secret(attrs \\ %{}) do
    %Secret{}
    |> Secret.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates a DAG.

  ## Examples

      iex> create_dag(%{field: value})
      {:ok, %Dag{}}

      iex> create_dag(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_dag(attrs \\ %{}) do
    %Dag{}
    |> Dag.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates a run.

  ## Examples

      iex> create_run(%{field: value})
      {:ok, %Run{}}

      iex> create_run(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_run(attrs \\ %{}) do
    %Run{}
    |> Run.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates a test run.
  """
  def create_test_run(attrs \\ %{}) do
    %Run{}
    |> Run.test_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets a single run.

  Raises `Ecto.NoResultsError` if the Run does not exist.

  ## Examples

      iex> get_run!(123)
      %Run{}

      iex> get_run!(456)
      ** (Ecto.NoResultsError)

  """
  def get_run!(id), do: Repo.get!(Run, id)

  @doc """
  Gets a single run with its tasks preloaded.
  """
  def get_run_with_tasks!(id) do
    get_run!(id) |> Repo.preload(:tasks)
  end

  @doc """
  Gets runs for a list of DAG IDs with the given statuses.

  ## Parameters

    - `dag_ids`: List of DAG IDs to filter runs by.
    - `statuses`: List of statuses (atoms) to filter runs by (e.g., [:running, :queued]).

  ## Examples

      iex> get_running_runs_by_dag([1, 2, 3], [:running, :retrying])
      [%Run{}, ...]
  """
  def get_running_runs_by_dag(dag_ids, statuses) do
    Repo.all(
      from r in Run,
        where: r.dag_id in ^dag_ids and r.status in ^statuses
    )
  end

  @doc """
  Gets a single log.

  Raises `Ecto.NoResultsError` if the Log does not exist.
  """
  def get_log!(id), do: Repo.get!(Log, id)

  @doc """
  Creates a log.
  """
  def create_log(attrs \\ %{}) do
    %Log{}
    |> Log.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets a single task.

  Raises `Ecto.NoResultsError` if the Task does not exist.
  """
  def get_task!(id), do: Repo.get!(Task, id)

  @doc """
  Gets a single secret.

  Raises `Ecto.NoResultsError` if the Secret does not exist.
  """
  def get_secret!(id), do: Repo.get!(Secret, id)

  @doc """
  Gets a single secret by name.
  """
  def get_secret_by_name(name), do: Repo.get_by(Secret, name: name)

  @doc """
  Creates a task.
  """
  def create_task(attrs \\ %{}) do
    %Task{}
    |> Task.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates a test task.
  """
  def create_test_task(attrs \\ %{}) do
    %Task{}
    |> Task.test_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a secret.
  """
  def update_secret(%Secret{} = secret, attrs) do
    secret
    |> Secret.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Updates a task result.
  """
  def update_task_result(task, result) do
    Task.changeset(task, %{result: result})
    |> Repo.update()
  end

  @doc """
  Updates a task attempt count.
  """
  def update_task_attempt(task, attempt) do
    Task.changeset(task, %{attempt: attempt})
    |> Repo.update()
  end

  @doc """
  Updates a task error.
  """
  def update_task_error(task, error) do
    Task.changeset(task, %{error: error})
    |> Repo.update()
  end

  @doc """
  Updates a task result and error.
  """
  def update_task_result_error(task, result, error) do
    Task.changeset(task, %{error: error, result: result})
    |> Repo.update()
  end

  @doc """
  Updates a task status.
  """
  def update_task_status(task, status) do
    Task.changeset(task, %{status: status})
    |> Repo.update()
  end

  @doc """
  Gets a task with its logs preloaded.
  """
  def get_task_with_logs!(id) do
    Task |> Repo.get!(id) |> Repo.preload(:logs)
  end

  @doc """
  Gets a task by name and run ID, with logs preloaded.

  Accepts an optional `log_level` argument:

    * When `log_level` is `nil` (the default), all logs for the task are preloaded.
    * When `log_level` is provided, only logs with the matching level are preloaded.

  Logs are ordered by their `inserted_at` timestamp in ascending order.
  """
  def get_task_by_name_run_with_logs(name, run_id, log_level \\ nil) do
    base = from l in Log, order_by: [asc: l.inserted_at]

    dynamic_filter =
      if log_level,
        do: dynamic([l], l.level == ^log_level),
        else: true

    log_query = where(base, ^dynamic_filter)

    get_task_by_name_run(name, run_id)
    |> Repo.preload(logs: log_query)
  end

  @doc """
  Gets a task by name and run ID.
  """
  def get_task_by_name_run(name, run_id) do
    Task |> where(run_id: ^run_id, name: ^name) |> Repo.one()
  end

  @doc """
  Updates a run status.
  """
  def update_run_status(run, status) do
    Run.changeset(run, %{status: status})
    |> Repo.update()
  end

  @doc """
  Toggles the enabled status of a DAG.
  """
  def toggle_enabled(dag) do
    Dag.changeset(dag, %{enabled: !dag.enabled})
    |> Repo.update()
  end

  @doc """
  Gets a single DAG.

  Raises `Ecto.NoResultsError` if the Dag does not exist.
  """
  def get_dag!(id), do: Repo.get!(Dag, id)

  @doc """
  Gets a DAG with its runs preloaded.
  """
  def get_dag_with_runs!(id) do
    Dag |> Repo.get!(id) |> Repo.preload(:runs)
  end

  @doc """
  Gets a DAG with its runs and tasks preloaded, with pagination for runs.
  """
  def get_dag_with_runs_and_tasks!(name, limit: limit, offset: offset) do
    runs_q =
      from r in Run,
        order_by: [desc: r.inserted_at],
        limit: ^limit,
        offset: ^offset,
        preload: [:tasks]

    Repo.one!(
      from d in Dag,
        where: d.name == ^name,
        preload: [runs: ^runs_q]
    )
  end

  def get_dag_by_name_with_runs!(name, limit: limit, offset: offset) do
    runs_q =
      from r in Run,
        order_by: [desc: r.inserted_at],
        limit: ^limit,
        offset: ^offset

    Repo.one!(
      from d in Dag,
        where: d.name == ^name,
        preload: [runs: ^runs_q]
    )
  end

  @doc """
  Count all runs with given dag_id.
  """
  def count_runs_on_dag(dag_id) do
    Repo.aggregate(from(r in Run, where: r.dag_id == ^dag_id), :count)
  end

  @doc """
  Lists all secrets.
  """
  def list_secrets do
    Repo.all(Secret)
  end

  @doc """
  Lists all DAGs.
  """
  def list_dags do
    Repo.all(Dag)
  end

  @doc """
  Gets a DAG by name.
  """
  def get_dag_by_name(name) do
    Repo.get_by(Dag, name: name)
  end

  @doc """
  Deletes all DAGs whose IDs are not in the provided list.
  """
  def delete_not_found_ids([]), do: {:ok, 0}

  def delete_not_found_ids(ids) do
    from(d in Dag, where: d.id not in ^ids)
    |> Repo.delete_all()
  end

  @doc """
  Deletes a DAG.
  """
  def delete_dag!(dag) do
    Repo.delete!(dag)
  end

  @doc """
  Deletes a secret.
  """
  def delete_secret(%Secret{} = secret) do
    Repo.delete(secret)
  end

  @doc """
  Deletes a run.
  """
  def delete_run(%Run{} = run) do
    Repo.delete(run)
  end
end
