defmodule DAG.Runtime.Adapters.ElixirTest do
  use Gust.DataCase
  alias Gust.DAG.Runtime.Adapters.Elixir, as: Adapter
  alias Gust.DAG.Definition
  import Gust.FSHelpers

  @original_mod_name "TheOffspring"

  setup do
    content = """
      defmodule #{@original_mod_name} do
        
      end
    """

    dir = make_rand_dir!("dags")
    dag_name = "the_offspring"
    file_path = "#{dir}/#{dag_name}.ex"
    File.write!(file_path, content)

    dag_def = %Definition{
      file_path: file_path,
      mod: Module.concat([@original_mod_name])
    }

    %{original_def: dag_def}
  end

  describe "setup/2" do
    test "module is compiled and available", %{original_def: dag_def} do
      runtime_id = 12345
      %{mod: updated_mod} = Adapter.setup(dag_def, runtime_id)
      assert Code.ensure_loaded?(updated_mod)
      assert "Elixir.Gust.Runner.#{@original_mod_name}_#{runtime_id}" == to_string(updated_mod)
    end
  end

  describe "teardown/1" do
    test "purge code", %{original_def: dag_def} do
      Adapter.teardown(dag_def, nil)

      assert Code.ensure_loaded?(dag_def.mod) == false
    end
  end
end
