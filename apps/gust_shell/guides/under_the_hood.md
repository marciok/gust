# Under the Hood

When a YAML DAG is loaded, the parser validates it and prepares each task's
command and execution options up front. Nothing is evaluated at run time, so
a broken DAG fails when it is parsed, not halfway through a run.

For each task, Gust starts a task worker that runs the command through
[erlexec](https://hex.pm/packages/erlexec). The OS process is monitored, and
stdout and stderr are collected as they are emitted. When the process exits,
the worker turns the exit status into a result or a
`GustShell.ShellExitError` and reports it back to the run.

By default each command starts in its own process group, and the whole group
is killed when the task stops. This keeps commands that spawn children, like
`make` or a shell pipeline, from leaving orphaned processes behind.

Unlike Python DAGs, there is no per-run setup: the command runs directly from
the parsed definition. The `on_finished_callback` DAG option is accepted but
has no effect for shell DAGs.
