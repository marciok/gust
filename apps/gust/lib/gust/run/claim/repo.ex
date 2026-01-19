defmodule Gust.Run.Claim.Repo do
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

  def next_run do
    node = to_string(Node.self())
    token = Ecto.UUID.generate()
    now = DateTime.utc_now()
    expires_at = expire_date(now)

    {:ok, run} =
      Repo.transaction(fn ->
        from(r in Run,
          where: r.status == :enqueued or (r.status == :running and r.claim_expires_at < ^now),
          order_by: [asc: r.inserted_at],
          limit: 1,
          lock: "FOR UPDATE SKIP LOCKED"
        )
        |> Repo.one()
        |> maybe_update_claim(node, expires_at, token)
      end)

    run
  end

  defp maybe_update_claim(nil, _node, _expires_at, _token), do: nil

  defp maybe_update_claim(run, node, expires_at, token) do
    run
    |> Ecto.Changeset.change(
      status: :running,
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
