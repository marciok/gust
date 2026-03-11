defmodule DAG.Runtime.Adapters.ElixirTest do
  use Gust.DataCase
  alias Gust.DAG.Definition
  alias Gust.DAG.Runtime.Adapters.Elixir, as: Adapter
  import Gust.FSHelpers

  @original_mod_name "TheOffspring"

  setup do
    content = """
      defmodule #{@original_mod_name} do
        def notify(status, pid) do
          send(pid, {:callback_called, status})
          :custom_result
        end
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
      runtime_id = 12_345
      %{mod: updated_mod} = Adapter.setup(dag_def, runtime_id)
      assert Code.ensure_loaded?(updated_mod)
      assert "Elixir.Gust.Runner.#{@original_mod_name}_#{runtime_id}" == to_string(updated_mod)
    end
  end

  describe "teardown/2" do
    test "purges code and returns :ok", %{original_def: dag_def} do
      dag_def = Adapter.setup(dag_def, "runtime")

      assert Code.ensure_loaded?(dag_def.mod)
      assert :ok = Adapter.teardown(dag_def, "runtime")
      assert Code.ensure_loaded?(dag_def.mod) == false
    end
  end

  describe "on_finished_callback/4" do
    test "invokes the callback and returns :ok", %{original_def: dag_def} do
      dag_def = Adapter.setup(dag_def, "runtime")

      assert :ok = Adapter.on_finished_callback(dag_def, :notify, self(), :ok)
      assert_receive {:callback_called, :ok}
    end
  end

  describe "kill/1" do
    test "kills the task process" do
      task_pid =
        spawn(fn ->
          Process.sleep(:infinity)
        end)

      ref = Process.monitor(task_pid)

      assert :ok = Adapter.kill(task_pid)
      assert_receive {:DOWN, ^ref, :process, ^task_pid, :killed}
    end
  end
end
