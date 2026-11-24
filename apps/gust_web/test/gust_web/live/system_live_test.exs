defmodule GustWeb.SystemLiveTest do
  use GustWeb.ConnCase

  import Phoenix.LiveViewTest
  import Gust.ApplicationEnvHelpers
  import Mox

  alias Gust.DAG.Definition

  setup :verify_on_exit!

  setup do
    stub(GustWeb.DAGLoaderMock, :get_definitions, fn -> %{} end)
    :ok
  end

  test "renders safe runtime and cluster information", %{conn: conn} do
    previous_role = System.get_env("GUST_ROLE")
    System.put_env("GUST_ROLE", "worker")

    on_exit(fn -> restore_env("GUST_ROLE", previous_role) end)

    {:ok, view, _html} = live(conn, ~g"/system")

    assert has_element?(view, "#system-page")
    assert view |> element("#system-role") |> render() =~ "worker"

    assert view |> element("#system-environment") |> render() =~
             to_string(Mix.env())

    assert view |> element("#current-node") |> render() =~ to_string(Node.self())
    assert has_element?(view, "#connected-node-count")
  end

  test "uses the default role when GUST_ROLE is absent", %{conn: conn} do
    previous_role = System.get_env("GUST_ROLE")
    System.delete_env("GUST_ROLE")

    on_exit(fn -> restore_env("GUST_ROLE", previous_role) end)

    {:ok, view, _html} = live(conn, ~g"/system")

    assert view |> element("#system-role") |> render() =~ "single"
  end

  test "shows the configured run dispatcher", %{conn: conn} do
    previous_dispatcher = Application.get_env(:gust, :run_dispatcher)
    Application.put_env(:gust, :run_dispatcher, Gust.PGNotifier.Worker)

    on_exit(fn -> restore_application_env(:gust, :run_dispatcher, previous_dispatcher) end)

    {:ok, view, _html} = live(conn, ~g"/system")

    assert view |> element("#system-run-dispatcher") |> render() =~
             to_string(Gust.PGNotifier.Worker)
  end

  test "reports that the theme follows the system preference", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~g"/system")

    assert has_element?(view, "#theme-preference")
    assert has_element?(view, "#theme-preference", "System preference")
  end

  describe "run pruning" do
    test "is off without prune_schedule", %{conn: conn} do
      replace_env(:runs, [])

      {:ok, view, _html} = live(conn, ~g"/system")

      assert view |> element("#pruning-status") |> render() =~ "Off"
      assert view |> element("#pruning-schedule") |> render() =~ "Not set"
      assert has_element?(view, "#pruning-hint")
      assert has_element?(view, "#pruning-dags-empty")
    end

    test "shows the schedule and the dags with retention", %{conn: conn} do
      replace_env(:runs, prune_schedule: "@daily")

      stub(GustWeb.DAGLoaderMock, :get_definitions, fn ->
        %{
          1 =>
            {:ok, %Definition{name: "minutely", options: [runs: [retention: [max_count: 50]]]}},
          2 => {:ok, %Definition{name: "no_retention", options: []}},
          3 => {:error, :enoent}
        }
      end)

      {:ok, view, _html} = live(conn, ~g"/system")

      assert view |> element("#pruning-status") |> render() =~ "On"
      assert view |> element("#pruning-schedule") |> render() =~ "@daily"
      refute has_element?(view, "#pruning-hint")
      assert view |> element("#pruning-dag-1") |> render() =~ "max_count: 50"
      assert has_element?(view, "#pruning-dag-1 a[href='/dags/minutely/dashboard']")
      refute has_element?(view, "#pruning-dag-2")
    end

    test "shows why an invalid schedule is off", %{conn: conn} do
      replace_env(:runs, prune_schedule: "@reboot")

      {:ok, view, _html} = live(conn, ~g"/system")

      assert view |> element("#pruning-status") |> render() =~ "Invalid schedule"
      assert view |> element("#pruning-error") |> render() =~ "@reboot is not supported"
      assert has_element?(view, "#pruning-hint")
    end
  end

  test "format_uptime/1 presents minutes, hours, and days compactly" do
    assert GustWeb.SystemLive.format_uptime(59) == "0m"
    assert GustWeb.SystemLive.format_uptime(3_660) == "1h 1m"
    assert GustWeb.SystemLive.format_uptime(90_060) == "1d 1h 1m"
  end

  defp restore_env(name, nil), do: System.delete_env(name)
  defp restore_env(name, value), do: System.put_env(name, value)

  defp restore_application_env(application, key, nil),
    do: Application.delete_env(application, key)

  defp restore_application_env(application, key, value),
    do: Application.put_env(application, key, value)
end
