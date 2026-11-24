defmodule Gust.Run.Claim.Repo do
  @moduledoc """
  Claims runs from the `gust_runs` table.

  `next_run/1` claims the oldest `:enqueued` run of an enabled DAG, or a
  `:starting`/`:running` run whose lease expired, with `FOR UPDATE SKIP LOCKED`
  so concurrent claimers never take the same run.

  DAGs whose ids are passed as `sequential_dag_ids` (`runs: [concurrency:
  :sequential]`) run one at a time, oldest first: their `:enqueued` runs are
  only claimable when the DAG has no active (`:starting`, `:running` or
  `:waiting`) run and no older `:enqueued` run. Two claimers can't start two
  runs of the same DAG at once: while one claims the oldest queued run, the
  next one is still behind an older queued run (before the claim commits) or
  an active run (after).
  """

  @behaviour Gust.Run.Claim

  alias Gust.Repo
  import Ecto.Query, warn: false
  alias Gust.Flows.Run

  def renew_run(run_id, token) do
    now = DateTime.utc_now()
    expires_at = expire_date(now)

    query =
      from r in Gust.Flows.Run,
        where: r.id == ^run_id and r.claim_token == ^token,
        update: [set: [claim_expires_at: ^expires_at]],
        select: r

    case Gust.Repo.update_all(query, [], returning: true) do
      {1, [run]} -> run
      {0, []} -> nil
    end
  end

  @active_statuses [:starting, :running, :waiting]

  def next_run(sequential_dag_ids \\ []) do
    node = to_string(Node.self())
    token = Ecto.UUID.generate()
    now = DateTime.utc_now()
    expires_at = expire_date(now)

    {:ok, run} =
      Repo.transaction(fn ->
        from(r in Run,
          as: :run,
          join: d in assoc(r, :dag),
          where: d.enabled == true,
          where:
            r.status == :enqueued or
              (r.status in [:starting, :running] and r.claim_expires_at < ^now),
          where:
            r.status != :enqueued or r.dag_id not in ^sequential_dag_ids or
              (not exists(active_run()) and not exists(older_enqueued_run())),
          order_by: [asc: r.inserted_at, asc: r.id],
          limit: 1,
          lock: "FOR UPDATE SKIP LOCKED"
        )
        |> Repo.one()
        |> maybe_update_claim(node, expires_at, token)
      end)

    run
  end

  defp active_run do
    from a in Run,
      where: a.dag_id == parent_as(:run).dag_id and a.status in ^@active_statuses,
      select: 1
  end

  defp older_enqueued_run do
    from o in Run,
      where: o.dag_id == parent_as(:run).dag_id and o.status == :enqueued,
      where:
        o.inserted_at < parent_as(:run).inserted_at or
          (o.inserted_at == parent_as(:run).inserted_at and o.id < parent_as(:run).id),
      select: 1
  end

  defp maybe_update_claim(nil, _node, _expires_at, _token), do: nil

  defp maybe_update_claim(run, node, expires_at, token) do
    run
    |> Ecto.Changeset.change(
      status: :starting,
      claimed_by: node,
      claim_expires_at: expires_at,
      claim_token: token
    )
    |> Repo.update!()
  end

  defp expire_date(now) do
    lease_seconds = Application.get_env(:gust, :claim_lease_seconds, 15)
    DateTime.add(now, lease_seconds)
  end
end
