defmodule DAG.Compiler.CodeTest do
  alias DAG.Compiler
  use Gust.DataCase
  alias Gust.DAG.Compiler
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

    updated_mod = Compiler.Code.compile(dag_def)
    %{updated_mod: updated_mod}
  end

  describe "compile/1" do
    test "module is compiled and available", %{updated_mod: updated_mod} do
      assert Code.ensure_loaded?(updated_mod)
      assert "Elixir.Gust.Runner." <> random_udid = to_string(updated_mod)
      assert [@original_mod_name, _run_udid] = String.split(random_udid, "_")
    end
  end

  describe "purge/1" do
    test "purge code", %{updated_mod: updated_mod} do
      Compiler.Code.purge(updated_mod)

      assert Code.ensure_loaded?(updated_mod) == false
    end
  end
end
