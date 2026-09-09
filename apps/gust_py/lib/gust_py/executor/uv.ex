defmodule GustPy.Executor.UV do
  @moduledoc false

  @behaviour GustPy.Executor

  @working_dir_flag "UV_WORKING_DIR"

  @impl true
  def start_task(dag_def, task_name, context) do
    args = task_args(dag_def, task_name, context)
    run_exec(args)
  end

  defp task_args(dag_def, task_name, task_context) do
    [
      "run",
      "gust",
      "task",
      "run",
      "--file",
      dag_def.file_path,
      "--dag",
      dag_def.mod,
      "--task",
      task_name,
      "--ctx-json",
      Jason.encode!(task_context)
    ]
  end

  @impl true
  def run(args_list) do
    System.cmd(exec(), ["run", "gust" | args_list], env: %{@working_dir_flag => working_dir()})
  end

  def run_exec(args_list) do
    working_dir = working_dir()

    {:ok, _exec_pid, os_pid} =
      :exec.run([exec() | args_list], [
        :stdin,
        {:stdout, self()},
        {:stderr, self()},
        :monitor,
        {:group, 0},
        :kill_group,
        {:kill_timeout, 5},
        {:env, [{@working_dir_flag, working_dir}]}
      ])

    os_pid
  end

  defp working_dir do
    dag_folder = Application.get_env(:gust, :dags_folder)
    Application.get_env(:gust_py, :uv_working_dir, dag_folder)
  end

  defp exec, do: System.find_executable("uv")
end
