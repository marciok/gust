defmodule GustWeb.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      GustWeb.Telemetry,
      GustWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: GustWeb.Supervisor]

    children =
      if System.get_env("GUST_ROLE", "single") in ["web", "single"], do: children, else: []

    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    GustWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
