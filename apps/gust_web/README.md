# GustWeb

The web UI for Gust.

---

GustWeb is a Phoenix web server. Run `mix phx.server` to start it.

By default, it also starts the Gust core, which means DAGs are loaded and executed.

If you are working in multi-node mode and want to run only the web server, use:

`GUST_ROLE=web mix phx.server`

---

## API

GustWeb includes a small HTTP API for triggering DAG runs and resuming tasks
that are waiting on external events.

Mount it inside any Phoenix API scope with the `GustWeb.API` router macro:

```elixir
import GustWeb.API

scope "/gust/api", MyAppWeb do
  pipe_through :api

  gust_api()
end
```

Requests must include a bearer token matching the configured
`:gust_web, :api_token`; in releases, the default runtime config reads it from
`GUST_API_TOKEN`.

### Available endpoints

| Method | Path | Description |
| --- | --- | --- |
| `POST` | `/gust/api/dags/:dag_name/run` | Create and dispatch a run for a DAG. |
| `POST` | `/gust/api/tasks/resume` | Resume task runs paused by `wait_for`. |

### Trigger a DAG run

`POST /gust/api/dags/:dag_name/run`

Body:

```json
{
  "params": {
    "name": "Ada"
  }
}
```

```sh
curl -X POST http://localhost:4000/gust/api/dags/daily_import/run \
  -H "Authorization: Bearer $GUST_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"params":{"name":"Ada"}}'
```

Successful requests return `201 Created` with the new run id and status:

```json
{
  "id": "123",
  "status": "enqueued"
}
```

Disabled DAGs create a run without enqueueing it and return `"status": "created"`.

### Resume a waiting task

`POST /gust/api/tasks/resume`

Body:

```json
{
  "waiting_for": "approval",
  "run_id": 123,
  "payload": {
    "approved": true,
    "reviewed_by": "marcio"
  }
}
```

```sh
curl -X POST http://localhost:4000/gust/api/tasks/resume \
  -H "Authorization: Bearer $GUST_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"waiting_for":"approval","run_id":123,"payload":{"approved":true,"reviewed_by":"marcio"}}'
```

`waiting_for` must match the task's `wait_for` key. `run_id` is optional; when
omitted, Gust resumes every waiting task with the same key. `payload` is made
available to the resumed task params under `"__gust_wait_payload__"`.

Successful requests return `200 OK` with the resumed tasks:

```json
[
  {
    "id": "456",
    "run_id": "123",
    "name": "await_approval",
    "status": "created",
    "params": {
      "__gust_wait_payload__": {
        "approved": true,
        "reviewed_by": "marcio"
      }
    },
    "result": null,
    "error": null,
    "waiting_for": null,
    "wait_satisfied_at": "2026-07-02T19:00:00Z",
    "attempt": 0,
    "map_index": null
  }
]
```

### Errors

Unknown DAGs return `404` with `{"error":"dag_not_found"}`, and invalid tokens
return `401` with `{"error":"unauthorized"}`.
