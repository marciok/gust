defmodule GustWeb.SystemLive do
  use GustWeb, :live_view

  @environment Mix.env()

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
      role: System.get_env("GUST_ROLE", "single"),
      uptime_seconds: div(uptime_ms, 1_000)
    }
  end

  defp application_version(application) do
    application
    |> Application.spec(:vsn)
    |> to_string()
  end
end
