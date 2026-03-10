# GustPy

Enable Python DAGs in your Gust project.

## Motivation
Python is the default language for many DAG processors, including Airflow. Because of that, many teams have years of existing DAG definitions written in Python.

GustPy brings Python DAG support to Gust, making it possible to reuse legacy workflows on a lightweight and efficient orchestration engine. This helps reduce resource usage and modernize execution without the cost of rewriting everything in Elixir.


## Installation
**Attention:** this assumes you already have a Gust project.

1. Add `gust_py` to your Gust project’s mix.exs file:
 ```elixir
defp deps do
  [
    # Your other deps, such as {:gust_web, "..."},
    {:gust_py, "~> 0.1.0"},
    # ...
  ]
end
```
2. Declare the adapter in your `config.exs`:
  ```elixir

  config :gust,
    dag_adapter: [
      python: %{
        parser: GustPy.Parser.Adapter,
        runtime: GustPy.Runtime.Adapter,
        task_worker: GustPy.TaskWorker.Adapter
      }
    ]
  ```
 3. [Install Python's uv package manager](https://docs.astral.sh/uv/) in your DAG folder
 4. Add the `gust-py`  [dependency](https://github.com/marciok/gust_py):
  ```bash
 uv add gust-py
  ``` 

You may also install any other dependencies your DAGs need, such as numpy or pytorch.

## Writing DAGs
You can now write in Python with full support, just as you would with an Elixir DAG. For example:

```python
from gust import Dag, task, log, get_task_by_name_run, get_secret_by_name

class HelloWorld(Dag):

    def __init__(self):
	      # `schedule` and `on_finished_callback` are optional.
        super().__init__(schedule="* * * * *", on_finished_callback="notify_something")

    def notify_something(self, status, run):
        print("DAG is done!")

    @task(downstream=["second_task"], save=True)
    def first_task(self, ctx):
        greetings = "Hi!"
        secret = get_secret_by_name("SECRET")
        log(f"I know your secret: {secret}")

        return {"result": greetings}

    @task()
    def second_task(self, ctx):
        run_id = ctx["run_id"]
        run = get_task_by_name_run("first_task", run_id)
        log(run)

```


## Under the Hood

Before a DAG run starts, Gust copies the DAG file and launches a dedicated Python process for each task. This enables parallel Python execution while preserving the DAG state as it was defined before the run.

To make future support for other languages and runtimes easier, communication between processes is done through JSON messages. Elixir Ports are responsible for managing the lifecycle of the Python processes, including startup and shutdown.

The main trade-off is the OS overhead of spawning a new process for every task. In practice, however, these tasks are expected to be long-running, so the relative startup cost becomes negligible. Using a persistent Python worker would also undermine the design goal of keeping orchestration in Elixir while allowing other languages to focus only on task execution.

