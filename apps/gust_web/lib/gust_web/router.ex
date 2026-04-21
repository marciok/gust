defmodule GustWeb.Router do
  use GustWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {GustWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  defmacro gust_dashboard(path, opts \\ []) do
    opts =
      if Macro.quoted_literal?(opts) do
        Macro.prewalk(opts, &expand_alias(&1, __CALLER__))
      else
        opts
      end

    quote bind_quoted: binding() do
      scope path, alias: false, as: false do
        import Phoenix.Router, only: [get: 4]
        import Phoenix.LiveView.Router, only: [live: 4, live_session: 3]

        {session_name, session_opts, route_opts} = GustWeb.Router.__options__(opts)

        live_session session_name, session_opts do
          # Gust assets
          get "/css-:md5", GustWeb.Dashboard.Assets, :css, as: :live_dashboard_asset
          get "/js-:md5", GustWeb.Dashboard.Assets, :js, as: :live_dashboard_asset

          get "/", PageController, :home
          live "/dags", DagLive.Index, :index
          live "/dags/:name/dashboard", DagLive.Dashboard, :dashboard
          live "/dags/:name/runs", RunLive.Index, :index
          live "/secrets", SecretLive.Index, :index
          live "/secrets/new", SecretLive.Index, :new
          live "/secrets/:id/edit", SecretLive.Index, :edit
        end
      end
    end
  end

  defp expand_alias({:__aliases__, _, _} = alias, env),
    do: Macro.expand(alias, %{env | function: {:live_dashboard, 2}})

  defp expand_alias(other, _env), do: other

  def __options__(options) do
    live_socket_path = Keyword.get(options, :live_socket_path, "/live")
    repo = Keyword.get(options, :repo)

    session_args = [repo]

    {
      :gust_dashboard,
      [
        session: {__MODULE__, :__session__, session_args},
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

  auth_enabled? = Application.compile_env(:gust_web, :basic_auth)

  if auth_enabled? do
    defp basic_auth(conn, _opts) do
      Plug.BasicAuth.basic_auth(conn,
        username: System.get_env("BASIC_AUTH_USER"),
        password: System.get_env("BASIC_AUTH_PASS")
      )
    end
  end

  scope "/", GustWeb do
    pipe_through if auth_enabled?, do: [:browser, :basic_auth], else: :browser

    get "/", PageController, :home
    live "/dags", DagLive.Index, :index
    live "/dags/:name/dashboard", DagLive.Dashboard, :dashboard
    live "/dags/:name/runs", RunLive.Index, :index
    live "/secrets", SecretLive.Index, :index
    live "/secrets/new", SecretLive.Index, :new
    live "/secrets/:id/edit", SecretLive.Index, :edit
  end

  if Application.compile_env(:gust_web, :mcp_enabled) do
    scope "/", GustWeb do
      match :*, "/.well-known/*path", WellKnownController, :not_found
    end

    scope "/mcp", GustWeb do
      pipe_through :api

      post "/server", MCPController, :message
      get "/server/.well-known/oauth-authorization-server", WellKnownController, :not_found
    end
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:gust_web, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: GustWeb.Telemetry
      # forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
