defmodule Gust.DAG.Source.GitWebhook do
  @moduledoc """
  DAG source that loads definitions from a Git repository via webhooks.

  Instead of polling, this source receives real-time updates via Git platform webhooks
  (GitHub, GitLab, Gitea). Provides instant DAG reload on push instead of 30-second polling delay.

  Configuration:
    - `:url`              — Git repository URL (required)
    - `:branch`           — Branch to check out (default: "main")
    - `:path`             — Local path where to clone/pull (default: System.tmp_dir)
    - `:webhook_secret`   — Shared secret for HMAC validation (required)
    - `:webhook_platforms`— List of platforms to support [:github, :gitlab, :gitea] (default: [:github])
    - `:credentials`      — Optional authentication (see Gust.DAG.Source.Git for format)

  Webhook endpoints:
    - POST /api/webhooks/github
    - POST /api/webhooks/gitlab
    - POST /api/webhooks/gitea
    - POST /api/webhooks/generic

  Signature validation:
    - GitHub: X-Hub-Signature-256 header (sha256=...)
    - GitLab: X-Gitlab-Token header
    - Gitea: X-Gitea-Signature header
    - Generic: Authorization: Bearer <token> or ?token=<token>
  """

  @behaviour Gust.DAG.Source

  alias Gust.DAG.Source.Git
  alias Gust.DAG.WebhookHandler
  require Logger

  @impl true
  def load(effective_date \\ nil), do: Git.load(effective_date)

  @impl true
  def monitor(loader_pid, config \\ %{}) do
    secret = resolve_webhook_secret(config)

    if secret do
      __MODULE__.Monitor.start_link(loader_pid, secret)
    else
      {:error,
       "GitWebhook source requires :webhook_secret in the dag_source tuple config or GIT_WEBHOOK_SECRET env var"}
    end
  end

  @impl true
  def name, do: "GitWebhook"

  @doc """
  Handles a webhook request from a Git platform.

  Called by the controller to process incoming webhooks.
  """
  def handle_webhook(platform, headers, body, loader_pid) do
    secret = resolve_webhook_secret(%{}, platform)

    case validate_and_parse(platform, headers, body, secret) do
      {:ok, payload} ->
        Logger.debug("Processing webhook from #{platform}: #{payload.repository}")
        trigger_reload(loader_pid, payload)
        {:ok, "Webhook #{platform} processed"}

      {:error, reason} ->
        Logger.warning("Webhook validation failed (#{platform}): #{reason}")
        {:error, reason}
    end
  rescue
    e -> {:error, "Internal server error #{inspect(e)}"}
  end

  defp validate_and_parse(:github, headers, body, secret) do
    case get_header(headers, "x-hub-signature-256") do
      nil ->
        {:error, "Missing X-Hub-Signature-256 header"}

      signature ->
        case parse_signature(signature) do
          {:ok, sig} ->
            validate_signature(body, sig, secret)

          :error ->
            {:error, "Invalid signature format"}
        end
    end
  end

  defp validate_and_parse(:gitlab, headers, body, secret) do
    case get_header(headers, "x-gitlab-token") do
      nil ->
        {:error, "Missing X-Gitlab-Token header"}

      ^secret ->
        # GitLab tokens are simple string comparison, not HMAC
        case Glazer.JSON.decode(body) do
          {:ok, payload} -> WebhookHandler.parse_gitlab_payload(payload)
          {:error, e} -> {:error, "Invalid JSON: #{inspect(e)}"}
        end

      _ ->
        {:error, "Invalid token"}
    end
  end

  defp validate_and_parse(:gitea, headers, body, secret) do
    case get_header(headers, "x-gitea-signature") do
      nil ->
        {:error, "Missing X-Gitea-Signature header"}

      signature ->
        validate_signature(body, signature, secret)
    end
  end

  defp validate_and_parse(:generic, headers, body, secret) do
    # Generic endpoint supports Bearer token or query parameter
    case get_header(headers, "authorization") do
      "Bearer " <> token when token == secret ->
        case Glazer.JSON.decode(body) do
          {:ok, payload} -> {:ok, payload}
          {:error, e} -> {:error, "Invalid JSON: #{inspect(e)}"}
        end

      _ ->
        {:error, "Missing or invalid Authorization header"}
    end
  end

  defp validate_signature(body, sig, secret) do
    if WebhookHandler.validate_signature(body, sig, secret) do
      case Glazer.JSON.decode(body) do
        {:ok, payload} -> WebhookHandler.parse_github_payload(payload)
        {:error, e} -> {:error, "Invalid JSON: #{inspect(e)}"}
      end
    else
      {:error, "Invalid signature"}
    end
  end

  defp trigger_reload(loader_pid, _payload) do
    case load() do
      dags when is_map(dags) ->
        # Send reload messages for all DAGs
        Enum.each(dags, fn {dag_name, result} ->
          send(loader_pid, {dag_name, result, "reload"})
        end)

      error ->
        error
    end
  end

  defp get_header(headers, name) do
    name_lower = String.downcase(name)

    Enum.find_value(headers, fn {key, value} ->
      if String.downcase(key) == name_lower, do: value
    end)
  end

  defp parse_signature("sha256=" <> sig), do: {:ok, sig}
  defp parse_signature(_), do: :error

  defp resolve_webhook_secret(config, platform \\ nil) do
    config =
      case config do
        config when is_map(config) -> config
        config when is_list(config) -> Map.new(config)
        _ -> %{}
      end

    config[:webhook_secret] ||
      Gust.DAG.Source.config() |> Keyword.get(:webhook_secret) ||
      System.get_env("GIT_WEBHOOK_SECRET") ||
      platform_specific_secret(platform)
  end

  defp platform_specific_secret(platform) do
    case platform do
      :github -> System.get_env("GITHUB_WEBHOOK_SECRET")
      :gitlab -> System.get_env("GITLAB_WEBHOOK_SECRET")
      :gitea -> System.get_env("GITEA_WEBHOOK_SECRET")
      _ -> nil
    end
  end
end

defmodule Gust.DAG.Source.GitWebhook.Monitor do
  @moduledoc false

  use GenServer

  def start_link(loader_pid, secret) do
    GenServer.start_link(__MODULE__, {loader_pid, secret})
  end

  @impl true
  def init({loader_pid, secret}) do
    {:ok,
     %{
       loader_pid: loader_pid,
       secret: secret,
       status: :running
     }}
  end

  @impl true
  def handle_call(:pause, _from, state) do
    {:reply, :ok, %{state | status: :paused}}
  end

  @impl true
  def handle_call(:resume, _from, state) do
    {:reply, :ok, %{state | status: :running}}
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, state.status, state}
  end

  @impl true
  def handle_info(_msg, state) do
    # Webhook monitor doesn't need to handle any messages
    # All processing happens through the HTTP endpoint
    {:noreply, state}
  end
end
