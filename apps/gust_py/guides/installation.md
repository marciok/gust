# Installation

**Attention:** this assumes you already have a Gust project.

1. Add `gust_py` to your Gust project's `mix.exs` file:

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

3. [Install Python's uv package manager](https://docs.astral.sh/uv/) in your DAG folder.

4. Add the `gust-py` [dependency](https://github.com/marciok/gust_py):

   ```bash
   uv add gust-py
   ```

You may also install any other dependencies your DAGs need, such as numpy or
pytorch.

## Environment variables

Python DAGs inherit the environment of your Gust app, like any code you
deploy with it (see "Trusted code" in the Writing DAGs guide). To keep values
such as `DATABASE_URL` or `SECRET_KEY_BASE` out of reach of DAG code and out
of task logs, start `uv` with a cleared environment:

```elixir
config :gust_py, :clear_env, true
```

`uv` then only receives `PATH`, `HOME`, the user, shell, temp dir, timezone,
locale, XDG directories, TLS certificate and proxy settings, and any `UV_*`
variable. Read secrets with `get_secret_by_name`, and list any other variables
your DAGs need by name:

```elixir
config :gust_py, :env_passthrough, ["AWS_PROFILE", "HF_HOME"]
```
