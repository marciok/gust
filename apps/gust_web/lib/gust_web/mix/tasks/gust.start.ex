defmodule Mix.Tasks.Gust.Start do
  @moduledoc false
  use Mix.Task

  # coveralls-ignore-start
  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("gust.dags.boot")
    Mix.Task.run("phx.server")
  end

  # coveralls-ignore-stop
end
