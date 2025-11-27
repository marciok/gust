defmodule DSLTest do
  use Gust.DataCase

  test "task macro without schedule option" do
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

  test "task macro without downstream opts" do
    dag_code = """
      defmodule MyValidDagEmpty do
        use Gust.DSL

        task :bye do
          # saying bye
          2 + 2
        end

        task :hi, downstreams: [:bye] do
          # saying hi
          1 + 1
        end

      end
    """

    [{mod, _bin}] = Code.compile_string(dag_code)

    assert mod.__dag_tasks__() == [{:hi, [downstreams: [:bye]]}, {:bye, []}]

    :code.purge(mod)
    :code.delete(mod)
  end
end
