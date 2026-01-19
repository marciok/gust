defmodule DBLocker.PostgresTest do
  alias Gust.DBLocker.Postgres
  use Gust.DataCase

  describe "try_lock/2" do
    test "repo checkouts connection" do
      Postgres.try_lock(12_345, fn attempt ->
        send(self(), {:result, attempt})
      end)

      assert_receive {:result, true}
    end
  end
end
