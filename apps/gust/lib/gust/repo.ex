defmodule Gust.Repo do
  use Ecto.Repo,
    otp_app: :gust,
    adapter: Ecto.Adapters.Postgres

  @connection_options [
    :hostname,
    :port,
    :username,
    :password,
    :database,
    :socket,
    :socket_dir,
    :endpoints,
    :ssl,
    :ssl_opts,
    :parameters,
    :connect_timeout,
    :socket_options,
    :types,
    :after_connect,
    :prepare,
    :target_server_type,
    :idle_interval
  ]

  @doc """
  Returns options for a standalone Postgrex connection that reuses this repo's
  connection settings, merged with `overrides`.

  A `:url` in `overrides` is expanded into its connection options, so a
  dedicated connection can point somewhere else than the repo (e.g. a direct
  connection when the repo goes through PgBouncer in transaction mode).
  """
  def connection_opts(overrides \\ []) do
    {url, overrides} = Keyword.pop(overrides, :url)
    url_opts = if url, do: Ecto.Repo.Supervisor.parse_url(url), else: []

    config()
    |> Keyword.take(@connection_options)
    |> Keyword.merge(url_opts)
    |> Keyword.merge(overrides)
  end
end
