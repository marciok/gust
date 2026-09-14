<p align="center">
  <picture>
    <img alt="Gust" src="https://gust-github.s3.us-east-1.amazonaws.com/gust-symbol-logo.png" width="320">
  </picture>
</p>

<p align="center">
A task orchestration system designed to be efficient, fast, developer-friendly, and easy to scale. Built on the Erlang VM, Gust recovers gracefully from failures, supports manual retries, and is production-ready.
</p>

<p align="center">
  <a href="https://github.com/marciok/gust/actions/workflows/test.yml">
    <img src="https://github.com/marciok/gust/actions/workflows/test.yml/badge.svg" alt="Test" />
  </a>
  <a href="https://coveralls.io/github/marciok/gust?branch=main">
    <img src="https://coveralls.io/repos/github/marciok/gust/badge.svg?branch=main" alt="Coverage Status" />
  </a>
</p>

<p align="center">
  <a href="https://hexdocs.pm/gust_web">
    <img src="https://img.shields.io/hexpm/v/gust_web?color=0084d1&label=Gust+Web" alt="Gust Web" />
  </a>
  <a href="https://hexdocs.pm/gust">
    <img src="https://img.shields.io/hexpm/v/gust?color=0084d1&label=Gust" alt="Gust" />
  </a>

  <a href="https://hexdocs.pm/gust_py">
    <img src="https://img.shields.io/hexpm/v/gust_py?color=0084d1&label=Gust+Python" alt="Gust Python" />
  </a>

  <a href="https://opensource.org/license/MIT">
    <img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License-MIT" />
  </a>
</p>

---
## Why Gust

Running task orchestration in production often means:

- Standing up and maintaining multiple databases and services just to keep the scheduler alive.
- Fighting Docker complexity before a single DAG runs.
- Living with a clunky, outdated UI that slows debugging down.

Gust strips that away. One system, minimal moving parts, efficient and with a UI built for speed so you spend time writing DAGs, not babysitting infrastructure.

---

<img width="1920" height="1080" alt="gust-demo-1 5speed" src="https://github.com/user-attachments/assets/f44e16be-fb88-49f0-b9ca-ed307fd1aa30" />


## Table of Contents

- [Overview](#overview)
- [Getting Started](#getting-started)
- [Features](#features)
- [Guides](#guides)
- [Examples](https://github.com/marciok/gust/tree/main/examples)
- [Benchmark](#benchmark)

---
## Overview

From code to running workflow: you (or your agent) write a DAG, save it in the `dags/` folder, and Gust picks it up. Once loaded, the DAG shows up in the Web UI, ready to be triggered manually or to run on its own if a `schedule` is set.

### DAG Code Example
```elixir
defmodule HelloGust do
  @moduledoc false
  use Gust.DSL

  require Logger
  alias Gust.Flows

  task :first_task, downstream: [:second_task], save: true do
    greetings = "Hi from first_task"
    Logger.info(greetings)
    greetings = ["Hello!", "Olá!", "¡Hola!", "Bonjour!"]

    # You can get secrets created on the Web UI
    secret = Flows.get_secret_by_name("SUPER_SECRET")

    if secret do
      Logger.warning("I know your secret: #{secret.value}")
    end

    # The return value must be a map or a list when `save` is true.
    greetings
  end

  task :second_task,
    downstream: [:final_task],
    ctx: %{params: params},
    map_over: :first_task,
    save: true do
    message = "#{params["item"]} World!"
    Logger.warning(message)
    %{greeting: message}
  end

  task :final_task, ctx: %{run_id: run_id} do
    # Getting tasks results
    second_tasks = Flows.get_tasks_by_name("second_task", run_id)

    Enum.each(second_tasks, fn task ->
      Logger.warning(inspect(task.result))
    end)
  end
end

```

--- 

## Getting started

- [Quickstart with Docker](https://github.com/marciok/gust/tree/main/examples/docker)
- [Setup a new Gust project](https://hexdocs.pm/gust_web/installation.html)

---

## Features

**Orchestration**
  - **Cron scheduling** — schedule DAGs with cron-style expressions via the Gust DSL.
  - **Dependency-aware DAGs** — declare task dependencies and downstream execution order.
  - **Parallel mapping** — `:map_over` creates one task instance per upstream list item.
  - **Conditional skipping** — `:skip_if` skips a task, and its downstream dependents, based on a condition.
  - **Durable waiting** — `:wait_for` pauses a DAG until another DAG, webhook, or external process resumes it.

**Reliability**
  - **[Multi-node support](https://hexdocs.pm/gust/roles.html)** — split core, web, and console roles across nodes, or run everything on one.
  - **Retry logic with backoff**, plus state clearing for clean restarts.
  - **Corrupted-state recovery** and graceful handling of syntax errors during development.

**Developer experience**
  - **[Python DAG support](https://github.com/marciok/gust/tree/main/apps/gust_py)** — write DAGs in Python, not just Elixir.
  - **Manual task controls** — stop running tasks, cancel retries, and restart tasks on demand.
  - **Run-finished hooks** — trigger a callback when a DAG run finishes.
  - **[MCP server](https://hexdocs.pm/gust_web/mcp_server.html)** — give your LLM or agent access to Gust: list DAGs, trigger runs, explore definitions, and debug executions.

**Observability**
  - **Web UI** for live monitoring of DAGs and runs, plus secrets editing.
  - **Run-time tracking** of task execution state and history.
  - **[Error tracking](https://hexdocs.pm/gust/error_tracking.html)** — asynchronously report terminal task failures to Sentry or another provider, without interrupting DAG execution.

---

## Guides

**Gust**
  - [Writing DAGs](https://hexdocs.pm/gust/writing_dags.html)
  - [Configuration](https://hexdocs.pm/gust/configuration.html)
  - [Gust Roles](https://hexdocs.pm/gust/roles.html)
  - [Error Tracking](https://hexdocs.pm/gust/error_tracking.html)

**Gust Web**
  - [Installation](https://hexdocs.pm/gust_web/installation.html)
  - [MCP Server](https://hexdocs.pm/gust_web/mcp_server.html)
  - [HTTP API](https://hexdocs.pm/gust_web/http_api.html)

**Gust Python**
  - [Installation](https://hexdocs.pm/gust_py/installation.html)
  - [Writing Python DAGs](https://hexdocs.pm/gust_py/writing_python_dags.html)
  - [Under the Hood](https://hexdocs.pm/gust_py/under_the_hood.html)

**Repo**
  - [Contributing](https://github.com/marciok/gust/blob/main/CONTRIBUTING.md)

---

## Benchmark

Gust is significantly more resource-efficient than Apache Airflow, requiring
up to 4.4× less memory when idle and roughly half the peak RAM to handle
identical parallel workloads, while maintaining a lower CPU footprint during
orchestration.

<img width="1600" height="600" alt="Gust vs Airflow benchmark" src="https://github.com/user-attachments/assets/34be8e55-49d8-4d61-a1b0-aa5eb738420b" />


See the [gust-benchmark](https://github.com/marciok/gust-benchmark) repo for
the full methodology, results, and how to reproduce it.

---
### Sponsors


![Comparacar](https://gust-github.s3.us-east-1.amazonaws.com/comparacar-sponsor-v2.jpg)


[Find the best offers and save money on car subscription service.](https://comparacar.com.br)


## License

Gust is released under the MIT License.


---

![No more Astronomer hefty bills](https://gust-github.s3.us-east-1.amazonaws.com/gust-airflow.png)
