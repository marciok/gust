defmodule Gust.DBLocker.Postgres do
  @moduledoc """
  Implements DB-backed advisory locking using Postgres.

  Uses `pg_try_advisory_lock/1` inside a checkout to attempt the lock and passes
  the success flag to the provided callback.
  """

  alias Gust.Repo
  @behaviour Gust.DBLocker

  def try_lock(lock_key, attempt_result_fun) do
    Repo.checkout(
      fn ->
        [[success]] = Repo.query!("SELECT pg_try_advisory_lock($1)", [lock_key]).rows
        attempt_result_fun.(success)
      end,
      timeout: :infinity
    )
  end
end
