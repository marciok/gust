defmodule GustWeb.SystemLive do
  use GustWeb, :live_view

  alias Gust.Run.Pruner

  @environment Mix.env()

  @pruning_labels %{scheduled: "On", off: "Off", invalid: "Invalid schedule"}
  @pruning_badges %{scheduled: "badge-success", off: "badge-ghost", invalid: "badge-error"}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "System")
     |> assign(:system, system_info())}
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
      uptime_seconds: div(uptime_ms, 1_000),
      pruning: pruning_info()
    }
  end

  defp pruning_info do
    {status, error} =
      case Pruner.schedule() do
        {:ok, _schedule} -> {:scheduled, nil}
        :disabled -> {:off, nil}
        {:error, reason} -> {:invalid, reason}
      end

    %{
      status: status,
      label: @pruning_labels[status],
      badge: @pruning_badges[status],
      error: error,
      schedule: Pruner.configured_schedule(),
      dags: Pruner.retained_dags()
    }
  end

  defp application_version(application) do
    application
    |> Application.spec(:vsn)
    |> to_string()
  end
end
