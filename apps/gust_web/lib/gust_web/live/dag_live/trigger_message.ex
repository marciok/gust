defmodule GustWeb.DagLive.TriggerMessage do
  @moduledoc false

  @unpin_hint "Unpin your history to view it."

  @doc """
  Returns the `{kind, message}` flash for a run triggered on `dag`.

  Paused DAGs get a `:warning`, since the run will not start until the DAG is
  enabled. Pass `pinned?: true` when the run history is pinned, so the new run
  is not visible; the message then explains how to view it.
  """
  def flash(dag, run, opts \\ []) do
    pinned? = Keyword.get(opts, :pinned?, false)

    case {dag.enabled, pinned?} do
      {true, false} -> {:info, "Run #{run.id} triggered"}
      {true, true} -> {:warning, "Run #{run.id} triggered. #{@unpin_hint}"}
      {false, false} -> {:warning, paused(dag, run)}
      {false, true} -> {:warning, "#{paused(dag, run)} #{@unpin_hint}"}
    end
  end

  defp paused(dag, run) do
    "Run #{run.id} created, but DAG #{dag.name} is paused. It will start once the DAG is enabled."
  end
end
