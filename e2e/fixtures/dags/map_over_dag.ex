defmodule MapOverDag do
  use Gust.DSL

  task :produce, downstream: [:double], save: true do
    [1, 2, 3]
  end

  task :double, downstream: [:check], map_over: :produce, ctx: %{params: params}, save: true do
    %{value: params["item"] * 2}
  end

  task :check, ctx: %{run_id: run_id} do
    values =
      "double"
      |> Gust.Flows.get_tasks_by_name(run_id)
      |> Enum.map(& &1.result["value"])
      |> Enum.sort()

    if values != [2, 4, 6], do: raise("unexpected mapped results: #{inspect(values)}")
  end
end
