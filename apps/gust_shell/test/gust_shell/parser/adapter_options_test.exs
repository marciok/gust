defmodule GustShell.Parser.AdapterOptionsTest do
  use ExUnit.Case, async: true

  import GustShell.TestFixtures

  for {yaml, expected} <- [
        {"cd: /tmp", {:cd, "/tmp"}},
        {"cwd: /tmp", {:cd, "/tmp"}},
        {"working_dir: /tmp", {:cd, "/tmp"}},
        {"cgroup: workers", {:cgroup, "workers"}},
        {"executable: /bin/sh", {:executable, "/bin/sh"}},
        {"user: app", {:user, "app"}},
        {"group: 100", {:group, 100}},
        {"group: staff", {:group, "staff"}},
        {"debug: 2", {:debug, 2}},
        {"debug: 0", {:debug, 0}},
        {"kill_timeout: 10", {:kill_timeout, 10}},
        {"kill_timeout: 0", {:kill_timeout, 0}},
        {"nice: -5", {:nice, -5}},
        {"nice: -20", {:nice, -20}},
        {"nice: 19", {:nice, 19}},
        {"success_exit_code: 42", {:success_exit_code, 42}},
        {"success_exit_code: 0", {:success_exit_code, 0}},
        {"pty: true", :pty},
        {"pty_echo: true", :pty_echo}
      ] do
    test "parses #{yaml}" do
      assert unquote(Macro.escape(expected)) in options(unquote(yaml))
    end
  end

  for key <- [:stdin, :stdout, :stderr],
      {yaml_value, expected} <- [
        {"'null'", :null},
        {"close", :close},
        {"/tmp/output", "/tmp/output"}
      ] do
    test "parses #{key}: #{yaml_value} and replaces its default" do
      opts = options("#{unquote(key)}: #{unquote(yaml_value)}")
      assert {unquote(key), unquote(expected)} in opts
      refute unquote(key) in opts
    end
  end

  test "includes process and output defaults exactly once" do
    assert options("") == [:stdin, :stdout, :stderr, :monitor, {:group, 0}, :kill_group]
    opts = options("group: 123")
    refute {:group, 0} in opts
    assert {:group, 123} in opts
    assert :monitor in opts
    assert :kill_group in opts
  end

  for key <- [:pty, :pty_echo] do
    test "omits #{key}: false" do
      assert options("#{unquote(key)}: false") == options("")
    end
  end

  test "disabling PTY echo preserves PTY allocation" do
    opts = options("pty: true\npty_echo: false")
    assert :pty in opts
    refute :pty_echo in opts
  end

  test "converts scalar environment values and preserves variable names" do
    opts =
      options("env: {TEXT: hello, COUNT: 123, ENABLED: true, DISABLED: false, '$KEEP': value}")

    assert {:env, env} = List.keyfind(opts, :env, 0)

    assert Map.new(env) == %{
             "TEXT" => "hello",
             "COUNT" => "123",
             "ENABLED" => "true",
             "DISABLED" => "false",
             "$KEEP" => "value"
           }
  end

  test "supports save and canonical store_result independently" do
    for key <- ["save", "store_result"] do
      assert {:ok, definition} = parse_shell_dag("tasks: [{name: task, run: echo, #{key}: true}]")
      assert definition.tasks["task"].store_result
    end
  end

  for yaml <- [
        "pty: 'true'",
        "pty: 'false'",
        "pty_echo: 'true'",
        "pty_echo: 'false'",
        "env: []",
        "env: text",
        "env: {KEY: []}",
        "env: {KEY: {nested: value}}",
        "env: {KEY: null}",
        "stdin: true",
        "stdout: 123",
        "stderr: []",
        "cd: 123",
        "cwd: null",
        "working_dir: []",
        "cgroup: {}",
        "executable: []",
        "user: 123",
        "group: []",
        "debug: '2'",
        "debug: -1",
        "kill_timeout: -1",
        "kill_timeout: '2'",
        "nice: 20",
        "nice: -21",
        "nice: '0'",
        "success_exit_code: false",
        "success_exit_code: -1",
        "save: null",
        "cd: /tmp\ncwd: /var",
        "save: true\nstore_result: false",
        "unknown: value",
        "monitor: false",
        "' cd ': /tmp",
        "'$cd': /tmp",
        "CD: /tmp"
      ] do
    test "rejects #{yaml}" do
      assert {:error, {[], "invalid shell DAG", reason}} = parse_options(unquote(yaml))
      assert reason =~ ~s(task "task")
    end
  end

  defp options(yaml) do
    assert {:ok, definition} = parse_options(yaml)
    definition.tasks["task"].exec_opts
  end

  defp parse_options(yaml) do
    fields = yaml |> String.split("\n", trim: true) |> Enum.map_join("\n", &("    " <> &1))
    parse_shell_dag("tasks:\n  - name: task\n    run: echo hello\n" <> fields)
  end
end
