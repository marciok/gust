defmodule Gust.DBLocker.Postgres do
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
