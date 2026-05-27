defmodule GustWeb.Plugs.APIAuth do
  @moduledoc """
  Authenticates Gust API requests with the configured bearer token.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]
  require Logger

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    with {:ok, token} <- bearer_token(conn),
         true <- token_valid?(token) do
      conn
    else
      _ ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "unauthorized"})
        |> halt()
    end
  end

  defp bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      [authorization] ->
        parse_authorization(authorization)

      _ ->
        :error
    end
  end

  defp parse_authorization(authorization) do
    case String.split(authorization, " ", parts: 2) do
      [scheme, token] ->
        if String.downcase(scheme) == "bearer" and token != "" do
          {:ok, token}
        else
          :error
        end

      _ ->
        :error
    end
  end

  defp token_valid?(token) when is_binary(token) do
    case Application.get_env(:gust_web, :api_token) do
      configured_token when is_binary(configured_token) and configured_token != "" ->
        byte_size(token) == byte_size(configured_token) and
          Plug.Crypto.secure_compare(token, configured_token)

      nil ->
        Logger.warning(
          "Gust API token is not configured. " <>
            "Set :gust_web, :api_token to authorize API requests."
        )

        false

      _ ->
        false
    end
  end
end
