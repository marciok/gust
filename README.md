<p align="center">
  <picture>
    <img alt="Gust" src="https://gust-github.s3.us-east-1.amazonaws.com/gust-symbol-logo.png" width="320">
  </picture>
</p>

<p align="center">
A task orchestration system designed to be efficient, fast, developer-friendly, and easy to scale. Built on the Erlang VM, Gust recovers gracefully from failures, supports manual retries, and is production-ready.
</p>

<div align="center">

  [![Build](https://github.com/marciok/gust/actions/workflows/test.yml/badge.svg)](https://github.com/marciok/gust/actions/workflows/test.yml)
  [![coverage](https://coveralls.io/repos/github/marciok/gust/badge.svg?branch=main)](https://coveralls.io/github/marciok/gust?branch=main)

</div>

<div align="center">

  [![Gust Web](https://img.shields.io/hexpm/v/gust_web?color=0084d1&label=Gust+Web)](https://hexdocs.pm/gust_web)
  [![Gust](https://img.shields.io/hexpm/v/gust?color=0084d1&label=Gust)](https://hexdocs.pm/gust)
  [![Gust Python](https://img.shields.io/hexpm/v/gust?color=0084d1&label=Gust+Python)](https://hexdocs.pm/gust_py)
  [![Gust Shell](https://img.shields.io/hexpm/v/gust?color=0084d1&label=Gust+Shell)](https://hexdocs.pm/gust_shell)
  [![License](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/license/MIT)

</div>

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

- [Why Gust](#why-gust)
- [Table of Contents](#table-of-contents)
- [Overview](#overview)
  - [DAG Code Example](#dag-code-example)
  - [Web Interface](#web-interface)
  - [Shell tasks](#shell-tasks)
- [Getting started](#getting-started)
- [Features](#features)
  - [MCP Server](#mcp-server)
  - [Connect to an MCP client](#connect-to-an-mcp-client)
  - [Skills](#skills)
- [Guides](#guides)
- [Benchmark](#benchmark)
  - [Sponsors](#sponsors)
- [License](#license)

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
### Web Interface

![ss-1](https://gust-github.s3.us-east-1.amazonaws.com/gustweb-01.png)
![ss-2](https://gust-github.s3.us-east-1.amazonaws.com/gustweb-02.png)
![ss-3](https://gust-github.s3.us-east-1.amazonaws.com/gustweb-03.png)
![ss-4](https://gust-github.s3.us-east-1.amazonaws.com/gustweb-04.png)

### Shell tasks

Gust also supports shell-backed tasks for command execution workflows via `gust_shell`. Shell DAGs are defined in YAML, and each task executes its required `run` command. Stdout and stderr are captured and returned to the runtime as structured task output.

This is a shell DAG example, not an Elixir DSL task definition.

```yaml
tasks:
  - name: backup
    run: tar -czf /tmp/backup.tar.gz /var/data
```

At runtime, Gust launches the command using the shell adapter, tracks the OS process, and emits a result like:

```elixir
%{
  status: :success,
  stdout: "...",
  stderr: "...",
  exit_code: 0
}
```

If the process exits with a non-zero status, the task result is returned as an error payload with the captured output and exit code intact. For signal-based termination, the `exit_code` contains the signal atom name (for example `:sigterm` or `:sigkill`) rather than a numeric exit status.

---

## Getting started

- [Quickstart with Docker](https://github.com/marciok/gust/tree/main/examples/docker)
- [Setup a new Gust project](https://hexdocs.pm/gust_web/installation.html)

---

## Features

  - Task orchestration with Cron-style scheduling and dependency-aware DAGs via the Gust DSL.
  - Shell-backed tasks for running OS commands and capturing stdout, stderr, and exit codes.
  - Configurable DAG sources: filesystem, S3, git, database.
  - Parallel task mapping with `:map_over`, creating one task instance per upstream list item.
  - Conditional task skipping with `:skip_if`; dependent downstream tasks are skipped when an upstream task is skipped.
  - Durable task waiting with `:wait_for`, so a DAG can pause until another DAG, webhook, or external process resumes it.
  - Support multiple nodes.
  - [Support for Python DAGs](https://github.com/marciok/gust/tree/main/apps/gust_py)
  - Manual task controls: stop running tasks, cancel retries, and restart tasks on demand.
  - Run-time tracking, corrupted-state recovery, and graceful handling of syntax errors during development.
  - Retry logic with backoff, plus state clearing for clean restarts.
  - Hook for finished dag run.
  - Web UI for live monitoring, runs and secrets editing.

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
### MCP Server

GustWeb includes a built-in MCP server that gives your LLM access to Gust’s core features, including listing DAGs, triggering runs, exploring DAG definitions, and debugging executions.

To mount it in your Phoenix router:

```elixir
import GustWeb.MCPRouter

scope "/mcp", MyAppWeb do
  pipe_through :api
  gust_mcp_server()
end
```

The prefix comes from your `MyAppWeb` router scope, so you can also mount it
under a project-specific path to avoid clashes:

```elixir
scope "/gust/mcp", MyAppWeb do
  pipe_through :api
  gust_mcp_server()
end
```

That would expose `POST /gust/mcp/server`. Keep auth and any app-specific
policy outside the macro, at the router scope or pipeline level.

### Connect to an MCP client
- claude: `claude mcp add --transport http gust-mcp http://localhost:4000/gust/mcp/server`
- codex: `codex mcp add gust-mcp --url http://localhost:4000/gust/mcp/server`

### Skills

- [Available Skills](https://github.com/marciok/gust/tree/main/skills)

- Install
```
gh skill install marciok/gust elixir-dag-creator
```

---

## Guides

**Gust**
  - [Writing DAGs](https://hexdocs.pm/gust/writing_dags.html)
  - [Configuration](https://hexdocs.pm/gust/configuration.html)
  - [DAG Sources](https://hexdocs.pm/gust/dag_sources.html)
  - [Gust Roles](https://hexdocs.pm/gust/roles.html)
  - [Error Tracking](https://hexdocs.pm/gust/error_tracking.html)

**Gust Shell**
  - [Shell DAGs](apps/gust_shell) — YAML and shell command orchestration
  - [Task Options](apps/gust_shell#task-options) — Process control, environment, and output handling

**Gust Python**
  - [Installation](https://hexdocs.pm/gust_py/installation.html)
  - [Writing Python DAGs](https://hexdocs.pm/gust_py/writing_python_dags.html)
  - [Under the Hood](https://hexdocs.pm/gust_py/under_the_hood.html)

**Gust Web**
  - [Installation](https://hexdocs.pm/gust_web/installation.html)
  - [MCP Server](https://hexdocs.pm/gust_web/mcp_server.html)
  - [HTTP API](https://hexdocs.pm/gust_web/http_api.html)

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
