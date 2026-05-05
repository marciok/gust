defmodule GustWeb.DashboardRouterTest do
  use GustWeb.ConnCase

  alias GustWeb.DashboardRouter

  @dashboard_paths [
    "/images",
    "/css-:md5",
    "/js-:md5",
    "/dags",
    "/dags/:name/dashboard",
    "/dags/:name/runs",
    "/secrets",
    "/secrets/new",
    "/secrets/:id/edit"
  ]

  describe "gust_dashboard/1" do
    test "defines dashboard routes for opts" do
      quote do
        gust_dashboard(if 1 > 2, do: [repo: TestRepo], else: [])
      end
      |> dashboard_router()
      |> assert_dashboard_routes()
    end

    test "defines dashboard routes for literal options" do
      quote do
        gust_dashboard(repo: MyApp.Repo)
      end
      |> dashboard_router()
      |> assert_dashboard_routes()
    end
  end

  describe "__options__/1" do
    test "returns default session name and layout" do
      {name, session_opts} = DashboardRouter.__options__([])

      assert name == :gust_dashboard
      assert session_opts[:root_layout] == {GustWeb.Layouts, :root}
    end

    test "passes repo to session config" do
      {_name, session_opts} = DashboardRouter.__options__(repo: MyApp.Repo)

      assert {:__MODULE__, :__session__, [MyApp.Repo]} =
               put_elem(session_opts[:session], 0, :__MODULE__)
    end

    test "passes on_mount option" do
      {_name, session_opts} = DashboardRouter.__options__(on_mount: SomeHook)

      assert session_opts[:on_mount] == SomeHook
    end

    test "defaults on_mount to nil" do
      {_name, session_opts} = DashboardRouter.__options__([])

      assert session_opts[:on_mount] == nil
    end
  end

  describe "__session__/2" do
    test "returns repo from argument" do
      session = DashboardRouter.__session__(%Plug.Conn{}, MyApp.Repo)

      assert session == %{"repo" => MyApp.Repo}
    end

    test "falls back to app config when repo is nil" do
      session = DashboardRouter.__session__(%Plug.Conn{}, nil)

      assert session == %{"repo" => Application.get_env(:gust, :repo)}
    end
  end

  defp dashboard_router(gust_dashboard_call) do
    module = Module.concat(__MODULE__, "TestRouter#{System.unique_integer([:positive])}")

    {:module, ^module, _, _} =
      Module.create(
        module,
        quote do
          use Phoenix.Router
          import GustWeb.DashboardRouter

          scope "/" do
            unquote(gust_dashboard_call)
          end
        end,
        Macro.Env.location(__ENV__)
      )

    module
  end

  defp assert_dashboard_routes(module) do
    paths =
      module.__routes__()
      |> Enum.map(& &1.path)

    Enum.each(@dashboard_paths, fn path ->
      assert path in paths
    end)

    module
  end
end
