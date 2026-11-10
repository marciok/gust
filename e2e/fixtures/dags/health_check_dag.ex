defmodule HealthCheckDag do
  use Gust.DSL

  task :wait do
    Process.sleep(90_000)
  end
end
