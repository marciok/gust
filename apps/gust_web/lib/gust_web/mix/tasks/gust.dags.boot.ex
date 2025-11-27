defmodule Mix.Tasks.Gust.Dags.Boot do
  @moduledoc false
  use Mix.Task
  require Logger

  # coveralls-ignore-start
  @impl Mix.Task
  def run(_args) do
    Logger.info("Booting DAGs")
    Application.put_env(:gust, :boot_dag, true)
  end

  # coveralls-ignore-stop
end
