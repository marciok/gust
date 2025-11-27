defmodule Mix.Tasks.Gust.Ecto.Migrate do
  @moduledoc false
  require Logger
  use Mix.Task

  # coveralls-ignore-start
  @impl Mix.Task
  def run(_args) do
    Logger.info("Migrating Gust")
    Mix.Task.run("mix ecto.migrate --repo Gust.Repo")
  end

  # coveralls-ignore-stop
end
