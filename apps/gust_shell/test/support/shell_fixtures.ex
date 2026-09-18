defmodule GustShell.TestFixtures do
  @moduledoc """
  This module provides test helpers and fixtures for shell DAG testing.
  """

  alias GustShell.Parser.Adapter, as: ParserAdapter

  @doc """
  Writes a YAML DAG definition to a temporary file and returns the file path.

  The returned path should be cleaned up using on_exit/1 callback.
  """
  def yaml_dag_fixture(yaml_content) when is_binary(yaml_content) do
    # Use timestamp and random to generate unique filename
    timestamp = System.os_time(:millisecond)
    random = :rand.uniform(100_000)
    tmp_file = Path.join(System.tmp_dir!(), "shell_dag_test_#{timestamp}_#{random}.yml")
    File.write!(tmp_file, yaml_content)
    tmp_file
  end

  @doc """
  Creates and parses a shell DAG definition from YAML content.

  Returns {:ok, dag_definition} tuple or {:error, reason}.
  """
  def parse_shell_dag(yaml_content) when is_binary(yaml_content) do
    tmp_file = yaml_dag_fixture(yaml_content)

    try do
      ParserAdapter.parse_file(tmp_file)
    after
      File.rm(tmp_file)
    end
  end

  @doc """
  Helper to create a simple sequential DAG YAML: task1 -> task2
  """
  def sequential_dag_yaml(opts \\ []) do
    cmd1 = Keyword.get(opts, :cmd1, "echo task1")
    cmd2 = Keyword.get(opts, :cmd2, "echo task2")

    """
    tasks:
      - name: task1
        run: #{cmd1}
        downstream: [task2]
      - name: task2
        run: #{cmd2}
    """
  end

  @doc """
  Helper to create a parallel DAG YAML: task1 -> [task2, task3]
  """
  def parallel_dag_yaml(opts \\ []) do
    cmd1 = Keyword.get(opts, :cmd1, "echo task1")
    cmd2 = Keyword.get(opts, :cmd2, "echo task2")
    cmd3 = Keyword.get(opts, :cmd3, "echo task3")

    """
    tasks:
      - name: task1
        run: #{cmd1}
        downstream: [task2, task3]
      - name: task2
        run: #{cmd2}
      - name: task3
        run: #{cmd3}
    """
  end

  @doc """
  Helper to create a DAG with environment variables and other options
  """
  def configured_dag_yaml(opts \\ []) do
    cmd1 = Keyword.get(opts, :cmd1, "echo $MY_VAR")
    env_var = Keyword.get(opts, :env_var, "my_value")

    """
    tasks:
      - name: configured_task
        run: #{cmd1}
        env:
          MY_VAR: #{env_var}
    """
  end

  @doc """
  Helper to create a DAG where a task fails
  """
  def failing_dag_yaml(opts \\ []) do
    fail_cmd = Keyword.get(opts, :fail_cmd, "exit 42")
    pass_cmd = Keyword.get(opts, :pass_cmd, "echo success")

    """
    tasks:
      - name: failing_task
        run: #{fail_cmd}
        downstream: [downstream_task]
      - name: downstream_task
        run: #{pass_cmd}
    """
  end
end
