# Writing Shell DAGs

A shell DAG is a YAML file in your DAG folder. The file name is the DAG name,
so `backup_files.yml` becomes the `backup_files` DAG. For example:

```yaml
# `schedule` and `on_finished_callback` are optional.
schedule: "0 3 * * *"

tasks:
  - name: backup_data
    run: "tar -czf backup.tar.gz /data"
    cd: "/var/backups"
    downstream: [upload_backup]
    save: true

  - name: upload_backup
    run: "aws s3 cp backup.tar.gz s3://my-bucket/"
    cd: "/var/backups"
    env:
      AWS_PROFILE: production
```

Each task runs its `run` command in a shell. Tasks without a dependency between
them run in parallel.

## Task keys

- `name` (required): unique, non-empty task name.
- `run` (required): the shell command to execute.
- `downstream`: list of task names that run after this one.
- `save` (alias `store_result`): store the task result. Defaults to `false`.

A successful task returns `%{stdout: ..., stderr: ..., exit_code: 0, status: :success}`.

## Execution options

- `cd` (aliases `cwd`, `working_dir`): working directory.
- `env`: mapping of environment variables. Values may be strings, numbers or
  booleans; they are converted to strings.
- `user`: run the command as another user (requires permissions).
- `group`: process group. Defaults to `0`, a new group, so child processes are
  killed with the task.
- `nice`: CPU priority, from `-20` to `19`.
- `kill_timeout`: seconds to wait before force-killing the process.
- `success_exit_code`: passed to erlexec. It does not make a non-zero exit
  code succeed.
- `pty`, `pty_echo`: run in a pseudo-terminal (YAML booleans).
- `stdout`, `stderr`, `stdin`: `"null"`, `"close"` or a file path. Output is
  captured by default. Quote `"null"`, an unquoted `null` is rejected.
- `executable`: shell executable to use.
- `cgroup`: Linux control group.
- `debug`: erlexec debug level.

## Validation

The whole file is checked when it is parsed, before any command starts.
Unknown keys, wrong value types, duplicate task names, unknown `downstream`
tasks and cycles are all reported as parse errors. Using two spellings of the
same option, like `cd` with `cwd` or `save` with `store_result`, is an error.

## Failures

A non-zero exit code or a signal fails the task with a
`GustShell.ShellExitError`, which carries the exit code, stdout, stderr and
whether the process dumped core.
