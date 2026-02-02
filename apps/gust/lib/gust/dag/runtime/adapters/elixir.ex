defmodule Gust.DAG.Runtime.Adapters.Elixir do
  @moduledoc false

  @behaviour Gust.DAG.Runtime.Adapter

  alias Gust.DAG.Compiler
  alias Gust.DAG.Definition

  @impl true
  def setup(%Definition{} = dag_def) do
    runtime_mod = Compiler.compile(dag_def)
    %{dag_def | mod: runtime_mod}
  end

  @impl true
  def teardown(%Definition{mod: mod}) do
    Compiler.purge(mod)
  end
end
