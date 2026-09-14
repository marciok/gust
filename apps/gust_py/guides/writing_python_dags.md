# Writing Python DAGs

You can write DAGs in Python with full support, just as you would with an
Elixir DAG. For example:

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
