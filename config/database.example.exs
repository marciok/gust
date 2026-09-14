# Configuration example for Database-based DAG source
#
# To use this configuration:
# 1. Run the migration to create gust_dag_sources table:
#    mix ecto.migrate
#
# 2. Insert DAGs into the database (via SQL or migration):
#    INSERT INTO gust_dag_sources (name, content, format, enabled, inserted_at, updated_at)
#    VALUES ('my_dag', 'defmodule MyDAG do...', 'elixir', true, now(), now());
#
# 3. Or source this config by adding to config/config.exs:
#    import_config "database.exs"

import Config

config :gust,
  dag_source: {
    Gust.DAG.Source.Database,
    poll_seconds: String.to_integer(System.get_env("DAG_POLL_SECONDS", "30"))
  }
