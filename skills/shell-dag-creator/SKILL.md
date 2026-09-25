---
name: Shell DAG Creator
description: Instructions for creating a YAML shell DAG to run on Gust with gust_shell. Use this when you need to create a new DAG that runs shell commands.
license: Complete terms in LICENSE.txt
---

# Gust Shell DAG Creator

Use this guide to create a shell DAG in YAML for Gust.

## Prerequisites

The project must depend on `gust_shell` and register its adapter in `config.exs`:

```elixir
config :gust,
  dag_adapter: [
    shell: %{
      parser: GustShell.Parser.Adapter,
      runtime: GustShell.Runtime.Adapter,
      task_worker: GustShell.TaskWorker.Adapter
    }
  ]
```

If the adapter is missing, `.yml` files are not loaded as DAGs.

## Create a DAG file

Create a `.yml` file under `dags/`. The file name is the DAG name, so
`dags/backup_files.yml` becomes the `backup_files` DAG. Use `.yml`, not `.yaml`.

## DAG syntax

A shell DAG is a YAML mapping with a `tasks` list. Each task runs its `run`
command in a shell. Tasks run after their upstream tasks finish; tasks without a
dependency between them run in parallel.

### Example

```yaml
# `schedule` and `on_finished_callback` are optional.
schedule: "0 3 * * *"

tasks:
  - name: backup_data
    run: "tar -czf backup.tar.gz /data"
    cd: "/var/backups"
    downstream: [upload_backup, checksum]
    save: true

  - name: checksum
    run: "sha256sum backup.tar.gz > backup.tar.gz.sha256"
    cd: "/var/backups"

  - name: upload_backup
    run: "aws s3 cp backup.tar.gz s3://my-bucket/"
    cd: "/var/backups"
    env:
      AWS_PROFILE: production
    kill_timeout: 30
```

## DAG options

Only these top-level keys are allowed:

- `tasks` (required): list of task mappings. Use `tasks: []` for an empty DAG.
- `schedule`: a cron expression.
- `on_finished_callback`: accepted, but has no effect for shell DAGs.

## Task keys

- `name` (required): unique, non-empty string.
- `run` (required): the shell command, as a string.
- `downstream`: list of task names that run after this task. Every name must exist in the file.
- `save` (alias `store_result`): YAML boolean, defaults to `false`. When `true`, the result
  `%{stdout: ..., stderr: ..., exit_code: 0, status: :success}` is persisted.

## Execution options

- `cd` (aliases `cwd`, `working_dir`): working directory, string.
- `env`: mapping of variable names to strings, numbers or booleans.
- `user`: user to run the command as, string (requires permissions).
- `group`: process group, integer or string. Defaults to `0`, a new group, so child
  processes are killed with the task.
- `nice`: integer from `-20` to `19`.
- `kill_timeout`: non-negative integer, in seconds, before force-killing the process.
- `success_exit_code`: non-negative integer, passed to erlexec. It does not make a non-zero exit
  code succeed; append `|| true` to the command for that.
- `pty`, `pty_echo`: YAML booleans.
- `stdout`, `stderr`, `stdin`: `"null"`, `"close"` or a file path. Output is captured by default.
- `executable`: shell executable path, string.
- `cgroup`: Linux control group, string.
- `debug`: non-negative integer erlexec debug level.

## Templates

`run` and string `env` values are [EEx](https://hexdocs.pm/eex/EEx.html)
templates. They are checked when the DAG is parsed and rendered when each task
attempt starts, so a retry sees the current secrets and run params. A template
can use:

- `run_id`: the current run id.
- `run_params`: the params the run was triggered with, a map with string keys.
  For example, `gust-cli trigger_run my_dag --run_params '{"target": "arm64"}'`
  makes `run_params["target"]` return `"arm64"`.
- `params`: the task's own params, a map with string keys. It is empty unless
  the task is a `map_over` item or was resumed from a wait.
- `secret!("NAME")`: the value of a Gust secret. The task fails if it does not exist.
- `task_result!("NAME")`: the saved result of another task in the same run, a
  map with the keys `"stdout"`, `"stderr"`, `"exit_code"` and `"status"`. That
  task must be upstream of this one, and the task fails if it does not exist.
  Without `save: true` on it, the result is an empty map, so a key like
  `"stdout"` renders as an empty string. To fail instead, check it in the
  template: `<%= task_result!("NAME")["stdout"] || raise "NAME saved no output" %>`.
- `Flows`: an alias for `Gust.Flows`, for anything else, such as
  `Flows.get_run!(run_id)`.

```yaml
tasks:
  - name: build_release
    run: 'cargo build --release --target <%= run_params["target"] %> --token "$TOKEN"'
    cd: "/project"
    env:
      TOKEN: '<%= secret!("CARGO_TOKEN") %>'
```

To use one task's output in another, save it and read it downstream:

```yaml
tasks:
  - name: read_version
    run: "cat VERSION"
    cd: "/project"
    save: true
    downstream: [tag_image]

  - name: tag_image
    run: 'docker tag myapp:latest "myapp:$VERSION"'
    env:
      VERSION: '<%= String.trim(task_result!("read_version")["stdout"]) %>'
```

Pass secrets and task output through `env` and read them as variables in the
command, as above. A secret written straight into `run` is visible in `ps` output and can
break the command if it contains spaces or quotes. Wrap templates in single
quotes in YAML, and write `<%%` for a literal `<%`.

## Rules

The file is validated when parsed, before any command runs. The DAG fails to load if:

- a key is unknown at the DAG or task level;
- a value has the wrong type (for example `save: "true"` instead of `save: true`);
- task names are duplicated, or `downstream` points to an unknown task;
- the tasks form a cycle;
- a template in `run` or `env` has an EEx syntax error;
- two spellings of one option are combined (`cd` with `cwd`/`working_dir`, or `save` with `store_result`).

Also keep in mind:

- Quote `"null"` for `stdout`/`stderr`/`stdin`. An unquoted `null` is rejected.
- Quote commands that contain YAML-special characters such as `:`, `#`, `{`, `[`, `*` or `&`.
- Tasks do not share state. Pass data downstream with `save: true` and `task_result!/1`, or
  through files, for example in a shared `cd`.
- Only `run` and `env` values are templates. Other options, such as `cd`, are used as written.
- A non-zero exit code or a signal fails the task with
  `GustShell.ShellExitError`, which includes the exit code, stdout and stderr.

## Validation

For example, if the file is `dags/backup_files.yml`, confirm that the `backup_files` DAG is valid.

Run command: `mix gust.cli dag_definition backup_files`

The DAG is valid when the output has `status: "ok"`. Otherwise fix the reported error and run
the command again.
