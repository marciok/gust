# Under the Hood

GustShell plugs into Gust through three adapters: a parser reads the YAML
file, a task worker (`GustShell.TaskWorker.Adapter`) runs each task, and a
runtime adapter stops a task's command when the task is cancelled.

When a YAML DAG is loaded, the parser validates it, builds the task graph and
prepares each task's command and execution options up front, so a broken DAG
fails when it is parsed, not halfway through a run. Templates are checked at
this point too, but only rendered when each task attempt starts.

For each task, Gust starts a task worker that runs the command through
[erlexec](https://hex.pm/packages/erlexec). The OS process is monitored, and
stdout and stderr are collected as they are emitted. When the process exits,
the worker turns the exit status into a result or a
`GustShell.ShellExitError` and reports it back to the run. Gust stores the
result when the task has `save: true`.

By default each command starts in its own process group, and the whole group
is killed when the task stops. This keeps commands that spawn children, like
`make` or a shell pipeline, from leaving orphaned processes behind.

Unlike Python DAGs, there is no per-run setup: the command runs directly from
the parsed definition. The `on_finished_callback` DAG option is accepted but
has no effect for shell DAGs.
