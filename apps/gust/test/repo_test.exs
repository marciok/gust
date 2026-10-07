defmodule Gust.RepoTest do
  use ExUnit.Case, async: true
  alias Gust.Repo

  describe "connection_opts/1" do
    test "reuses the repo connection settings" do
      opts = Repo.connection_opts()

      assert opts[:database] == Repo.config()[:database]
      refute Keyword.has_key?(opts, :pool_size)
    end

    test "expands a url override and lets explicit overrides win" do
      opts =
        Repo.connection_opts(
          url: "ecto://direct-user:secret@direct.example.flympg.net:5433/direct_db",
          database: "explicit_db"
        )

      assert opts[:hostname] == "direct.example.flympg.net"
      assert opts[:port] == 5433
      assert opts[:username] == "direct-user"
      assert opts[:password] == "secret"
      assert opts[:database] == "explicit_db"
      refute Keyword.has_key?(opts, :url)
    end
  end
end
