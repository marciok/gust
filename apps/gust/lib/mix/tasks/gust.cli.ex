defmodule Mix.Tasks.Gust.Cli do
  use Mix.Task

  @moduledoc false

  @impl Mix.Task
  def run(args) do
    System.put_env("GUST_ROLE", System.get_env("GUST_ROLE", "console"))
    result = Gust.CLI.exec(args)
    Mix.shell().info(result)
  end
end
