defmodule Gust.PersistentTermCache do
  @moduledoc """
  A cache backed by `:persistent_term` that supports automatic reloading
  and validation of cached entries.

  This is useful for caching values that are expensive to compute and need to
  be recomputed only when necessary.

  ## Examples

      iex> Gust.PersistentTermCache.fetch_or_reload(:my_key,
        fn -> {:value, :erlang.phash2(:value)} end,
        fn
          ({_value, hash}) -> hash == :calculate_hash_fun_result
          (_) -> false
        end)
      :value
  """

  @doc """
  Fetches the cached value for the given key, or reloads it if the cache is invalid.
  The cache validity is determined by the provided `valid_fun`.
  """
  @spec fetch_or_reload(term(), (-> {term(), term()}), (term(), term() -> boolean())) :: term()
  def fetch_or_reload(cache_key, reload_fun, valid_fun) when is_function(valid_fun, 2) do
    with {value, _} = cached <- :persistent_term.get(cache_key, nil),
         true <- cache_valid?(cached, valid_fun) do
      value
    else
      _ ->
        reload(cache_key, reload_fun)
    end
  end

  @doc """
  Forces a reload of the cached value for the given key using the provided `reload_fun`.
  Updates the persistent cache with the new value.
  """
  @spec reload(term(), (-> {term(), term()})) :: term()
  def reload(cache_key, reload_fun) when is_function(reload_fun, 0) do
    {value, _hash} = store_val = reload_fun.()
    :ok = :persistent_term.put(cache_key, store_val)
    value
  end

  defp cache_valid?({value, hash}, valid_fun), do: valid_fun.(value, hash)
end
