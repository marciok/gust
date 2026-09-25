# Under the Hood

Before a DAG run starts, Gust copies the DAG file and launches a dedicated
Python process for each task. This enables parallel Python execution while
preserving the DAG state as it was defined before the run.

To make future support for other languages and runtimes easier, communication
between processes is done through JSON messages. Elixir Ports are responsible
for managing the lifecycle of the Python processes, including startup and
shutdown.

The main trade-off is the OS overhead of spawning a new process for every
task. In practice, however, these tasks are expected to be long-running, so
the relative startup cost becomes negligible. Using a persistent Python
worker would also undermine the design goal of keeping orchestration in
Elixir while allowing other languages to focus only on task execution.
