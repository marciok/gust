# Gust DAG Examples

Here you will find a collection of useful DAGs that showcase Gust's power.

## Elixir DAGs

| Name | Description |
|---|---|
| [DailyStockDecider](https://github.com/marciok/gust/blob/main/examples/dags/daily_stock_decider.ex) | A daily stock decision DAG that collects market, company, news, and macro inputs, asks multiple LLMs for an independent recommendation, and produces a final buy/hold/sell decision for the configured ticker. |
| [ParentWaitsForChild](https://github.com/marciok/gust/blob/main/examples/dags/parent_waits_for_child.ex) and [ChildResumesParent](https://github.com/marciok/gust/blob/main/examples/dags/child_resumes_parent.ex) | A pair of DAGs showing how one DAG can trigger another, wait with `TaskWaiter`, and continue with the child result. |

## Shell DAGs (YAML)

| Name | Description |
|---|---|
| [file_backup.yml](https://github.com/marciok/gust/blob/main/examples/dags/file_backup.yml) | A sequential backup workflow that creates a tar archive, generates a checksum for integrity verification, and moves the backup to an archive directory. Demonstrates working directory control and environment variables. |
| [parallel_build.yml](https://github.com/marciok/gust/blob/main/examples/dags/parallel_build.yml) | A parallel Rust build pipeline with linting and unit tests running concurrently, followed by integration tests and a release build. Shows how shell DAGs can orchestrate build and test processes efficiently. |
