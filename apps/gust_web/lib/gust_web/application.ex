defmodule GustWeb.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    warn_if_api_token_missing()

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

  defp warn_if_api_token_missing do
    case Application.get_env(:gust_web, :api_token) do
      token when is_binary(token) and token != "" ->
        :ok

      _ ->
        Logger.warning(
          "Gust API routes are mounted, but :gust_web, :api_token is not configured. " <>
            "Set GUST_API_TOKEN to authorize API requests."
        )
    end
  end
end
