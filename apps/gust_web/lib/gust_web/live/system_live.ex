defmodule GustWeb.SystemLive do
  use GustWeb, :live_view

  alias Gust.DAG.Source
  alias Gust.DAG.Source.Config
  alias Gust.PubSub
  alias GustWeb.LiveView.Helpers

  @environment Mix.env()

  @impl true
  def mount(_params, _session, socket) do
    PubSub.subscribe_dag_source_status()

    {:ok,
     socket
     |> assign(:page_title, "System")
     |> assign(:system, system_info())
     |> assign(:dag_source_rows, dag_source_rows())}
  end

  @impl true
  def handle_event("toggle_dag_monitor_status", _params, socket) do
    {:noreply, toggle_dag_monitor_status(socket)}
  end

  @impl true
  def handle_event("toggle_dag_source_status", params, socket) do
    source_id = Map.get(params, "id") || Map.get(params, "value")

    {:noreply,
     socket
     |> assign(:dag_source_rows, dag_source_rows())
     |> toggle_dag_source_status(source_id)}
  end

  @impl true
  def handle_event("pause_dag_source", %{"value" => source_id}, socket) do
    {:noreply, Helpers.pause(socket, source_id)}
  end

  @impl true
  def handle_event("resume_dag_source", %{"value" => source_id}, socket) do
    {:noreply, Helpers.resume(socket, source_id)}
  end

  @impl true
  def handle_info({:dag_source, :status_changed, %{source_id: source_id, status: status}}, socket) do
    rows =
      Enum.map(socket.assigns[:dag_source_rows] || dag_source_rows(), fn row ->
        row_id = Map.get(row, :id) || Map.get(row, "id")

        if row_id == source_id or to_string(row_id) == to_string(source_id) do
          Map.put(row, :status, status)
        else
          row
        end
      end)

    {:noreply, assign(socket, :dag_source_rows, rows)}
  end

  def format_uptime(total_seconds) do
    days = div(total_seconds, 86_400)
    hours = total_seconds |> rem(86_400) |> div(3_600)
    minutes = total_seconds |> rem(3_600) |> div(60)

    [
      days > 0 && "#{days}d",
      (days > 0 or hours > 0) && "#{hours}h",
      "#{minutes}m"
    ]
    |> Enum.filter(& &1)
    |> Enum.join(" ")
  end

  defp system_info do
    {uptime_ms, _since_last_call_ms} = :erlang.statistics(:wall_clock)

    %{
      connected_nodes: Node.list() |> Enum.sort(),
      current_node: Node.self(),
      environment: @environment,
      gust_version: application_version(:gust),
      gust_web_version: application_version(:gust_web),
      run_dispatcher: Application.get_env(:gust, :run_dispatcher),
      role: System.get_env("GUST_ROLE", "single"),
      uptime_seconds: div(uptime_ms, 1_000)
    }
  end

  defp toggle_dag_monitor_status(socket) do
    case Process.whereis(Gust.FileMonitor.Worker) do
      nil ->
        put_flash(socket, :warning, "DAG monitor is unavailable.")

      _pid ->
        case Gust.FileMonitor.Worker.status() do
          :running ->
            Helpers.pause(socket)

          :paused ->
            Helpers.resume(socket)

          {:error, reason} ->
            put_flash(socket, :error, "DAG monitor is unavailable: #{inspect(reason)}")

          _ ->
            put_flash(socket, :warning, "DAG monitor status could not be changed.")
        end
    end
  end

  def dag_source_rows do
    Config.read()
    |> Enum.map(fn source ->
      id = Map.get(source, :id) || Map.get(source, "id")
      type = source_type(source)
      status = dag_source_status(id)

      %{
        id: id,
        source: source_display(source, type),
        type: type,
        path: source_path(source, type),
        status: status
      }
    end)
  rescue
    _ -> []
  end

  defp toggle_dag_source_status(socket, nil) do
    put_flash(socket, :warning, "No DAG source was selected.")
  end

  defp toggle_dag_source_status(socket, source_id) do
    case dag_source_status(source_id) do
      :running -> Helpers.pause(socket, source_id)
      :paused -> Helpers.resume(socket, source_id)
      :stopped -> Helpers.resume(socket, source_id)
      _ -> put_flash(socket, :warning, "DAG source #{source_id} is unavailable.")
    end
  end

  defp dag_source_status(id) do
    case Source.monitor_status(id) do
      status when status in [:running, :paused, :stopped] -> status
      _ -> :unavailable
    end
  rescue
    _ -> :unavailable
  end

  defp source_type(source) do
    type = Map.get(source, :type) || Map.get(source, "type")

    case type do
      nil -> "Unknown"
      module when is_atom(module) -> module |> Module.split() |> List.last()
      value -> value
    end
  end

  defp source_display(source, "Database") do
    "#{database_user(source)}@#{database_name(source)}"
  end

  defp source_display(source, "Git") do
    source_value(source, [:url, "url"]) || "git repository"
  end

  defp source_display(source, "S3") do
    s3_url(s3_bucket(source), s3_prefix(source))
  end

  defp source_display(source, "Folder") do
    source_value(source, [:folder, "folder", :path, "path"]) || "folder"
  end

  defp source_display(source, _type) do
    source_value(source, [:source, "source"]) || "-"
  end

  defp source_path(source, "Database"), do: database_name(source)

  defp source_path(source, "Git") do
    source_value(source, [:branch, "branch"]) || "main"
  end

  defp source_path(source, "S3") do
    bucket = s3_bucket(source)
    prefix = s3_prefix(source)

    if prefix == "", do: bucket, else: "#{bucket}/#{prefix}"
  end

  defp source_path(source, "Folder") do
    source_value(source, [:folder, "folder", :path, "path"]) || "-"
  end

  defp source_path(_source, _type), do: "-"

  defp s3_url(bucket, "") do
    "s3://#{bucket}"
  end

  defp s3_url(bucket, prefix) do
    "s3://#{bucket}/#{prefix}"
  end

  defp database_user(source) do
    source_value(source, [:user, "user"]) || "postgres"
  end

  defp database_name(source) do
    source_value(source, [:database, "database", :dbname, "dbname"]) || "database"
  end

  defp s3_bucket(source) do
    source_value(source, [:bucket, "bucket"]) || "bucket"
  end

  defp s3_prefix(source) do
    source_value(source, [:prefix, "prefix"]) || ""
  end

  defp source_value(source, keys) do
    Enum.find_value(keys, fn key ->
      case key do
        atom when is_atom(atom) -> Map.get(source, atom)
        string when is_binary(string) -> Map.get(source, string)
      end
    end)
  end

  defp application_version(application) do
    application
    |> Application.spec(:vsn)
    |> to_string()
  end
end
