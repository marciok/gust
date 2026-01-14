defmodule DBLocker.PostgresTest do
  use Gust.DataCase

  describe "try_lock/2" do
    test "repo checkouts connection" do
      Gust.DBLocker.Postgres.try_lock(12_2345, fn attempt ->
        send(self(), {:result, attempt})
      end)

      assert_receive {:result, true}
    end
  end
end
