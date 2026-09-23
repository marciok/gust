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

## Rules

The file is validated when parsed, before any command runs. The DAG fails to load if:

- a key is unknown at the DAG or task level;
- a value has the wrong type (for example `save: "true"` instead of `save: true`);
- task names are duplicated, or `downstream` points to an unknown task;
- the tasks form a cycle;
- two spellings of one option are combined (`cd` with `cwd`/`working_dir`, or `save` with `store_result`).

Also keep in mind:

- Quote `"null"` for `stdout`/`stderr`/`stdin`. An unquoted `null` is rejected.
- Quote commands that contain YAML-special characters such as `:`, `#`, `{`, `[`, `*` or `&`.
- Tasks do not share state. Pass data between tasks through files, for example in a shared `cd`.
- Run params do not change the command or options. Use `env` or the command itself instead.
- A non-zero exit code or a signal fails the task with
  `GustShell.ShellExitError`, which includes the exit code, stdout and stderr.

## Validation

For example, if the file is `dags/backup_files.yml`, confirm that the `backup_files` DAG is valid.

Run command: `mix gust.cli dag_definition backup_files`

The DAG is valid when the output has `status: "ok"`. Otherwise fix the reported error and run
the command again.
