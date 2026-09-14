defmodule GustShell.Parser.AdapterTest do
  use ExUnit.Case, async: true

  alias Gust.DAG.Definition
  alias GustShell.Parser.Adapter

  @file_path Path.join(System.tmp_dir!(), "gust_shell_backup_test.yml")

  setup do
    File.write!(@file_path, """
    schedule: "0 2 * * *"
    tasks:
      - name: tar_data
        run: |
          tar -czf /tmp/backup.tar.gz /var/data
        downstream: [notify]
        cwd: /tmp
        env:
          FOO: bar
        kill_timeout: 10
      - name: notify
        run: notify.sh
        user: app
    """)

    on_exit(fn -> File.rm(@file_path) end)

    :ok
  end

  test "parses shell YAML into a DAG definition" do
    assert {:ok, %Definition{} = dag_def} = Adapter.parse_file(@file_path)

    assert dag_def.options == [schedule: "0 2 * * *"]
    assert dag_def.adapter == :shell
    assert Map.has_key?(dag_def.tasks, "tar_data")
    assert dag_def.tasks["tar_data"][:downstream] == ["notify"]
    assert dag_def.tasks["tar_data"][:cwd] == "/tmp"
    assert dag_def.tasks["tar_data"][:env] == %{"FOO" => "bar"}
    assert dag_def.tasks["tar_data"][:kill_timeout] == 10
  end
end
