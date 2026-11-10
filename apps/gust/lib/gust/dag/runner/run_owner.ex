defmodule Gust.DAG.Runner.RunOwner do
  @moduledoc false

  alias Gust.Flows.Run

  @doc """
  Resolves the connected node that owns `run`, based on `run.claimed_by`.

  Unclaimed runs resolve to the local node.
  """
  @spec node(Run.t()) :: {:ok, node()} | {:error, :run_owner_unavailable | :run_not_active}
  def node(%Run{claimed_by: nil}), do: {:ok, Node.self()}

  def node(%Run{claimed_by: claimed_by} = run) do
    case Enum.find([Node.self() | Node.list()], &(to_string(&1) == claimed_by)) do
      nil ->
        if active_lease?(run),
          do: {:error, :run_owner_unavailable},
          else: {:error, :run_not_active}

      target_node ->
        {:ok, target_node}
    end
  end

  @spec active_lease?(Run.t()) :: boolean()
  def active_lease?(%Run{status: status, claim_expires_at: expires_at})
      when status in [:starting, :running] and not is_nil(expires_at) do
    DateTime.after?(expires_at, DateTime.utc_now())
  end

  def active_lease?(_run), do: false
end
