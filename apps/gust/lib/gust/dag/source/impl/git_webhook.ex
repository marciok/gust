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

  @name __MODULE__ |> Module.split() |> List.last()

  alias Gust.DAG.Source.Config, as: SourceConfig
  alias Gust.DAG.Source.Git
  alias Gust.DAG.WebhookHandler
  require Logger

  @impl true
  # This avoids compiler warnings about non-exported load/0
  def load, do: load(nil)

  @impl true
  def load(effective_date), do: Git.load(effective_date)

  @impl true
  def monitor(loader_pid, config \\ %{}) do
    secret = resolve_monitor_secret(config)

    if secret do
      __MODULE__.Monitor.start_link(loader_pid, secret)
    else
      {:error,
       "GitWebhook source requires :webhook_secret, GIT_WEBHOOK_SECRET, or a platform-specific secret env var for a configured webhook platform"}
    end
  end

  @impl true
  def name, do: @name

  @doc """
  Handles a webhook request from a Git platform.

  Called by the controller to process incoming webhooks.
  """
  def handle_webhook(platform, headers, body, loader_pid) do
    handle_webhook(platform, headers, body, loader_pid, %{})
  end

  def handle_webhook(platform, headers, body, loader_pid, params) do
    secret = resolve_webhook_secret(%{}, platform)

    case validate_and_parse(platform, headers, body, secret, params) do
      {:ok, payload} ->
        Logger.debug("Processing webhook from #{platform}: #{payload.repository}")

        case request_reload(payload) do
          :not_dispatched -> trigger_reload(loader_pid, payload)
          _ -> :ok
        end

        {:ok, "Webhook #{platform} processed"}

      {:error, reason} ->
        Logger.warning("Webhook validation failed (#{platform}): #{reason}")
        {:error, reason}
    end
  rescue
    e -> {:error, "Internal server error #{inspect(e)}"}
  end

  defp validate_and_parse(:github, headers, body, secret, _params) do
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

  defp validate_and_parse(:gitlab, headers, body, secret, _params) do
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

  defp validate_and_parse(:gitea, headers, body, secret, _params) do
    case get_header(headers, "x-gitea-signature") do
      nil ->
        {:error, "Missing X-Gitea-Signature header"}

      signature ->
        validate_signature(body, signature, secret)
    end
  end

  defp validate_and_parse(:generic, headers, body, secret, params) do
    # Generic endpoint supports Bearer token or query parameter
    query_token = get_query_param(params, "token")

    with :ok <- validate_generic_token(get_header(headers, "authorization"), query_token, secret) do
      case Glazer.JSON.decode(body) do
        {:ok, payload} -> {:ok, payload}
        {:error, e} -> {:error, "Invalid JSON: #{inspect(e)}"}
      end
    end
  end

  defp validate_generic_token("Bearer " <> token, _query_token, secret) when token == secret,
    do: :ok

  defp validate_generic_token(_auth_header, token, secret)
       when token == secret and is_binary(token),
       do: :ok

  defp validate_generic_token(_auth_header, _query_token, _secret),
    do: {:error, "Missing or invalid Authorization header"}

  defp get_query_param(params, key) when is_map(params), do: Map.get(params, key)
  defp get_query_param(_params, _key), do: nil

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

  @spec request_reload(map()) :: :queued | :not_dispatched
  defp request_reload(payload) do
    dispatched =
      SourceConfig.read()
      |> Enum.filter(fn source -> SourceConfig.source_module(source) == __MODULE__ end)
      |> Enum.reduce(0, fn source, count ->
        source_id = Map.get(source, :id) || Map.get(source, "id")

        case Registry.lookup(Gust.Registry, source_id) do
          [{pid, _}] when is_pid(pid) ->
            send(pid, {:git_webhook_reload, payload})
            count + 1

          _ ->
            count
        end
      end)

    if dispatched > 0, do: :queued, else: :not_dispatched
  end

  @doc false
  def trigger_reload(loader_pid, _payload, last_snapshot \\ %{}) do
    case load() do
      %{success: success, error: error} ->
        current_snapshot = build_snapshot(success, error)

        current_snapshot
        |> Enum.each(fn {dag_name, result} ->
          maybe_send_reload(last_snapshot, loader_pid, dag_name, result)
        end)

        last_snapshot
        |> Map.keys()
        |> Enum.reject(&Map.has_key?(current_snapshot, &1))
        |> Enum.each(fn dag_name ->
          send(loader_pid, {dag_name, {:error, "DAG removed"}, "removed"})
        end)

        current_snapshot

      {:error, _reason} ->
        # Preserve previous state when the source cannot be loaded.
        last_snapshot
    end
  end

  defp build_snapshot(success, error) do
    success_entries = Enum.map(success, fn {name, value} -> {name, {:ok, value}} end)
    error_entries = Enum.map(error, fn {name, reason} -> {name, {:error, reason}} end)

    Map.new(success_entries ++ error_entries)
  end

  defp maybe_send_reload(last_snapshot, loader_pid, dag_name, result) do
    case Map.get(last_snapshot, dag_name) do
      previous when previous != result and previous != nil ->
        :ok

      _ ->
        send(loader_pid, {dag_name, result, "reload"})
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

  defp resolve_monitor_secret(config) do
    case resolve_webhook_secret(config) do
      secret when is_binary(secret) and secret != "" ->
        secret

      _ ->
        config
        |> configured_platforms()
        |> Enum.reduce(%{}, &(&1 |> platform_specific_secret() |> acc_secrets(&2)))
        |> case do
          platform_secrets when map_size(platform_secrets) > 0 -> platform_secrets
          _ -> nil
        end
    end
  end

  defp acc_secrets(secret, acc) when not is_binary(secret) or secret == "", do: acc
  defp acc_secrets(secret, acc), do: Map.put(acc, :default, secret)

  defp configured_platforms(config) do
    config
    |> normalize_config()
    |> Map.get(:webhook_platforms, [:github])
    |> List.wrap()
    |> Enum.map(&normalize_platform/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp normalize_platform(platform) when platform in [:github, :gitlab, :gitea], do: platform
  defp normalize_platform("github"), do: :github
  defp normalize_platform("gitlab"), do: :gitlab
  defp normalize_platform("gitea"), do: :gitea
  defp normalize_platform(_), do: nil

  defp normalize_config(config) when is_map(config), do: config
  defp normalize_config(config) when is_list(config), do: Map.new(config)
  defp normalize_config(_), do: %{}

  defp resolve_webhook_secret(config, platform \\ nil) do
    config = normalize_config(config)

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
  alias Gust.DAG.Source.GitWebhook

  def start_link(loader_pid, secret) do
    start_link(loader_pid, secret, &GitWebhook.trigger_reload/3)
  end

  def start_link(loader_pid, secret, reload_fun) do
    GenServer.start_link(__MODULE__, {loader_pid, secret, reload_fun})
  end

  @impl true
  def init({loader_pid, secret, reload_fun}) do
    {:ok,
     %{
       loader_pid: loader_pid,
       secret: secret,
       status: :running,
       reload_fun: reload_fun,
       pending_payload: nil,
       last_snapshot: %{}
     }}
  end

  @impl true
  def handle_call(:pause, _from, state) do
    {:reply, :ok, %{state | status: :paused}}
  end

  @impl true
  def handle_call(:resume, _from, state) do
    state = %{state | status: :running}

    state =
      case state.pending_payload do
        nil ->
          state

        payload ->
          next_snapshot = state.reload_fun.(state.loader_pid, payload, state.last_snapshot)
          %{state | pending_payload: nil, last_snapshot: next_snapshot}
      end

    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, state.status, state}
  end

  @impl true
  def handle_info({:git_webhook_reload, payload}, %{status: :paused} = state) do
    {:noreply, %{state | pending_payload: payload}}
  end

  @impl true
  def handle_info({:git_webhook_reload, payload}, state) do
    next_snapshot = state.reload_fun.(state.loader_pid, payload, state.last_snapshot)
    {:noreply, %{state | last_snapshot: next_snapshot}}
  end

  @impl true
  def handle_info(_msg, state) do
    # Webhook monitor doesn't need to handle any messages
    # All processing happens through the HTTP endpoint
    {:noreply, state}
  end
end
