defmodule GustWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use GustWeb, :html

  alias GustWeb.Dashboard.Assets

  embed_templates "layouts/*"

  @doc false
  def asset_path(conn, asset) when asset in [:css, :js] do
    hash = Assets.current_hash(asset)
    prefix = String.trim_trailing(GustWeb.DashboardPath.base(), "/")

    Phoenix.VerifiedRoutes.unverified_path(
      conn,
      conn.private.phoenix_router,
      "#{prefix}/#{asset}-#{hash}"
    )
  end

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div id="app-shell" class="app-shell">
      <div class="app-shell__body">
        <header id="mobile-app-bar" class="mobile-app-bar">
          <.link navigate={~g"/dags"} class="mobile-app-bar__brand">
            <img src={~g"/images/gust-logo.svg"} alt="Gust" class="mobile-app-bar__logo" />
            <span class="gust-wordmark">Gust</span>
          </.link>
          <div class="mobile-app-bar__actions">
            <.theme_toggle id="mobile-theme-toggle" compact />
            <button
              type="button"
              id="mobile-navigation-button"
              class="mobile-app-bar__menu-button"
              aria-label="Open navigation"
              aria-controls="app-sidebar"
              aria-expanded="false"
              phx-click={mobile_navigation(:open)}
            >
              <.icon name="hero-bars-3" class="size-5" />
            </button>
          </div>
        </header>

        <button
          type="button"
          id="mobile-navigation-backdrop"
          class="sidebar-backdrop"
          aria-label="Close navigation"
          tabindex="-1"
          phx-click={mobile_navigation(:closed)}
        ></button>

        <aside
          id="app-sidebar"
          class="sidebar"
          aria-label="Application navigation"
          phx-window-keydown={mobile_navigation(:closed)}
          phx-key="escape"
        >
          <div class="sidebar__brand">
            <img src={~g"/images/gust-logo.svg"} alt="Gust" class="sidebar__logo" />
            <span class="gust-wordmark">Gust</span>
            <button
              type="button"
              id="mobile-navigation-close"
              class="sidebar__close"
              aria-label="Close navigation"
              phx-click={mobile_navigation(:closed)}
            >
              <.icon name="hero-x-mark" class="size-5" />
            </button>
          </div>
          <nav id="primary-navigation" class="sidebar__links" aria-label="Primary navigation">
            <.link
              id="nav-dags"
              navigate={~g"/dags"}
              class="sidebar__link"
              phx-click={mobile_navigation(:closed)}
            >
              <.icon name="hero-queue-list" class="h-5 w-5 text-sky-600" />
              <span>DAGs</span>
            </.link>

            <.link
              id="nav-secrets"
              navigate={~g"/secrets"}
              class="sidebar__link"
              phx-click={mobile_navigation(:closed)}
            >
              <.icon name="hero-lock-closed" class="h-5 w-5 text-sky-600" />
              <span>Secrets</span>
            </.link>

            <.link
              id="nav-system"
              navigate={~g"/system"}
              class="sidebar__link"
              phx-click={mobile_navigation(:closed)}
            >
              <.icon name="hero-server-stack" class="h-5 w-5 text-sky-600" />
              <span>System</span>
            </.link>
          </nav>
          <div class="sidebar__footer">
            <.theme_toggle id="sidebar-theme-toggle" />
          </div>
        </aside>

        <main
          id="app-content"
          class={["min-w-0", "max-w-full", "flex-1", "overflow-y-auto"]}
        >
          <div class="app-shell__content">
            <div class={["container", "mx-auto", "min-w-0", "max-w-full", "flex-1", "w-full"]}>
              {render_slot(@inner_block)}
            </div>
          </div>
        </main>
      </div>

      <.flash_group flash={@flash} />
    </div>
    """
  end

  defp mobile_navigation(:open) do
    JS.add_class(%JS{}, "app-shell--mobile-navigation-open", to: "#app-shell")
    |> JS.set_attribute({"aria-expanded", true}, to: "#mobile-navigation-button")
    |> JS.focus(to: "#mobile-navigation-close")
  end

  defp mobile_navigation(:closed) do
    JS.remove_class(%JS{}, "app-shell--mobile-navigation-open", to: "#app-shell")
    |> JS.set_attribute({"aria-expanded", false}, to: "#mobile-navigation-button")
    |> JS.focus(to: "#mobile-navigation-button")
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div
      class="fixed left-1/2 transform -translate-x-1/2 z-50 max-w-md w-full"
      id={@id}
      aria-live="polite"
    >
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:warning} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  The client-side theme controller in app.js applies and persists the theme.
  """
  attr :id, :string, required: true
  attr :compact, :boolean, default: false

  def theme_toggle(assigns) do
    ~H"""
    <button
      type="button"
      id={@id}
      class={["theme-toggle", @compact && "theme-toggle--compact"]}
      data-theme-toggle
      aria-label="Switch to dark mode"
      aria-pressed="false"
      title="Switch to dark mode"
    >
      <.icon name="hero-moon" class="theme-toggle__icon theme-toggle__icon--moon size-5" />
      <.icon name="hero-sun" class="theme-toggle__icon theme-toggle__icon--sun size-5" />
      <span class={[@compact && "sr-only", !@compact && "theme-toggle__label"]}>Dark mode</span>
    </button>
    """
  end
end
