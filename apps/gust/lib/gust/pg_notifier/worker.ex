defmodule Gust.PGNotifier.Worker do
  @moduledoc false

  use GenServer
  require Logger

  alias Gust.PGNotifier

  @behaviour Gust.Run.Dispatcher
  @channel "run_dispatch"
  @connection Gust.PGNotifier.Connection

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

  @impl Gust.Run.Dispatcher
  def enqueue_all(runs), do: PGNotifier.enqueue_all(runs)

  @impl Gust.Run.Dispatcher
  def setup do
    GenServer.call(__MODULE__, {:setup, self()})
  end

  def start_link(opts) do
    notification_opts = Application.get_env(:gust, :pg_notifications, [])
    conn = connection_opts(opts, notification_opts)
    reconnect_backoff = Keyword.get(conn, :reconnect_backoff, 1_000) |> validate_backoff!()

    GenServer.start_link(__MODULE__, {conn, reconnect_backoff}, name: __MODULE__)
  end

  @impl true
  def init({opts, reconnect_backoff}) do
    {:ok, connection} = connect(opts, reconnect_backoff)
    {:ok, %{claimer: nil, connection: connection}}
  end

  @impl true
  def handle_call({:setup, claimer}, _from, state) do
    {:ok, _listen_ref} = PGNotifier.listen(@connection, @channel)
    {:reply, :ok, %{state | claimer: claimer}}
  end

  @impl true
  def handle_info({:notification, _pid, _ref, @channel, _payload}, state) do
    send(state.claimer, :claim_runs)
    {:noreply, state}
  end

  defp validate_backoff!(backoff) when is_integer(backoff) and backoff >= 0, do: backoff

  defp validate_backoff!(backoff) do
    raise ArgumentError,
          ":pg_notifications :reconnect_backoff must be a non-negative integer, got: #{inspect(backoff)}"
  end

  defp connection_opts(opts, notifier_opts) do
    Gust.Repo.config()
    |> Keyword.take(@connection_options)
    |> Keyword.merge(notifier_opts)
    |> Keyword.merge(opts)
    |> Keyword.put(:name, @connection)
    |> Keyword.put(:sync_connect, true)
    |> Keyword.put(:auto_reconnect, false)
  end

  defp connect(opts, reconnect_backoff) do
    case PGNotifier.start_link(opts) do
      {:ok, _pid} = started ->
        started

      {:error, reason} ->
        Logger.warning(
          "PostgreSQL notification connection failed: #{Exception.format_banner(:error, reason)}; " <>
            "retrying in #{reconnect_backoff}ms"
        )

        Process.sleep(reconnect_backoff)
        connect(opts, reconnect_backoff)
    end
  end
end
