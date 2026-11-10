defmodule GustWeb.PaginationTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias GustWeb.Pagination

  describe "pagination/1" do
    test "lists every page when there are few" do
      assert page_labels(3, 7) == ["1", "2", "3", "4", "5", "6", "7"]
    end

    test "collapses the end near the first page" do
      assert page_labels(2, 20) == ["1", "2", "3", "4", "5", "…", "20"]
    end

    test "collapses the start near the last page" do
      assert page_labels(19, 20) == ["1", "…", "16", "17", "18", "19", "20"]
    end

    test "collapses both sides in the middle" do
      assert page_labels(10, 20) == ["1", "…", "9", "10", "11", "…", "20"]
    end
  end

  describe "total_pages/2" do
    test "rounds up" do
      assert Pagination.total_pages(5, 2) == 3
    end

    test "does not add a page for an exact fit" do
      assert Pagination.total_pages(4, 2) == 2
    end

    test "is at least one" do
      assert Pagination.total_pages(0, 2) == 1
    end
  end

  describe "parse_page/1" do
    test "parses a positive integer" do
      assert Pagination.parse_page("3") == 3
    end

    test "falls back to the first page" do
      assert Pagination.parse_page(nil) == 1
      assert Pagination.parse_page("abc") == 1
      assert Pagination.parse_page("0") == 1
      assert Pagination.parse_page("-2") == 1
      assert Pagination.parse_page("2x") == 1
    end
  end

  defp page_labels(page, total) do
    html =
      render_component(&Pagination.pagination/1,
        id: "pager",
        prefix: "test",
        label: "Test pagination",
        page: page,
        total: total,
        event: "select"
      )

    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#pager .join-item")
    |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))
    |> Enum.slice(1..-2//1)
  end
end
