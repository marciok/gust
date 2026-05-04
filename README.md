
<p align="center">
  <picture>
    <img alt="Gust" src="https://gust-github.s3.us-east-1.amazonaws.com/gust-symbol-logo.png" width="320">
  </picture>
</p>

<p align="center">
A task orchestration system designed to be efficient, fast and developer-friendly.
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
</p>

---

## Table of Contents

- [Motivation](#motivation)
- [Overview](#overview)
- [Getting Started](#getting-started)
- [Adding to an existing app](#adding-gust-to-an-existing-phoenix-app)
- [Getting Started with Docker](#getting-started-with-docker)
- [Features](#features)
- [Examples](https://github.com/marciok/gust/tree/main/examples)
- [Upgrading from 0.1.29](#upgrading-from-0.1.29)


---
## Motivation
As a CTO and founder, I was tired of spending buckets of money to set up and manage [Airflow](https://airflow.apache.org/), dealing with multiple databases, countless processes, Docker complexity, and of course its outdated and buggy UI. So we decided to build something that kept what we liked about Airflow and ditched what we didn’t. The result is Gust: a platform that’s 10× more efficient, faster, and far easier to set up.

Gust is the perfect fit for our needs, and I encourage you to try it and push it even further. There’s still plenty of room for improvements and new features. If you spot something or want to contribute an idea, don’t be shy! Drop an Issue or submit a PR.

---
## Overview

### DAG Code Example
```elixir
defmodule HelloWorld do
  # `schedule` and `on_finished_callback` are optional.
  # You can use special expressions provided by the quantum package, ex: @daily, @hourly, and etc..
  # https://hexdocs.pm/quantum/crontab-format.html
  use Gust.DSL, schedule: "* * * * *", on_finished_callback: :notify_something

  # Gust logs are stored and displayed through GustWeb via Logger.
  require Logger

  # Gust.Flows is used to query Dag, Run, and Task.
  alias Gust.Flows

  # Defining a callback for when run is done.
  def notify_something(status, run) do
    dag = Flows.get_dag!(run.dag_id)
    message = "DAG: #{dag.name}; completed with status: #{status}"
    Logger.info(message)
  end

  # Declaring "first_task" task; setting a downstream task and telling Gust to store its result.
  task :first_task, downstream: [:second_task], save: true do
    greetings = "Hi from first_task"
    Logger.info(greetings)

    # You can get secrets created on the Web UI
    secret = Flows.get_secret_by_name("SUPER_SECRET")
    Logger.warning("I know your secret: #{secret.value}")

    # The return value must be a map when `save` is true.
    %{result: greetings}
  end
  
  # Declaring "second_task" task; using context to fetch another task result.
  task :second_task, ctx: %{run_id: run_id} do

    # Getting "first_task"'s result
    task = Flows.get_task_by_name_run("first_task", run_id)

    Logger.info(task.result)
  end
end

```

### Web Interface

![ss-1](https://gust-github.s3.us-east-1.amazonaws.com/gust-ss-1.png)

![ss2](https://gust-github.s3.us-east-1.amazonaws.com/gust-ss-2.png)

--- 

## Getting started

### Prerequisites

- [x] macOS/Ubuntu
- [x] Elixir must be at least [this version](https://github.com/marciok/gust/blob/main/.tool-versions)
- [x] Postgres


### Creating a new Gust app

1. Replace `my_app` for your app name and run:

```
GUST_APP=my_app bash -c "$(curl -fsSL https://raw.githubusercontent.com/marciok/gust/main/setup_gust_app.sh)"

```
	 
2. Configure Postgres credentials on `my_app/config/dev.exs`

3. Run database setup:
	 - `mix ecto.create`
	 - `mix ecto.migrate`
	 
4. Run Gust start:
	 `mix phx.server`


5. Check [the docs](https://hexdocs.pm/gust/Gust.DSL.html) on how to customize your DAG

6. Open  "http://localhost:4000/gust" to visualize your app

--- 

## Getting started with Docker

### Prerequisites

- [x] Docker
- [x] Docker Compose (`docker compose`)

### Single-node setup

1. Download the example `docker-compose.yml` file:

```sh
curl -fsSL https://raw.githubusercontent.com/marciok/gust/main/examples/docker/single-node/docker-compose.yml -o docker-compose.yml
```

2. Generate the required secrets:

`B64_SECRETS_CLOAK_KEY`

```sh
openssl rand -base64 32
```

`SECRET_KEY_BASE`

```sh
mix phx.gen.secret
```

If you do not have Phoenix installed locally, generate a compatible fallback value with:

```sh
openssl rand -hex 32
```

3. Replace the placeholders in `docker-compose.yml`:

- `B64_SECRETS_CLOAK_KEY`
- `SECRET_KEY_BASE`
- `BASIC_AUTH_USER`
- `BASIC_AUTH_PASS`

4. Create a local `dags` folder:

```sh
mkdir dags
```

5. Download an example DAG:

```sh
curl -fsSL https://raw.githubusercontent.com/marciok/gust/main/examples/dags/hello_world.ex -o dags/hello_world.ex
```

6. Start Gust:

```sh
docker compose up
```


---

## Features

  - Task orchestration with Cron-style scheduling and dependency-aware DAGs via the Gust DSL.
  - Support multiple nodes.
  - [Support for Python DAGs](https://github.com/marciok/gust/tree/main/apps/gust_py)
  - Manual task controls: stop running tasks, cancel retries, and restart tasks on demand.
  - Run-time tracking, corrupted-state recovery, and graceful handling of syntax errors during development.
  - Retry logic with backoff, plus state clearing for clean restarts.
  - Hook for finished dag run.
  - Web UI for live monitoring, runs and secrets editing.


---
### MCP Server

GustWeb includes a built-in MCP server that gives your LLM access to Gust’s core features, including listing DAGs, triggering runs, exploring DAG definitions, and debugging executions.

To enable it, add the following to your config file:

```elixir
# dev.exs
config :gust_web, mcp_enabled: true
```

### Connect to an MCP client

- claude: `claude mcp add --transport http gust-mcp http://localhost:4000/mcp/server`
- codex: `codex mcp add gust-mcp --url http://localhost:4000/mcp/server`

### Skills

- [Available Skills](https://github.com/marciok/gust/tree/main/skills)


---


## Adding Gust to an existing Phoenix app

If you already have a Phoenix project and want to add Gust in place, install `gust_web` with [Igniter](https://hexdocs.pm/igniter).

### Upgrading from 0.1.29

This note applies only to projects upgrading from Gust `0.1.29` to `0.1.30`
or later.

Starting with Gust `0.1.30`, `Gust.Repo` stores its migration history in
`gust_schema_migrations` instead of the default `schema_migrations` table.
Fresh installs do not need any special handling.

If your project already ran Gust migrations on `0.1.29`, you must bootstrap
the new migration-tracking table before running `mix ecto.migrate`. Otherwise
Ecto will treat all Gust migrations as pending and attempt to run them again.

Run this SQL once against your database before migrating:

```sql
CREATE TABLE IF NOT EXISTS gust_schema_migrations (
  version bigint PRIMARY KEY,
  inserted_at timestamp(0) without time zone
);

INSERT INTO gust_schema_migrations (version, inserted_at)
SELECT version, inserted_at
FROM schema_migrations
WHERE version IN (
  20250806203011,
  20250815190135,
  20250815205059,
  20250930125654,
  20251026200057,
  20251031173208,
  20251230160539,
  20260429173000
)
ON CONFLICT (version) DO NOTHING;
```

After that, continue with `mix ecto.migrate` as usual.

1. If you do not have Igniter installed yet, bootstrap it first:

```sh
mix local.hex --force
mix archive.install hex igniter_new --force
```

2. From the root of your existing Phoenix project, install `gust_web`:

```sh
mix igniter.install gust_web
```

It will mount the dashboard at `/gust` in your router, and create a `dags/` folder.

3. Review your database config.

Open `dev.exs` and set `Gust.Repo`s credentials

4. Run setup and start the app:

```sh
mix ecto.create
mix ecto.migrate
mix phx.server
```

Open "http://localhost:4000/gust".

---

### Multi-node 

You can run Gust on multiple nodes by passing a role:
-   `core`: Starts only children who are responsible for the pool and executing DAGs
```zsh
GUST_ROLE=core iex --sname core -S mix run --no-halt
```
-   `web`: Starts the server and reads DAG's file children.
```zsh
GUST_ROLE=web iex --sname web -S mix phx.server
```
If you don't pass anything Gust will run as `single` role, that means both `core` and `web` will be enabled.

### Multi-node on Docker
To use Gust on Docker it is straight forward, generate a Docker file using the Phoenix command:
```zsh
mix phx.gen.release --docker
```
Include this line to copy your `dags` folder:
```zsh
COPY dags /app/dags
```

After the Dockerfile is set, create a `docker-compose.yml` to include the rest of the dependencies.
```yml
services:
  db:
    image: postgres:16-alpine
    container_name: gust_db
    environment:
      POSTGRES_USER: gust
      POSTGRES_PASSWORD: gust
      POSTGRES_DB: gust_prod
    ports:
      - "5432:5432"
    volumes:
      - gust_pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U gust -d gust_prod"]
      interval: 5s
      timeout: 3s
      retries: 20

  web:
    build:
      context: .
      args:
          RELEASE_NAME: gust_web # Set a release name for DNSCluster to connect nodes 
    depends_on:
      db:
        condition: service_healthy
    ports:
      - "4000:4000"
    environment:
      RELEASE_COOKIE: "a-very-long-random-secret-same-for-all-nodes"
      PHX_SERVER: "true"
      PHX_HOST: "localhost"
      PORT: "4000"
      B64_SECRETS_CLOAK_KEY: YOUR_KEY
      SECRET_KEY_BASE: YOUR_KEY
      DATABASE_URL: "ecto://gust:gust@db:5432/gust_prod"
      POOL_SIZE: "10"
      GUST_ROLE: "web" # Web Gust role
      DNS_CLUSTER_QUERY: "core" # Query 'core' to connect nodes.
      # Note: You have to update `server` file so nodes can connect.
    command: ["/app/bin/server"] # See server script configuration below".
  core:
    deploy:
      replicas: 3
    build:
      context: .
      args:
          RELEASE_NAME: gust_core # Set a release name for DNSCluster to connect nodes 
    depends_on:
      db:
        condition: service_healthy
    environment:
      RELEASE_COOKIE: "a-very-long-random-secret-same-for-all-nodes"
      B64_SECRETS_CLOAK_KEY: YOUR_KEY
      SECRET_KEY_BASE: YOUR_KEY
      DATABASE_URL: "ecto://gust:gust@db:5432/gust_prod"
      POOL_SIZE: "10"
      GUST_ROLE: "core" # Core Gust role
      # Note: You have to create `start-core` on `rel/overlays/bin/`
    command: ["/app/bin/start-core"] # See start-core script instructions below.
volumes:
  gust_pgdata:
```
 
 Edit `server` file to allow nodes to connect:
 ```
 #!/bin/sh
set -eu

IP="$(hostname -i | awk '{print $1}')"
export RELEASE_DISTRIBUTION=name # Needed for DNSCluster
export RELEASE_NODE="gust@${IP}" # Needed for DNSCluster

cd -P -- "$(dirname -- "$0")"
PHX_SERVER=true exec ./my_app start
 ```

Create a `start-core` file on `rel/overlays/bin/` and `chmod a+x rel/overlays/bin/start-core`
```
#!/bin/sh
set -eu
IP="$(hostname -i | awk '{print $1}')"

export RELEASE_DISTRIBUTION=name # Needed for DNSCluster
export RELEASE_NODE="gust@${IP}" # Needed for DNSCluster

exec /app/bin/my_app start
```
 **Note:  There's some repetition, in the future we will have one file to start both Gust roles**


## How to Run Tests Locally

1. Start Postgres.
2. Copy `.env.example` to `.env.test`:
   ```bash
   cp .env.example .env.test
   ```
3. Load test environment variables:
   ```bash
   source .env.test
   ```
4. Install dependencies:
   ```bash
   mix setup
   ```
5. Create and migrate the test database:
   ```bash
   MIX_ENV=test mix ecto.create
   MIX_ENV=test mix ecto.migrate
   ```
6. Run tests:
   ```bash
   mix test
   ```

### Useful Commands

```bash
mix test test/path/to/file_test.exs
mix test --failed
MIX_ENV=test mix coveralls.html --umbrella
```

### Common Failures

- `connection refused`: Postgres is not running or `PGHOST`/`PGUSER`/`PGPASSWORD` are incorrect.
- `database "gust_rc_test" does not exist`: run `MIX_ENV=test mix ecto.create && MIX_ENV=test mix ecto.migrate`.


---
### Sponsors


![Comparacar](https://gust-github.s3.us-east-1.amazonaws.com/comparacar-sponsor-v2.jpg)


[Find the best offers and save money on car subscription service.](https://comparacar.com.br)


## License

Gust is released under the MIT License.


---

![No more Astronomer hefty bills](https://gust-github.s3.us-east-1.amazonaws.com/gust-airflow.png)
