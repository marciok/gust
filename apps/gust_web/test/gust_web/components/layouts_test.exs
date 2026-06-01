defmodule GustWeb.LayoutsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias GustWeb.Layouts

  test "renders connected nodes as options" do
    html =
      render_component(&Layouts.node_selector/1,
        nodes: [:"first@127.0.0.1", :"second@127.0.0.1"]
      )

    document = LazyHTML.from_fragment(html)

    assert [
             {"option", [{"disabled", ""}, {"selected", ""}], ["Nodes Connected"]},
             {"option", [], ["first@127.0.0.1"]},
             {"option", [], ["second@127.0.0.1"]}
           ] =
             document
             |> LazyHTML.query("#node-selector > option")
             |> LazyHTML.to_tree()
  end
end
