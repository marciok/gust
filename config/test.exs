import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :gust, Gust.Repo,
  hostname: System.get_env("PGHOST"),
  username: System.get_env("PGUSER"),
  password: System.get_env("PGPASSWORD"),
  database: "gust_rc_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :gust_web, GustWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "dWKtgAuY24rgqDQCLkN9S5CaOqSFzdrnqO4iHqVlIp5uLQPB6MjVJqlEN7w1nOvX",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# In test we don't send emails
config :gust, Gust.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

config :gust, dag_runner_supervisor: Gust.DAGRunnerSupervisorMock
config :gust, dag_task_runner_supervisor: Gust.DAGTaskRunnerSupervisorMock
config :gust, file_reload_delay: 0
config :gust, b64_secrets_cloak_key: "PF4/V7ZLI8Nyjymua0eUy2K8q/lcSFi3USe3UUDb7sY="
