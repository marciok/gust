defmodule GustShell.Runtime.Adapter do
  @moduledoc false

  @behaviour Gust.DAG.Runtime.Adapter

  alias Gust.DAG.Definition

  @impl true
  def setup(%Definition{} = dag_def, _runtime_id), do: dag_def

  @impl true
  def teardown(%Definition{}, _runtime_id), do: :ok

  @impl true
  def on_finished_callback(_definition, _fn_name, _run, _status), do: :ok

  @impl true
  def kill(task_pid) do
    GenServer.cast(task_pid, {:kill})
    :ok
  end
end
