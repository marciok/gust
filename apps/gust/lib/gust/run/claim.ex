defmodule Gust.Run.Claim do
  @moduledoc """
  Behavior + facade for claiming/renewing run leases.

  Configure the implementation with:

      config :gust, Gust.Run.Claim, Gust.Run.Claim.Repo
  """

  @type run_id :: term()
  @type token :: Ecto.UUID.t()
  @type run :: Gust.Flows.Run.t()

  @type next_run_result ::
          nil
          | %{run: run(), token: token(), claimed_by: String.t(), claim_expires_at: DateTime.t()}

  @callback renew_run(run_id(), token()) :: run() | nil
  @callback next_run() :: next_run_result()

  def renew_run(run_id, token), do: impl().renew_run(run_id, token)
  def next_run, do: impl().next_run()

  defp impl do
    Application.get_env(:gust, :run_claim, Gust.Run.Claim.Repo)
  end
end
