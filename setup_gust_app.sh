#!/usr/bin/env sh

set -e

if ! command -v elixir >/dev/null 2>&1; then
  echo "ERROR: Elixir is not installed or not in PATH."
  echo "Please install Elixir before running this installer."
  exit 1
fi

ELIXIR_VERSION=$(elixir -v | grep "Elixir" | awk '{print $2}')

echo "Detected Elixir version: $ELIXIR_VERSION"

echo "==> Gust Project Generator"
echo

GUST_APP=${GUST_APP:-${1:-}}

if [ -z "$GUST_APP" ]; then
  printf "Enter your app name (ex: my_app): "
  read GUST_APP
fi

if [ -z "$GUST_APP" ]; then
  echo "ERROR: app name cannot be empty"
  exit 1
fi

echo "==> Creating new Elixir supervised app: $GUST_APP"
mix new "$GUST_APP" --sup

cd "$GUST_APP"

echo "==> Adding Gust + Plug dependencies to mix.exs"

# Insert deps inside defp deps do ... end
# sed is portable across Linux/macOS using this strategy
# sed -i.bak 's/{:logger, "~> 1.0"}/{:logger, "~> 1.0"}/' mix.exs

sed -i.bak '/defp deps do/,/end/ c\
  defp deps do\
    [\
      {:plug_cowboy, "~> 2.7", only: :prod},\
      {:hackney, "~> 1.9"},\
      {:file_system, "~> 1.1", only: :dev},\
      {:gust_web, "0.1.23"}\
    ]\
  end
' mix.exs

rm mix.exs.bak

echo "==> Installing dependencies"
mix deps.get

echo "==> Creating dags directory"
mkdir -p dags

echo "==> Creating config files"

mkdir -p config

cat >config/config.exs <<EOF
import Config

config :${GUST_APP},
  ecto_repos: [Gust.Repo]

config :gust, dag_logger: Gust.DAG.Logger.Database

config :logger, :default_formatter,
  format: "\$time \$metadata[\$level] \$message\n",
  metadata: [:request_id, :task_id, :attempt]

config :logger, backends: [:console, Gust.DAG.Logger.Database]

import_config "#{config_env()}.exs"
EOF

echo "==> Creating dev config file"

echo "==> Generating SIGNING_SALT"
SIGNING_SALT=$(elixir -e 'IO.puts(:crypto.strong_rand_bytes(8) |> Base.encode64(padding: false) |> binary_part(0, 8))')
PROD_SIGNING_SALT=$(elixir -e 'IO.puts(:crypto.strong_rand_bytes(8) |> Base.encode64(padding: false) |> binary_part(0, 8))')

echo "==> Generating SECRET_KEY_BASE"
SECRET_KEY_BASE=$(elixir -e 'IO.puts(:crypto.strong_rand_bytes(64) |> Base.encode64(padding: false) |> binary_part(0, 64))')

echo "==> Generating B64_SECRETS_CLOAK_KEY"
B64_SECRETS_CLOAK_KEY=$(elixir -e 'IO.puts(Base.encode64(:crypto.strong_rand_bytes(64)))')

cat >.gitignore <<EOF
# The directory Mix will write compiled artifacts to.
/_build/

# If you run "mix test --cover", coverage assets end up here.
/cover/

# The directory Mix downloads your dependencies sources to.
/deps/

# Where third-party dependencies like ExDoc output generated docs.
/doc/

# Ignore .fetch files in case you like to edit your project deps locally.
/.fetch

# If the VM crashes, it generates a dump, let's ignore it too.
erl_crash.dump

# Also ignore archive artifacts (built via "mix archive.build").
*.ez

# Ignore package tarball (built via "mix hex.build").
${GUST_APP}-*.tar

# Temporary files, for example, from tests.
/tmp/
EOF

cat >config/dev.exs <<EOF
import Config

config :gust_web, GustWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: GustWeb.ErrorHTML, json: GustWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Gust.PubSub,
  live_view: [signing_salt: "${SIGNING_SALT}"],
  http: [ip: {127, 0, 0, 1}, port: String.to_integer(System.get_env("PORT") || "4000")],
  check_origin: false,
  secret_key_base: "${SECRET_KEY_BASE}"

config :gust, Gust.Repo,
  username: System.get_env("PGUSER") || raise("environment variable PGUSER is missing"),
  password: System.get_env("PGPASSWORD") || raise("environment variable PGPASSWORD is missing"),
  hostname: System.get_env("PGHOST") || raise("environment variable PGHOST is missing"),
  database: "${GUST_APP}_gust_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :gust, dags_folder: Path.join(File.cwd!(), "dags")
config :gust, file_reload_delay: 1_000

config :gust, b64_secrets_cloak_key: "${B64_SECRETS_CLOAK_KEY}"

config :gust, dag_runner_supervisor: Gust.DAG.RunnerSupervisor.DynamicSupervisor
config :gust, dag_task_runner_supervisor: Gust.DAG.TaskRunnerSupervisor.DynamicSupervisor
config :gust, dag_stage_runner_supervisor: Gust.DAG.StageRunnerSupervisor.DynamicSupervisor
config :gust, dag_scheduler: Gust.DAG.Scheduler.Worker
config :gust, dag_loader: Gust.DAG.Loader.Worker
config :gust, dag_stage_runner: Gust.DAG.Runner.StageWorker
EOF

cat >config/test.exs <<EOF
import Config

EOF

cat >config/runtime.exs <<EOF
import Config

if config_env() == :prod do
  config :gust, b64_secrets_cloak_key: System.get_env("B64_SECRETS_CLOAK_KEY")

  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :gust, Gust.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :gust_web, GustWeb.Endpoint,
    server: true,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base

  config :gust, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")
end
EOF

cat >config/prod.exs <<EOF
import Config

config :gust_web, GustWeb.Endpoint,
  cache_static_manifest: "priv/static/cache_manifest.json",
  secret_key_base: System.get_env("SECRET_KEY_BASE") || raise("environment variable SECRET_KEY_BASE is missing."),
  check_origin: true,
  live_view: [signing_salt: "${PROD_SIGNING_SALT}"]

# Configures Swoosh API Client
config :swoosh, :api_client, Swoosh.ApiClient.Req

# Disable Swoosh Local Memory Storage
config :swoosh, local: false

# Do not print debug messages in production
config :logger, level: :info

config :gust_web, basic_auth: true

config :gust, dags_folder: Path.join(File.cwd!(), "dags")

config :gust, dag_runner_supervisor: Gust.DAG.RunnerSupervisor.DynamicSupervisor
config :gust, dag_task_runner_supervisor: Gust.DAG.TaskRunnerSupervisor.DynamicSupervisor
config :gust, dag_stage_runner_supervisor: Gust.DAG.StageRunnerSupervisor.DynamicSupervisor
config :gust, dag_scheduler: Gust.DAG.Scheduler.Worker
config :gust, dag_loader: Gust.DAG.Loader.Worker
config :gust, dag_stage_runner: Gust.DAG.Runner.StageWorker
EOF

echo "==> Creating sample DAG in dags/hello_world.ex"

cat >dags/hello_world.ex <<EOF
defmodule HelloWorld do
  # Schedule is optional, if you change, make sure to restart the server 
  # in order to update the cron job.
  use Gust.DSL, schedule: "* * * * *"
  require Logger

  task :first_task, downstream: [:second_task], store_result: true do
    greetings = "Hi from first_task"
    Logger.info(greetings)
    # The return value must be a map when store result is true
    %{result: greetings}
  end

  task :second_task, ctx: %{run_id: run_id} do
    task = Gust.Flows.get_task_by_name_run("first_task", run_id)
    Logger.info(task.result)
  end
end
EOF

echo
echo "==> Done!"
echo "Your Gust app '$GUST_APP' is ready."
echo "Now, you need to:"
echo "1) Configure Postgres credentials on dev.exs"
echo "2) Create & migrate database:"
echo "mix ecto.create --repo Gust.Repo && mix ecto.migrate --repo Gust.Repo"
echo "3) Run Gust start command:"
echo "mix gust.start"
