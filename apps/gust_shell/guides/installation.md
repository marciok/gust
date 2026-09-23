# Installation

**Attention:** this assumes you already have a Gust project.

1. Add `gust_shell` to your Gust project's `mix.exs` file:

   ```elixir
   defp deps do
     [
       # Your other deps, such as {:gust_web, "..."},
       {:gust_shell, "~> 0.1.0"},
       # ...
     ]
   end
   ```

2. Declare the adapter in your `config.exs`:

   ```elixir
   config :gust,
     dag_adapter: [
       shell: %{
         parser: GustShell.Parser.Adapter,
         runtime: GustShell.Runtime.Adapter,
         task_worker: GustShell.TaskWorker.Adapter
       }
     ]
   ```

3. Drop `.yml` files in your DAG folder. Gust picks them up like any other DAG.

Make sure the commands your DAGs call (such as `tar`, `aws` or `docker`) are
installed on the machine running Gust.
