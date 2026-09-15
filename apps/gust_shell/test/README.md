# GustShell Tests

This directory contains tests for the GustShell application, which provides shell task execution within the Gust DAG framework.

## Test Structure

### Unit Tests

- **`gust_shell/task_worker/adapter_test.exs`** - Tests for the TaskWorker Adapter that handles shell command execution
  - Command execution and output capture
  - Exit code and signal handling
  - Mismatch handling for process IDs
  - Configuration precedence (DAG definition → task params → runtime options)

- **`gust_shell/parser/adapter_test.exs`** - Tests for the YAML DAG parser
  - YAML parsing and validation
  - Task structure creation
  - Environment variable handling

### Integration Tests

- **`gust_shell/integration/shell_dag_integration_test.exs`** - End-to-end tests for shell DAG loading and execution
  - YAML DAG file parsing
  - Task graph structure creation
  - Sequential and parallel task execution patterns
  - Error handling and edge cases

## Test Fixtures

### Fixture Helpers (`support/shell_fixtures.ex`)

The `GustShell.TestFixtures` module provides helpers for creating test DAGs:

- `yaml_dag_fixture/1` - Writes YAML content to a temporary file
- `parse_shell_dag/1` - Parses YAML content into a DAG definition
- `sequential_dag_yaml/1` - Creates a simple sequential DAG (task1 → task2)
- `parallel_dag_yaml/1` - Creates a parallel DAG (task1 → [task2, task3])
- `configured_dag_yaml/1` - Creates a DAG with environment variables
- `failing_dag_yaml/1` - Creates a DAG with a failing task

### Example DAG Files (`fixtures/dags/`)

Reference YAML DAG definitions demonstrating common patterns:

- **simple_sequential.yml** - Basic sequential task execution
- **parallel_tasks.yml** - Parallel task execution
- **with_options.yml** - Tasks with environment variables and configuration
- **complex_pipeline.yml** - Diamond-shaped DAG with merge points

## Running Tests

Run all shell tests:
```bash
eval "$(cat .env.example | tr '\n' ';')" && mix test apps/gust_shell/test/
```

Run specific test file:
```bash
eval "$(cat .env.example | tr '\n' ';')" && mix test apps/gust_shell/test/gust_shell/integration/shell_dag_integration_test.exs
```

Run tests with verbose output:
```bash
eval "$(cat .env.example | tr '\n' ';')" && mix test apps/gust_shell/test/ --trace
```

## Test Coverage

The test suite covers:

1. **YAML Parsing**
   - Valid and invalid YAML syntax
   - Task graph structure creation
   - Option parsing (schedule, environment variables, etc.)

2. **Task Execution**
   - Sequential task execution
   - Parallel task execution
   - Task output capture (stdout, stderr)
   - Exit code handling (success, failure, signals)

3. **Configuration**
   - Configuration precedence
   - Environment variable handling
   - Working directory and other execution options

4. **Error Handling**
   - Failed task handling
   - Missing required parameters
   - Invalid input validation

## Design Patterns

### Mocking Shell Execution

For integration tests that don't actually execute shell commands, the `:exec.run` function can be mocked using Mox:

```elixir
Mox.expect(ExecMock, :run, fn _command, _opts ->
  {:ok, _exec_pid, pid}
end)
```

### Test Fixtures

Tests use `Gust.DataCase` for database access and the fixtures defined in `support/shell_fixtures.ex` for creating test DAGs.

### Cleanup

Temporary YAML files created by `yaml_dag_fixture/1` should be cleaned up using `on_exit/1`:

```elixir
file_path = yaml_dag_fixture(yaml_content)
on_exit(fn -> File.rm(file_path) end)
```

## Adding New Tests

To add new integration tests:

1. Create a test case in `shell_dag_integration_test.exs`
2. Use the fixture helpers from `GustShell.TestFixtures`
3. Follow the pattern of existing tests
4. Ensure proper cleanup with `on_exit/1`

Example:

```elixir
test "my new test" do
  yaml = sequential_dag_yaml(cmd1: "my command", cmd2: "another command")
  assert {:ok, %Definition{} = dag_def} = parse_shell_dag(yaml)

  # Assert your test conditions
  assert dag_def.tasks["task1"]["run"] == "my command"
end
```
