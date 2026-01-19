defmodule Gust.DBLocker do
  @moduledoc """
  Behaviour for acquiring a DB-backed lock (e.g. Postgres advisory lock).

  Implementations must return `true` if the lock was acquired, `false` otherwise.
  """

  @typedoc "Lock identifier (e.g. integer key, string name, tuple, etc.)"
  @type lock_key :: term()

  @typedoc "Function to execute if the lock is acquired"
  @type attempt_result_fun :: (boolean() -> any())

  @callback try_lock(lock_key(), attempt_result_fun()) :: boolean()

  # coveralls-ignore-start
  @spec try_lock(lock_key(), attempt_result_fun()) :: boolean()
  def try_lock(lock_key, attempt_result) do
    impl().try_lock(lock_key, attempt_result)
  end

  defp impl, do: Application.get_env(:gust, :db_locker, Gust.DBLocker.Postgres)
  # coveralls-ignore-stop
end
