defmodule Gust.DNSCluster do
  @moduledoc false

  def parse_query(nil), do: :ignore

  def parse_query(term) when is_binary(term),
    do:
      String.split(term, ",")
      |> Enum.map(&String.trim(&1))
      |> Enum.reject(fn query -> query == "" end)
end
