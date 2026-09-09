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
  Gets the requested DAGs with their most recent runs preloaded.

  Runs are ordered from oldest to newest so they can be displayed as a
  chronological history. A lateral join limits the runs per DAG while keeping
  the operation to one database query.
  """

  def get_dags_with_recent_runs(dag_ids, limit \\ 10) when is_integer(limit) and limit > 0 do
    limit
    |> dags_with_recent_runs_query()
    |> where([dag], dag.id in ^dag_ids)
    |> Repo.all()
  end

  @doc """
  Gets a DAG by name with its most recent runs preloaded.
  """
  def get_dag_with_recent_runs(name, limit \\ 10) do
    limit
    |> dags_with_recent_runs_query()
    |> where([dag], dag.name == ^name)
    |> Repo.one()
  end

  defp dags_with_recent_runs_query(limit) do
    recent_runs =
      from run in Run,
        where: run.dag_id == parent_as(:dag).id,
        order_by: [desc: run.inserted_at, desc: run.id],
        limit: ^limit

    from dag in Dag,
      as: :dag,
      left_lateral_join: run in subquery(recent_runs),
      on: true,
      order_by: [asc: dag.id, asc: run.inserted_at, asc: run.id],
      preload: [runs: run]
  end

  @doc """
  Gets a single log.

  Raises `Ecto.NoResultsError` if the Log does not exist.
  """
  def get_log!(id), do: Repo.get!(Log, id)

  @doc """
  Gets logs for a task, optionally filtered by level.

  Logs are ordered by their insertion timestamp in ascending order.

  """
  def get_logs(task_id, level \\ nil) do
    query =
      Log
      |> where(task_id: ^task_id)
      |> order_by([log], asc: log.inserted_at)

    query =
      if level in [nil, ""] do
        query
      else
        where(query, [log], log.level == ^level)
      end

    Repo.all(query)
  end

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

  def get_task(id), do: Repo.get(Task, id)

  @doc """
  Gets task statuses for the given task IDs.
  """
  def get_task_statuses([]), do: []

  def get_task_statuses(task_ids) do
    task_ids = Enum.to_list(task_ids)

    Task
    |> where([task], task.id in ^task_ids)
    |> select([task], task.status)
    |> Repo.all()
  end

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
  Marks a task as retrying and persists when its next attempt starts.
  """
  def schedule_task_retry(%Task{} = task, retry_at) do
    task
    |> Ecto.Changeset.change(
      status: :retrying,
      retry_at: retry_at
    )
    |> Repo.update()
  end

  @doc """
  Updates a task map index and its persisted parameters.
  """
  def update_task_mapping(task, map_index, params) do
    Task.changeset(task, %{map_index: map_index, params: params})
    |> Repo.update()
  end

  @doc """
  Updates a task's persisted parameters.
  """
  def update_task_params(task, params) do
    Task.changeset(task, %{params: params})
    |> Repo.update()
  end

  @doc """
  Updates a resumed waiting task's params, wait state, and status in one write.
  """
  def resume_waiting_task(task, params, wait_satisfied_at) do
    task
    |> Task.changeset(%{
      params: params,
      waiting_for: nil,
      wait_satisfied_at: wait_satisfied_at,
      status: :created
    })
    |> Repo.update()
  end

  @doc """
  Cancels a waiting task by clearing its wait markers and marking it failed in one write.
  """
  def cancel_waiting_task(task) do
    task
    |> Task.changeset(%{
      waiting_for: nil,
      wait_satisfied_at: nil,
      status: :failed
    })
    |> Repo.update()
  end

  @doc """
  Updates a task's persisted wait state.
  """
  def update_task_wait_state(task, attrs) do
    task
    |> Task.changeset(attrs)
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
  Adds an external reporter reference to a failed task's error.

  A non-failed task is treated as stale so a delayed reporter response cannot
  overwrite the state of a task that has moved on.
  """
  def attach_task_error_reference(task_id, url) do
    case Repo.get(Task, task_id) do
      %Task{status: :failed} = task ->
        update_task_error(task, Map.put(task.error, "external_reference", url))

      %Task{} ->
        {:error, :stale_task}

      nil ->
        {:error, :stale_task}
    end
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
  Clears execution state before manually restarting a terminal task instance.

  Mapping identity and persisted params are intentionally preserved so a mapped
  task can be restarted without rebuilding or collapsing its sibling instances.
  """
  def prepare_task_restart(%Task{} = task) do
    task
    |> Task.changeset(%{
      status: :created,
      result: %{},
      error: %{},
      attempt: 1,
      waiting_for: nil,
      wait_satisfied_at: nil
    })
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
  Gets a task by name, run ID, and map index.
  """
  def get_task_by_name(name, run_id, map_index) do
    query =
      Task
      |> where(run_id: ^run_id, name: ^name)

    query =
      if is_nil(map_index) do
        where(query, [task], is_nil(task.map_index))
      else
        where(query, [task], task.map_index == ^map_index)
      end

    Repo.one(query)
  end

  @doc """
  Gets all task instances by name and run ID.
  """
  def get_tasks_by_name(name, run_id) do
    Task
    |> where(run_id: ^run_id, name: ^name)
    |> order_by([task], asc_nulls_first: task.map_index)
    |> Repo.all()
  end

  @doc """
  Gets all task statuses by name and run ID.
  """
  def get_task_statuses_by_name(name, run_id) do
    Task
    |> where(run_id: ^run_id, name: ^name)
    |> select([task], task.status)
    |> Repo.all()
  end

  @doc """
  Updates a run status.
  """
  def update_run_status(run, status) do
    Run.changeset(run, %{status: status})
    |> Repo.update()
  end

  @doc """
  Updates the status of multiple runs in one database statement.
  """
  def update_runs_status(runs, status) do
    run_ids = Enum.map(runs, & &1.id)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {_count, updated_runs} =
      Run
      |> where([run], run.id in ^run_ids)
      |> select([run], run)
      |> Repo.update_all(set: [status: status, updated_at: now])

    updated_runs_by_id = Map.new(updated_runs, &{&1.id, &1})
    Enum.map(runs, &Map.fetch!(updated_runs_by_id, &1.id))
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

  Tasks are loaded with only the fields required by the run-history grid.
  Use the task or run detail functions when payload fields are needed.

  The `:limit` option is required. Pass `:offset` for normal pagination or
  `:pinned_run_id` to load a window containing the pinned followed by older
  runs. The pinned must belong to the named DAG.
  """
  def get_dag_with_runs_and_tasks!(name, opts) do
    limit = Keyword.fetch!(opts, :limit)

    tasks_q =
      from t in Task,
        select: struct(t, [:id, :name, :status, :map_index, :run_id])

    runs_q =
      from r in Run,
        order_by: [desc: r.inserted_at, desc: r.id],
        limit: ^limit,
        preload: [tasks: ^tasks_q]

    runs_q = apply_run_window(runs_q, name, opts)

    Repo.one!(
      from d in Dag,
        where: d.name == ^name,
        preload: [runs: ^runs_q]
    )
  end

  defp apply_run_window(query, name, opts) do
    case Keyword.fetch(opts, :pinned_run_id) do
      {:ok, pinned_run_id} ->
        pinned = get_run_pinned!(name, pinned_run_id)

        where(
          query,
          [run],
          run.inserted_at < ^pinned.inserted_at or
            (run.inserted_at == ^pinned.inserted_at and run.id <= ^pinned.id)
        )

      :error ->
        offset(query, ^Keyword.fetch!(opts, :offset))
    end
  end

  defp get_run_pinned!(dag_name, run_id) do
    Repo.one!(
      from run in Run,
        join: dag in assoc(run, :dag),
        where: dag.name == ^dag_name and run.id == ^run_id,
        select: %{id: run.id, inserted_at: run.inserted_at}
    )
  end

  @doc """
  Gets a DAG by name with its runs preloaded, with pagination for runs.

  The DAG is looked up by its `name`. The associated runs are ordered by
  descending `inserted_at` and paginated using the required `:limit` and
  `:offset` keyword options.

  ## Parameters

    * `name` - The name of the DAG to retrieve.

  ## Options

    * `:limit` - Required. The maximum number of runs to preload.
    * `:offset` - Required. The number of runs to skip before starting to preload.
    * `:status` - Optional. Filters preloaded runs by status when present.
    * `:params_search` - Optional. Case-insensitively filters runs by parameter keys or values.

  ## Returns

  Returns the `%Dag{}` struct with its `:runs` association preloaded according
  to the given pagination options. Raises `Ecto.NoResultsError` if no DAG
  with the given name exists. Raises `KeyError` if `:limit` or `:offset` is
  missing from `opts`.
  """
  def get_dag_by_name_with_runs!(name, opts) do
    limit = Keyword.fetch!(opts, :limit)
    offset = Keyword.fetch!(opts, :offset)
    status = Keyword.get(opts, :status)
    params_search = Keyword.get(opts, :params_search)

    runs_q =
      from r in Run,
        order_by: [desc: r.inserted_at],
        limit: ^limit,
        offset: ^offset

    runs_q =
      runs_q
      |> maybe_filter_run_status(status)
      |> maybe_filter_run_params(params_search)

    Repo.one!(
      from d in Dag,
        where: d.name == ^name,
        preload: [runs: ^runs_q]
    )
  end

  @doc """
  Returns the number of runs associated with a given DAG.

  ## Parameters

    * `dag_id` - The identifier of the DAG whose runs should be counted.
    * `status` - Optional status to filter by.
    * `params_search` - Optional case-insensitive parameter key or value search.

  ## Returns

    * The integer count of runs associated with the specified DAG.
  """
  def count_runs_on_dag(dag_id, status \\ nil, params_search \\ nil) do
    Run
    |> where([r], r.dag_id == ^dag_id)
    |> maybe_filter_run_status(status)
    |> maybe_filter_run_params(params_search)
    |> Repo.aggregate(:count)
  end

  @doc """
  Gets runs by ID that belong to the given DAG.
  """
  def get_runs_on_dag(dag_id, run_ids) when is_list(run_ids) do
    run_ids = Enum.uniq(run_ids)

    Run
    |> where([run], run.dag_id == ^dag_id and run.id in ^run_ids)
    |> Repo.all()
  end

  defp maybe_filter_run_status(query, nil), do: query

  defp maybe_filter_run_status(query, status) do
    where(query, [r], r.status == ^status)
  end

  defp maybe_filter_run_params(query, nil), do: query

  defp maybe_filter_run_params(query, params_search) do
    case String.trim(params_search) do
      "" ->
        query

      params_search ->
        where(
          query,
          [r],
          fragment("strpos(lower(CAST(? AS text)), lower(?)) > 0", r.params, ^params_search)
        )
    end
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
  Deletes the given run from the database.

  The `run` must be a persisted `%Run{}` struct. This function delegates to
  `Repo.delete/1` and returns `{:ok, %Run{}}` if the run is successfully
  deleted, or `{:error, %Ecto.Changeset{}}` if the delete operation fails.

  ## Examples

      iex> delete_run(run)
      {:ok, %Run{}}

      iex> delete_run(invalid_run)
      {:error, %Ecto.Changeset{}}
  """
  def delete_run(%Run{} = run) do
    Repo.delete(run)
  end

  @doc """
  Deletes runs that belong to the given DAG.

  Returns the deleted run structs so callers can update LiveView streams.
  """

  def delete_runs_on_dag(dag_id, run_ids) when is_list(run_ids) do
    run_ids = Enum.uniq(run_ids)

    Repo.transaction(fn ->
      runs =
        Run
        |> where([run], run.dag_id == ^dag_id and run.id in ^run_ids)
        |> Repo.all()

      ids = Enum.map(runs, & &1.id)

      if ids != [] do
        Run
        |> where([run], run.dag_id == ^dag_id and run.id in ^ids)
        |> Repo.delete_all()
      end

      runs
    end)
  end

  def delete_task!(%Task{} = task) do
    Repo.delete!(task)
  end

  def reconcile_run_tasks(names, run_id) do
    Repo.transaction(fn ->
      Repo.query!("SELECT pg_advisory_xact_lock($1)", [run_id])

      task_ids = ensure_task_ids(names, run_id)

      tasks_by_id =
        Task
        |> where([task], task.id in ^task_ids)
        |> Repo.all()
        |> Map.new(&{&1.id, &1})

      Enum.map(task_ids, &{:ok, Map.fetch!(tasks_by_id, &1)})
    end)
  end

  defp ensure_task_ids(names, run_id) do
    sql = """
    WITH requested AS (
      SELECT name, MIN(position) AS position
      FROM unnest($1::text[]) WITH ORDINALITY AS input(name, position)
      GROUP BY name
    ),
    inserted AS (
      INSERT INTO gust_tasks (
        name,
        status,
        result,
        error,
        params,
        attempt,
        run_id,
        map_index,
        inserted_at,
        updated_at
      )
      SELECT
        requested.name,
        'created',
        '{}'::jsonb,
        '{}'::jsonb,
        '{}'::jsonb,
        1,
        $2,
        NULL,
        NOW(),
        NOW()
      FROM requested
      WHERE NOT EXISTS (
        SELECT 1
        FROM gust_tasks task
        WHERE task.run_id = $2
          AND task.name = requested.name
      )
      ON CONFLICT (run_id, name) WHERE map_index IS NULL
      DO NOTHING
      RETURNING id, name, map_index
    ),
    updated AS (
      UPDATE gust_tasks AS task
      SET status = 'created',
          updated_at = NOW()
      FROM requested
      WHERE task.run_id = $2
        AND task.name = requested.name
        AND task.status = 'running'
      RETURNING task.id, task.name, task.map_index
    ),
    existing AS (
      SELECT task.id, task.name, task.map_index
      FROM gust_tasks AS task
      JOIN requested ON requested.name = task.name
      WHERE task.run_id = $2
        AND task.status <> 'running'
    ),
    ensured AS (
      SELECT inserted.id, requested.position, inserted.map_index
      FROM inserted
      JOIN requested ON requested.name = inserted.name

      UNION ALL

      SELECT updated.id, requested.position, updated.map_index
      FROM updated
      JOIN requested ON requested.name = updated.name

      UNION ALL

      SELECT existing.id, requested.position, existing.map_index
      FROM existing
      JOIN requested ON requested.name = existing.name
    )
    SELECT id
    FROM ensured
    ORDER BY position, map_index NULLS FIRST
    """

    sql
    |> Repo.query!([names, run_id])
    |> Map.fetch!(:rows)
    |> List.flatten()
  end
end
