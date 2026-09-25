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

## Validation

The whole file is checked when it is parsed, before any command starts.
Unknown keys, wrong value types, duplicate task names, unknown `downstream`
tasks, cycles and template syntax errors are all reported as parse errors. Using two spellings of the
same option, like `cd` with `cwd` or `save` with `store_result`, is an error.

## Failures

A non-zero exit code or a signal fails the task with a
`GustShell.ShellExitError`, which carries the exit code, stdout, stderr and
whether the process dumped core.
