defmodule GustWeb.CoreComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias GustWeb.Layouts

  test "flash group renders warning flashes" do
    document =
      render_component(&Layouts.flash_group/1,
        flash: %{"warning" => "History is pinned"}
      )
      |> LazyHTML.from_fragment()

    assert [{"div", _attributes, content}] =
             document
             |> LazyHTML.query("#flash-warning .alert.alert-warning")
             |> LazyHTML.to_tree()

    assert content
           |> LazyHTML.from_tree()
           |> LazyHTML.text()
           |> String.contains?("History is pinned")
  end
end
