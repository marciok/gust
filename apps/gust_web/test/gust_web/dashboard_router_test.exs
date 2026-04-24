defmodule GustWeb.DashboardRouterTest do
  use GustWeb.ConnCase

  alias GustWeb.DashboardRouter

  describe "__options__/1" do
    test "returns default session name and layout" do
      {name, session_opts, _route_opts} = DashboardRouter.__options__([])

      assert name == :gust_dashboard
      assert session_opts[:root_layout] == {GustWeb.Layouts, :root}
    end

    test "defaults live_socket_path to /live" do
      {_name, _session_opts, route_opts} = DashboardRouter.__options__([])

      assert route_opts[:private][:live_socket_path] == "/live"
    end

    test "accepts custom live_socket_path" do
      {_name, _session_opts, route_opts} =
        DashboardRouter.__options__(live_socket_path: "/custom")

      assert route_opts[:private][:live_socket_path] == "/custom"
    end

    test "passes repo to session config" do
      {_name, session_opts, _route_opts} = DashboardRouter.__options__(repo: MyApp.Repo)

      assert {:__MODULE__, :__session__, [MyApp.Repo]} =
               put_elem(session_opts[:session], 0, :__MODULE__)
    end

    test "passes on_mount option" do
      {_name, session_opts, _route_opts} =
        DashboardRouter.__options__(on_mount: SomeHook)

      assert session_opts[:on_mount] == SomeHook
    end

    test "defaults on_mount to nil" do
      {_name, session_opts, _route_opts} = DashboardRouter.__options__([])

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
end
