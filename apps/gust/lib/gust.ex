defmodule Gust do
  @moduledoc """
  Gust keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """
  @env Application.compile_env(:gust, :env)

  @doc """
  Returns the current compile-time environment for the Gust application.

  This value should be used in place of `Mix.env()` because the later is only
  available at build time.
  """
  @spec env() :: atom()
  def env, do: @env
end
