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
