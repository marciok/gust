defmodule DNSClusterTest do
  alias Gust.DNSCluster
  use Gust.DataCase

  describe "parse_query/1" do
    test "when term is nil returns ignore" do
      assert :ignore = DNSCluster.parse_query(nil)
    end

    test "when term is binary and not a list" do
      assert ["app"] = DNSCluster.parse_query("app")
    end

    test "when term is binary and a list" do
      assert ["app", "background"] = DNSCluster.parse_query("app,background")
    end
  end
end
