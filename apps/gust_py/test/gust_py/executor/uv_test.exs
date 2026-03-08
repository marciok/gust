defmodule GustPy.Executor.UVTest do
  use ExUnit.Case, async: false
  alias GustPy.Executor.UV

  setup do
    tmp_dir =
      Path.join(System.tmp_dir!(), "gust_py_uv_test_#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp_dir)

    uv_path = Path.join(tmp_dir, "uv")
    File.write!(uv_path, uv_script())
    File.chmod!(uv_path, 0o755)

    old_path = System.get_env("PATH")

    new_path =
      case old_path do
        nil -> tmp_dir
        "" -> tmp_dir
        _ -> tmp_dir <> ":" <> old_path
      end

    System.put_env("PATH", new_path)

    old_gust_dags = Application.get_env(:gust, :dags_folder)
    old_uv_dir = Application.get_env(:gust_py, :uv_working_dir)
    old_uv_test_output = System.get_env("UV_TEST_OUTPUT")

    System.delete_env("UV_TEST_OUTPUT")

    on_exit(fn ->
      restore_app_env(:gust, :dags_folder, old_gust_dags)
      restore_app_env(:gust_py, :uv_working_dir, old_uv_dir)
      restore_env_var("UV_TEST_OUTPUT", old_uv_test_output)

      case old_path do
        nil -> System.delete_env("PATH")
        _ -> System.put_env("PATH", old_path)
      end

      File.rm_rf!(tmp_dir)
    end)

    {:ok, tmp_dir: tmp_dir}
  end

  test "run/1 uses UV_WORKING_DIR from gust :dags_folder when override not set" do
    Application.put_env(:gust, :dags_folder, "/tmp/dags")
    Application.delete_env(:gust_py, :uv_working_dir)

    {output, status} = UV.run(["hello"])

    assert status == 0
    assert output =~ "UV_WORKING_DIR=/tmp/dags"
    assert output =~ "ARGS=run gust hello"
  end

  test "open_port/1 passes args and sets UV_WORKING_DIR from gust_py override", %{
    tmp_dir: tmp_dir
  } do
    Application.put_env(:gust, :dags_folder, "/tmp/dags")
    Application.put_env(:gust_py, :uv_working_dir, "/custom/uv")

    output_file = Path.join(tmp_dir, "port_output.txt")
    port = UV.open_port(["--write-file", output_file, "alpha", "beta"])

    assert is_port(port)
    assert_receive {^port, {:exit_status, 0}}, 1_000

    contents = File.read!(output_file)
    assert contents =~ "UV_WORKING_DIR=/custom/uv"
    assert contents =~ "ARGS=alpha beta"
  end

  test "start_task_via_port/3 passes the dag info and encoded context", %{
    tmp_dir: tmp_dir
  } do
    Application.put_env(:gust, :dags_folder, "/tmp/dags")
    Application.delete_env(:gust_py, :uv_working_dir)

    output_file = Path.join(tmp_dir, "task_output.txt")
    System.put_env("UV_TEST_OUTPUT", output_file)

    dag_def = %Gust.DAG.Definition{name: "demo_dag", file_path: "/tmp/dags/demo.py"}
    context = %{"attempt" => 1, "owner" => "gust"}
    expected_ctx = Jason.encode!(context)

    port = UV.start_task_via_port(dag_def, "task_alpha", context)

    assert is_port(port)
    assert_receive {^port, {:exit_status, 0}}, 1_000

    contents = File.read!(output_file)
    assert contents =~ "UV_WORKING_DIR=/tmp/dags"

    assert contents =~
             "ARGS=run gust task run --file /tmp/dags/demo.py --dag nil --task task_alpha --ctx-json #{expected_ctx}"
  end

  defp uv_script do
    """
    #!/bin/sh
    if [ -n "$UV_TEST_OUTPUT" ]; then
      {
        echo "UV_WORKING_DIR=$UV_WORKING_DIR"
        echo "ARGS=$*"
      } > "$UV_TEST_OUTPUT"
      exit 0
    fi
    if [ "$1" = "--write-file" ]; then
      file="$2"
      shift 2
      {
        echo "UV_WORKING_DIR=$UV_WORKING_DIR"
        echo "ARGS=$*"
      } > "$file"
      exit 0
    fi
    echo "UV_WORKING_DIR=$UV_WORKING_DIR"
    echo "ARGS=$*"
    """
  end

  defp restore_app_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_app_env(app, key, value), do: Application.put_env(app, key, value)

  defp restore_env_var(key, nil), do: System.delete_env(key)
  defp restore_env_var(key, value), do: System.put_env(key, value)
end
