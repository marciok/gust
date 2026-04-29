defmodule Gust.DNSCluster do
  @moduledoc false

  def parse_query(nil), do: :ignore
  def parse_query(term) when is_binary(term), do: String.split(term, ",")
end
