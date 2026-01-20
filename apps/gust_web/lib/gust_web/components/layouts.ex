defmodule GustWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use GustWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

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
    <div class="app-shell">
      <div class="app-shell__body">
        <aside class="sidebar">
          <div class="sidebar__brand">
            <img src={~p"/images/gust-logo.png"} alt="Logo" />
            <h1 class="gust-wordmark">Gust</h1>
          </div>
          <nav class="sidebar__links">
            <.link navigate={~p"/dags"} class="sidebar__link">
              <.icon name="hero-queue-list" class="h-5 w-5 text-sky-600" />
              <span>DAGs</span>
            </.link>

            <.link navigate={~p"/secrets"} class="sidebar__link">
              <.icon name="hero-lock-closed" class="h-5 w-5 text-sky-600" />
              <span>Secrets</span>
            </.link>
          </nav>
        </aside>

        <main class="flex-1 overflow-y-auto">
          <div class="flex min-h-full flex-col gap-6 px-3 py-4">
            <div class="container mx-auto flex-1 w-full">
              {render_slot(@inner_block)}
            </div>
          </div>
        </main>
      </div>

      <footer class="app-footer w-full">
        <div class="app-footer__content">
          <div class="app-footer__meta">
            <select class="select">
              <option disabled selected>Nodes Connected</option>
              <option :for={node <- Node.list()}>{node}</option>
            </select>
            <span class="app-footer__value">{System.get_env("MIX_ENV")}</span>
          </div>
        </div>
      </footer>

      <.flash_group flash={@flash} />
    </div>
    """
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

  See <head> in root.html.heex which applies the theme before page load.
  """
end
