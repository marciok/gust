defmodule DSLTest do
  use Gust.DataCase

  test "use macro with schedule option" do
    dag_code = """
      defmodule MyValidDagEmpty do
        use Gust.DSL, schedule: "0 17 * * *"

        task :hi do
          # saying hi
          1 + 1
        end

      end
    """

    [{mod, _bin}] = Code.compile_string(dag_code)

    assert mod.__dag_options__() == [schedule: "0 17 * * *"]

    :code.purge(mod)
    :code.delete(mod)
  end

  test "task macro without opts" do
    dag_code = """
      defmodule MyValidDagEmpty do
        use Gust.DSL

        task :hi do
          # saying hi
          1 + 1
        end

      end
    """

    [{mod, _bin}] = Code.compile_string(dag_code)

    assert mod.__dag_tasks__() == [{:hi, []}]

    :code.purge(mod)
    :code.delete(mod)
  end

  test "task macro with context option" do
    run_id = 1234
    ctx = %{run_id: 1234}

    dag_code = """
      defmodule MyValidDagEmpty do
        use Gust.DSL

        task :hi, ctx: %{run_id: run_id} do
          run_id
        end

      end
    """

    [{mod, _bin}] = Code.compile_string(dag_code)
    assert mod.__dag_tasks__() == [{:hi, []}]

    # credo:disable-for-next-line Credo.Check.Refactor.Apply
    assert apply(mod, :hi, [ctx]) == run_id

    :code.purge(mod)
    :code.delete(mod)
  end

  test "task macro with save option" do
    dag_code = """
      defmodule MyValidDagEmpty do
        use Gust.DSL

        task :hi, save: true do
          # saying hi
          1 + 1
        end

      end
    """

    [{mod, _bin}] = Code.compile_string(dag_code)

    assert mod.__dag_tasks__() == [{:hi, [store_result: true]}]

    :code.purge(mod)
    :code.delete(mod)
  end

  test "task macro with store_result option" do
    dag_code = """
      defmodule MyValidDagEmpty do
        use Gust.DSL

        task :hi, store_result: true do
          # saying hi
          1 + 1
        end

      end
    """

    [{mod, _bin}] = Code.compile_string(dag_code)

    assert mod.__dag_tasks__() == [{:hi, [store_result: true]}]

    :code.purge(mod)
    :code.delete(mod)
  end

  test "task macro with map_over option and mapped context" do
    dag_code = """
      defmodule MyMappedDag do
        use Gust.DSL

        task :insert_models, map_over: :say_by, ctx: %{params: %{"model" => model}} do
          model
        end
      end
    """

    [{mod, _bin}] = Code.compile_string(dag_code)

    assert mod.__dag_tasks__() == [{:insert_models, [map_over: :say_by]}]
    assert mod.insert_models(%{params: %{"model" => "gpt-5"}}) == "gpt-5"

    :code.purge(mod)
    :code.delete(mod)
  end

  test "task macro supports the default scalar map_over item context" do
    dag_code = """
      defmodule MyScalarMappedDag do
        use Gust.DSL

        task :say_bye, map_over: :names, ctx: %{params: %{"item" => item}} do
          item
        end
      end
    """

    [{mod, _bin}] = Code.compile_string(dag_code)

    assert mod.say_bye(%{params: %{"item" => "MARCIO"}}) == "MARCIO"

    :code.purge(mod)
    :code.delete(mod)
  end

  test "task macro with downstream opts" do
    dag_code = """
      defmodule MyValidDagEmpty do
        use Gust.DSL

        task :bye do
          # saying bye
          2 + 2
        end

        task :hi, downstream: [:bye] do
          # saying hi
          1 + 1
        end

      end
    """

    [{mod, _bin}] = Code.compile_string(dag_code)

    assert mod.__dag_tasks__() == [{:hi, [downstream: [:bye]]}, {:bye, []}]

    :code.purge(mod)
    :code.delete(mod)
  end
end
