defmodule GustWeb.DashboardRouter do
  @moduledoc """
  Router macro that mounts the Gust dashboard at a chosen path.

  Import this module into your Phoenix router and call `gust_dashboard/2`
  inside a `scope` block:

      import GustWeb.DashboardRouter

      scope "/" do
        pipe_through :browser
        gust_dashboard "/gust"
      end
  """

  defmacro gust_dashboard(path, opts \\ []) do
    opts =
      if Macro.quoted_literal?(opts) do
        Macro.prewalk(opts, &expand_alias(&1, __CALLER__))
      else
        opts
      end

    quote bind_quoted: binding() do
      scope path, alias: false, as: false do
        import Phoenix.Router, only: [get: 3, get: 4]
        import Phoenix.LiveView.Router, only: [live: 3, live: 4, live_session: 3]

        {session_name, session_opts, route_opts} = GustWeb.DashboardRouter.__options__(opts)

        live_session session_name, session_opts do
          get "/css-:md5", GustWeb.Dashboard.Assets, :css, as: :gust_dashboard_asset
          get "/js-:md5", GustWeb.Dashboard.Assets, :js, as: :gust_dashboard_asset

          live "/dags", GustWeb.DagLive.Index, :index
          live "/dags/:name/dashboard", GustWeb.DagLive.Dashboard, :dashboard
          live "/dags/:name/runs", GustWeb.RunLive.Index, :index
          live "/secrets", GustWeb.SecretLive.Index, :index
          live "/secrets/new", GustWeb.SecretLive.Index, :new
          live "/secrets/:id/edit", GustWeb.SecretLive.Index, :edit
        end
      end
    end
  end

  defp expand_alias({:__aliases__, _, _} = alias, env),
    do: Macro.expand(alias, %{env | function: {:gust_dashboard, 2}})

  defp expand_alias(other, _env), do: other

  def __options__(options) do
    live_socket_path = Keyword.get(options, :live_socket_path, "/live")
    repo = Keyword.get(options, :repo)

    {
      :gust_dashboard,
      [
        session: {__MODULE__, :__session__, [repo]},
        root_layout: {GustWeb.Layouts, :root},
        on_mount: options[:on_mount] || nil
      ],
      [
        private: %{live_socket_path: live_socket_path},
        as: :gust_dashboard
      ]
    }
  end

  def __session__(_conn, repo) do
    %{"repo" => repo || Application.get_env(:gust, :repo)}
  end
end
