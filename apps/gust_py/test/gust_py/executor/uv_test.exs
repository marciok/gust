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
    old_passthrough = Application.get_env(:gust_py, :env_passthrough)
    old_clear_env = Application.get_env(:gust_py, :clear_env)

    Application.put_env(:gust, :dags_folder, "/tmp/dags")

    System.put_env(%{
      "GUST_UV_TEST_SECRET" => "leaked",
      "UV_CACHE_DIR" => "/tmp/uv-cache",
      "GUST_UV_TEST_ALLOWED" => "allowed"
    })

    on_exit(fn ->
      restore_app_env(:gust, :dags_folder, old_gust_dags)
      restore_app_env(:gust_py, :uv_working_dir, old_uv_dir)
      restore_app_env(:gust_py, :env_passthrough, old_passthrough)
      restore_app_env(:gust_py, :clear_env, old_clear_env)
      Enum.each(~w(GUST_UV_TEST_SECRET UV_CACHE_DIR GUST_UV_TEST_ALLOWED), &System.delete_env/1)

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

  test "run/1 returns an error when uv is not found on PATH" do
    System.put_env("PATH", "")

    assert {:error, :uv_not_found} = UV.run(["hello"])
  end

  test "run_exec/1 passes args and sets UV_WORKING_DIR from gust_py override" do
    Application.put_env(:gust, :dags_folder, "/tmp/dags")
    Application.put_env(:gust_py, :uv_working_dir, "/custom/uv")

    os_pid = UV.run_exec(["alpha", "beta"])

    assert is_integer(os_pid)
    output = collect_stdout(os_pid)

    assert output =~ "UV_WORKING_DIR=/custom/uv"
    assert output =~ "ARGS=alpha beta"
  end

  test "start_task/3 passes the dag info and encoded context" do
    Application.put_env(:gust, :dags_folder, "/tmp/dags")
    Application.delete_env(:gust_py, :uv_working_dir)

    dag_def = %Gust.DAG.Definition{
      name: "demo_dag",
      mod: "DemoDag",
      file_path: "/tmp/dags/demo.py"
    }

    context = %{"attempt" => 1, "owner" => "gust"}
    expected_ctx = Jason.encode!(context)

    os_pid = UV.start_task(dag_def, "task_alpha", context)

    assert is_integer(os_pid)
    output = collect_stdout(os_pid)

    assert output =~ "UV_WORKING_DIR=/tmp/dags"

    assert output =~
             "ARGS=run gust task run --file /tmp/dags/demo.py --dag DemoDag --task task_alpha --ctx-json #{expected_ctx}"
  end

  test "uv inherits the runtime environment by default" do
    {output, 0} = UV.run(["hello"])
    assert output =~ "SECRET=leaked"

    output = ["hello"] |> UV.run_exec() |> collect_stdout()
    assert output =~ "BINDIR=#{System.get_env("BINDIR")}"
    assert output =~ "UV_WORKING_DIR=/tmp/dags"
  end

  test "run/1 hides the runtime environment from uv when :clear_env is set" do
    Application.put_env(:gust_py, :clear_env, true)

    {output, 0} = UV.run(["hello"])

    assert output =~ "SECRET=\n"
    assert output =~ "BINDIR=\n"
    assert output =~ "UV_CACHE_DIR=/tmp/uv-cache"
    assert output =~ "HOME=#{System.get_env("HOME")}"
    assert output =~ "PATH=#{System.get_env("PATH")}"
  end

  test "run_exec/1 hides the runtime environment from uv when :clear_env is set" do
    Application.put_env(:gust_py, :clear_env, true)

    output = ["hello"] |> UV.run_exec() |> collect_stdout()

    assert output =~ "BINDIR=\n"
    assert output =~ "ALLOWED=\n"
    assert output =~ "UV_CACHE_DIR=/tmp/uv-cache"
    assert output =~ "HOME=#{System.get_env("HOME")}"
    assert output =~ "PATH=#{System.get_env("PATH")}"
  end

  test "passes the variables listed in :env_passthrough when :clear_env is set" do
    Application.put_env(:gust_py, :clear_env, true)
    Application.put_env(:gust_py, :env_passthrough, ["GUST_UV_TEST_ALLOWED"])

    {output, 0} = UV.run(["hello"])
    assert output =~ "ALLOWED=allowed"
    assert output =~ "SECRET=\n"

    output = ["hello"] |> UV.run_exec() |> collect_stdout()
    assert output =~ "ALLOWED=allowed"
    assert output =~ "SECRET=\n"
  end

  defp collect_stdout(os_pid, acc \\ "") do
    receive do
      {:stdout, ^os_pid, data} -> collect_stdout(os_pid, acc <> data)
      {:DOWN, ^os_pid, :process, _pid, _reason} -> acc
    after
      1_000 -> flunk("timed out waiting for process output and exit")
    end
  end

  defp uv_script do
    """
    #!/bin/sh
    echo "UV_WORKING_DIR=$UV_WORKING_DIR"
    echo "ARGS=$*"
    echo "SECRET=$GUST_UV_TEST_SECRET"
    echo "BINDIR=$BINDIR"
    echo "ALLOWED=$GUST_UV_TEST_ALLOWED"
    echo "UV_CACHE_DIR=$UV_CACHE_DIR"
    echo "HOME=$HOME"
    echo "PATH=$PATH"
    """
  end

  defp restore_app_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_app_env(app, key, value), do: Application.put_env(app, key, value)
end
