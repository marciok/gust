defmodule GustWeb.Pagination do
  @moduledoc false

  use GustWeb, :html

  def total_pages(count, size), do: max(div(count + size - 1, size), 1)

  def parse_page(nil), do: 1

  def parse_page(page) do
    case Integer.parse(page) do
      {page, ""} when page > 0 -> page
      _invalid -> 1
    end
  end

  attr :id, :string, required: true
  attr :prefix, :string, required: true, doc: "prefixes the id of each button"
  attr :label, :string, required: true
  attr :page, :integer, required: true
  attr :total, :integer, required: true
  attr :event, :string, required: true
  attr :running, :integer, default: nil, doc: "the page to mark as currently running"
  attr :compact, :boolean, default: false
  attr :class, :string, default: nil

  def pagination(assigns) do
    ~H"""
    <nav id={@id} class={["flex justify-center", @class]} aria-label={@label}>
      <div class="join">
        <button
          id={"#{@prefix}-previous-page"}
          type="button"
          phx-click={@event}
          phx-value-page={@page - 1}
          disabled={@page == 1}
          class={["join-item btn", button_size(@compact)]}
          aria-label="Previous page"
        >
          <.icon name="hero-chevron-left" class={icon_size(@compact)} />
        </button>

        <%= for page_item <- items(@page, @total) do %>
          <span
            :if={page_item == :ellipsis}
            class={[
              "pagination-ellipsis join-item btn btn-disabled pointer-events-none",
              button_size(@compact)
            ]}
            aria-hidden="true"
          >
            …
          </span>
          <button
            :if={is_integer(page_item)}
            id={"#{@prefix}-page-#{page_item}"}
            type="button"
            phx-click={@event}
            phx-value-page={page_item}
            data-running={page_item == @running}
            class={[
              "join-item btn",
              button_size(@compact),
              page_item == @page && "btn-active",
              page_item == @running && "text-info font-bold"
            ]}
            aria-label={"Page #{page_item}"}
            aria-current={if(page_item == @page, do: "page", else: nil)}
          >
            {page_item}
          </button>
        <% end %>

        <button
          id={"#{@prefix}-next-page"}
          type="button"
          phx-click={@event}
          phx-value-page={@page + 1}
          disabled={@page == @total}
          class={["join-item btn", button_size(@compact)]}
          aria-label="Next page"
        >
          <.icon name="hero-chevron-right" class={icon_size(@compact)} />
        </button>
      </div>
    </nav>
    """
  end

  defp items(_page, total) when total <= 7, do: Enum.to_list(1..total)
  defp items(page, total) when page <= 4, do: [1, 2, 3, 4, 5, :ellipsis, total]

  defp items(page, total) when page >= total - 3,
    do: [1, :ellipsis | Enum.to_list((total - 4)..total)]

  defp items(page, total), do: [1, :ellipsis, page - 1, page, page + 1, :ellipsis, total]

  defp button_size(true), do: "btn-xs"
  defp button_size(false), do: "btn-sm"

  defp icon_size(true), do: "h-3 w-3"
  defp icon_size(false), do: "h-4 w-4"
end
