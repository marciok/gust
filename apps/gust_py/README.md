# GustPy

Enable Python DAGs in your Gust project.

## Motivation
Python is the default language for many DAG processors, including Airflow. Because of that, many teams have years of existing DAG definitions written in Python.

GustPy brings Python DAG support to Gust, making it possible to reuse legacy workflows on a lightweight and efficient orchestration engine. This helps reduce resource usage and modernize execution without the cost of rewriting everything in Elixir.


## Guides

- [Installation](guides/installation.md) — add `gust_py` to a Gust project
  and wire up the Python adapter.
- [Writing Python DAGs](guides/writing_python_dags.md) — a full DAG example.
- [Under the Hood](guides/under_the_hood.md) — how Gust runs Python tasks.

