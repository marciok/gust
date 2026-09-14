defmodule GustWeb.DagWebhookController do
  @moduledoc """
  Handles incoming Git webhook requests.

  Receives webhooks from GitHub, GitLab, Gitea and other Git platforms,
  validates signatures, and triggers immediate DAG reloads.
  """

  use GustWeb, :controller
  require Logger

  alias Gust.DAG.Source.GitWebhook

  @doc """
  Handle GitHub push webhook.

  Expects a push event with HMAC-SHA256 signature in X-Hub-Signature-256 header.
  """
  def github(conn, _params) do
    handle_webhook(conn, :github)
  end

  @doc """
  Handle GitLab push webhook.

  Expects a push event with token in X-Gitlab-Token header.
  """
  def gitlab(conn, _params) do
    handle_webhook(conn, :gitlab)
  end

  @doc """
  Handle Gitea push webhook.

  Expects a push event with signature in X-Gitea-Signature header.
  """
  def gitea(conn, _params) do
    handle_webhook(conn, :gitea)
  end

  @doc """
  Handle generic Git webhook.

  Expects authorization token in Authorization: Bearer <token> header.
  """
  def generic(conn, _params) do
    handle_webhook(conn, :generic)
  end

  # Private helpers

  defp handle_webhook(conn, platform) do
    # Ensure we have a DAG loader configured
    loader = Application.get_env(:gust, :dag_loader, Gust.DAG.Loader.Worker)
    headers = Enum.map(conn.req_headers, fn {k, v} -> {String.downcase(k), v} end)

    with {:ok, loader_pid} <- get_loader_pid(loader),
         {:ok, conn, body} <- read_request_body(conn),
         {:ok, message} <- GitWebhook.handle_webhook(platform, headers, body, loader_pid) do
      respond(conn, 200, %{status: "ok", message: message})
    else
      :error ->
        Logger.error("DAG loader not available")
        respond(conn, 503, %{status: "error", message: "Service unavailable"})

      {:error, :closed} ->
        Logger.warning("Webhook #{platform} handler error: connection closed")
        Plug.Conn.halt(conn)

      {:error, reason} ->
        Logger.warning("Webhook #{platform} handler error: #{reason}")
        respond(conn, 400, %{status: "error", message: reason})
    end
  rescue
    e ->
      Logger.error("Webhook error: #{inspect(e)}")
      respond(conn, 500, %{status: "error", message: "Internal server error"})
  end

  defp respond(conn, status, body) do
    conn
    |> put_resp_header("content-type", "application/json")
    |> send_resp(status, Glazer.JSON.encode!(body))
  end

  defp read_request_body(conn) do
    case do_read_body(conn, []) do
      {:ok, conn, ""} ->
        # Fallback: In tests, Phoenix parses the body into params before we can read it
        # Re-encode params as JSON to get the original body for signature validation
        response = if map_size(conn.params) > 0, do: Glazer.JSON.encode!(conn.params), else: ""
        {:ok, conn, response}

      {:ok, conn, body} ->
        {:ok, conn, body}

      error ->
        error
    end
  end

  defp do_read_body(conn, acc) do
    case Plug.Conn.read_body(conn, size: 8_388_608) do
      {:ok, data, conn} when acc == [] ->
        {:ok, conn, data}

      {:ok, data, conn} ->
        {:ok, conn, IO.iodata_to_binary([acc, data])}

      {:more, data, conn} ->
        do_read_body(conn, acc ++ [data])

      {:error, :closed} ->
        {:error, :closed}

      {:error, reason} ->
        {:error, "Failed to read data from connection: #{inspect(reason)}"}
    end
  end

  defp get_loader_pid(loader_module) when is_atom(loader_module) do
    # First try the local process registry (common case)
    case Process.whereis(loader_module) do
      pid when is_pid(pid) ->
        {:ok, pid}

      nil ->
        # Try global registry
        case :global.whereis_name(loader_module) do
          :undefined -> :error
          pid -> {:ok, pid}
        end
    end
  end

  defp get_loader_pid(_), do: :error
end
