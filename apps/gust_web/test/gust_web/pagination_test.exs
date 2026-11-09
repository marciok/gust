defmodule GustWeb.PaginationTest do
  use ExUnit.Case, async: true

  alias GustWeb.Pagination

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
end
