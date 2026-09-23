defmodule GustShell.Parser.AdapterTest do
  use ExUnit.Case, async: true

  import GustShell.TestFixtures

  alias Gust.DAG.Definition
  alias GustShell.Parser.Adapter

  test "builds a canonical definition with graph metadata and execution options" do
    assert {:ok, %Definition{} = definition} =
             parse_shell_dag("""
             schedule: "0 2 * * *"
             tasks:
               - name: backup
                 run: echo backup
                 downstream: [notify]
                 save: true
                 cwd: /tmp
                 env:
                   FOO: bar
                 kill_timeout: 10
               - name: notify
                 run: echo done
             """)

    assert definition.adapter == :shell
    assert definition.options == [schedule: "0 2 * * *"]
    assert definition.stages == [["backup"], ["notify"]]
    assert definition.task_list == ["backup", "notify"]
    assert definition.tasks["backup"].downstream == MapSet.new(["notify"])
    assert definition.tasks["notify"].upstream == MapSet.new(["backup"])
    assert definition.tasks["backup"].store_result
    refute definition.tasks["notify"].store_result
    assert definition.tasks["backup"].run == "echo backup"
    assert {:cd, "/tmp"} in definition.tasks["backup"].exec_opts
    assert {:env, [{"FOO", "bar"}]} in definition.tasks["backup"].exec_opts
    assert {:kill_timeout, 10} in definition.tasks["backup"].exec_opts
    refute Map.has_key?(definition.tasks["backup"], "cwd")
  end

  test "accepts an explicitly empty task list" do
    assert {:ok, %Definition{tasks: %{}, stages: [], task_list: []}} =
             parse_shell_dag("tasks: []")
  end

  for yaml <- [
        "schedule: '* * * * *'",
        "tasks: 123",
        "tasks: null",
        "tasks: {name: single, run: echo}",
        "tasks: [123]",
        "[]"
      ] do
    test "rejects malformed task structure #{yaml}" do
      assert {:error, {[], "invalid shell DAG", _}} = parse_shell_dag(unquote(yaml))
    end
  end

  for {fields, reason} <- [
        {"run: echo", "name must be"},
        {"name: example", "run must be"},
        {"name: example\n  run: 123", "run must be"},
        {"name: example\n  run: echo\n  downstream: other", "downstream must be"},
        {"name: example\n  run: echo\n  downstream: [123]", "downstream must be"},
        {"name: example\n  run: echo\n  save: 'true'", "must be a boolean"}
      ] do
    test "rejects invalid task fields #{fields}" do
      assert {:error, {[], "invalid shell DAG", reason}} =
               parse_shell_dag("tasks:\n- " <> unquote(fields))

      assert reason =~ unquote(reason)
    end
  end

  test "rejects unknown task options with the task name and allowed keys" do
    assert {:error, {[], "invalid shell DAG", reason}} =
             parse_shell_dag("tasks: [{name: backup, run: echo, kill_timout: 10}]")

    assert reason =~ ~s(task "backup")
    assert reason =~ ~s(unknown keys ["kill_timout"])
    assert reason =~ "allowed keys"
    assert reason =~ "kill_timeout"
  end

  test "rejects unknown DAG options" do
    assert {:error, {[], "invalid shell DAG", reason}} =
             parse_shell_dag("tasks: []\nschedul: '* * * * *'")

    assert reason =~ ~s(unknown keys ["schedul"])
  end

  test "rejects duplicate task names" do
    assert {:error, {[], "invalid shell DAG", reason}} =
             parse_shell_dag("tasks: [{name: same, run: echo}, {name: same, run: echo}]")

    assert reason =~ "task names must be unique"
  end

  test "rejects undefined downstream tasks" do
    assert {:error, {[], "invalid shell DAG", reason}} =
             parse_shell_dag("tasks: [{name: first, run: echo, downstream: [missing]}]")

    assert reason =~ "unknown downstream"
    assert reason =~ "missing"
  end

  test "returns an error for cycles" do
    assert {:error, {[], "invalid shell DAG", _}} =
             parse_shell_dag("tasks: [{name: first, run: echo, downstream: [first]}]")
  end

  test "returns an error for invalid YAML" do
    assert {:error, {[], "invalid shell DAG", _}} = parse_shell_dag("tasks: [")
  end

  test "returns an error for an unreadable file" do
    path = Path.join(System.tmp_dir!(), "missing-shell-#{System.unique_integer([:positive])}.yml")
    assert {:error, {[], "invalid shell DAG", _}} = Adapter.parse_file(path)
  end
end
