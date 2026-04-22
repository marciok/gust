defmodule GustWeb.Router do
  use GustWeb, :router
  import GustWeb.DashboardRouter

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

  auth_enabled? = Application.compile_env(:gust_web, :basic_auth)

  if auth_enabled? do
    defp basic_auth(conn, _opts) do
      Plug.BasicAuth.basic_auth(conn,
        username: System.get_env("BASIC_AUTH_USER"),
        password: System.get_env("BASIC_AUTH_PASS")
      )
    end
  end

  scope "/" do
    pipe_through if auth_enabled?, do: [:browser, :basic_auth], else: :browser

    gust_dashboard("/")
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
