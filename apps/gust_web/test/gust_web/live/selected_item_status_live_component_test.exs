defmodule GustWeb.SelectedItemStatusLiveComponentTest do
  use GustWeb.ConnCase

  import Phoenix.LiveViewTest

  require GustWeb.LiveComponentTest
  import GustWeb.LiveComponentTest

  alias Gust.Flows.Task
  alias GustWeb.SelectedItemStatusComponent

  test "shows a countdown only while retrying", %{conn: conn} do
    retry_at = DateTime.add(DateTime.utc_now(), 30, :second)

    {:ok, component, _html} =
      live_component_isolated(conn, SelectedItemStatusComponent, %{
        id: "retry-status",
        status: :retrying,
        item: %Task{status: :retrying, retry_at: retry_at}
      })

    assert has_element?(
             component,
             "#status-badge-container.tooltip.tooltip-open[data-tip]"
           )

    Phoenix.LiveView.send_update(component.pid, SelectedItemStatusComponent,
      id: "retry-status",
      status: :failed,
      item: %Task{status: :failed}
    )

    refute has_element?(component, "#status-badge-container.tooltip")
    refute has_element?(component, "#status-badge-container[data-tip]")
  end

  test "ignores an update from a stale deadline", %{conn: conn} do
    retry_at = DateTime.add(DateTime.utc_now(), 30, :second)

    {:ok, component, _html} =
      live_component_isolated(conn, SelectedItemStatusComponent, %{
        id: "retry-status",
        status: :retrying,
        item: %Task{status: :retrying, retry_at: retry_at}
      })

    Phoenix.LiveView.send_update(component.pid, SelectedItemStatusComponent,
      id: "retry-status",
      tick: DateTime.add(retry_at, -60, :second)
    )

    assert has_element?(
             component,
             "#status-badge-container.tooltip.tooltip-open[data-tip]"
           )
  end

  test "refreshes the countdown for the active deadline", %{conn: conn} do
    retry_at = DateTime.add(DateTime.utc_now(), 30, :second)

    {:ok, component, _html} =
      live_component_isolated(conn, SelectedItemStatusComponent, %{
        id: "retry-status",
        status: :retrying,
        item: %Task{status: :retrying, retry_at: retry_at}
      })

    Phoenix.LiveView.send_update(component.pid, SelectedItemStatusComponent,
      id: "retry-status",
      tick: retry_at
    )

    assert has_element?(
             component,
             "#status-badge-container.tooltip.tooltip-open[data-tip]"
           )
  end

  test "uses the earliest retry deadline for a mapped task group", %{conn: conn} do
    now = DateTime.utc_now()

    {:ok, component, _html} =
      live_component_isolated(conn, SelectedItemStatusComponent, %{
        id: "retry-status",
        status: :retrying,
        item: [
          %Task{status: :retrying, retry_at: DateTime.add(now, -1, :second)},
          %Task{status: :retrying, retry_at: DateTime.add(now, 30, :second)}
        ]
      })

    refute has_element?(component, "#status-badge-container.tooltip")
  end

  test "ignores a retry deadline for a non-retrying status", %{conn: conn} do
    retry_at = DateTime.add(DateTime.utc_now(), 30, :second)

    {:ok, component, _html} =
      live_component_isolated(conn, SelectedItemStatusComponent, %{
        id: "retry-status",
        status: :succeeded,
        item: %Task{status: :retrying, retry_at: retry_at}
      })

    refute has_element?(component, "#status-badge-container.tooltip")
    refute has_element?(component, "#status-badge-container[data-tip]")
  end

  test "has no retry deadline when a mapped task group has no retrying tasks", %{conn: conn} do
    {:ok, component, _html} =
      live_component_isolated(conn, SelectedItemStatusComponent, %{
        id: "retry-status",
        status: :retrying,
        item: [%Task{status: :succeeded}]
      })

    refute has_element?(component, "#status-badge-container.tooltip")
    refute has_element?(component, "#status-badge-container[data-tip]")
  end
end
