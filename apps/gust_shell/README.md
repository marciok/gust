# Gust Shell

YAML and Elixir shell DAG support for Gust.

## Overview

Gust Shell extends Gust with the ability to define and execute shell command DAGs. This allows you to orchestrate shell scripts, system commands, and tools as part of your Gust workflows.

## Guides

- [Installation](guides/installation.md) — add `gust_shell` to a Gust project
  and wire up the shell adapter.
- [Writing Shell DAGs](guides/writing_shell_dags.md) — a full DAG example and
  every task option.
- [Under the Hood](guides/under_the_hood.md) — how Gust runs shell tasks.

## Features

- **YAML DAG Support**: Define shell DAGs using simple YAML files (`.yml`)
- **Shell Command Execution**: Run OS commands with full control over execution options
- **Output Capture**: Automatically capture stdout, stderr, and exit codes
- **Process Management**: Control process groups, timeouts, environment variables, and more
- **Error Handling**: Graceful error handling with detailed error messages and exit status reporting

## Installation

Add to your `mix.exs`:

```elixir
def deps do
  [
    {:gust_shell, "~> 0.1"}
  ]
end
```

## Quick Start

### YAML DAG Example

Create a file named `backup_files.yml` in your `dags/` folder:

```yaml
tasks:
  - name: backup_data
    run: "tar -czf backup.tar.gz /data"
    cd: "/var/backups"
    downstream: [upload_backup]

  - name: upload_backup
    run: "aws s3 cp backup.tar.gz s3://my-bucket/"
    cd: "/var/backups"
    env:
      AWS_PROFILE: production
```

## YAML DAG Configuration

### Task Structure

Each task in a YAML DAG requires:

- **name**: Unique identifier for the task
- **run**: The shell command to execute
- **downstream** (optional): List of downstream task names

`tasks` must be a YAML list of mappings with string names and commands. Use
`tasks: []` for an empty DAG. Unknown task or DAG options and invalid task option
types are rejected when the file is parsed, before any command starts.

The parser prepares each task's command and complete execution options. Task
params are input data and do not override the command or execution options.
Use YAML booleans for `pty`, `pty_echo`, and `save` (not quoted strings), and a
mapping for `env`. Environment values may be strings, numbers, or booleans; the
parser converts them to strings without changing variable names.

`save` (also accepted as `store_result`) controls result persistence and defaults
to `false`. Specify only one spelling of an aliased option: combining `cd` with
`cwd` or `working_dir`, or `save` with `store_result`, is an error.

### Task Options

Shell tasks support the following execution options:

#### Process Control

- **cd**: Working directory for the command (aliases: `cwd`, `working_dir`)
- **user**: User to run the command as (requires appropriate permissions)
- **group**: Process group ID (default: 0 - creates new process group)
- **nice**: CPU priority level (-20 to 19)
- **pty**: Run in pseudo-terminal mode (true/false)
- **pty_echo**: Enable PTY echo mode (true/false)
- **kill_timeout**: Seconds before force-killing the process

#### Environment

- **env**: Environment variables as a map
  ```yaml
  env:
    DATABASE_URL: "postgresql://..."
    DEBUG: "true"
  ```

#### Output Control

- **stdout**: Stream handling - "null", "close", or file path (default: captured)
- **stderr**: Stream handling - "null", "close", or file path (default: captured)
- **stdin**: Stream handling - "null", "close", or file path (default: managed by erlexec)

Quote `"null"` in YAML; an unquoted `null` is a null value and is rejected.

#### Debugging

- **debug**: Debug level for the exec system (0, 1, 2, ...)
- **executable**: Custom shell executable path (default: system shell)
- **cgroup**: Linux control group for resource limits

### Example: Complex Shell DAG

```yaml
tasks:
  - name: build
    run: "make build"
    cd: "/app"
    nice: 10
    downstream: [run_tests]

  - name: run_tests
    run: "pytest tests/"
    cd: "/app"
    downstream: [deploy]
    env:
      PYTHONUNBUFFERED: "1"

  - name: deploy
    run: "docker push myapp:latest && kubectl rollout restart deployment/myapp"
    env:
      DOCKER_REGISTRY: "registry.example.com"
    kill_timeout: 30000
```

## Exit Codes and Error Handling

Shell tasks report detailed exit information:

- **Success**: Exit code 0, stdout/stderr captured
- **Command Failure**: Non-zero exit code with error message
- **Signal Termination**: Process killed by signal (e.g., SIGTERM, SIGSEGV)
- **Core Dump**: Detected and reported if the process dumped core

## Process Execution Details

Gust Shell uses the Erlang `:exec` module for reliable process management:

- Processes are monitored and properly cleaned up
- Process groups ensure all child processes are terminated
- Timeouts prevent runaway processes
- Exit status properly decodes normal exits, signals, and core dumps

## Configuration

### Environment Variables

Configure gust_shell behavior through environment variables:

- **ERLEXEC_DEBUG**: Enable debug logging for exec module (0-2)

### Gust Integration

Gust Shell integrates automatically when added as a dependency. The shell adapter is registered with Gust's DAG system and will process any `.yml` files in your `dags/` folder.

## Testing

Run the comprehensive test suite:

```bash
mix test apps/gust_shell/test/
```

The test suite includes:
- Parser tests for option validation, normalization, defaults, and task graphs
- TaskWorker tests for process lifecycle, output, and errors
- 16+ Runtime adapter tests
- Integration tests for complete DAG execution

## Architecture

### Components

- **Parser Adapter** (`GustShell.Parser.Adapter`): Validates YAML DAG files and prepares commands and complete execution options
- **Task Worker Adapter** (`GustShell.TaskWorker.Adapter`): Executes shell commands and manages process lifecycle
- **Runtime Adapter** (`GustShell.Runtime.Adapter`): Bridges Gust's runtime system with shell execution

### Process Lifecycle

1. DAG loaded from YAML file
2. Parser creates task graph and normalizes options
3. Task worker spawned for each task
4. Shell command executed via `:exec.run/2`
5. Output streamed and captured
6. Process termination detected and handled
7. Results stored in database

## Compatibility

- **Elixir**: 1.18+
- **Erlang**: OTP 27+
- **OS**: Linux, macOS, and Unix-like systems
- **Requires**: erlexec library for process management

## Limitations

- **Windows**: Limited support for process group management
- **TTY Features**: PTY options require TTY device in environment
- **Permissions**: Some options (user, cgroup) require elevated privileges
- **Resource Limits**: cgroup support depends on system configuration

## Contributing

Contributions welcome! See [CONTRIBUTING.md](../../CONTRIBUTING.md) for guidelines.

## License

Gust Shell is released under the Apache License 2.0.
