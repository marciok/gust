defmodule DNSClusterTest do
  alias Gust.DNSCluster
  use Gust.DataCase

  describe "parse_query/1" do
    test "when term is nil returns ignore" do
      assert :ignore = DNSCluster.parse_query(nil)
    end

    test "when term is a single term string" do
      assert ["app"] = DNSCluster.parse_query("app")
    end

    test "when term is a comma-separated string" do
      assert ["app", "background"] = DNSCluster.parse_query("app ,background ")
      assert ["app", "background"] = DNSCluster.parse_query("app,background")
    end

    test "when term is an empty string" do
      assert [] = DNSCluster.parse_query("")
    end
  end
end
