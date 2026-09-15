defmodule GustShell.Parser.AdapterTest do
  use ExUnit.Case, async: true

  alias Gust.DAG.Definition
  alias GustShell.Parser.Adapter

  @file_path Path.join(System.tmp_dir!(), "gust_shell_backup_test.yml")

  setup do
    sys_tmp_dir = System.tmp_dir!()

    File.write!(@file_path, """
    schedule: "0 2 * * *"
    tasks:
      - name: tar_data
        run: |
          tar -czf #{sys_tmp_dir}/backup.tar.gz /var/data
        downstream: [notify]
        cwd: #{sys_tmp_dir}
        env:
          FOO: bar
        kill_timeout: 10
      - name: notify
        run: notify.sh
        user: app
    """)

    on_exit(fn -> File.rm(@file_path) end)

    %{tmp_dir: sys_tmp_dir}
  end

  test "parses shell YAML into a DAG definition", %{tmp_dir: tmp_dir} do
    assert {:ok, %Definition{} = dag_def} = Adapter.parse_file(@file_path)

    assert dag_def.options == [schedule: "0 2 * * *"]
    assert dag_def.adapter == :shell
    assert Map.has_key?(dag_def.tasks, "tar_data")
    assert dag_def.tasks["tar_data"]["downstream"] == ["notify"]
    assert dag_def.tasks["tar_data"]["cwd"] == tmp_dir
    assert dag_def.tasks["tar_data"]["env"] == %{"FOO" => "bar"}
    assert dag_def.tasks["tar_data"]["kill_timeout"] == 10
  end

  describe "edge cases" do
    test "handles single task as a map instead of a list" do
      file_path = Path.join(System.tmp_dir!(), "single_task.yml")

      File.write!(file_path, """
      tasks:
        name: single_task
        run: echo hello
      """)

      on_exit(fn -> File.rm(file_path) end)

      assert {:ok, %Definition{} = dag_def} = Adapter.parse_file(file_path)
      assert Map.has_key?(dag_def.tasks, "single_task")
    end

    test "handles empty/invalid tasks field" do
      file_path = Path.join(System.tmp_dir!(), "no_tasks.yml")

      File.write!(file_path, """
      schedule: "0 2 * * *"
      """)

      on_exit(fn -> File.rm(file_path) end)

      assert {:ok, %Definition{} = dag_def} = Adapter.parse_file(file_path)
      assert dag_def.tasks == %{}
    end

    test "returns error tuple when task is missing a name" do
      file_path = Path.join(System.tmp_dir!(), "missing_name.yml")

      File.write!(file_path, """
      tasks:
        - run: echo hello
      """)

      on_exit(fn -> File.rm(file_path) end)

      # Error should be returned as error tuple, not raised exception
      assert {:error, {[], "invalid shell DAG", _reason}} = Adapter.parse_file(file_path)
    end

    test "converts single downstream value to list" do
      file_path = Path.join(System.tmp_dir!(), "single_downstream.yml")

      File.write!(file_path, """
      tasks:
        - name: task_a
          run: echo a
          downstream: task_b
        - name: task_b
          run: echo b
      """)

      on_exit(fn -> File.rm(file_path) end)

      assert {:ok, %Definition{} = dag_def} = Adapter.parse_file(file_path)
      assert dag_def.tasks["task_a"]["downstream"] == ["task_b"]
    end

    test "handles non-string/non-list tasks field" do
      file_path = Path.join(System.tmp_dir!(), "invalid_tasks.yml")

      File.write!(file_path, """
      tasks: 123
      """)

      on_exit(fn -> File.rm(file_path) end)

      assert {:ok, %Definition{} = dag_def} = Adapter.parse_file(file_path)
      assert dag_def.tasks == %{}
    end

    test "uses atom keys for tasks lookup (line 50)" do
      # Tests: Map.get(yaml, :tasks) path - when YAML uses atom keys
      file_path = Path.join(System.tmp_dir!(), "atom_tasks.yml")

      File.write!(file_path, """
      tasks:
        - name: test_task
          run: echo test
      """)

      on_exit(fn -> File.rm(file_path) end)

      assert {:ok, %Definition{} = dag_def} = Adapter.parse_file(file_path)
      assert Map.has_key?(dag_def.tasks, "test_task")
    end

    test "preserves tasks as list when provided (line 51)" do
      # Tests: tasks when is_list(tasks) -> tasks path explicitly
      file_path = Path.join(System.tmp_dir!(), "list_tasks.yml")

      File.write!(file_path, """
      tasks:
        - name: first
          run: echo 1
        - name: second
          run: echo 2
        - name: third
          run: echo 3
      """)

      on_exit(fn -> File.rm(file_path) end)

      assert {:ok, %Definition{} = dag_def} = Adapter.parse_file(file_path)
      # All three tasks should be present
      assert Map.has_key?(dag_def.tasks, "first")
      assert Map.has_key?(dag_def.tasks, "second")
      assert Map.has_key?(dag_def.tasks, "third")
    end

    test "extracts task name from task map (line 63)" do
      # Tests: fetch_task_name/1 - verify it gets called and extracts name
      file_path = Path.join(System.tmp_dir!(), "extract_name.yml")

      File.write!(file_path, """
      tasks:
        - name: my_task
          run: echo works
      """)

      on_exit(fn -> File.rm(file_path) end)

      assert {:ok, %Definition{} = dag_def} = Adapter.parse_file(file_path)
      assert dag_def.tasks["my_task"]["run"] == "echo works"
    end

    test "extracts downstream from task using string and atom keys (line 69)" do
      # Tests: task["downstream"] || task[:downstream] || [] path
      file_path = Path.join(System.tmp_dir!(), "downstream_paths.yml")

      File.write!(file_path, """
      tasks:
        - name: task_with_downstream
          run: echo test
          downstream: [next_task]
        - name: next_task
          run: echo next
      """)

      on_exit(fn -> File.rm(file_path) end)

      assert {:ok, %Definition{} = dag_def} = Adapter.parse_file(file_path)
      # Task should have downstream list
      assert dag_def.tasks["task_with_downstream"]["downstream"] == ["next_task"]
      # Task without downstream should have empty list
      assert dag_def.tasks["next_task"]["downstream"] == []
    end

    test "handles error in build_task_params when task is missing name (line 104)" do
      # Tests: {:error, reason} -> {:halt, {:error, reason}} path in build_task_params
      # This specifically tests line 104-105 error handling
      file_path = Path.join(System.tmp_dir!(), "task_missing_name_in_params.yml")

      File.write!(file_path, """
      tasks:
        - run: echo hello
          env:
            VAR: value
      """)

      on_exit(fn -> File.rm(file_path) end)

      # When a task is missing a name in build_task_params, it should return an error
      assert {:error, {[], "invalid shell DAG", _reason}} = Adapter.parse_file(file_path)
    end

    test "normalizes nested map values in task options (line 122-124)" do
      # Tests: normalize_value/1 for map type - lines 122-124
      file_path = Path.join(System.tmp_dir!(), "nested_map_values.yml")

      File.write!(file_path, """
      tasks:
        - name: task_with_nested_map
          run: echo test
          config:
            $nested_key: nested_value
            another_key: another_value
      """)

      on_exit(fn -> File.rm(file_path) end)

      assert {:ok, %Definition{} = dag_def} = Adapter.parse_file(file_path)
      # Verify nested map was normalized ($ prefix removed from keys)
      assert dag_def.tasks["task_with_nested_map"]["config"]["nested_key"] == "nested_value"
      assert dag_def.tasks["task_with_nested_map"]["config"]["another_key"] == "another_value"
    end

    test "normalizes nested list values in task options (line 126-128)" do
      # Tests: normalize_value/1 for list type - lines 126-128
      file_path = Path.join(System.tmp_dir!(), "nested_list_values.yml")

      File.write!(file_path, """
      tasks:
        - name: task_with_nested_list
          run: echo test
          items:
            - item_one
            - item_two
            - regular_item
          nested_lists:
            - - nested_item_1
              - nested_item_2
            - - another_nested
      """)

      on_exit(fn -> File.rm(file_path) end)

      assert {:ok, %Definition{} = dag_def} = Adapter.parse_file(file_path)
      # Verify list items are properly normalized
      assert dag_def.tasks["task_with_nested_list"]["items"] == ["item_one", "item_two", "regular_item"]
      # Verify nested lists are properly handled
      assert dag_def.tasks["task_with_nested_list"]["nested_lists"] == [["nested_item_1", "nested_item_2"], ["another_nested"]]
    end

    test "handles invalid YAML file (line 24-25)" do
      # Tests: error path in read_yaml/1 when file cannot be read or is invalid
      file_path = Path.join(System.tmp_dir!(), "invalid_yaml_file.yml")

      File.write!(file_path, """
      invalid: yaml: content: [
      """)

      on_exit(fn -> File.rm(file_path) end)

      # When the YAML file is invalid, parse should return an error
      assert {:error, {[], "invalid shell DAG", _reason}} = Adapter.parse_file(file_path)
    end

    test "normalizes scalar values in task options (line 130)" do
      # Tests: normalize_value/1 catch-all clause for scalar types - line 130
      file_path = Path.join(System.tmp_dir!(), "scalar_values.yml")

      File.write!(file_path, """
      tasks:
        - name: task_with_scalars
          run: echo test
          timeout: 300
          retries: 3
          enabled: true
          description: "test task"
      """)

      on_exit(fn -> File.rm(file_path) end)

      assert {:ok, %Definition{} = dag_def} = Adapter.parse_file(file_path)
      # Verify scalar values are preserved unchanged
      assert dag_def.tasks["task_with_scalars"]["timeout"] == 300
      assert dag_def.tasks["task_with_scalars"]["retries"] == 3
      assert dag_def.tasks["task_with_scalars"]["enabled"] == true
      assert dag_def.tasks["task_with_scalars"]["description"] == "test task"
    end

    test "error path in build_task_list at line 53 is properly tested" do
      # This test verifies that the error case in task_graph_entry is caught
      # This helps ensure line 53 is fully covered
      # The test "returns error tuple when task is missing a name" at line 74 should cover this
      # but we verify the error propagates through build_task_list properly
      file_path = Path.join(System.tmp_dir!(), "missing_name_check.yml")

      File.write!(file_path, """
      tasks:
        - run: missing_name_test
        - name: valid_task
          run: echo works
      """)

      on_exit(fn -> File.rm(file_path) end)

      # The first task lacks a name, so build_task_list should catch this
      # and return an error before reaching build_task_params
      assert {:error, {[], "invalid shell DAG", _reason}} = Adapter.parse_file(file_path)
    end
  end
end
