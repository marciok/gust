# Gust on Docker

This folder contains Docker examples for running Gust without creating a Phoenix app from scratch.

If this is your first time trying Gust, start with the single-node setup. It is the fastest way to get the UI, the database, and DAG execution running locally.

## Choose a setup

- [Single-node](https://github.com/marciok/gust/tree/main/examples/docker/single-node): one Gust container handles both the web UI and DAG scheduling/execution.
- [Multi-node](https://github.com/marciok/gust/tree/main/examples/docker/multi-node): one container handles the web UI and one or more separate containers handle DAG scheduling/execution.

## Prerequisites

- Docker
- Docker Compose via `docker compose`

## Recommended first run: single-node

1. Create a working directory for the Docker setup:

```sh
mkdir gust-docker
cd gust-docker
```

2. Download the example `docker-compose.yml` file:

```sh
curl -fsSL https://raw.githubusercontent.com/marciok/gust/main/examples/docker/single-node/docker-compose.yml -o docker-compose.yml
```

3. Generate the required secrets.

Generate `B64_SECRETS_CLOAK_KEY`:

```sh
openssl rand -base64 32
```

Generate `SECRET_KEY_BASE`:

```sh
mix phx.gen.secret
```

If you do not have Phoenix installed locally, use this fallback value instead:

```sh
openssl rand -hex 32
```

4. Open `docker-compose.yml` and replace these placeholders:

- `ADD_HERE_AS_BASE64`
- `ADD_HERE_SECRET_KEY_BASE`
- `admin` for `BASIC_AUTH_USER`
- `admin` for `BASIC_AUTH_PASS`

5. Create the DAG folder expected by the container:

```sh
mkdir dags
```

Your folder should now look like this:

```text
gust-docker/
├── dags/
└── docker-compose.yml
```

6. Download an example DAG into the `dags` folder:

```sh
curl -fsSL https://raw.githubusercontent.com/marciok/gust/main/examples/dags/hello_world.ex -o dags/hello_world.ex
```

7. Start Gust:

```sh
docker compose up
```

8. Open the UI:

```text
http://localhost:4000/gust
```

Use the `BASIC_AUTH_USER` and `BASIC_AUTH_PASS` values you set in `docker-compose.yml`.

## What each single-node service does

- `db`: PostgreSQL database used by Gust.
- `gust-init`: runs database migrations once before the app starts.
- `gust-web`: serves the UI and also schedules and executes DAGs in the single-node setup.

## Multi-node setup

Use multi-node when you want to keep the web UI separate from the workers that schedule and execute DAGs.

1. Create a working directory:

```sh
mkdir gust-docker
cd gust-docker
```

2. Download the multi-node compose file:

```sh
curl -fsSL https://raw.githubusercontent.com/marciok/gust/main/examples/docker/multi-node/docker-compose.yml -o docker-compose.yml
```

3. Generate and replace the same required secrets:

- `B64_SECRETS_CLOAK_KEY`
- `SECRET_KEY_BASE`

Also review these distributed-node settings in the compose file:

- `RELEASE_COOKIE`: must be the same across all Gust nodes.
- `DNS_CLUSTER_QUERY`: used so the nodes can find each other.
- `BASIC_AUTH_USER`
- `BASIC_AUTH_PASS`

4. Create the DAG folder:

```sh
mkdir dags
```

5. Download an example DAG:

```sh
curl -fsSL https://raw.githubusercontent.com/marciok/gust/main/examples/dags/hello_world.ex -o dags/hello_world.ex
```

6. Start the stack:

```sh
docker compose up
```

7. Open the UI:

```text
http://localhost:4000/gust
```

## What each multi-node service does

- `db`: PostgreSQL database.
- `gust-init`: runs database migrations once.
- `gust-web`: serves the UI and loads DAG files.
- `gust`: runs the `core` role responsible for scheduling and executing DAGs.

Both `gust-web` and `gust` mount the same local `./dags` folder, so keep your DAG files there.

## Useful next steps

- Add more DAG files to `dags/` and restart the stack if needed.
- Start from the example DAGs in [examples/dags](https://github.com/marciok/gust/tree/main/examples/dags).
- Read the DSL docs at [hexdocs.pm/gust/Gust.DSL.html](https://hexdocs.pm/gust/Gust.DSL.html).
